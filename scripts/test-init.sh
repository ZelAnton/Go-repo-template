#!/usr/bin/env bash
# Exercise both initializers against disposable copies of this template.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/go-repo-template-init.XXXXXXXX")"
trap 'rm -rf -- "$tmp_root"' EXIT

fail() {
  echo "test failure: $*" >&2
  exit 1
}

copy_template() {
  local destination="$1"
  rm -rf -- "$destination"
  mkdir -p -- "$destination"
  cp -a -- "$repo_root"/. "$destination"/
  rm -rf -- "$destination/.git"
  mkdir -p -- "$destination/__ProjectName__-fixtures"
  printf '%s\n' '__ProjectName__' > "$destination/__ProjectName__-fixtures/__ProjectName__.txt"
}

assert_same_tree() {
  local expected="$1"
  local actual="$2"
  if ! diff -r -q -- "$expected" "$actual" >/dev/null; then
    diff -r -q -- "$expected" "$actual" >&2 || true
    fail "the tree changed after an injected failure"
  fi
}

assert_generated() {
  local copy="$1"
  grep -Fq -- 'module github.com/acme/safe-widgets' "$copy/go.mod" || fail "module substitution missing"
  test -f "$copy/.claude/settings.json" || fail "settings activation missing"
  test ! -e "$copy/.claude/settings.json.template" || fail "settings template remained"
  test ! -e "$copy/TEMPLATE.md" || fail "TEMPLATE.md remained"
  test ! -e "$copy/docs/AGENT-INIT-GUIDE.md" || fail "agent guide remained"
  test -f "$copy/safe-widgets-fixtures/safe-widgets.txt" || fail "token-named fixture was not renamed"
  grep -Fq -- 'safe-widgets' "$copy/safe-widgets-fixtures/safe-widgets.txt" || fail "fixture content was not substituted"
  test ! -e "$copy/scripts/test-init.sh" || fail "test harness remained"
}

find_transaction_dir() {
  local copy="$1"
  local kind="$2"
  find "$(dirname "$copy")" -mindepth 1 -maxdepth 1 -type d \
    -name ".$(basename "$copy").init-$kind*" -print
}

assert_no_transaction_dirs() {
  local copy="$1"
  local survivors
  survivors="$(find_transaction_dir "$copy" 'stage'; find_transaction_dir "$copy" 'backup')"
  [ -z "$survivors" ] || fail "transaction directories survived for '$copy': $survivors"
}

run_initializer() {
  local initializer="$1"
  local copy="$2"
  local keep_script="${3:-1}"
  if [ "$initializer" = sh ]; then
    if [ "$keep_script" -eq 1 ]; then
      bash "$copy/scripts/init.sh" --project-name safe.widgets \
        --author 'Jane Doe' --author-email jane@example.com --github-owner acme \
        --description 'Safe template' --keep-script
    else
      bash "$copy/scripts/init.sh" --project-name safe.widgets \
        --author 'Jane Doe' --author-email jane@example.com --github-owner acme \
        --description 'Safe template'
    fi
  else
    if [ "$keep_script" -eq 1 ]; then
      pwsh -NoLogo -NoProfile -File "$copy/scripts/init.ps1" \
        -ProjectName safe.widgets -Author 'Jane Doe' -AuthorEmail jane@example.com \
        -GitHubOwner acme -Description 'Safe template' -KeepScript
    else
      pwsh -NoLogo -NoProfile -File "$copy/scripts/init.ps1" \
        -ProjectName safe.widgets -Author 'Jane Doe' -AuthorEmail jane@example.com \
        -GitHubOwner acme -Description 'Safe template'
    fi
  fi
}

run_failure_stage() {
  local initializer="$1"
  local stage="$2"
  local copy="$tmp_root/$initializer-$stage"
  local baseline="$tmp_root/$initializer-$stage-baseline"
  local log="$tmp_root/$initializer-$stage.log"

  copy_template "$copy"
  cp -a -- "$copy" "$baseline"
  set +e
  TEMPLATE_INIT_FAIL_AT="$stage" run_initializer "$initializer" "$copy" 1 >"$log" 2>&1
  local status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$initializer accepted injected $stage failure"
  assert_same_tree "$baseline" "$copy"
  assert_no_transaction_dirs "$copy"
  test -f "$copy/scripts/init.sh" || fail "$initializer failure removed init.sh at $stage"
  test -f "$copy/scripts/init.ps1" || fail "$initializer failure removed init.ps1 at $stage"

  # A failed preparation can be retried without restoring the disposable copy.
  run_initializer "$initializer" "$copy" 1 >"$tmp_root/$initializer-$stage-retry.log" 2>&1
  assert_generated "$copy"
  echo "PASS $initializer failure stage: $stage (rollback + retry)"
}

run_restore_failure() {
  local initializer="$1"
  local copy="$tmp_root/$initializer-restore"
  local baseline="$tmp_root/$initializer-restore-baseline"
  local log="$tmp_root/$initializer-restore.log"
  local backup recovered reported_backup status

  copy_template "$copy"
  cp -a -- "$copy" "$baseline"
  set +e
  TEMPLATE_INIT_FAIL_AT=restore run_initializer "$initializer" "$copy" 1 >"$log" 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$initializer accepted injected restore failure"

  backup="$(find_transaction_dir "$copy" 'backup')"
  [ -n "$backup" ] || fail "$initializer did not preserve a backup after incomplete restore"
  [ "$(printf '%s\n' "$backup" | wc -l)" -eq 1 ] || fail "$initializer preserved multiple restore backups"
  reported_backup="$backup"
  if [ "$initializer" = ps1 ] && command -v cygpath >/dev/null 2>&1; then
    reported_backup="$(cygpath -w "$backup")"
  fi
  grep -Fq -- "$reported_backup" "$log" || fail "$initializer did not report the recovery backup path"
  [ -z "$(find_transaction_dir "$copy" 'stage')" ] || fail "$initializer retained a staging tree after restore failure"

  recovered="$tmp_root/$initializer-restore-recovered"
  mkdir -p -- "$recovered"
  cp -a -- "$copy"/. "$recovered"/
  cp -a -- "$backup"/. "$recovered"/
  assert_same_tree "$baseline" "$recovered"

  while IFS= read -r -d '' entry; do
    mv -- "$entry" "$copy/"
  done < <(find "$backup" -mindepth 1 -maxdepth 1 -print0)
  rmdir -- "$backup"
  assert_same_tree "$baseline" "$copy"
  run_initializer "$initializer" "$copy" 1 >"$tmp_root/$initializer-restore-retry.log" 2>&1
  assert_generated "$copy"
  assert_no_transaction_dirs "$copy"
  echo "PASS $initializer failure stage: restore (preserved backup + recovery + retry)"
}

run_default_cleanup() {
  local initializer="$1"
  local copy="$tmp_root/$initializer-default"
  copy_template "$copy"
  run_initializer "$initializer" "$copy" 0 >"$tmp_root/$initializer-default.log" 2>&1
  assert_generated "$copy"
  test ! -e "$copy/scripts/init.sh" || fail "$initializer retained init.sh"
  test ! -e "$copy/scripts/init.ps1" || fail "$initializer retained init.ps1"
  echo "PASS $initializer default cleanup"
}

stages='copy content rename activate delete remove-scripts evacuate commit'
tested_initializers=0
for initializer in sh ps1; do
  if [ "$initializer" = ps1 ] && ! command -v pwsh >/dev/null 2>&1; then
    echo 'SKIP ps1: pwsh not found'
    continue
  fi
  tested_initializers=$((tested_initializers + 1))
  for stage in $stages; do
    run_failure_stage "$initializer" "$stage"
  done
  run_restore_failure "$initializer"
  run_default_cleanup "$initializer"
done

[ "$tested_initializers" -gt 0 ] || fail 'no initializer was available'
echo "initializer failure-path tests passed: $tested_initializers initializers, 10 checks each (9 injected failure stages, 1 default cleanup)"
