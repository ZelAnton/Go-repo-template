# Agent guide: initializing a repo from this template

This guide is for an AI agent (Claude Code or similar) asked to "initialize a new
repository from this template." It exists because real initialization sessions have
gone wrong in avoidable ways. **Read it before touching any files.**

> **Living document — keep it accurate.** If you make a mistake while initializing a
> repo (or watch one happen), add it to [Failure log](#failure-log) with the symptom,
> the root cause, and the rule that prevents it. The whole point is that the *next*
> agent doesn't repeat what the last one got wrong.

## TL;DR — the seven rules

1. **Read before you write.** Read `TEMPLATE.md`, this file, `AGENTS.md`, and
   `CLAUDE.md` *first*. Do not generate a single file based on an assumed layout.
2. **Check the toolchain first.** Run `scripts/check-env.ps1` (or
   `scripts/check-env.sh`). If it reports a missing tool, STOP and offer the user the
   install commands it prints — don't run init against an environment that can't build
   or test.
3. **Prefer the init script over hand-rolling.** `scripts/init.ps1` (or `init.sh`) is
   the supported path for a standard single-project init. Run it; don't recreate its
   work by hand.
4. **Match the shell to the tool.** On Windows the Bash tool is POSIX (git bash);
   PowerShell cmdlets fail there. Use the PowerShell tool for cmdlets.
5. **Don't fight the permission model.** `.claude/settings.json` ships as a
   `.template`; activating it is the script's / user's job, not something you force by
   writing allow-rules yourself.
6. **Verify, then clean.** `go build ./...` + `go test ./...`, then remove build
   artifacts before finishing.
7. **Keep agent files local.** In the *new* repo, git-ignore and untrack the
   agent-instruction files (`CLAUDE.md`, `AGENTS.md`, `.claude/`) so they stay on disk
   for tools but never reach the remote. See
   [Keep agent-instruction files local](#keep-agent-instruction-files-local-to-the-new-repo).

## What this template actually is

Confirm these facts by reading, not by assuming:

- It is a **token template**, not a ready project. Placeholder tokens
  (`__ProjectName__`, `__GoPackage__`, `__Author__`, `__AuthorEmail__`,
  `__GitHubOwner__`, `__Description__`, `__Year__`) appear in file *contents* (and,
  for `__ProjectName__`, potentially in file/folder *names*). `__ProjectName__`
  (the module slug) and `__GoPackage__` (the package identifier) are both *derived*
  from `--project-name`; the init script substitutes them.
- It is **single-package** by default: a library at the module root (`greeter.go`),
  with tests beside it (`greeter_test.go`). There is no `src/`/`tests/` split — Go
  packages live flat next to `go.mod`.
- Stack and conventions (all enforced — see `AGENTS.md`):
  - Go 1.25 (the floor in `go.mod`'s `go` directive); build/test with
    `go build ./...` / `go test ./...` (CI also runs `-race` on Linux).
  - Formatter: `gofmt` (tabs — `gofmt -l .` is a CI gate). `go vet ./...` must pass.
    Dependencies via `go.mod` + `go.sum`; `govulncheck` audits them.
- It uses **jujutsu (`jj`)** colocated with git. Drive VCS through `jj`.

## The happy path (standard single-project init)

1. **Read** `TEMPLATE.md` and this guide. Skim `AGENTS.md` / `CLAUDE.md`.
2. **Check the environment.** Run `scripts/check-env.ps1` (or `check-env.sh`). If it
   flags a missing tool, stop and offer the user the install commands it prints before
   continuing — don't init against an environment that can't build or test.
3. **Run the init script** with the values the user gave you:

   ```pwsh
   pwsh ./scripts/init.ps1 -ProjectName my-widgets -Author "Jane Doe" -GitHubOwner acme -Description "Widget toolkit"
   ```

   `-ProjectName` is required; the rest fall back to sensible defaults. The script
   derives the module slug + Go package id, substitutes tokens, activates
   `.claude/settings.json` from its `.template`, and deletes `TEMPLATE.md` (and itself
   unless `-KeepScript`).
4. **Verify**: `go build ./...` then `go test ./...`.
5. Replace the placeholder `Greet` function with the real API, delete or rewrite the
   sample test, fill in the `CLAUDE.md` "Architecture" section, and work through the
   `TEMPLATE.md` post-setup checklist.
6. **Git-ignore and untrack the agent-instruction files** — see
   [Keep agent-instruction files local](#keep-agent-instruction-files-local-to-the-new-repo).
7. Remove build artifacts before finishing.

If the user only asks to "initialize from the template" with a project name and
nothing structurally unusual, **this is the whole job.** Resist the urge to redesign.

## Tooling discipline (this is where agents slip)

- **Shell ≠ shell.** The Bash tool runs POSIX (git bash) here; PowerShell cmdlets
  fail in it. Use the PowerShell tool for cmdlets and the Bash tool only for POSIX
  commands. Prefer the dedicated Read / Glob / Grep tools for file inspection.
- **Don't over-batch.** A failure in one call of a parallel batch can cancel the
  rest. Never batch *exploratory* calls or calls that depend on each other with file
  writes. Read and ask first; write once you know the answers.
- **Permission model.** Do not write permission allow-rules into
  `.claude/settings.json` yourself — the self-modification classifier will block it.
- **VCS.** The repo is jj-colocated. Use `jj` commands; if you must use raw git,
  follow with `jj git import`.

## Keep agent-instruction files local to the new repo

This template *itself* tracks and ships its agent-instruction files — intentional,
must not change here. But a repository **created from** this template should keep
those files **out of its remote**. Make them *untracked* in the new repo: present on
disk, invisible to version control, never pushed. **The init script does not touch
tracking; this is a by-hand step, done before the first push.**

Which files: `CLAUDE.md`, `AGENTS.md`, and the `.claude/` directory (after init
activates `settings.json`). Two facts make it more than a one-line append:

1. The files start out *tracked*. An ignore rule never untracks an already-tracked
   file — you must also drop it from the index.
2. The `.gitignore` here **deliberately ships** `.claude/settings.json` (`.claude/*`
   plus negations). So append `.claude/` **after** that block (a later
   directory-exclude overrides the negations), or delete the negation lines.

```bash
printf '\n/CLAUDE.md\n/AGENTS.md\n.claude/\n' >> .gitignore
git rm -r --cached CLAUDE.md AGENTS.md .claude
git add .gitignore && git commit -m "Keep agent instructions local"
# jj-colocated: jj file untrack CLAUDE.md AGENTS.md .claude
```

Verify with `git status` (or `jj st`): the files must not appear as tracked, and a
`git push` must not carry them.

**Caveat — files already in the remote's history.** Untrack-and-ignore stops the
files going *forward*. If you created the repo via GitHub's **"Use this template"**,
the template's copies are *already* in the first commit on the remote — removing them
now drops them from the tip but they survive in history. For a repo that never
contained them, copy the template into a fresh `git init` and untrack before the
first commit.

## Updating this guide

When something goes wrong during an init — yours or one you review — do this in the
**same change set**, not as a follow-up:

1. Add an entry to [Failure log](#failure-log): the symptom, the root cause, and the
   rule (what to do instead).
2. If the lesson generalizes, fold it into the TL;DR or the relevant section above.
3. If `scripts/init.*`, `TEMPLATE.md`, `AGENTS.md`, or `CLAUDE.md` could be changed to
   make the mistake *impossible*, prefer that fix and note it in the entry.

## Failure log

Newest first. Each entry: **Symptom → Root cause → Rule.**

_(none yet)_
