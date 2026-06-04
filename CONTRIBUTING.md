# Contributing to __ProjectName__

Thanks for your interest in improving **__ProjectName__**.

## Prerequisites

- Go 1.25 or later (the minimum is pinned by the `go` directive in `go.mod`).

## Build and test

```sh
go build ./...
go test ./...
```

CI also runs the tests with the race detector (`go test -race ./...`) on Linux; it
needs cgo (a C compiler), so it is not required for the basic local loop.

Before opening a pull request, also run the formatter and vet — CI gates on both:

```sh
gofmt -l .   # must print nothing; run `gofmt -w .` to fix
go vet ./...
```

## Conventions

- **Formatting** is owned by `gofmt` (tabs, canonical layout); `.editorconfig`
  mirrors it. Do not reformat code you are not changing.
- **Dependencies** are tracked in `go.mod` / `go.sum` — add them with `go get`,
  pin versions, and commit both files. `go mod tidy` keeps them honest.
- See [`AGENTS.md`](AGENTS.md) for the full, authoritative set of conventions.

## Changelog

Every user-visible change ships its [`CHANGELOG.md`](CHANGELOG.md) entry in the
same change set, under `## [Unreleased]`. Write the bullet for a consumer of the
library, not the implementer. Pure internal refactors are exempt.

## Pull requests

- Keep changes focused; unrelated cleanups belong in their own PR.
- Ensure CI (build/test on Linux, Windows, macOS) passes.
- Fill in the pull-request checklist.
