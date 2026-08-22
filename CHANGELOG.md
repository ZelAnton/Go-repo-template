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

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
