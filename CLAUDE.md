# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build all packages.
go build ./...

# Run all tests. (CI also runs `go test -race ./...` on Linux; -race needs cgo.)
go test ./...

# Format (gofmt is canonical) and vet.
gofmt -w .
go vet ./...
```

## Architecture

> **Fill this in for `__ProjectName__`.** Describe the public surface, the main
> types, and any non-obvious design decisions so an agent can navigate the code
> without re-deriving the structure each time.

The library package lives beside `go.mod` at the module root (`greeter.go` is the
sample to replace; `*_test.go` files sit next to the code they test). Keep the
public API surface small and intentional, keep implementation details unexported,
and prefer simple, direct code over new abstractions.

## Conventions

See [AGENTS.md](AGENTS.md) for the authoritative conventions: dependencies, build
ordering, formatting, error-handling style, changelog rules, and the release
process. The most load-bearing rules:

- Treat warnings as errors; keep the public API minimal and intentional.
- Every user-visible change ships its `CHANGELOG.md` entry under `## [Unreleased]`
  in the same change set (auto-fill from git log is a fallback, not the default).
- The release workflow's publish step is the single irreversible pivot — see
  AGENTS.md → "Release".

## Agent instruction files (in repos created from this template)

This applies to a repo **created from a template**, not the template itself (here
they stay tracked and pushed). Downstream, keep `CLAUDE.md`, `AGENTS.md`, and
`.claude/` **git-ignored and untracked** so they stay on disk for tooling but never
reach the remote — a by-hand step before the first push (the init script does not do
it). Recipe: the "Agent instruction files are local-only in generated repos" section
of [AGENTS.md](AGENTS.md), or `docs/AGENT-INIT-GUIDE.md` while it exists.

## Version control workflow

The repo uses [jujutsu (`jj`)](https://jj-vcs.github.io/jj/) colocated with git. Use
`jj` commands. Describe work early (`jj describe -m`), publish through a feature
bookmark per PR (never advance `main` locally), and sync only on the user's explicit
`pull`/`push` trigger. Full workflow in [AGENTS.md](AGENTS.md) → "Version control".
