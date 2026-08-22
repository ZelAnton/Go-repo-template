#!/usr/bin/env bash
# Exercise both initializers against disposable copies of this template.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/go-repo-template-init.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  echo "test failure: $*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "expected '$needle' in $file"
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

copy_template() {
  local destination="$1"
  if [ -e "$destination" ]; then
    rm -rf "$destination"
  fi
  mkdir -p "$destination"
  cp -a "$repo_root"/. "$destination"/
  rm -rf "$destination/.git"
}

run_initializer() {
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

run_rejection_test() {
  local initializer="$1"
  local copy="$tmp_root/reject-$initializer"
  local output="$tmp_root/reject-$initializer.log"
  copy_template "$copy"
  if run_initializer "$initializer" "$copy" 'Bad"; echo injected; #' 'safe@example.com' 'acme'; then
    fail "$initializer accepted shell syntax in author"
  fi >"$output" 2>&1
  assert_contains "unsafe" "$output"
  assert_unchanged_after_rejection "$copy"

  copy_template "$copy"
  if run_initializer "$initializer" "$copy" $'Bad\nName' 'safe@example.com' 'acme'; then
    fail "$initializer accepted a newline in author"
  fi >"$output" 2>&1
  assert_contains 'control characters' "$output"
  assert_unchanged_after_rejection "$copy"

  copy_template "$copy"
  # Keep the value above a typical pipe buffer while staying below the Windows
  # process command-line limit used by the WSL test runner.
  local long_author="Bad$(printf '\a')$(printf '%70000s' '' | tr ' ' x)"
  if run_initializer "$initializer" "$copy" "$long_author" 'safe@example.com' 'acme'; then
    fail "$initializer accepted a long author containing BEL"
  fi >"$output" 2>&1
  assert_contains 'control characters' "$output"
  assert_unchanged_after_rejection "$copy"

  copy_template "$copy"
  if run_initializer "$initializer" "$copy" 'Jane Doe' 'safe@example.com' 'bad owner'; then
    fail "$initializer accepted an invalid GitHub owner"
  fi >"$output" 2>&1
  assert_contains 'github-owner' "$output"
  assert_unchanged_after_rejection "$copy"
}

run_valid_test() {
  local initializer="$1"
  local copy="$tmp_root/valid-$initializer"
  copy_template "$copy"
  run_initializer "$initializer" "$copy" "O'Connor" 'jane+release@example.com' 'acme-labs' >"$tmp_root/valid-$initializer.log"
  assert_contains 'module github.com/acme-labs/safe-widgets' "$copy/go.mod"
  assert_contains 'Copyright (c) ' "$copy/LICENSE"
  assert_contains "git config user.name \"O'Connor\"" "$copy/.github/workflows/release.yml"
  assert_contains 'git config user.email "jane+release@example.com"' "$copy/.github/workflows/release.yml"
  test ! -e "$copy/scripts/test-init.sh" || fail "generated repository retained disposable test-init.sh"
  if command -v go >/dev/null 2>&1; then
    (cd "$copy" && go mod edit -json >/dev/null)
  fi
}

bash -n "$script_dir/init.sh"
run_valid_test sh
run_rejection_test sh

if command -v pwsh >/dev/null 2>&1; then
  run_valid_test ps1
  run_rejection_test ps1
else
  echo 'pwsh not found; skipped PowerShell initializer checks.'
fi

echo 'initializer tests passed'
