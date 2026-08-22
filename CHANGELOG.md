# Changelog

All notable changes to **__ProjectName__** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
-

### Changed
-

### Fixed
- Initializers now validate release identity values before mutation, preventing unsafe workflow text and invalid GitHub owner segments in generated modules.
- Initializers now perform token substitution in one pass, preserving token-shaped author and email values when descriptions or years contain replacement text.
- Made PowerShell and POSIX template initialization failure-safe with staged changes,
  rollback protection, and automatic recovery of a single interrupted-rollback
  backup before retry; ambiguous or conflicting recovery fails closed.
- Restored token substitution and token-named path handling for ordinary files under
  `scripts/` while keeping the live directory and initializer files in place and
  unchanged until final cleanup, including when initialization runs from Git Bash.
- Initializers now preserve an existing `.claude/settings.json` byte-for-byte on
  first run and retry instead of replacing it with the shipped settings template.

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
