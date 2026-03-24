# Gap Analysis -- Resolved Gaps

**Repository:** gitlab.com/devnw/zig/slog
**Created:** 2026-03-23
**Last updated:** 2026-03-24 (rev 2 -- pass 3 resolved items added)

---

This file tracks gaps that have been verified as resolved.
Move entries here from GAP_ANALYSIS.md when resolution evidence is confirmed.

---

## Resolved Gaps -- Security (GAP_ANALYSIS.md)

### SEC-0001: HTTPS URLs sent over plaintext TCP
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** https:// URLs are now rejected at `Context.init()` with `error.HttpsNotSupported`, preventing silent plaintext transmission. TLS implementation deferred as separate feature.
- **Evidence:** `src/sinks/http_sink.zig:64-67` -- returns error on https:// prefix; test `HttpSink rejects https URLs` validates behavior.

### SEC-0002: stderrHandler returns dangling pointer (use-after-free)
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** API changed from returning `struct { ctx, handler }` to accepting `*Context` out-parameter. Caller owns the Context memory; handler references caller-owned storage.
- **Evidence:** `src/slogz.zig:106-116` -- `stderrHandler(ctx: *text.Context, level: Level) Handler`; test `stderrHandler caller-owned context avoids dangling pointer`.

### SEC-0003: HTTP header injection via unvalidated custom headers
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** Headers containing control characters (CR, LF, NUL) are skipped during HTTP request construction via `containsControlChars()` check.
- **Evidence:** `src/sinks/http_sink.zig:160` -- `if (containsControlChars(header.name) or containsControlChars(header.value)) continue;`

### SEC-0005: isSensitiveKey() dead code; no auto-redaction occurs
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** `redact.isSensitiveKey()` wired into all handler `writeAttr` functions: text, json, syslog, journald, windows_eventlog, rotating_file, and all network sinks.
- **Evidence:** `src/handlers/text_handler.zig:107-111`, `src/handlers/json_handler.zig:143-147`, `src/handlers/journald.zig:124-128`, etc.; tests `TextHandler auto-redacts sensitive keys`, `JSONHandler auto-redacts sensitive keys`.

### SEC-0006: Log injection via unsanitized messages
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** New `sanitize.sanitizeOutput()` function escapes `\n`, `\r`, `\t`, and control characters (0x00-0x1F). Applied to message writes in text, syslog, rotating_file, and journald handlers.
- **Evidence:** `src/util/sanitize.zig:138-160` -- `sanitizeOutput` implementation; `src/handlers/text_handler.zig:72` -- `sanitize.sanitizeOutput(writer, rec.message)`; test `sanitizeOutput`.

### SEC-0007: Path traversal in rotating file handler
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 05c6a16)
- **Resolution:** Path traversal validation added at `Context.init()` time; paths containing `..` components are rejected.
- **Evidence:** `src/handlers/rotating_file.zig` -- path validation at init.

### SEC-0009: Rotating file handler missing secret redaction
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 05c6a16)
- **Resolution:** Rotating file handler now uses shared `writeValue` with proper `.secret` handling via `redact.REDACTED` and `isSensitiveKey()` auto-redaction.
- **Evidence:** `src/handlers/rotating_file.zig` -- writeValue and writeAttr functions with redaction.

### SEC-0010: Text handler string values unescaped
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** String attribute values now pass through `sanitize.sanitizeOutput()`, escaping newlines and control characters.
- **Evidence:** `src/handlers/text_handler.zig:122` -- `try sanitize.sanitizeOutput(writer, s);`

### SEC-0011: Global fatal_hook race condition
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** `fatal_hook` changed from `pub var` to private `var` with atomic `getFatalHook()`/`setFatalHook()` accessors using acquire/release ordering.
- **Evidence:** `src/logger.zig:30-39` -- atomic load/store functions; `src/logger.zig:164` -- `getFatalHook()(&rec)`; test `fatal_hook uses atomic access`.

### SEC-0012: Secret values plaintext in memory
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** Limitation documented in `Secret` struct doc comment. Memory scrubbing deferred as defense-in-depth improvement.
- **Evidence:** `src/value.zig:12-15` -- doc comment: "Note: The secret value is stored in plaintext in process memory."

### SEC-0013: Async handler drops secret attributes silently
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Resolution:** QueuedRecord now serializes all attributes via `StoredAttr` with type-aware `serializeValue()`. Secret values are serialized as `[REDACTED]` at serialization time, never stored as plaintext in the queue.
- **Evidence:** `src/internal/queue.zig:46-112` -- `StoredAttr` and `serializeValue()`; `.secret` case serializes `redact.REDACTED`.

### SEC-0014: Gitleaks blanket exclusion of examples/tests
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** `.gitleaks.toml` allowlist narrowed from `examples/.*` + `tests/.*` to only `examples/secret_redaction\.zig`.
- **Evidence:** `.gitleaks.toml:9-11` -- single specific path exclusion.

### SEC-0015: SECURITY.md false claims (fuzz testing, no external C deps)
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** Fuzz testing claim removed. Dependency claim updated to: "External Zig dependencies: json and spice (no C dependencies)". Security email updated to correct address.
- **Evidence:** `SECURITY.md:35` -- corrected dependency claim; fuzz testing line removed.

### SEC-0017: No CI build/test pipeline active
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** Added `build`, `test`, and `format-check` stages to `.gitlab-ci.yml` using `registry.gitlab.com/devnw/zig/ci:0.15.2` image. Stale Zig version comment removed.
- **Evidence:** `.gitlab-ci.yml:35-60` -- build, test, format-check job definitions.

### SEC-0018: HTTP status check too permissive
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** HTTP status check changed from substring search for `" 2"` to positional check at index 9 of the response line (`resp_buf[9] == '2'`), matching the HTTP/1.1 status line format.
- **Evidence:** `src/sinks/http_sink.zig:180-182`; test `HttpSink HTTP status check position`.

### SEC-0019: Journald fallback unsanitized stderr
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** Journald fallback now (1) writes to an 8KB `fixedBufferStream` reducing syscalls to a single `writeAll`, and (2) applies `sanitize.sanitizeOutput()` to messages and auto-redacts sensitive keys.
- **Evidence:** `src/handlers/journald.zig:143-162` -- buffered stderr output with sanitization.

---

## Resolved Gaps -- Quality (QUALITY_GAP_ANALYSIS.md)

### Rank 1: AsyncHandler drops ALL record attributes
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Resolution:** QueuedRecord redesigned with `StoredAttr[32]` array. `fromRecord()` serializes all attribute key/value pairs; worker thread restores them via `toAttr()`. All Value types handled including secrets.
- **Evidence:** `src/internal/queue.zig:46-112`; `src/handlers/async_handler.zig` worker loop; test verifies attrs round-trip.

### Rank 2: stderrHandler / stderrJsonHandler return dangling pointers
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Evidence:** See SEC-0002 above.

### Rank 3: AsyncHandler.Context.init thread receives dangling pointer
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Resolution:** Thread spawn deferred from `init()` to explicit `startWorker()` call. Caller creates Context, stores at stable address, then starts worker.
- **Evidence:** `src/handlers/async_handler.zig` -- `startWorker()` method.

### Rank 5: CI pipeline has no build or test stage
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Evidence:** See SEC-0017 above.

### Rank 6: Network sinks (TCP, UDP, HTTP) drop all record attributes
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** All three sinks now iterate `rec.attrs` and serialize them into JSON output with auto-redaction for sensitive keys.
- **Evidence:** `src/sinks/tcp_sink.zig`, `src/sinks/udp_sink.zig`, `src/sinks/http_sink.zig` -- attrs serialization loop in handle().

### Rank 7: QueuedRecord i64 serialization broken
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Resolution:** Replaced broken `formatInt` + discard pattern with `serializeValue()` using `std.fmt.bufPrint("{d}", .{i})`.
- **Evidence:** `src/internal/queue.zig:75-82` -- `serializeValue` i64 case.

### Rank 8: formatBackupPath buffer aliasing causes rotation failure
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 05c6a16)
- **Resolution:** Added `path_buf2` to Context; `formatBackupPath` uses separate buffers for old and new paths to avoid aliasing.
- **Evidence:** `src/handlers/rotating_file.zig:51` -- `path_buf2` field.

### Rank 9: writeValue duplicated 3x across handlers
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** All handlers updated with consistent writeValue including @errorName guard, hex lookup table, secret redaction, and sanitizeOutput. Shared patterns applied to journald, windows_eventlog, syslog.
- **Evidence:** Consistent writeValue in `text_handler.zig`, `journald.zig`, `windows_eventlog.zig`, `syslog_rfc5424.zig`.

### Rank 10: JSON encoding duplicated 3x in network sinks
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** All three sinks now include attrs serialization with consistent JSON encoding patterns and auto-redaction.
- **Evidence:** `src/sinks/tcp_sink.zig`, `src/sinks/udp_sink.zig`, `src/sinks/http_sink.zig`.

### Rank 11: @errorName guard missing in 4 of 5 handlers
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** Raw-value guard (`@intFromError(e) == 0` check) applied to json_handler, syslog_rfc5424, journald, and windows_eventlog.
- **Evidence:** `src/handlers/json_handler.zig:175-180`, `src/handlers/syslog_rfc5424.zig`, `src/handlers/journald.zig`, `src/handlers/windows_eventlog.zig`.

### Rank 12: Silent error swallowing in rotating_file.zig
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 05c6a16)
- **Resolution:** Error catch blocks now call `metrics.global.incErrors()` to track failures instead of silently swallowing them.
- **Evidence:** `src/handlers/rotating_file.zig` -- `catch` blocks with `metrics.global.incErrors()`.

### Rank 13: LoggerOptions re-exported but does not exist
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** Phantom `LoggerOptions` re-export removed from slogz.zig.
- **Evidence:** `src/slogz.zig` -- line removed.

### Rank 14: FixedClock mechanism non-functional
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** FixedClock now properly wires its `timestamp_us` field into the returned clock function pointer.
- **Evidence:** `src/internal/clock.zig` -- FixedClock implementation.

### Rank 15: Syslog handler writeSDValue missing @errorName guard
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Evidence:** See Rank 11 above (same root cause).

### Rank 17: rotating_file.zig imports text_handler but never uses it
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 05c6a16)
- **Resolution:** Unused `text_handler` import removed; replaced with direct imports for Value, Secret, redact.
- **Evidence:** `src/handlers/rotating_file.zig:23-24` -- new imports replacing dead text_handler import.

### Rank 18: epochDays / ymdToEpochDay duplicated
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** clock.zig now imports epoch-day functions from rfc3339.zig; duplication removed.
- **Evidence:** `src/internal/clock.zig` and `src/fmt/rfc3339.zig`.

### Rank 19: BaseHandlerContext defined but never used
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** `BaseHandlerContext` removed from handler.zig (32 lines of dead code).
- **Evidence:** `src/handler.zig` -- 32-line deletion in diff.

### Rank --: Metrics.incReconnections() never called
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit ec068d0)
- **Resolution:** `incReconnections()` wired into tcp_sink.zig reconnection logic.
- **Evidence:** `src/sinks/tcp_sink.zig` and `src/metrics/metrics.zig`.

---

## Resolved Gaps -- Performance (PERF_GAP_ANALYSIS.md)

### PERF-004: Missing connect/read timeouts
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** `SO_RCVTIMEO` and `SO_SNDTIMEO` set via `setsockopt` in both TCP and HTTP sinks using configured timeout values.
- **Evidence:** `src/sinks/tcp_sink.zig:91-100` -- `applySocketTimeouts()`; `src/sinks/http_sink.zig:138-145`.

### PERF-005: Async handler drops ALL attributes
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Evidence:** See Quality Rank 1 above.

### PERF-007: HTTP/TCP/UDP sinks omit attrs from JSON output
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Evidence:** See Quality Rank 6 above.

### PERF-009: HTTP sink silently accepts HTTPS but sends cleartext
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Evidence:** See SEC-0001 above.

### PERF-010: No circuit breaker for TCP sink failures
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** Circuit breaker with `circuit_breaker_threshold=3` and `circuit_cooldown_ms=30000` added to TCP sink. After 3 consecutive failures, fast-fails for 30s cooldown.
- **Evidence:** `src/sinks/tcp_sink.zig:44-49` -- circuit breaker constants; `:88-91` -- fast-fail check; `:113-116` -- circuit open on threshold.

### PERF-011: Journald fallback makes 14+ stderr syscalls per record
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Evidence:** See SEC-0019 above.

### PERF-012: Per-byte hex encoding via fmt.print in 4 handlers
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** Replaced `writer.print("{x:0>2}", .{byte})` with precomputed `hex_chars` lookup table and bulk `writeAll(&[2]u8{...})`.
- **Evidence:** `src/handlers/text_handler.zig:136-137` -- hex_chars lookup.

### PERF-013: Rotating file handler lacks write buffering
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 05c6a16)
- **Resolution:** Added 8KB `write_buf` with `write_buf_pos` tracking; flushes on buffer full, rotation, or explicit flush.
- **Evidence:** `src/handlers/rotating_file.zig:50-51` -- `write_buf` and `write_buf_pos` fields.

### PERF-014: Async handler flush uses busy-wait polling
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Resolution:** Replaced `sleep(1ms)` polling loop with `queue.waitEmpty()` using condition-variable-based signaling.
- **Evidence:** `src/handlers/async_handler.zig` -- `flush()` uses `ctx.queue.waitEmpty(wait_ms)`.

### PERF-015: Async handler double-locks on enqueue (TOCTOU race)
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 3fcd5a5)
- **Resolution:** Removed external mutex lock around len check. Now uses `queue.droppedCount()` before/after `pushDropOldest()` to atomically detect drops.
- **Evidence:** `src/handlers/async_handler.zig` -- enqueue uses `droppedCount()` comparison.

### PERF-016: JSON handler pre-validates all attrs before serializing
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (commit 0ed8afe)
- **Resolution:** Pre-validation loop removed. `isValidJson()` check for f64 NaN/Inf done inline during `writeJsonValue()` serialization.
- **Evidence:** `src/handlers/json_handler.zig:49` -- pre-validation loop removed; `:157-161` -- inline NaN/Inf check.

---

## Won't Do Items

### SEC-0004: TCP/UDP sinks transmit plaintext only
- **Status:** Won't Do
- **Reason:** TLS/DTLS implementation is a significant effort requiring either `std.crypto.tls` integration or a C TLS library. The https:// URL rejection (SEC-0001) provides an interim safety net for the HTTP sink. TCP/UDP sinks are clearly documented as plaintext-only.

### SEC-0016: No authentication for TCP/UDP network sinks
- **Status:** Won't Do
- **Reason:** mTLS and auth token support require significant infrastructure. Network sinks are designed for trusted internal networks. Documentation notes the limitation.

### Quality Rank 4: withAttrs/withGroup universally no-op
- **Status:** Won't Do
- **Reason:** Requires allocator-aware context cloning across all 9 handler types. This is a large architectural change tracked separately via issues #8 and #17.

### Quality Rank 16: VTable boilerplate duplicated 9x
- **Status:** Won't Do
- **Reason:** A comptime mixin or default VTable depends on the withAttrs/withGroup implementation (Rank 4). Deferred until that work is complete.

### PERF-001: HTTP sink creates new TCP connection per record
- **Status:** Won't Do
- **Reason:** Connection pooling with keep-alive requires significant effort including connection health checks, staleness detection, and graceful reconnection. Tracked as separate feature.

### PERF-002: TCP sink holds mutex during retry+sleep
- **Status:** Won't Do
- **Reason:** Lock scope reduction requires careful refactoring to avoid data races on the shared stream. Partially mitigated by circuit breaker (PERF-010) which fast-fails after 3 consecutive failures.

### PERF-003: HTTP sink holds mutex during full HTTP round-trip+retry
- **Status:** Won't Do
- **Reason:** Same as PERF-002. Partially mitigated by socket timeouts (PERF-004) which limit the worst-case block time.

### PERF-006: All handlers hold mutex during format+I/O
- **Status:** Won't Do
- **Reason:** Reducing lock scope from format+write to write-only requires thread-local or per-call buffers with careful lifetime management. Tracked as separate optimization.

### PERF-008: QueuedRecord ~3.8KB per entry
- **Status:** Open
- **Reason:** Variable-length arena allocation would reduce memory but adds complexity. Current fixed-buffer approach is correct and simple. Tracked as separate optimization.

### PERF-017: parallel.zig dead code adds build-time cost
- **Status:** Open
- **Reason:** The parallel module was intentionally added as a published module (commits 1fa06e6, 1041b15). Build-time impact is minor. No action taken.

### PERF-018: Benchmark suite lacks statistical rigor
- **Status:** Won't Do
- **Reason:** Benchmark infrastructure improvement is a separate effort. Current benchmarks serve as smoke tests.

### PERF-019: No multi-threaded benchmarks
- **Status:** Won't Do
- **Reason:** Multi-threaded benchmark infrastructure is a separate effort.

### PERF-020: Metrics struct potential false sharing
- **Status:** Won't Do
- **Reason:** Minor optimization. Cache-line padding would increase struct from 56 to ~448 bytes. Deferred as low priority.

### PERF-021: getPool() acquires mutex on every call
- **Status:** Won't Do
- **Reason:** parallel.zig is optional and not on the hot path for any handler. Double-checked locking optimization deferred.

---

## Resolved Gaps -- Pass 3 (2026-03-24)

### SEC-0006: Log injection via unsanitized messages (rotating_file.zig -- reopened, now fixed)
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** rotating_file.zig now imports `sanitize` module and applies `sanitize.sanitizeOutput()` to `rec.message` at line 298, `sanitize.sanitizeKey()` to attribute keys at line 305, and shared `writeTextValue()` for attribute values at line 312.
- **Evidence:** `src/handlers/rotating_file.zig:298` -- `sanitize.sanitizeOutput(writer, rec.message)`; `src/handlers/rotating_file.zig:305` -- `sanitize.sanitizeKey(&key_buf, attr.key)`; `src/handlers/rotating_file.zig:312` -- `writeTextValue(writer, attr.value)`.

### SEC-0009: Rotating file handler missing isSensitiveKey() auto-redaction (reopened, now fixed)
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** rotating_file.zig now calls `redact.isSensitiveKey(attr.key)` in the attribute loop at line 309 and outputs `redact.REDACTED` for matching keys, consistent with all other handlers.
- **Evidence:** `src/handlers/rotating_file.zig:309` -- `if (redact.isSensitiveKey(attr.key))`.

### SEC-0020: Windows Event Log stderr fallback missing sanitizeOutput()
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** windows_eventlog.zig stderr fallback now uses buffered output with `sanitize.sanitizeOutput()` on message content and `sanitize.sanitizeKey()` on attribute keys. `deprecatedWriter()` removed from this handler.
- **Evidence:** `src/handlers/windows_eventlog.zig:107` -- `sanitize.sanitizeOutput(writer, rec.message)`; `:113` -- `sanitize.sanitizeKey(&key_buf, attr.key)`; `:145` -- `sanitize.sanitizeOutput(stderr_writer, ctx.source_name)`.

### SEC-0021: Journald stderr fallback unsanitized attribute keys
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Journald stderr fallback path now applies `sanitize.sanitizeKey()` to attribute keys, consistent with the native journald path.
- **Evidence:** `src/handlers/journald.zig:166` -- `const stderr_key = sanitize.sanitizeKey(&stderr_key_buf, attr.key)`.

### SEC-0022: Windows Event Log unsanitized attribute keys
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** windows_eventlog.zig now applies `sanitize.sanitizeKey()` to attribute keys in the main write path and stderr fallback.
- **Evidence:** `src/handlers/windows_eventlog.zig:113` -- `const key = sanitize.sanitizeKey(&key_buf, attr.key)`.

### SEC-0023: Syslog writeSDString no control character escaping
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** `writeSDString()` now escapes control characters (0x00-0x08, 0x0a-0x1f) as `\xHH` using hex_chars lookup table. Tab (0x09) is preserved per RFC 5424.
- **Evidence:** `src/handlers/syslog_rfc5424.zig:268-284` -- switch on `0x00...0x08, 0x0a...0x1f` writes `\\x` followed by hex_chars lookup.

### SEC-0024: Gitleaks allowlist incomplete
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** `.gitleaks.toml` allowlist extended to include `examples/json_logging.zig` and `tests/accept.zig` as specific file-level entries.
- **Evidence:** `.gitleaks.toml:9-13` -- three file-specific allowlist paths.

### Q-21: writeJsonValue() duplicated verbatim across 4 files
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Extracted to `src/fmt/json_value.zig` with canonical `writeJsonValue()` function. All 4 consumers (json_handler.zig, tcp_sink.zig, udp_sink.zig, http_sink.zig) import the shared function.
- **Evidence:** `src/fmt/json_value.zig:19` -- shared `writeJsonValue`; `src/handlers/json_handler.zig:22` -- import; `src/sinks/tcp_sink.zig:23`, `src/sinks/udp_sink.zig:23`, `src/sinks/http_sink.zig:24` -- imports.

### Q-22: writeValue() behavioral drift across 4 text-mode copies
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Extracted to `src/fmt/text_value.zig` with canonical `writeTextValue()` function. All 4 text-mode handlers (text_handler.zig, journald.zig, windows_eventlog.zig, rotating_file.zig) import the shared function. Canonical behavior: f64 with `.6` precision, hex encoding via lookup table, `<marshaler>` for marshalers.
- **Evidence:** `src/fmt/text_value.zig:27` -- shared `writeTextValue`; `src/handlers/text_handler.zig:21`, `src/handlers/journald.zig:20`, `src/handlers/windows_eventlog.zig:20`, `src/handlers/rotating_file.zig:26` -- imports.

### Q-23: rotating_file.zig missing sanitizeOutput() on .str values
- **Status:** Closed / Implemented (resolved by SEC-0006 fix)
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Duplicate of SEC-0006 rotating_file fix. The shared `writeTextValue()` function handles .str values with proper formatting. The rotating_file handler now uses this shared function.
- **Evidence:** `src/handlers/rotating_file.zig:312` -- `writeTextValue(writer, attr.value)`.

### Q-24: rotating_file.zig missing close vtable entry
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Added `close` function at line 353 delegating to `Context.deinit()`, wired into vtable at line 364.
- **Evidence:** `src/handlers/rotating_file.zig:353-355` -- `fn close(ctx_ptr: *anyopaque) void { ctx.deinit(); }`; `:358-365` -- vtable includes `.close = close`.

### Q-25: incReconnections() has zero callers (regression)
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** `metrics.global.incReconnections()` wired into tcp_sink.zig reconnection path at line 139, called on successful reconnection in writeWithRetry.
- **Evidence:** `src/sinks/tcp_sink.zig:139` -- `metrics.global.incReconnections()`.

### Q-26: UDP sink serializes under mutex
- **Status:** Closed / Implemented (resolved by PERF-022 fix)
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Duplicate of PERF-022. JSON formatting moved outside mutex in udp_sink.zig; mutex acquired only for the send operation.
- **Evidence:** `src/sinks/udp_sink.zig` -- formatting happens before mutex lock.

### Q-28: error.UnsupportedPlatform not in HandlerError
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Changed `error.UnsupportedPlatform` to `error.FeatureDisabled` in both journald.zig and windows_eventlog.zig. `FeatureDisabled` is in the `HandlerError` error set.
- **Evidence:** `src/handler.zig:22` -- `FeatureDisabled` in HandlerError; `src/handlers/journald.zig:73` -- `return error.FeatureDisabled`; `src/handlers/windows_eventlog.zig:96` -- `return error.FeatureDisabled`.

### PERF-022: UDP sink holds mutex during format+send
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** JSON formatting moved outside mutex. Mutex is now acquired only for the `ctx.send()` call, consistent with TCP and HTTP sinks.
- **Evidence:** `src/sinks/udp_sink.zig` -- formatting outside `mutex.lock()` scope.

### PERF-024: rotating_file per-byte hex encoding via writer.print
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** rotating_file now uses the shared `writeTextValue()` from `src/fmt/text_value.zig` which uses a precomputed `hex_chars` lookup table for hex encoding, consistent with the PERF-012 fix applied to other handlers.
- **Evidence:** `src/fmt/text_value.zig:42-44` -- `hex_chars` lookup table; `src/handlers/rotating_file.zig:26` -- imports writeTextValue.

### PERF-028: Journald stderr fallback runs unconditionally on Linux
- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 3)
- **Resolution:** Field-building code guarded by `comptime native_sendv_available` flag (currently false). When native_sendv is unavailable, the handler skips the 16KB field-building code and goes straight to the stderr fallback, saving ~25KB of stack allocation.
- **Evidence:** `src/handlers/journald.zig:29` -- `const native_sendv_available = false`; `:84` -- `if (native_sendv_available)` comptime guard around field-building.

### PERF-025: Stack allocations 8-25KB per log call
- **Status:** Won't Do
- **Reason:** Reducing stack buffer sizes without profiling data risks truncation of legitimate large records. The zero-allocation stack-based design is intentional for performance. Requires actual profiling with production workloads to safely determine optimal buffer sizes.

### PERF-027: Multi-handler re-formats same Record per child
- **Status:** Won't Do
- **Reason:** Architecturally expected behavior. Pre-formatting would require handler-specific format negotiation. Each child handler may use a different output format (text vs JSON vs syslog).

---

## ID Registry

The following Gap-IDs have been assigned. Never reuse an ID.

| Range | Status |
|-------|--------|
| GAP-0001 through GAP-0025 | Assigned (see GAP_ANALYSIS.md) |
| GAP-0036 | Assigned (SEC-0020, see GAP_ANALYSIS.md) |
| SEC-0001 through SEC-0024 | Assigned (see GAP_ANALYSIS.md) |
| PERF-001 through PERF-028 | Assigned (see PERF_GAP_ANALYSIS.md) |
| Quality Rank 1-20, Q-21 through Q-28 | Assigned (see QUALITY_GAP_ANALYSIS.md) |
| GAP-0026 through GAP-0035 | Available |
| GAP-0037+ | Available |
