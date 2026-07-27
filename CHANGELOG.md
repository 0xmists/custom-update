# Changelog

All notable changes to the custom-update skill will be documented in this file.

## [1.0.0] - 2026-07-27

### Added

- Initial release of the custom-update skill.
- Phase-based update workflow (Backup → Update → Apply → Verify → Publish).
- Hermes adapter layer to isolate Hermes-specific commands, paths, and version detection.
- Backup creation with Git tag and bundle export.
- Backup reuse detection via state fingerprint matching.
- Interrupted update resume with persistent state tracking.
- Retention policy with configurable `max_backups`.
- Configurable update providers (hermes-update, git-pull, custom).
- Automated test suite (unit, integration, regression).
- GitHub Actions CI pipeline (ShellCheck, bash -n, full test suite).
- Comprehensive documentation (README, ARCHITECTURE.md).

### Changed

- Refactored duplicated update provider logic into shared modules.
- Removed hardcoded Hermes installation paths; now resolved via adapter.
- Extracted verification logic into standalone `verify.sh` module.

### Fixed

- N/A — initial release.

---

## [Unreleased]

### Planned

- Additional update providers (e.g., custom script support).
- Web-based status dashboard.
- Backup checksum verification (SHA-256).
- Parallel patch application for large patch sets.