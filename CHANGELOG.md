# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.16] - 2026-11-15

### Changed

- json v0.1.20 -> v0.1.21 and thread-pool v0.2.9 -> v0.2.11, so slog and its
  consumers resolve a single thread-pool (SONNY-6630).

## [0.1.14] - 2026-10-11

### Planned
- TLS/HTTPS support for HTTP sink
- Log sampling and rate limiting

### Changed

- json v0.1.19 and thread-pool v0.2.8 (single thread-pool in the graph).
- CI: create GitLab Releases with the job token.

## [0.1.13] - 2026-09-12

### Changed

- Converge thread_pool v0.2.7, fips v0.1.1, protobuf v0.1.5 (GAP-0838 diamond sync).

## [0.1.11] - 2026-06-12

### Fixed
- Compare-bench regression gate restored under Zig 0.16 (PERF-043)
- Multi-handler fan-out dispatches sequentially without per-record overhead, fixing a ~200x regression (PERF-039)
- Async queue worker woken via condvar; dead condvars removed and enqueue uses a single lock (PERF-040, PERF-041, PERF-042)
- Rotating log files are created with 0o600 permissions (SEC-0034)
- Log-path symlink guard with absolute-path opt-in (SEC-0037)
- Full-key redaction scan covers all sensitive key patterns (SEC-0038)
- Oversized records are truncated with a marker and counted in the new `slogz_records_truncated_total` metric (SEC-0039)
- All 8 examples ported to Zig 0.16 and compile-checked in CI (Q-48)

## [0.1.0] - 2026-01-24

### Added
- **Core Logging Framework**
  - High-performance structured logging inspired by Go's slog
  - Multiple log levels: trace, debug, info, warn, error, fatal
  - Zero-allocation for disabled/simple log calls
  - Stable key order in output

- **Output Handlers**
  - Text handler (human-readable format)
  - JSON handler (structured JSON output with stable key ordering)
  - Syslog RFC5424 handler
  - Rotating file handler with size-based rotation and backup management
  - Discard handler (for benchmarking)

- **Async Handler**
  - Background thread delivery
  - Bounded queue with configurable size
  - Drop-oldest policy with metrics tracking
  - Optional blocking mode with timeout

- **Network Sinks**
  - TCP with automatic reconnection and retry/backoff
  - UDP (fire-and-forget)
  - HTTP POST with configurable retry

- **Platform-Specific Handlers** (feature-gated)
  - Journald support for Linux (requires libsystemd)
  - Windows Event Log support

- **Additional Features**
  - Prometheus-style metrics export
  - i18n catalog for message translation
  - Secret redaction (sensitive values automatically redacted in output)
  - Key sanitization for structured output
  - JSON library integration for serialization in handlers and sinks

- **Attribute Types**
  - string, int, uint, float, boolean
  - error type support
  - secret type (automatically redacted)

- **Build System**
  - Feature flags for optional platform handlers
  - zig-package component for dependency management

### Changed
- Removed 'zig' prefix from library name (now just 'slog')
- Refactored to use JSON library for serialization
- Updated json dependency to use GitLab archive URL

### Fixed
- Correct Zig download URL format for 0.15.x compatibility
- Added libsystemd-dev for journald tests
- ARM32 build configuration

### Security
- Apache-2.0 open source license
- GitLab native Secret Detection integration
- Advanced SAST and Dependency Scanning enabled
- Gitleaks allowlist for test data and implementation details

### Infrastructure
- CI pipeline using devnw/ci-catalog components (v1.7.1)
- SBOM generation
- Coverage support
- Issue templates for bug reports, features, and questions
- Merge request template

[Unreleased]: https://gitlab.com/devnw/zig/slog/-/compare/v0.1.0...HEAD
[0.1.0]: https://gitlab.com/devnw/zig/slog/-/releases/v0.1.0
