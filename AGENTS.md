# AGENTS.md

## Project

- This repository contains `__ProjectName__`, a Go module.
- The public API lives in the package beside `go.mod` at the module root (`greeter.go` is the sample to replace).
- Tests live next to the code they test, in `*_test.go` files in the same package.
- Keep the repository focused; do not introduce CLI, UI, hosting, logging, or dependency injection infrastructure unless explicitly requested.

## Agent instruction files are local-only in generated repos

> **Scope:** this section is for a repository **created from a template**, not the
> template itself. In the template, `CLAUDE.md`, `AGENTS.md`, and `.claude/` stay
> **tracked and pushed** — that is how the guidance ships. If you are reading this
> in the template repo, leave them tracked and do nothing.

In a generated repo, `CLAUDE.md`, `AGENTS.md`, and `.claude/` are local guidance for whoever (human or agent) works in the clone — not project source. Keep them **git-ignored and untracked** so they stay on disk for tooling but never reach the remote; each developer keeps their own. This is a **by-hand step — the init script does not do it** — done **before the first push**:

```bash
# Append last so `.claude/` overrides the earlier `!.claude/...` ship lines.
printf '\n/CLAUDE.md\n/AGENTS.md\n.claude/\n' >> .gitignore
git rm -r --cached CLAUDE.md AGENTS.md .claude
git add .gitignore && git commit -m "Keep agent instructions local"   # commit the ignore rule *and* the removals together
# jj-colocated: jj file untrack CLAUDE.md AGENTS.md .claude  (folds .gitignore + removals into the working copy; no separate commit)
```

`git rm --cached` keeps the files on disk; an ignore rule alone won't untrack already-committed files. `init` deletes `TEMPLATE.md` and `docs/AGENT-INIT-GUIDE.md`, so this section is the surviving copy of the recipe downstream — consult that guide while it exists for precedence details and the caveat that a repo created via GitHub's *Use this template* already carries these files in its initial commit's history (untracking drops them from the tip only).

## Runtime

- Use Go 1.25 (the floor set by the `go` directive in `go.mod`). Do not change it unless explicitly asked.
- `go.mod` is the single source of truth for the module path and language version; CI, CodeQL, and the release workflow all read it via `go-version-file: go.mod`.

## Dependencies

- Do not introduce new dependencies without explicit approval.
- Add dependencies with `go get`, which records them in `go.mod` and pins their checksums in `go.sum`; commit both files. Run `go mod tidy` to drop unused entries.
- Pin to specific module versions; do not depend on pseudo-versions of `main` unless unavoidable.
- The standard library is preferred — reach for it before adding a dependency.
- Supply-chain audit: `govulncheck ./...` (a CI job) flags known vulnerabilities reachable from the code.

## Architecture

- Keep all functionality available as reusable library APIs.
- Keep implementation details (helpers, platform-specific code, internal types) internal to the library.
- Do not expose implementation types publicly unless explicitly requested.
- Prefer simple, direct code over new abstractions.
- Minimize public API surface area; public API changes must be intentional and documented.
- Do not add dependency injection unless there is a concrete need.

## Build, references, and repository structure

- A library package's files live beside `go.mod` at the module root; tests sit next to them as `*_test.go`. Helper scripts go under `scripts/`. For a command-line program, add `cmd/<name>/main.go`; keep reusable logic in importable packages (optionally under `internal/` to keep it private to the module).
- `go build ./...` and `go test ./...` operate over every package; the Go toolchain resolves build order from import graphs — there is no manual ordering to maintain.
- Imports use the full module path (`github.com/__GitHubOwner__/__ProjectName__/...`); use `internal/` for packages that must not be importable outside this module.

## Build And Test

- Use `go build ./...` to validate compilation across all packages.
- Use `go test ./...` to run tests. CI additionally runs `go test -race ./...` on Linux (the race detector needs cgo / a C compiler, so it is not part of the default cross-platform loop).
- A successful test run must execute the discovered tests, not only compile them. Note that a package with no test files reports `[no test files]` — that is not the same as a passing test.

## Formatting

- `gofmt` is the source of truth for formatting (tabs, import grouping, layout); `.editorconfig` mirrors it. Run `gofmt -w .` before committing; CI fails if `gofmt -l .` is non-empty.
- `.editorconfig` reflects gofmt's rules — follow it for non-Go files too.
- Preserve LF line endings, except Windows batch files (`.cmd`/`.bat`) which require CRLF.

## Go Style

- Code must be `gofmt`-clean and `go vet`-clean; both are CI gates.
- Exported identifiers (types, funcs, vars, the package itself) carry doc comments that begin with the identifier's name, per Go convention.
- Keep the exported surface minimal; unexported (lowercase) identifiers are package-private — prefer them for implementation detail.
- Prefer the standard library and simple, direct code over new abstractions and dependencies.

### Error handling style

- Go uses explicit error values, not exceptions. Return errors; do not panic for ordinary failures. Check `err` immediately and wrap with context using `fmt.Errorf("...: %w", err)` so callers can `errors.Is`/`errors.As`.
- An ignored error must say **what** is being dropped and **why** that is correct — a bare `_ = f()` is not enough:

  ```go
  // Best-effort cache write; a failure here is non-fatal and the next read
  // recomputes the value, so the error is intentionally ignored.
  _ = cache.Store(key, value)
  ```

## Documentation

- All documentation and code comments must be written in English.
- Functional changes must include corresponding README updates when behavior, requirements, usage, or public API changes.
- Do not leave changed behavior undocumented.

## Changelog

- `CHANGELOG.md` is the single source of truth for release notes.
- The release workflow reads `## [Unreleased]` automatically to populate the GitHub Release body (and, where applicable, the package's release-notes field).
- **Every user-visible change must be accompanied by a `CHANGELOG.md` update in the same change set.** Non-negotiable for new/modified public API, behavioural changes, bug fixes, deprecations, removals. Pure internal refactors are the only exemption.
- Add a manual bullet under `## [Unreleased]` in the appropriate subsection (`### Added` / `### Changed` / `### Fixed` / `### Removed` / `### Deprecated`). Write it for a consumer, not the implementer. Replace the placeholder `-`.
- Do not modify versioned sections (`## [1.0.0]`, etc.) — those are managed by the release workflow.

### Auto-fill fallback

- If `## [Unreleased]` has no real bullets at release time, the workflow auto-generates entries from commits since the previous tag using `git-cliff` (config: `cliff.toml`). Manual entries always win.
- The first word of the commit subject decides the bucket (case-insensitive): `Add`/`Feat` → Added; `Fix`/`Bug` → Fixed; `Remove`/`Delete`/`Drop` → Removed; `Refactor`/`Update`/`Change`/`Rename`/`Perf`/`CI`/`Cleanup` → Changed; `Doc`/`Chore`/`Test`/`Style` and `Release v...`/merges → skipped; anything else → Changed (fallback).

## Release

- The release workflow (`.github/workflows/release.yml`) publishes a Go module by **pushing a `vX.Y.Z` git tag**. There is no registry credential and no version field in `go.mod`: the tag *is* the release. The Go module proxy (`proxy.golang.org`) fetches the module at that tag on first request and the version is then immutable forever; pkg.go.dev indexes it.
- No publish secret is needed. The only optional secret is the release App token (`RELEASE_APP_ID` + `RELEASE_APP_PRIVATE_KEY`) used to push to a protected `main`.
- **Step ordering invariant:** the atomic tag push is the only irreversible step, so it is the pivot. Build/vet/test and a *local* (unpushed) commit+tag run before it; the idempotent GitHub Release runs after. A failure before the push leaves no tag on the remote or proxy — re-run freely. **Once the tag is pushed, do not re-run the whole workflow** (it would compute the next version and strand this one) — finish the GitHub Release manually using the command the failing step prints. When editing `release.yml`, never move the tag push before the build/test gate, and keep the post-push steps idempotent.
- Because a published version is immutable, never delete or move a release tag. To fix a bad release, publish the next patch version.

## Security Scanning

- **CodeQL** (`.github/workflows/codeql.yml`) — GitHub static analysis for Go, on push / PR / weekly. CodeQL supports Go, so this workflow ships enabled.
- **govulncheck** — a CI job (`ci.yml`) running `govulncheck ./...` against the Go vulnerability database; it reports only vulnerabilities reachable from the code.
- **Dependabot** (`.github/dependabot.yml`) — weekly grouped updates for GitHub Actions and Go modules (`gomod`).

## Comments

- Minimize comments. Write them only to explain why something exists, an architectural decision, or non-obvious platform/runtime behavior.
- Do not write comments describing what the code already says.

## Version control (jujutsu)

This repository uses [jujutsu (`jj`)](https://jj-vcs.github.io/jj/) for version control. The repo is colocated with git, but `jj` is the primary tool — use `jj` commands for everything in this workflow, not raw `git`.

### Describing the current change

- When you start a new piece of work, set the change description right away:
	```
	jj describe -m "Concise summary of what this change does"
	```
- For larger work, fold subsequent small edits into the current change without asking — keep extending the same change rather than starting a new one for each follow-up.
- If the scope of the current change shifts mid-work, refresh the description with another `jj describe -m "..."`.

- **Per-prompt evaluation (mandatory).** Before any edits, run `jj st` and classify the incoming prompt against the current change description:

	| Signal in prompt | Category | Action |
	|---|---|---|
	| Same topic, refinement, follow-up of in-progress work | **Continuation** | Just work. jj auto-folds edits into the current change. |
	| Same change but goal has been refined or expanded | **Scope shift** | `jj describe -m "<refined summary>"`. **Don't** start a new change. |
	| Orthogonal topic, different area, "теперь сделай X" | **New work** | If current change is finished → `jj new -m "<summary>"` (descendant). If still in progress → `jj new @- -m "..."` (parallel sibling). |

	Reliable signals: "теперь" / "now" / "next" / "также сделай" / "and also" usually mean **new work** or **scope shift**. Imperative follow-ups inside the same scope ("исправь это", "fix this", "продолжи") mean **continuation**. When in doubt, ask the user.

### Pushing to remote

The user signals "synchronise with remote" with a short trigger word (typically `pull` or `push`). On that signal, run the full sync:
1. `jj git fetch` — pull down remote movement **before** doing anything else.
2. If `main@origin` has moved past the local change, rebase onto it: `jj rebase -r @- -d main@origin` (or `jj rebase -d main@origin` for a stack).
3. Put the work on a **feature bookmark — never advance `main` locally to publish.** First push: `jj bookmark create <topic> -r @` then `jj git push --allow-new -b <topic>`. Later pushes: `jj bookmark move <topic> --to @` then `jj git push -b <topic>`.
4. Open / update a pull request into `main` (`gh pr create --base main --head <topic> --fill`). `main` advances only when the PR merges; afterwards `jj git fetch` and `jj bookmark delete <topic>`.

Never push without an explicit signal from the user. **Direct-push fallback:** where `main` is unprotected the old single-step flow still works — `jj bookmark move main --to @` then `jj git push -b main`; once PRs are required this is rejected for everyone except the release workflow's GitHub App, which sits in the ruleset's bypass list (`RELEASE_APP_ID` + `RELEASE_APP_PRIVATE_KEY`; see `release-token-bypass.md`).

### Undoing work

- **`jj undo`** (alias of `jj op undo`) — reverses the last operation (describe / edit / squash / rebase / abandon / push). Repeatable.
- **`jj abandon <rev>`** — drops a specific change entirely; descendants auto-rebase onto its parent.
- **`jj restore`** — discards working-copy modifications and resets `@` to its parent's tree.
- **`jj op log`** is the reflog equivalent; `jj op restore <op-id>` jumps to any prior point.

Never hide a deliberate undo: if the user asks to "undo the last commit/change", run `jj undo` (or `jj abandon`) and tell them what was reverted.

### Bookmarks & safety

- Work is published through a **feature bookmark per PR** (short kebab-case topic name), merged into `main` via pull request.
- Do not revert or amend changes the user authored without explicit agreement.
- Do not rewrite unrelated files when making a focused change.

## Command Conventions

- Commands and APIs should be idempotent where possible.
- Output should remain concise and script-friendly.
- Breaking changes must be explicit.
