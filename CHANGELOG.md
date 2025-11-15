# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2025-11-15

### Fixed
- Fixed `DefaultPgHealthCheckers.pg_health_checks/1` to return zero-argument functions compatible with health checker framework (changed from arity 1 to returning closures with arity 0)

## [0.2.0] - 2025-11-15

### Changed
- Add AdaptiveBackfill namespace prefix to all modules for proper package organization
- Update all module references to use full namespaced paths
- Update all test files to use module aliases

## [0.1.0] - 2025-11-15

### Added
- Initial release of AdaptiveBackfill library
- Single operation processor with health checks
- Batch operation processor with health checks
- Synchronous and asynchronous health monitoring modes
- PostgreSQL health checkers (long queries, hot I/O tables, temp file usage)
- CI/CD pipeline with GitHub Actions
- Code formatting and linting with Credo
- Docker Compose setup for testing with PostgreSQL

### Features
- `AdaptiveBackfill.run/1` - Main entry point for running operations
- `SingleOperationProcessor` - Process single operations with health check callbacks
- `BatchOperationProcessor` - Process batches with automatic health checks
- `SyncMonitor` - Synchronous health check monitoring
- `AsyncMonitor` - Background health check monitoring with GenServer
- `MonitorResultEvaluator` - Evaluate health check results and determine halt conditions
- Mimic-based mocking for testability

[Unreleased]: https://github.com/ArtAhmetaj/adaptive_backfill/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/ArtAhmetaj/adaptive_backfill/compare/v0.1.0...v0.2.1
[0.1.0]: https://github.com/ArtAhmetaj/adaptive_backfill/releases/tag/v0.1.0
