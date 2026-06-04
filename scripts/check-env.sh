#!/usr/bin/env bash
#
# Checks this machine can build and test this Go module before you initialize the
# template (POSIX counterpart of check-env.ps1 — use whichever matches your shell;
# both do the same thing).
#
# Verifies the Go toolchain (`go`) is on PATH so `go build ./...` and
# `go test ./...` can run. gofmt and go vet ship with the toolchain, so only `go`
# needs to be present. Exits 0 when ready; if Go is missing it prints per-OS
# install commands and exits 1 — install it, then re-run.
#
# Usage: bash ./scripts/check-env.sh

set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,12p' "$0"; exit 0 ;; esac

problems=()
echo "==> Checking environment for Go development"

# Required: go (build/test driver, formatter via `gofmt`, and the compiler).
if command -v go >/dev/null 2>&1; then
  echo "    $(go version)"
else
  problems+=("the Go toolchain ('go' is not on PATH)")
fi

# Soft: git drives init's author/email defaults and the VCS workflow, but is not
# required to build.
command -v git >/dev/null 2>&1 || \
  echo "    note: git is not on PATH — init falls back to placeholder author/email."

if [ ${#problems[@]} -eq 0 ]; then
  echo
  echo "Environment ready. Next: bash ./scripts/init.sh --project-name ..."
  exit 0
fi

echo
echo "Environment NOT ready. Missing:"
for p in "${problems[@]}"; do echo "  - $p"; done
echo
echo "Install the Go toolchain, then re-run this check:"
echo "  Windows : winget install GoLang.Go"
echo "  macOS   : brew install go"
echo "  Linux   : see https://go.dev/doc/install (or your distro's package, e.g. apt install golang-go)"
echo "  (any OS): https://go.dev/dl"
exit 1
