#!/usr/bin/env bash

# Runs both initializers in disposable copies and verifies binary preservation and
# ordinary text substitution. The repository itself is never initialized.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/go-template-init-test.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT

create_fixture() {
  local case_root="$1"

  mkdir -p "$case_root/scripts" "$case_root/fixtures"
  cp "$script_dir/init.sh" "$script_dir/init.ps1" "$script_dir/test-init.sh" "$case_root/scripts/"

  # Unknown extension, embedded NUL, invalid UTF-8, and a token-shaped byte run.
  # Any text decoding or substitution would make the comparison below fail.
  printf '\211BIN\000__ProjectName__\377END' > "$case_root/fixtures/asset.unknown"
  cp "$case_root/fixtures/asset.unknown" "$case_root/expected-binary"

  # CRLF verifies that substitution does not normalize line endings.
  printf 'project=__ProjectName__\r\npackage=__GoPackage__\r\n' > "$case_root/fixtures/ordinary.txt"
  printf 'project=binary-safe\r\npackage=binarysafe\r\n' > "$case_root/expected-text"
}

assert_fixture() {
  local case_root="$1"
  local implementation="$2"

  cmp "$case_root/expected-binary" "$case_root/fixtures/asset.unknown" || {
    echo "error: $implementation initializer changed unknown binary content" >&2
    return 1
  }
  cmp "$case_root/expected-text" "$case_root/fixtures/ordinary.txt" || {
    echo "error: $implementation initializer did not preserve/substitute ordinary text" >&2
    return 1
  }
  if [ -e "$case_root/scripts/test-init.sh" ]; then
    echo "error: $implementation initializer left the disposable test harness behind" >&2
    return 1
  fi
}

run_bash_case() {
  local case_root="$temp_root/bash"
  create_fixture "$case_root"
  (
    cd "$case_root"
    bash ./scripts/init.sh --project-name Binary.Safe --author Tester \
      --author-email tester@example.com --github-owner example \
      --description Test --year 2026 --keep-script
  )
  assert_fixture "$case_root" Bash
}

run_powershell_case() {
  local case_root="$temp_root/powershell"
  create_fixture "$case_root"
  pwsh -NoLogo -NoProfile -File "$case_root/scripts/init.ps1" \
    -ProjectName Binary.Safe -Author Tester -AuthorEmail tester@example.com \
    -GitHubOwner example -Description Test -Year 2026 -KeepScript
  assert_fixture "$case_root" PowerShell
}

run_bash_case
if command -v pwsh >/dev/null 2>&1; then
  run_powershell_case
else
  echo "SKIP: pwsh is unavailable; PowerShell initializer runtime test not run." >&2
fi

echo "Initializer binary-preservation and text-substitution tests passed."
