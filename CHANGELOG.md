# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-11-15

### Added
- Initial release of AdaptiveBackfill library
- Single operation processor with health checks
- Batch operation processor with health checks
- Synchronous and asynchronous health monitoring modes
- PostgreSQL health checkers (long queries, hot I/O tables, temp file usage)
- Comprehensive test suite with 69 tests
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

[Unreleased]: https://github.com/YOUR_USERNAME/adaptive_backfill/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/YOUR_USERNAME/adaptive_backfill/releases/tag/v0.1.0
