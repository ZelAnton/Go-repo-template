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
- Made PowerShell and POSIX template initialization failure-safe with staged changes,
  rollback protection, and automatic recovery of a single interrupted-rollback
  backup before retry; ambiguous or conflicting recovery fails closed.
- Restored token substitution and token-named path handling for ordinary files under
  `scripts/` while keeping the initializer files unchanged until final cleanup.

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
