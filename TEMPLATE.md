# Go repository template

A starting point for Go modules: a `go.mod`-pinned language version, gofmt + go vet
gates, cross-platform CI, CodeQL + govulncheck scanning, an optional tag-based
release pipeline, and conventions for agents in [CLAUDE.md](CLAUDE.md) /
[AGENTS.md](AGENTS.md).

> **AI agents:** before initializing a repo from this template, read
> [docs/AGENT-INIT-GUIDE.md](docs/AGENT-INIT-GUIDE.md). It captures mistakes past
> initialization sessions made and is a living document you are expected to extend.

## Using this template

1. Create a new repository from this one (GitHub: **Use this template**), or copy
   the files into a fresh repo.
2. **Check your environment is ready.** Before initializing, confirm this machine
   has the toolchain to build and test a Go project. Use whichever matches
   your shell — both do the same thing:

   ```pwsh
   pwsh ./scripts/check-env.ps1
   ```

   ```bash
   bash ./scripts/check-env.sh
   ```

   It checks the Go toolchain (`go`) is on PATH. If anything
   required is missing it lists the install commands for your OS and exits non-zero —
   install what it names, then re-run it. **Don't run init until it reports the
   environment is ready.**
3. Run the init script once to stamp your project name in. Use whichever matches
   your shell — both do the same thing:

   ```pwsh
   pwsh ./scripts/init.ps1 -ProjectName my-widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
   ```

   ```bash
   bash ./scripts/init.sh --project-name my-widgets --author "Jane Doe" --github-owner acme --description "Widget toolkit"
   ```

   `-ProjectName` / `--project-name` is required; the rest fall back to sensible
   defaults. From the project name the script derives two values: a **module slug**
   (lowercase, non-alphanumerics → `-`; e.g. `Acme.Widgets` → `acme-widgets`) used
   in the `go.mod` module path and repository URLs, and a **Go package identifier**
   (lowercase, alphanumerics only; e.g. `acmewidgets`) used in the `package`
   declarations. Name your GitHub repository with the slug the script prints (or edit
   `go.mod`'s module path to match your real remote). The script also activates
   `.claude/settings.json` from its `.template` form, deletes this `TEMPLATE.md` and
   `docs/AGENT-INIT-GUIDE.md`, and (unless `-KeepScript` / `--keep-script`) removes
   **both** initializers (`check-env.{ps1,sh}` stay — they double as a contributor
   onboarding check).
4. Verify:

   ```sh
   go build ./...
   go test ./...
   ```

5. Replace the placeholder `Greet` function in `greeter.go` (at the module root)
   with your real API and delete or rewrite `greeter_test.go`.
6. **Keep the agent-instruction files local.** This template tracks and ships
   `CLAUDE.md`, `AGENTS.md`, and `.claude/` on purpose — but a repo *created from*
   it should keep them out of its remote. The init script does **not** do this — it
   is a by-hand step. Before your first push, git-ignore and untrack them:

   ```bash
   printf '\n/CLAUDE.md\n/AGENTS.md\n.claude/\n' >> .gitignore
   git rm -r --cached CLAUDE.md AGENTS.md .claude
   git add .gitignore && git commit -m "Keep agent instructions local"
   # jj-colocated: jj file untrack CLAUDE.md AGENTS.md .claude
   ```

   Appending `.claude/` last makes it win over the earlier `!.claude/...` ship
   lines. The surviving copy of this recipe downstream is the "Agent instruction
   files are local-only in generated repos" section of [AGENTS.md](AGENTS.md).

## Placeholder tokens

| Token | Meaning |
|---|---|
| `__ProjectName__` | module slug — the repo-name element of the `go.mod` module path, repository URLs, and any token-named files/folders (derived: lowercase, hyphenated) |
| `__GoPackage__` | Go package identifier in the `package` declarations (derived: lowercase, alphanumerics only) |
| `__Author__` | author (LICENSE) |
| `__AuthorEmail__` | author email (release-commit identity in `release.yml`) |
| `__GitHubOwner__` | GitHub owner/org in the module path and repository URLs |
| `__Description__` | project description |
| `__Year__` | copyright year |

`__ProjectName__` and `__GoPackage__` are both *derived from* the single
`--project-name` you pass; you don't supply them separately.

## Optional pieces — remove what you don't need

- **Releasing / publishing** — releases happen by pushing a `vX.Y.Z` tag (no
  registry credential; `proxy.golang.org` and pkg.go.dev pick it up automatically).
  If this is an app or you don't want a release pipeline, delete
  `.github/workflows/release.yml`. For an importable library, keep it.
- **Command-line program** — this template ships a library package at the module
  root. For a CLI, add `cmd/<name>/main.go` and keep reusable logic in importable
  packages.
- **Community-health files** — `SECURITY.md`, `CONTRIBUTING.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`, `.github/CODEOWNERS`. Edit to taste; delete
  any you don't want. `CODEOWNERS` ships with its rule commented out.
- **YAML linting** — `.yamllint.yml` + the CI `yaml-lint` job. Run locally with
  `yamllint .`. Delete both if unwanted.

## Security hardening (on by default)

- **Pinned actions** — every GitHub Action is pinned to a full commit SHA (with a
  `# vN` comment). Dependabot bumps the SHA and rewrites the comment.
- **Static analysis** — CodeQL (`.github/workflows/codeql.yml`) runs over the Go
  code on push / PR / weekly.
- **Dependency auditing** — `govulncheck` (a CI job) gates on vulnerabilities in
  the dependency tree that are reachable from your code.
- **Release ordering** — the release workflow builds and tests, then pushes the
  tag (the single irreversible step that publishes the module), then creates the
  GitHub Release, so a failure before the push can't orphan a release.

## Post-setup checklist

- [ ] Agent-instruction files (`CLAUDE.md`, `AGENTS.md`, `.claude/`) git-ignored and
      untracked (by hand, before the first push — step 6 above).
- [ ] `go.mod` module path matches your real GitHub repository (owner + repo name).
- [ ] LICENSE author/year reviewed.
- [ ] `SECURITY.md` reporting contact reviewed; `.github/CODEOWNERS` enabled if wanted.
- [ ] GitHub **Settings → Security → Private vulnerability reporting** enabled.
- [ ] `CLAUDE.md` "Architecture" section written for your project.
- [ ] Branch protection for `main` configured; if PRs are required, set up the
      release App token (`RELEASE_APP_ID` + `RELEASE_APP_PRIVATE_KEY`; recipe:
      `release-token-bypass.md`).
