#!/usr/bin/env bash
# Exercise both initializers against disposable copies of this template.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/go-repo-template-settings.XXXXXXXX")"
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
}

run_initializer() {
  local initializer="$1"
  local copy="$2"
  if [ "$initializer" = sh ]; then
    bash "$copy/scripts/init.sh" --project-name safe.widgets \
      --author 'Jane Doe' --author-email jane@example.com --github-owner acme \
      --description 'Safe template' --keep-script
  else
    pwsh -NoLogo -NoProfile -File "$copy/scripts/init.ps1" \
      -ProjectName safe.widgets -Author 'Jane Doe' -AuthorEmail jane@example.com \
      -GitHubOwner acme -Description 'Safe template' -KeepScript
  fi
}

write_user_settings() {
  local destination="$1"
  # BOM + CRLF and a token-looking value catch text rewrites as well as clobbers.
  printf '\357\273\277{\r\n  "literal": "__ProjectName__"\r\n}\r\n' > "$destination"
}

assert_settings_output() {
  local log="$1"
  local expected="$2"
  local actual
  actual="$(grep -F -- '.claude/settings.json' "$log" || true)"
  [ "$actual" = "$expected" ] || fail "unexpected settings output in $log: '$actual'"
}

run_existing_test() {
  local initializer="$1"
  local copy="$tmp_root/$initializer-existing"
  local expected_settings="$tmp_root/$initializer-existing-settings"
  local expected_template="$tmp_root/$initializer-existing-template"
  local log="$tmp_root/$initializer-existing.log"

  copy_template "$copy"
  write_user_settings "$copy/.claude/settings.json"
  cp -- "$copy/.claude/settings.json" "$expected_settings"
  cp -- "$copy/.claude/settings.json.template" "$expected_template"
  run_initializer "$initializer" "$copy" >"$log" 2>&1

  cmp -- "$expected_settings" "$copy/.claude/settings.json" >/dev/null ||
    fail "$initializer changed existing settings"
  cmp -- "$expected_template" "$copy/.claude/settings.json.template" >/dev/null ||
    fail "$initializer changed the unactivated template"
  assert_settings_output "$log" '    Preserved existing .claude/settings.json.'
  echo "PASS $initializer existing settings"
}

run_absent_and_retry_test() {
  local initializer="$1"
  local copy="$tmp_root/$initializer-absent-retry"
  local expected_template="$tmp_root/$initializer-absent-template"
  local expected_retry="$tmp_root/$initializer-retry-settings"
  local first_log="$tmp_root/$initializer-absent.log"
  local retry_log="$tmp_root/$initializer-retry.log"

  copy_template "$copy"
  cp -- "$copy/.claude/settings.json.template" "$expected_template"
  run_initializer "$initializer" "$copy" >"$first_log" 2>&1

  test ! -e "$copy/.claude/settings.json.template" ||
    fail "$initializer retained the activated template"
  cmp -- "$expected_template" "$copy/.claude/settings.json" >/dev/null ||
    fail "$initializer did not activate the template unchanged"
  assert_settings_output "$first_log" '    Activated .claude/settings.json'

  write_user_settings "$copy/.claude/settings.json"
  cp -- "$copy/.claude/settings.json" "$expected_retry"
  run_initializer "$initializer" "$copy" >"$retry_log" 2>&1

  cmp -- "$expected_retry" "$copy/.claude/settings.json" >/dev/null ||
    fail "$initializer changed settings on retry"
  assert_settings_output "$retry_log" '    Preserved existing .claude/settings.json.'
  echo "PASS $initializer absent settings + retry"
}

bash -n "$script_dir/init.sh"
tested_initializers=0
for initializer in sh ps1; do
  if [ "$initializer" = ps1 ] && ! command -v pwsh >/dev/null 2>&1; then
    echo 'SKIP ps1: pwsh not found'
    continue
  fi
  tested_initializers=$((tested_initializers + 1))
  run_existing_test "$initializer"
  run_absent_and_retry_test "$initializer"
done

[ "$tested_initializers" -gt 0 ] || fail 'no initializer was available'
echo "initializer settings tests passed: $tested_initializers initializer(s), 3 scenarios each"
