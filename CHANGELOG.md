# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- TLS/HTTPS support for HTTP sink
- DNS hostname resolution
- Multi-handler fan-out
- Log sampling and rate limiting

## [0.1.0] - Initial Release

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

[Unreleased]: https://gitlab.com/devnw/zig/slog/-/compare/main...HEAD
[0.1.0]: https://gitlab.com/devnw/zig/slog/-/commits/main
