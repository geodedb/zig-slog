# Slog - Structured Logging Library for Zig
# Makefile for development convenience

.PHONY: all build test test-unit clean check fmt dev ci install help
.PHONY: test-debug test-release-safe test-release-fast test-release-small test-all-optimizations
.PHONY: run

# Default target
all: build test

# Build the library
build:
	zig build

# Run all tests
test:
	zig build test --summary all

# Run tests with verbose output
test-unit:
	zig build test --summary all 2>&1 | head -100

# Clean build artifacts
clean:
	rm -rf zig-out zig-cache .zig-cache

# Syntax check without building
check:
	zig build --help > /dev/null

# Format source code
fmt:
	zig fmt src/ build.zig

# Check formatting (for CI)
fmt-check:
	zig fmt --check src/ build.zig

# Development workflow: format, check, and test
dev: fmt check test-unit

# Full CI pipeline
ci: fmt-check build test

# Run the example application
run:
	zig build run

# =============================================================================
# Optimization-specific test targets
# =============================================================================

test-debug:
	zig build test -Doptimize=Debug --summary all

test-release-safe:
	zig build test -Doptimize=ReleaseSafe --summary all

test-release-fast:
	zig build test -Doptimize=ReleaseFast --summary all

test-release-small:
	zig build test -Doptimize=ReleaseSmall --summary all

test-all-optimizations: test-debug test-release-safe test-release-fast test-release-small

# =============================================================================
# Cross-compilation targets
# =============================================================================

.PHONY: cross-linux-arm cross-linux-arm64 cross-linux-riscv64
.PHONY: cross-windows-x64 cross-windows-arm64
.PHONY: cross-macos-x64 cross-macos-arm64
.PHONY: cross-freebsd cross-netbsd
.PHONY: cross-all

cross-linux-arm:
	zig build -Dtarget=arm-linux-gnueabihf

cross-linux-arm64:
	zig build -Dtarget=aarch64-linux-gnu

cross-linux-riscv64:
	zig build -Dtarget=riscv64-linux-gnu

cross-windows-x64:
	zig build -Dtarget=x86_64-windows-gnu

cross-windows-arm64:
	zig build -Dtarget=aarch64-windows-gnu

cross-macos-x64:
	zig build -Dtarget=x86_64-macos

cross-macos-arm64:
	zig build -Dtarget=aarch64-macos

cross-freebsd:
	zig build -Dtarget=x86_64-freebsd

cross-netbsd:
	zig build -Dtarget=x86_64-netbsd

cross-all: cross-linux-arm cross-linux-arm64 cross-linux-riscv64 \
           cross-windows-x64 cross-windows-arm64 \
           cross-macos-x64 cross-macos-arm64 \
           cross-freebsd cross-netbsd

# =============================================================================
# Help
# =============================================================================

help:
	@echo "Slog - Structured Logging Library for Zig"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development targets:"
	@echo "  all                    Build and test (default)"
	@echo "  build                  Build the library"
	@echo "  test                   Run all tests"
	@echo "  test-unit              Run tests with limited output"
	@echo "  clean                  Remove build artifacts"
	@echo "  check                  Syntax check"
	@echo "  fmt                    Format source code"
	@echo "  fmt-check              Check formatting"
	@echo "  dev                    Format, check, and test"
	@echo "  ci                     Full CI pipeline"
	@echo "  run                    Run example application"
	@echo ""
	@echo "Optimization tests:"
	@echo "  test-debug             Test with Debug optimization"
	@echo "  test-release-safe      Test with ReleaseSafe optimization"
	@echo "  test-release-fast      Test with ReleaseFast optimization"
	@echo "  test-release-small     Test with ReleaseSmall optimization"
	@echo "  test-all-optimizations Run all optimization tests"
	@echo ""
	@echo "Cross-compilation:"
	@echo "  cross-linux-arm        ARM 32-bit Linux"
	@echo "  cross-linux-arm64      ARM64 Linux"
	@echo "  cross-linux-riscv64    RISC-V 64-bit Linux"
	@echo "  cross-windows-x64      Windows x86_64"
	@echo "  cross-windows-arm64    Windows ARM64"
	@echo "  cross-macos-x64        macOS x86_64"
	@echo "  cross-macos-arm64      macOS ARM64"
	@echo "  cross-freebsd          FreeBSD x86_64"
	@echo "  cross-netbsd           NetBSD x86_64"
	@echo "  cross-all              All cross-compilation targets"
	@echo ""
	@echo "  help                   Show this help message"
