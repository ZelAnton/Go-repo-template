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

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "expected '$needle' in $file"
}

assert_not_contains() {
  local needle="$1"
  local file="$2"
  if grep -Fq -- "$needle" "$file"; then
    fail "did not expect '$needle' in $file"
  fi
}

assert_unchanged_after_rejection() {
  local copy="$1"
  test -f "$copy/TEMPLATE.md" || fail "rejected initialization removed TEMPLATE.md"
  test -f "$copy/scripts/init.sh" || fail "rejected initialization removed init.sh"
  test -f "$copy/scripts/test-init.sh" || fail "rejected initialization removed test-init.sh"
  assert_contains '__Author__' "$copy/LICENSE"
  assert_contains '__GitHubOwner__' "$copy/go.mod"
  bash -n "$copy/scripts/test-init.sh"
}

run_identity_initializer() {
  local initializer="$1"
  local copy="$2"
  local author="$3"
  local email="$4"
  local owner="$5"
  if [ "$initializer" = sh ]; then
    bash "$copy/scripts/init.sh" --project-name safe.widgets \
      --author "$author" --author-email "$email" --github-owner "$owner" \
      --description "Safe template" --keep-script
  else
    pwsh -NoLogo -NoProfile -File "$copy/scripts/init.ps1" \
      -ProjectName safe.widgets -Author "$author" -AuthorEmail "$email" \
      -GitHubOwner "$owner" -Description "Safe template" -KeepScript
  fi
}

run_identity_rejection_test() {
  local initializer="$1"
  local copy="$tmp_root/identity-reject-$initializer"
  local output="$tmp_root/identity-reject-$initializer.log"

  copy_template "$copy"
  if run_identity_initializer "$initializer" "$copy" 'Bad"; echo injected; #' 'safe@example.com' 'acme'; then
    fail "$initializer accepted shell syntax in author"
  fi >"$output" 2>&1
  assert_contains "unsafe" "$output"
  assert_unchanged_after_rejection "$copy"

  copy_template "$copy"
  if run_identity_initializer "$initializer" "$copy" $'Bad\nName' 'safe@example.com' 'acme'; then
    fail "$initializer accepted a newline in author"
  fi >"$output" 2>&1
  assert_contains 'control characters' "$output"
  assert_unchanged_after_rejection "$copy"

  copy_template "$copy"
  # Keep the value above a typical pipe buffer while staying below the Windows
  # process command-line limit used by the WSL test runner.
  local long_author="Bad$(printf '\a')$(printf '%70000s' '' | tr ' ' x)"
  if run_identity_initializer "$initializer" "$copy" "$long_author" 'safe@example.com' 'acme'; then
    fail "$initializer accepted a long author containing BEL"
  fi >"$output" 2>&1
  assert_contains 'control characters' "$output"
  assert_unchanged_after_rejection "$copy"

  copy_template "$copy"
  if run_identity_initializer "$initializer" "$copy" 'Jane Doe' 'safe@example.com' 'bad owner'; then
    fail "$initializer accepted an invalid GitHub owner"
  fi >"$output" 2>&1
  assert_contains 'github-owner' "$output"
  assert_unchanged_after_rejection "$copy"
}

run_owner_rejection_test() {
  local initializer="$1"
  local copy="$tmp_root/owner-reject-$initializer"
  local output="$tmp_root/owner-reject-$initializer.log"
  local owner control code

  for owner in $'acme\n' $'acme\r\n'; do
    copy_template "$copy"
    if run_identity_initializer "$initializer" "$copy" 'Jane Doe' 'safe@example.com' "$owner"; then
      fail "$initializer accepted a GitHub owner with a trailing newline"
    fi >"$output" 2>&1
    assert_contains 'github-owner' "$output"
    assert_unchanged_after_rejection "$copy"
  done

  # NUL cannot be passed through argv; exercise every other C0 control byte and
  # DEL so both initializers reject the same representable input set.
  for code in $(seq 1 31) 127; do
    printf -v control '%b' "\\$(printf '%03o' "$code")"
    owner="acme${control}"
    copy_template "$copy"
    if run_identity_initializer "$initializer" "$copy" 'Jane Doe' 'safe@example.com' "$owner"; then
      fail "$initializer accepted GitHub owner control byte $code"
    fi >"$output" 2>&1
    assert_contains 'github-owner' "$output"
    assert_unchanged_after_rejection "$copy"
  done
}

run_valid_identity_test() {
  local initializer="$1"
  local copy="$tmp_root/valid-identity-$initializer"
  copy_template "$copy"
  run_identity_initializer "$initializer" "$copy" "O'Connor" 'jane+release@example.com' 'acme-labs' >"$tmp_root/valid-identity-$initializer.log"
  assert_contains 'module github.com/acme-labs/safe-widgets' "$copy/go.mod"
  assert_contains 'Copyright (c) ' "$copy/LICENSE"
  assert_contains "git config user.name \"O'Connor\"" "$copy/.github/workflows/release.yml"
  assert_contains 'git config user.email "jane+release@example.com"' "$copy/.github/workflows/release.yml"
  test ! -e "$copy/scripts/test-init.sh" || fail "generated repository retained disposable test-init.sh"
}

run_non_recursive_substitution_test() {
  local initializer="$1"
  local copy="$tmp_root/non-recursive-$initializer"
  local unsafe_description='$(echo unsafe-description)'
  local year=2026
  copy_template "$copy"
  if [ "$initializer" = sh ]; then
    year='$(echo unsafe-year)'
    bash "$copy/scripts/init.sh" --project-name safe.widgets \
      --author '__Description__' --author-email '__Year__@example.com' \
      --github-owner acme --description "$unsafe_description" --year "$year" --keep-script
  else
    pwsh -NoLogo -NoProfile -File "$copy/scripts/init.ps1" \
      -ProjectName safe.widgets -Author '__Description__' -AuthorEmail '__Year__@example.com' \
      -GitHubOwner acme -Description "$unsafe_description" -Year "$year" -KeepScript
  fi >"$tmp_root/non-recursive-$initializer.log"

  assert_contains "Copyright (c) $year __Description__" "$copy/LICENSE"
  assert_contains 'git config user.name "__Description__"' "$copy/.github/workflows/release.yml"
  assert_contains 'git config user.email "__Year__@example.com"' "$copy/.github/workflows/release.yml"
  assert_contains "$unsafe_description" "$copy/README.md"
  assert_not_contains "$unsafe_description" "$copy/.github/workflows/release.yml"
  assert_not_contains "$year" "$copy/.github/workflows/release.yml"
  assert_not_contains "$unsafe_description" "$copy/LICENSE"
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
  run_valid_identity_test "$initializer"
  run_non_recursive_substitution_test "$initializer"
  run_identity_rejection_test "$initializer"
  run_owner_rejection_test "$initializer"
done

[ "$tested_initializers" -gt 0 ] || fail 'no initializer was available'
echo "initializer tests passed: $tested_initializers initializer(s), transactional and identity checks complete"
