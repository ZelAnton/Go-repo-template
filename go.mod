// Module path and Go version for __ProjectName__.
//
// `scripts/init.ps1` (or init.sh) substitutes __GitHubOwner__ / __ProjectName__
// into the module path — name your GitHub repository with the same slug the init
// script prints, or edit this line to match your real remote.
//
// The `go` directive is the single source of truth for the language version: CI,
// CodeQL, and the release workflow all read it via `go-version-file: go.mod`, and
// it is the minimum version the module compiles on (Go's MSRV equivalent). Raise
// it when you adopt a newer language/std feature.
module github.com/__GitHubOwner__/__ProjectName__

go 1.25
