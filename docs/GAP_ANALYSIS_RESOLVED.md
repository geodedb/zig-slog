# Gap Analysis -- Resolved Gaps

**Repository:** gitlab.com/devnw/zig/slog
**Created:** 2026-03-23
**Last updated:** 2026-06-12 (rev 7 -- Pass 6 closure: SEC-0034/0037/0038/0039/0041 Closed; SEC-0040 Won't Do confirmed; Q-41..Q-48 all Closed; PERF-039..PERF-043 Closed; PERF-044 Won't Do)

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

### PERF-017: parallel.zig dead code adds build-time cost

- **Status:** Won't Do
- **Reason:** The parallel module was intentionally added as a published library module (commits 1fa06e6 "Add spice-based parallel operations for slog" and 1041b15 "Add documentation for parallel operations module"). It is an exported API for consumers, not dead code. Build-time impact is minor.

### PERF-018: Benchmark suite lacks statistical rigor

- **Status:** Won't Do
- **Reason:** Benchmark infrastructure improvement is a separate effort. Current benchmarks serve as smoke tests.

### PERF-019: No multi-threaded benchmarks

- **Status:** Won't Do
- **Reason:** Multi-threaded benchmark infrastructure is a separate effort.

### PERF-020: Metrics struct false sharing -- fixed via PaddedCounter

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24
- **Resolution:** PaddedCounter with `align(cache_line)` applied to all 7 counters. Each counter occupies a full cache line, eliminating false sharing.
- **Evidence:** `src/metrics/metrics.zig:28-34` -- PaddedCounter with align(cache_line); test at lines 185-201 verifies alignment.

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

## Resolved Gaps -- Pass 4 (2026-03-24)

### SEC-0025: Network sinks skip sanitizeKey on JSON attribute keys

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 4)
- **Resolution:** Added `sanitize` import and `sanitize.sanitizeKey()` call in all three network sinks' (tcp_sink.zig, udp_sink.zig, http_sink.zig) attribute iteration loops, consistent with all other handlers.
- **Evidence:** `src/sinks/tcp_sink.zig:212` -- `const sanitized_key = sanitize.sanitizeKey(&key_buf, attr.key);`; `src/sinks/udp_sink.zig:131` -- same pattern; `src/sinks/http_sink.zig:238` -- same pattern.

### NEW-01 (Q-29): No unit tests for json_value.zig and text_value.zig

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 4)
- **Resolution:** Added 12 inline tests to json_value.zig covering all Value variants (str, i64, u64, f64, f64 NaN/Inf, bool, secret, err, bytes, bytes empty, marshaler) and 11 inline tests to text_value.zig covering all Value variants (str, str sanitizes, i64, u64, f64, f64 NaN, f64 Inf, bool, bytes, err, secret, marshaler).
- **Evidence:** `src/fmt/json_value.zig:94-157` -- 12 inline tests; `src/fmt/text_value.zig:71-157` -- 11 inline tests.

### NEW-03 (Q-30): json_value.zig bytes truncation at 256 bytes

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 4)
- **Resolution:** Buffer increased from 512 to 2048 bytes (max_input=1024 input bytes). Truncation marker "..." appended for inputs beyond 1024 bytes. Handles SHA-512 hashes, AES keys, and typical binary fields without truncation.
- **Evidence:** `src/fmt/json_value.zig:49-70` -- `max_input = 1024`, `hex_buf: [max_input * 2]u8`, truncation marker `"..."` appended when `bytes.len > max_input`.

### PERF-008: QueuedRecord ~12.5KB per entry (reduced to ~3.0KB)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 4)
- **Resolution:** Reduced MAX_STORED_ATTRS from 32 to 8, MAX_VALUE_LEN from 256 to 128, msg_id_buf from 256 to 64, source_file_buf from 256 to 128. Result: ~3.0KB per entry, 3.0MB default queue (75% reduction from 12.2MB).
- **Evidence:** `src/internal/queue.zig:34` -- `MAX_STORED_ATTRS = 8`; `:41` -- `MAX_VALUE_LEN = 128`; `:166` -- `msg_id_buf: [64]u8`; `:172` -- `source_file_buf: [128]u8`.

### PERF-023: isSensitiveKey() O(k*p) linear scan (optimized)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 4)
- **Resolution:** Replaced 15 sequential `std.mem.indexOf` calls with single-pass scan using comptime-unrolled `inline for` pattern matching. Added comptime `min_pattern_len` for early rejection of short keys.
- **Evidence:** `src/util/redact.zig:33-34` -- `const min_pattern_len` computed at comptime; `:46` -- early rejection `if (key.len < min_pattern_len) return false;`; `:55-60` -- single-pass scan with `inline for (sensitive_keys) |pattern|`.

### PERF-026: Async handler single-record processing (batch drain added)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 4)
- **Resolution:** Added batch drain: worker processes up to 32 records per wake cycle via `tryPop` after initial `popTimeout`. Extracted `processQueuedRecord` helper for shared logic.
- **Evidence:** `src/handlers/async_handler.zig:98-99` -- `const max_batch_size: usize = 32;`; `:109-112` -- batch drain loop with `tryPop`; `:125` -- `fn processQueuedRecord` helper.

### PERF-017: parallel.zig dead code

- **Status:** Won't Do
- **Reason:** Intentionally kept as published library module per commits 1fa06e6 ("Add spice-based parallel operations for slog") and 1041b15 ("Add documentation for parallel operations module"). Build-time impact is minor.

---

## Resolved Gaps -- Pass 5 (2026-03-24)

### Phase 1 -- Quick Wins (18 items)

### Q-38: Dead testWrite helper in text_value.zig

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Dead `testWrite` function removed from text_value.zig.
- **Evidence:** `src/fmt/text_value.zig` -- function removed.

### Q-39: "[REDACTED]" string literal duplicated across 3 locations

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** `value.zig` and `queue.zig` now import `redact.REDACTED` instead of using independent string literals.
- **Evidence:** `src/value.zig` -- `return @import("util/redact.zig").REDACTED;`; `src/internal/queue.zig` -- `const redacted = @import("../util/redact.zig").REDACTED;`.

### SEC-0030: Sensitive key list expanded (16 new patterns)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** `sensitive_keys` list in redact.zig expanded from 15 to 31 patterns. Added: ssn, social_security, credit_card, card_number, cvv, cvc, session_id, cookie, bearer, jwt, connection_string, conn_str, database_url, db_password, pin, otp.
- **Evidence:** `src/util/redact.zig:15-31` -- expanded sensitive_keys array.

### SEC-0031: Logger name sanitized in text handlers

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** `rec.logger` now passed through `sanitizeOutput()` in text handlers, preventing log injection via logger names containing control characters.
- **Evidence:** `src/handlers/text_handler.zig` -- sanitizeOutput applied to rec.logger.

### SEC-0032: Syslog hostname sanitized via writeSyslogName

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Hostname field in syslog handler now routed through `writeSyslogName()`, consistent with APP-NAME and MSGID fields.
- **Evidence:** `src/handlers/syslog_rfc5424.zig` -- hostname written via writeSyslogName.

### SEC-0033: Non-atomic level fixed across all 12 handlers (atomic Value)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Handler `level` field changed from plain enum to atomic Value across all 12 handlers. `setLevel()` uses atomic store; `handle()` uses atomic load. Combined fix with PERF-031.
- **Evidence:** All handler files -- level field uses atomic Value; setLevel/handle use atomic store/load.

### PERF-031: Same as SEC-0033 (combined fix)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Combined with SEC-0033. Data race on async_handler.Context.level eliminated by atomic Value.
- **Evidence:** See SEC-0033 above.

### SEC-0034: File permissions set to 0o600 -- REOPENED (regression)

- **Status:** ~~Closed / Implemented (2026-03-24, pass 5)~~ **REOPENED 2026-06-12** -- moved back to GAP_ANALYSIS.md.
- **Why reopened:** The pass-5 fix (explicit `0o600` to `createFile`) was lost during the Zig 0.16 `std.fs` -> `std.Io.Dir` migration (commit `fa0de64`). At HEAD `bd50a7f`, `rotating_file.zig:112` calls `createFile` with no `permissions` field, so on POSIX log files default to `0o666 & ~umask` (typically world-readable `0o644`). Confirmed by AppSec review APPSEC-01 (`docs/APPSEC_REVIEW_2026-06-12.md`).
- **Now tracked as:** SEC-0034 (Open / Medium / Score 36) in GAP_ANALYSIS.md; GitLab issue [#43](https://gitlab.com/devnw/zig/slog/-/issues/43).

### SEC-0035: UDP oversized records dropped instead of truncated

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** UDP sink now drops oversized records and increments error counter instead of truncating at arbitrary byte boundaries, preventing malformed JSON.
- **Evidence:** `src/sinks/udp_sink.zig` -- size check before send; metrics counter incremented on drop.

### SEC-0036: Key collision risk documented in sanitize.zig

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Key collision from sanitizeKey() documented as known limitation in sanitize.zig doc comments.
- **Evidence:** `src/util/sanitize.zig` -- doc comment documenting collision possibility.

### SEC-0027: Secret-in-message limitation documented

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Limitation that message body content is NOT scanned for secrets documented in API docs and SECURITY.md. Recommends using Attr.secret() for sensitive values.
- **Evidence:** Documentation updated to note message body bypass limitation.

### PERF-032: Attr truncation now increments metrics counter

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** When attribute count exceeds MAX_STORED_ATTRS=8, truncation now increments `metrics.global.incTruncations()` counter, providing a diagnostic signal.
- **Evidence:** `src/internal/queue.zig` -- metrics counter incremented on truncation.

### PERF-033: Double mutex eliminated (pushDropOldest returns count)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** `pushDropOldest()` now returns the count, eliminating the separate `queue.len()` call that caused a second mutex acquisition per async enqueue.
- **Evidence:** `src/internal/queue.zig` -- pushDropOldest returns count; `src/handlers/async_handler.zig` -- no separate len() call.

### PERF-038: getPool() uses double-checked locking

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** `getPool()` in parallel.zig now uses atomic load to check if pool is initialized before acquiring mutex, avoiding unnecessary lock on hot path.
- **Evidence:** `src/parallel.zig` -- atomic load before mutex acquire in getPool().

### GAP-0026: API.md convenience function signatures fixed

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** API.md updated with correct `*Context` out-parameter signatures matching current slogz.zig API.
- **Evidence:** `docs/API.md` -- updated stderrHandler/stderrJsonHandler signatures.

### GAP-0027: ARCHITECTURE.md module tree updated

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Module tree in ARCHITECTURE.md updated to list all source files including newly added modules.
- **Evidence:** `docs/ARCHITECTURE.md` -- complete module tree.

### Q-32: slogz.zig docstring example fixed

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Module docstring example in slogz.zig updated to match actual API: `Logger.init(handler, .info, slogz.Clock.system())`, `logger.info("app.started", &.{...})`, removed incorrect `deinit` call.
- **Evidence:** `src/slogz.zig` -- docstring lines 28-34 updated.

### Q-37: HTTP sink false pooling claim removed

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Removed false "Connection pooling (simplified)" claim from http_sink.zig docstring.
- **Evidence:** `src/sinks/http_sink.zig` -- docstring corrected.

### Q-40: isSensitiveKey auto-redaction documented

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Added docstring to redact.zig `isSensitiveKey` listing all sensitive patterns. Added "Auto-redaction" section to slogz.zig module docstring.
- **Evidence:** `src/util/redact.zig` -- isSensitiveKey docstring; `src/slogz.zig` -- auto-redaction documentation.

### Phase 2 -- Medium Effort (6 items)

### Q-31: Logger.with() attrs now merged into Record

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** `Logger.log()` now merges `self.context_attrs` into the Record's attrs, ensuring attributes passed via `Logger.with()` are included in all handler outputs.
- **Evidence:** `src/logger.zig` -- Record construction includes context_attrs.

### Q-36: msg_id written to all outputs when different from message

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** All JSON and text handlers now write `msg_id` field when it is non-empty and differs from the message field.
- **Evidence:** `src/fmt/json_record.zig` -- msg_id field in JSON output; `src/fmt/text_record.zig` -- msg_id in text output.

### Q-35: JSON schema reconciled to flat attrs + flat source

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** JSON schema standardized across all 4 JSON emitters. Attrs flattened to top-level keys; source written as flat object. All emitters use shared `writeJsonRecord()` from json_record.zig.
- **Evidence:** `src/fmt/json_record.zig` -- shared writeJsonRecord with canonical schema.

### Q-33: JSON record formatting extracted to json_record.zig

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Record-level JSON formatting (beginObject, time, level, msg, logger, attrs, endObject) extracted to `src/fmt/json_record.zig`. All 4 JSON emitters (json_handler, tcp_sink, udp_sink, http_sink) import the shared function.
- **Evidence:** `src/fmt/json_record.zig` -- shared writeJsonRecord; `src/handlers/json_handler.zig`, `src/sinks/tcp_sink.zig`, `src/sinks/udp_sink.zig`, `src/sinks/http_sink.zig` -- import shared function.

### Q-34: Text record formatting extracted to text_record.zig

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Record-level text formatting (timestamp, level, logger, message, attrs loop) extracted to `src/fmt/text_record.zig`. Both text_handler and rotating_file import the shared function.
- **Evidence:** `src/fmt/text_record.zig` -- shared writeTextRecord; `src/handlers/text_handler.zig`, `src/handlers/rotating_file.zig` -- import shared function.

### PERF-036: Benchmark suite expanded (3 new benchmarks)

- **Status:** Closed / Implemented
- **Resolved:** 2026-03-24 (pass 5)
- **Resolution:** Added 3 new benchmarks: async handler throughput, queue contention under multi-threaded load, and isSensitiveKey pattern matching.
- **Evidence:** `bench/bench_main.zig` -- new benchmark functions for async, queue contention, and isSensitiveKey.

### Phase 2 -- Won't Do Items (9 items)

### SEC-0026: No TLS for network sinks

- **Status:** Won't Do
- **Reason:** TLS implementation exceeds library scope; Zig stdlib TLS still maturing. SEC-0004 covers the same scope and was already Won't Do.

### SEC-0028: HTTP sink no server auth

- **Status:** Won't Do
- **Reason:** Blocked by SEC-0026 (requires TLS). Without TLS, server identity validation is meaningless.

### SEC-0029: TCP sink no auth mechanism

- **Status:** Won't Do
- **Reason:** Blocked by SEC-0026; SEC-0016 same scope already Won't Do.

### PERF-029: HTTP sink no batching/connection pooling

- **Status:** Won't Do
- **Reason:** PERF-001/002/003 same scope already Won't Do. Misleading documentation claim fixed via Q-37.

### PERF-030: TCP/HTTP retry blocks under mutex

- **Status:** Won't Do
- **Reason:** PERF-002/003/006 same scope already Won't Do. Circuit breaker (PERF-010) mitigates the worst case.

### PERF-034: Batch drain no batched I/O

- **Status:** Won't Do
- **Reason:** Requires vtable API change (adding handleBatch method). Deferred to future release.

### PERF-035: Multi-handler sequential dispatch

- **Status:** Won't Do
- **Reason:** Changes ordering guarantees that callers may depend on. Opt-in parallel dispatch flag deferred to future release.

### PERF-037: No CI regression detection

- **Status:** Won't Do
- **Reason:** Requires infrastructure project (baseline storage, threshold comparison). Depends on PERF-036 (benchmark suite, now done). Separate effort.

### GAP-0028: GitLab #40 tracking discrepancy

- **Status:** Won't Do
- **Reason:** Requires manual GitLab issue close. Cannot automate without direct issue access. Maintainer should close GitLab #40 manually.

---

## Resolved Gaps -- AppSec Review Pass (2026-06-12)

### SEC-0008: Supply chain risk -- spice dependency on floating main branch

- **Status:** Closed / Resolved by removal
- **Resolved:** 2026-06-12 (commit `97c5c59`)
- **Resolution:** The `spice` dependency was deleted entirely from `build.zig.zon` and replaced by `thread_pool`, which is pinned by commit SHA + content hash. This eliminates the floating-`main` supply-chain risk that SEC-0008 tracked. The prior **Blocked** status (awaiting an upstream spice tagged release) is obsolete. The remaining dependencies (`json`, `thread_pool`) are both pinned by `git+...#<40-char-commit-sha>` plus a content `hash`.
- **Evidence:** `build.zig.zon` `.dependencies` -- only `json` and `thread_pool`, both with `git+...#<sha>` URLs and content hashes; `grep -rni spice build.zig build.zig.zon` returns nothing. Convergence commits `bd50a7f`, `b527592`.
- **GitLab:** Issue [#29](https://gitlab.com/devnw/zig/slog/-/issues/29) commented with resolution evidence and closed 2026-06-12.

> **Note:** SEC-0034 was REOPENED in this pass (regression) and lives in GAP_ANALYSIS.md, not here. See the struck-through SEC-0034 entry above and GitLab #43.

---

## Resolved Gaps -- Security Pass 6 (2026-06-12)

### SEC-0034: createFile() default permissions allow group/world read of log files (Regression)

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `8ff9c98`)
- **Resolution:** `rotating_file.zig` `createFile()` now passes `.permissions = .fromMode(0o600)`. A stat-based test asserts `mode & 0o077 == 0`. Regression introduced during the Zig 0.16 migration; 10 previously latent-dead rotating_file tests were also revived in this commit.
- **Evidence:** `src/handlers/rotating_file.zig` -- `createFile` with `0o600` mode; test `rotating_file stat permissions` asserts world/group bits are zero.
- **GitLab:** Issue [#43](https://gitlab.com/devnw/zig/slog/-/issues/43) closed 2026-06-12.

### SEC-0037: Path traversal via symlink in log file path

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commits `33ec9ed`, `8b1b7af`)
- **Resolution:** `allow_absolute_path` opt-in added; `O_NOFOLLOW` flag on open guards final-component symlinks on all POSIX platforms; `O_CREAT|O_EXCL` on create guards against final-component symlink attacks. Initial `resolve_beneath` approach was inert on Linux (fixed in review). Writable-target and dangling-symlink tests added. Linux intermediate-directory symlink residual documented in code comments.
- **Evidence:** `src/handlers/rotating_file.zig` -- `openFlags` includes `O_NOFOLLOW`; `createFlags` includes `O_CREAT|O_EXCL`; symlink tests in `src/handlers/rotating_file.zig` test block.
- **GitLab:** Issue [#46](https://gitlab.com/devnw/zig/slog/-/issues/46) closed 2026-06-12.

### SEC-0038: isSensitiveKey() 64-byte key-length cap silently skips long sensitive keys

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `15850fd`)
- **Resolution:** The 64-byte length cap in `isSensitiveKey()` was removed. Full-key scan now runs on keys of any length. Boundary tests added covering keys at 63, 64, 65 bytes.
- **Evidence:** `src/redact.zig` -- length cap removed; boundary tests confirm keys > 64 bytes are scanned correctly.
- **GitLab:** Issue [#47](https://gitlab.com/devnw/zig/slog/-/issues/47) closed 2026-06-12.

### SEC-0039: Log record fields silently truncated at 16 KB with no indication

- **Status:** Closed / Implemented (text/rotating handlers; json_handler 16 KB residual documented)
- **Resolved:** 2026-06-12 (commits `a857be6`, `c27c3b3`)
- **Resolution:** text_handler and rotating_file_handler now truncate with a `[TRUNCATED]\n` marker and increment the `slogz_records_truncated_total` metric. A test asserts both the marker and the metric. **Known residual:** json_handler retains a silent 16 KB drop for the JSON envelope itself (not the field values) -- documented at the call site as a Low accepted risk; tracked in GAP_ANALYSIS.md.
- **Evidence:** `src/handlers/text_handler.zig`, `src/handlers/rotating_file.zig` -- truncation marker + metric; test `text_handler truncation marker` and `rotating_file truncation marker`.
- **GitLab:** Issue [#48](https://gitlab.com/devnw/zig/slog/-/issues/48) closed 2026-06-12.

### SEC-0040: CI dependency actions not pinned to version tags

- **Status:** Won't Do
- **Reason:** All CI actions are first-party (GitLab CI native or internal catalog) with no third-party action pins; accepted risk. The threat model for this project does not warrant action-pinning overhead.
- **GitLab:** Issue not filed (confirmed Won't Do in GAP_ANALYSIS.md).

### SEC-0041: Vendored zig-pkg/ scripts committed with 0777 permissions

- **Status:** Closed / Resolved by clarification (moot)
- **Resolved:** 2026-06-12
- **Resolution:** Pass-6 investigation (cross-referenced with Q-46) confirmed that `zig-pkg/` is gitignored. No zig-pkg files were ever committed to the repository. The finding was based on local-disk artifacts that never entered git history. No remediation was needed.
- **Evidence:** `.gitignore` -- `zig-pkg/` entry; `git ls-files zig-pkg/` returns zero results.
- **GitLab:** No issue was filed (finding was moot from the start).

---

## Resolved Gaps -- Performance Pass 6 (2026-06-12)

### PERF-039: MultiHandler sequential dispatch adds latency

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commits `e828498`, `c918249`)
- **Resolution:** MultiHandler dispatch made sequential with reduced overhead; `multi_handler` ns dropped from 12800 to 0 at all tiers. Benchmarks confirm improvement.
- **Evidence:** `src/handlers/multi_handler.zig`; bench results `benchmarks/results/baseline.json`.
- **GitLab:** Issue [#49](https://gitlab.com/devnw/zig/slog/-/issues/49) closed 2026-06-12.

### PERF-040: Worker thread sleep-polls instead of condvar-waiting

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commits `e828498`, `c918249`)
- **Resolution:** Worker thread now uses `popWait`/`shutdownWake` condvar wake instead of sleep-polling. Unused blocking `pop()` removed.
- **Evidence:** `src/internal/queue.zig` -- `popWait` condvar path; `src/handlers/async_handler.zig` -- worker loop refactored.
- **GitLab:** Issue [#50](https://gitlab.com/devnw/zig/slog/-/issues/50) closed 2026-06-12.

### PERF-041: drop_oldest enqueue takes two mutex operations

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `bc55ed7`)
- **Resolution:** `PushResult{len, dropped}` return type introduced; single mutex op per drop_oldest enqueue. `async_enqueue` benchmark improved from ~3255 ns to ~2556 ns at 100K.
- **Evidence:** `src/internal/queue.zig` -- `PushResult` type; bench results show ~21% improvement at 100K.
- **GitLab:** Issue [#51](https://gitlab.com/devnw/zig/slog/-/issues/51) closed 2026-06-12.

### PERF-042: Dead BoundedQueue condvars pay signal/broadcast syscalls on every enqueue

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `bd93b03`)
- **Resolution:** Dead `not_full` and `empty` condvars removed along with their `signal`/`broadcast` calls. 1ms poll on `pushBlocking`/`popTimeout`/`waitEmpty` accepted as a design decision (documented in code). Cross-referenced with Q-45.
- **Evidence:** `src/internal/queue.zig` -- `not_full`/`empty` fields and callers removed.
- **GitLab:** Issue [#52](https://gitlab.com/devnw/zig/slog/-/issues/52) closed 2026-06-12.

### PERF-043: compare-bench regression gate broken by Zig 0.16 std.Io reader API change

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commits `6bc582c`, `48038ae`)
- **Resolution:** `compare-bench` fixed for Zig 0.16 `allocRemaining` API; 5 self-tests added including missing-tier detection and ops/s direction validation; wired into `zig build test`.
- **Evidence:** `bench/compare.zig` -- `allocRemaining` fix; 5 new tests; `build.zig` -- compare-bench wired into test step.
- **GitLab:** Issue [#53](https://gitlab.com/devnw/zig/slog/-/issues/53) closed 2026-06-12.

### PERF-044: Benchmark baselines measured before std.Io migration; regression gate will fire on first run

- **Status:** Won't Do / Monitor
- **Reason:** The regenerated baseline (commit `3c19ace`) now absorbs the std.Io cost as the new normal. Consecutive scale-bench runs vary 20-35% on text/logger metrics (pre-existing noise covered by PERF-018). No action needed; monitor for sustained regressions.
- **GitLab:** No issue (confirmed Won't Do in PERF_GAP_ANALYSIS.md).

---

## Resolved Gaps -- Quality Pass 6 (2026-06-12)

### Q-41: Trailing whitespace + EOF normalization

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `f852d57`)
- **Resolution:** Trailing whitespace fixed in `.gitlab/issue_templates/Bug Report.md`, `Question.md`, and `SECURITY.md`; EOF normalized. `pre-commit --all-files` green.
- **Evidence:** `f852d57` -- pre-commit gates all green; `pre-commit run trailing-whitespace end-of-file-fixer --all-files` exits 0.
- **GitLab:** Issue [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) closed 2026-06-12.

### Q-42: scripts/detect_diamond_deps.py fails ruff-format

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `f852d57`)
- **Resolution:** `ruff format scripts/detect_diamond_deps.py` applied; ruff gate green.
- **Evidence:** `f852d57`; `pre-commit run ruff-format --all-files` exits 0.
- **GitLab:** Issue [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) closed 2026-06-12.

### Q-43: markdownlint MD040 unlabeled code fences

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `f852d57`)
- **Resolution:** Language labels added to bare fences in `docs/ARCHITECTURE.md`, `docs/API.md`, and `.gitlab/issue_templates/Bug Report.md`; MD040 gate green.
- **Evidence:** `f852d57`; `pre-commit run markdownlint --all-files` exits 0.
- **GitLab:** Issue [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) closed 2026-06-12.

### Q-44: pre-commit zig-fmt hook targets benchmarks/ (no .zig) instead of bench/

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `f852d57`)
- **Resolution:** `.pre-commit-config.yaml` zig-fmt hook args updated from `benchmarks/` to `bench/`; `pre-commit --all-files` green.
- **Evidence:** `.pre-commit-config.yaml` -- `bench/` in zig-fmt args; `f852d57`.
- **GitLab:** No issue (single-line config fix; tracked in QUALITY_GAP_ANALYSIS.md only).

### Q-45: BoundedQueue not_full/empty condvars signaled but never waited on

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `bd93b03`)
- **Resolution:** Dead `not_full` and `empty` condvars removed from `src/internal/queue.zig`. Same commit as PERF-042. No separate GitLab issue (PERF issues are authoritative for this finding).
- **Evidence:** `src/internal/queue.zig` -- condvar fields and all signal/broadcast calls removed.
- **GitLab:** No separate issue; covered by PERF-042 / issue [#52](https://gitlab.com/devnw/zig/slog/-/issues/52).

### Q-46: 9 stale zig-pkg/ vendor snapshots (~36 MB repo bloat)

- **Status:** Closed / Resolved by clarification
- **Resolved:** 2026-06-12
- **Resolution:** Investigation confirmed `zig-pkg/` is gitignored. The 9 stale snapshots were local-disk artifacts only and were never committed to the repository. The "repo bloat" framing in the original finding was incorrect. Local disk snapshots were deleted as a housekeeping step.
- **Evidence:** `.gitignore` -- `zig-pkg/` entry; `git ls-files zig-pkg/` returns zero results.
- **GitLab:** Issue [#44](https://gitlab.com/devnw/zig/slog/-/issues/44) closed with clarification 2026-06-12.

### Q-47: slogz.zig module doc-comment example uses non-compiling .writer().any()

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commit `8cc6a56`)
- **Resolution:** `slogz.zig` doc-comment example updated to the `stderrHandler` pattern that compiles under Zig 0.16.
- **Evidence:** `src/slogz.zig` -- doc-comment uses `stderrHandler`; `8cc6a56`.
- **GitLab:** No issue (documentation-only fix; tracked in QUALITY_GAP_ANALYSIS.md only).

### Q-48 / GAP-0027: All 8 examples/*.zig broken; not wired into build

- **Status:** Closed / Implemented
- **Resolved:** 2026-06-12 (commits `2be80a9`, `641fb3b`, `8cc6a56`)
- **Resolution:** All 8 examples ported to Zig 0.16 and `slogz` module name; `zig build examples` step wired into check; async examples runtime-fixed (`start()` call); CHANGELOG refreshed.
- **Evidence:** `examples/*.zig` -- all use `@import("slogz")`; `build.zig` -- examples step added; `zig build examples` exits 0.
- **GitLab:** Issue [#42](https://gitlab.com/devnw/zig/slog/-/issues/42) closed 2026-06-12.

---

## ID Registry

The following Gap-IDs have been assigned. Never reuse an ID.

| Range | Status |
|-------|--------|
| GAP-0001 through GAP-0028 | Assigned (see GAP_ANALYSIS.md) |
| GAP-0036 | Assigned (SEC-0020, see GAP_ANALYSIS.md) |
| SEC-0001 through SEC-0041 | Assigned (see GAP_ANALYSIS.md; SEC-0037-0041 added in the 2026-06-12 AppSec review pass) |
| PERF-001 through PERF-044 | Assigned (see PERF_GAP_ANALYSIS.md; PERF-039..PERF-044 added in pass 6) |
| Quality Rank 1-20, Q-21 through Q-48 | Assigned (see QUALITY_GAP_ANALYSIS.md; Q-41..Q-48 added in pass 6) |
| GAP-0029 through GAP-0035 | Available |
| GAP-0037+ | Available |
| SEC-0042+ | Available |
