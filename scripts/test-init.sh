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

create_excluded_fixture() {
  local root="$1"
  local excluded
  for excluded in .git .jj vendor; do
    mkdir -p -- "$root/nested/$excluded/__ProjectName__-directory"
    printf '%s\n' '__ProjectName__' > "$root/nested/$excluded/__ProjectName__-directory/__ProjectName__.txt"
  done
}

excluded_fixture_expected="$tmp_root/excluded-fixture-expected"
create_excluded_fixture "$excluded_fixture_expected"

copy_template() {
  local destination="$1"
  rm -rf -- "$destination"
  mkdir -p -- "$destination"
  cp -a -- "$repo_root"/. "$destination"/
  rm -rf -- "$destination/.git"
  mkdir -p -- "$destination/__ProjectName__-fixtures"
  printf '%s\n' '__ProjectName__' > "$destination/__ProjectName__-fixtures/__ProjectName__.txt"
  mkdir -p -- "$destination/scripts/__ProjectName__-tool"
  printf '%s\n' '__ProjectName__' > "$destination/scripts/__ProjectName__-tool/__ProjectName__.txt"
  cp -a -- "$excluded_fixture_expected" "$destination/nested-excluded-fixture"
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
  test -f "$copy/scripts/safe-widgets-tool/safe-widgets.txt" || fail "token-named scripts fixture was not renamed"
  grep -Fq -- 'safe-widgets' "$copy/scripts/safe-widgets-tool/safe-widgets.txt" || fail "scripts fixture content was not substituted"
  if ! diff -r -q -- "$excluded_fixture_expected" "$copy/nested-excluded-fixture" >/dev/null; then
    diff -r -q -- "$excluded_fixture_expected" "$copy/nested-excluded-fixture" >&2 || true
    fail "nested .git/.jj/vendor fixture changed"
  fi
  test ! -e "$copy/scripts/test-init.sh" || fail "test harness remained"
}

assert_runtime_scripts_unchanged() {
  local copy="$1"
  cmp -- "$repo_root/scripts/init.sh" "$copy/scripts/init.sh" >/dev/null || fail "init.sh changed during initialization"
  cmp -- "$repo_root/scripts/init.ps1" "$copy/scripts/init.ps1" >/dev/null || fail "init.ps1 changed during initialization"
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
  assert_runtime_scripts_unchanged "$copy"

  # A failed preparation can be retried without restoring the disposable copy.
  run_initializer "$initializer" "$copy" 1 >"$tmp_root/$initializer-$stage-retry.log" 2>&1
  assert_generated "$copy"
  assert_runtime_scripts_unchanged "$copy"
  assert_no_transaction_dirs "$copy"
  echo "PASS $initializer failure stage: $stage (rollback + retry)"
}

run_restore_failure() {
  local initializer="$1"
  local copy="$tmp_root/$initializer-restore"
  local baseline="$tmp_root/$initializer-restore-baseline"
  local log="$tmp_root/$initializer-restore.log"
  local backup expected recovered reported_backup status

  copy_template "$copy"
  cp -a -- "$copy" "$baseline"
  expected="$tmp_root/$initializer-restore-expected"
  copy_template "$expected"
  run_initializer "$initializer" "$expected" 1 >"$tmp_root/$initializer-restore-expected.log" 2>&1
  assert_generated "$expected"
  assert_runtime_scripts_unchanged "$expected"
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

  # Retry immediately: the initializer must discover, restore, verify, and remove
  # the sole unresolved backup before preparing a fresh staged tree.
  run_initializer "$initializer" "$copy" 1 >"$tmp_root/$initializer-restore-retry.log" 2>&1
  assert_generated "$copy"
  assert_runtime_scripts_unchanged "$copy"
  if ! diff -r -q -- "$expected" "$copy" >/dev/null; then
    diff -r -q -- "$expected" "$copy" >&2 || true
    fail "$initializer retry after interrupted restore produced an incomplete tree"
  fi
  assert_no_transaction_dirs "$copy"
  echo "PASS $initializer failure stage: restore (automatic recovery + retry)"
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

stages='copy content rename activate delete evacuate commit remove-scripts scripts'
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
echo "initializer failure-path tests passed: $tested_initializers initializers, 11 checks each (10 injected failure stages, 1 default cleanup)"
