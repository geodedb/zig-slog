# Gap Closure Completion Report

**Repository:** gitlab.com/devnw/zig/slog
**Date:** 2026-03-24
**Commits:** ec068d0, 3fcd5a5, 05c6a16, 0ed8afe, 677630f (passes 1-2), pass 3 (current)

---

## GAP_ANALYSIS Status

| File | Closed | Blocked | Won't Do | Remaining Open | Total |
|------|--------|---------|----------|----------------|-------|
| GAP_ANALYSIS.md (Security) | 21 | 1 | 2 | 0 | 24 |
| QUALITY_GAP_ANALYSIS.md | 25 | 0 | 2 | 1 | 28 |
| PERF_GAP_ANALYSIS.md | 15 | 0 | 9 | 4 | 28 |
| **Total** | **61** | **1** | **13** | **5** | **80** |

**Overall:** 61 closed, 1 blocked, 13 won't do, 5 remaining open out of 80 total items.

**Note:** Item counts increased from 60 (pass 2) to 80 (pass 3) because pass 3 added new findings: SEC-0020 through SEC-0024, Q-21 through Q-28, PERF-022 through PERF-028.

---

## Pass 3 Summary

Pass 3 addressed 18 gap items (16 unique closures + 2 duplicates resolved by other fixes):

| Category | Closed | Won't Do | Blocked | Duplicates |
|----------|--------|----------|---------|------------|
| Security | 7 | 0 | 0 | 0 |
| Quality | 6 | 0 | 0 | 2 |
| Performance | 3 | 1 | 0 | 0 |
| **Total** | **16** | **1** | **0** | **2** |

---

## Closed Items (All Passes)

### Pass 1-2 Closures (previously reported)

| Gap-ID | File | Title | Evidence |
|--------|------|-------|----------|
| SEC-0001 | GAP_ANALYSIS.md | HTTPS URLs sent over plaintext TCP | src/sinks/http_sink.zig:64-67 -- returns error.HttpsNotSupported on https:// |
| SEC-0002 | GAP_ANALYSIS.md | stderrHandler returns dangling pointer | src/slogz.zig:106-116 -- accepts *Context out-param; test validates |
| SEC-0003 | GAP_ANALYSIS.md | HTTP header injection | src/sinks/http_sink.zig:160 -- containsControlChars() filter |
| SEC-0005 | GAP_ANALYSIS.md | isSensitiveKey() dead code | All handlers call redact.isSensitiveKey(); tests validate |
| SEC-0007 | GAP_ANALYSIS.md | Path traversal in rotating file | src/handlers/rotating_file.zig -- path validation at init |
| SEC-0010 | GAP_ANALYSIS.md | Text handler string values unescaped | src/handlers/text_handler.zig:122 -- sanitize.sanitizeOutput |
| SEC-0011 | GAP_ANALYSIS.md | Global fatal_hook race condition | src/logger.zig:30-39 -- atomic get/setFatalHook; test validates |
| SEC-0012 | GAP_ANALYSIS.md | Secret values plaintext in memory | src/value.zig:12-15 -- documented as known limitation |
| SEC-0013 | GAP_ANALYSIS.md | Async handler drops secret attrs | src/internal/queue.zig:46-112 -- secrets redacted at serialization |
| SEC-0014 | GAP_ANALYSIS.md | Gitleaks blanket exclusion | .gitleaks.toml:9-11 -- narrowed to specific file |
| SEC-0015 | GAP_ANALYSIS.md | SECURITY.md false claims | SECURITY.md:35 -- claims corrected |
| SEC-0017 | GAP_ANALYSIS.md | No CI build/test pipeline | .gitlab-ci.yml:35-60 -- build, test, format-check stages |
| SEC-0018 | GAP_ANALYSIS.md | HTTP status check too permissive | src/sinks/http_sink.zig:180-182 -- positional check at index 9 |
| SEC-0019 | GAP_ANALYSIS.md | Journald fallback unsanitized stderr | src/handlers/journald.zig:143-162 -- buffered + sanitized |
| Q-Rank1 | QUALITY_GAP_ANALYSIS.md | AsyncHandler drops ALL attributes | src/internal/queue.zig:46-112 -- StoredAttr serialization |
| Q-Rank2 | QUALITY_GAP_ANALYSIS.md | stderrHandler dangling pointers | src/slogz.zig:106-116 |
| Q-Rank3 | QUALITY_GAP_ANALYSIS.md | AsyncHandler.Context.init dangling ptr | src/handlers/async_handler.zig -- deferred startWorker() |
| Q-Rank5 | QUALITY_GAP_ANALYSIS.md | CI no build/test stage | .gitlab-ci.yml:35-60 |
| Q-Rank6 | QUALITY_GAP_ANALYSIS.md | Network sinks drop attrs | tcp_sink.zig, udp_sink.zig, http_sink.zig -- attrs loop added |
| Q-Rank7 | QUALITY_GAP_ANALYSIS.md | QueuedRecord i64 broken | src/internal/queue.zig:75-82 -- serializeValue |
| Q-Rank8 | QUALITY_GAP_ANALYSIS.md | formatBackupPath buffer aliasing | src/handlers/rotating_file.zig:51 -- path_buf2 |
| Q-Rank9 | QUALITY_GAP_ANALYSIS.md | writeValue duplicated 3x | All handlers updated with consistent writeValue |
| Q-Rank10 | QUALITY_GAP_ANALYSIS.md | JSON encoding duplicated 3x in sinks | All sinks include attrs serialization |
| Q-Rank11 | QUALITY_GAP_ANALYSIS.md | @errorName guard missing 4 handlers | All handlers have raw-value guard |
| Q-Rank12 | QUALITY_GAP_ANALYSIS.md | Silent error swallowing rotating_file | metrics.global.incErrors() in catch blocks |
| Q-Rank13 | QUALITY_GAP_ANALYSIS.md | LoggerOptions phantom export | Removed from slogz.zig |
| Q-Rank14 | QUALITY_GAP_ANALYSIS.md | FixedClock non-functional | clock.zig -- timestamp_us wired into fn ptr |
| Q-Rank15 | QUALITY_GAP_ANALYSIS.md | Syslog @errorName guard | Covered by Rank 11 fix |
| Q-Rank17 | QUALITY_GAP_ANALYSIS.md | rotating_file dead import | text_handler import removed |
| Q-Rank18 | QUALITY_GAP_ANALYSIS.md | epochDays duplicated | clock.zig imports from rfc3339.zig |
| Q-Rank19 | QUALITY_GAP_ANALYSIS.md | BaseHandlerContext dead code | Removed from handler.zig |
| Q-Rank20 | QUALITY_GAP_ANALYSIS.md | Metrics.incReconnections dead code | Wired into tcp_sink.zig |
| PERF-004 | PERF_GAP_ANALYSIS.md | Missing connect/read timeouts | SO_RCVTIMEO/SO_SNDTIMEO via setsockopt |
| PERF-005 | PERF_GAP_ANALYSIS.md | Async drops ALL attributes | StoredAttr array in queue.zig |
| PERF-007 | PERF_GAP_ANALYSIS.md | Sinks omit attrs from JSON | Attrs loop added to all sinks |
| PERF-009 | PERF_GAP_ANALYSIS.md | HTTP accepts HTTPS silently | error.HttpsNotSupported returned |
| PERF-010 | PERF_GAP_ANALYSIS.md | No circuit breaker for TCP | Circuit breaker with threshold=3, cooldown=30s |
| PERF-011 | PERF_GAP_ANALYSIS.md | Journald 14+ stderr syscalls | 8KB fixedBufferStream, single writeAll |
| PERF-012 | PERF_GAP_ANALYSIS.md | Per-byte hex encoding | hex_chars lookup table |
| PERF-013 | PERF_GAP_ANALYSIS.md | Rotating file no write buffering | 8KB write_buf with flush-on-full |
| PERF-014 | PERF_GAP_ANALYSIS.md | Async flush busy-wait polling | queue.waitEmpty() with CV signaling |
| PERF-015 | PERF_GAP_ANALYSIS.md | Async double-lock TOCTOU | droppedCount() before/after push |
| PERF-016 | PERF_GAP_ANALYSIS.md | JSON pre-validation loop | Removed; inline NaN/Inf check |
| PERF-020 | PERF_GAP_ANALYSIS.md | Metrics struct false sharing | PaddedCounter with align(cache_line) |

### Pass 3 Closures (new)

| Gap-ID | File | Title | Evidence |
|--------|------|-------|----------|
| SEC-0006 | GAP_ANALYSIS.md | Log injection -- rotating_file.zig (reopened, fixed) | rotating_file.zig:298 sanitizeOutput on message; :305 sanitizeKey on attr keys; :312 writeTextValue for values |
| SEC-0009 | GAP_ANALYSIS.md | Rotating file isSensitiveKey (reopened, fixed) | rotating_file.zig:309 isSensitiveKey check in attr loop |
| SEC-0020 | GAP_ANALYSIS.md | Windows Event Log stderr fallback sanitization | windows_eventlog.zig:107 sanitizeOutput on message; :113 sanitizeKey on keys; :145 sanitizeOutput on source_name |
| SEC-0021 | GAP_ANALYSIS.md | Journald stderr fallback attr key sanitization | journald.zig:166 sanitize.sanitizeKey(&stderr_key_buf, attr.key) |
| SEC-0022 | GAP_ANALYSIS.md | Windows Event Log attr key sanitization | windows_eventlog.zig:113 sanitize.sanitizeKey(&key_buf, attr.key) |
| SEC-0023 | GAP_ANALYSIS.md | Syslog SD string control char escaping | syslog_rfc5424.zig:268-284 control chars 0x00-0x08,0x0a-0x1f escaped as \xHH |
| SEC-0024 | GAP_ANALYSIS.md | Gitleaks allowlist extended | .gitleaks.toml:9-13 entries for json_logging.zig and accept.zig |
| Q-21 | QUALITY_GAP_ANALYSIS.md | writeJsonValue() extracted to shared module | src/fmt/json_value.zig:19; imported by json_handler.zig:22, tcp_sink.zig:23, udp_sink.zig:23, http_sink.zig:24 |
| Q-22 | QUALITY_GAP_ANALYSIS.md | writeTextValue() extracted to shared module | src/fmt/text_value.zig:27; imported by text_handler.zig:21, journald.zig:20, windows_eventlog.zig:20, rotating_file.zig:26 |
| Q-24 | QUALITY_GAP_ANALYSIS.md | rotating_file close vtable entry | rotating_file.zig:353-355 close fn; :358-365 vtable wired |
| Q-25 | QUALITY_GAP_ANALYSIS.md | incReconnections wired | tcp_sink.zig:139 metrics.global.incReconnections() |
| Q-28 | QUALITY_GAP_ANALYSIS.md | UnsupportedPlatform replaced with FeatureDisabled | handler.zig:22, journald.zig:73, windows_eventlog.zig:96 |
| PERF-022 | PERF_GAP_ANALYSIS.md | UDP mutex scope narrowed | udp_sink.zig -- formatting moved outside mutex |
| PERF-024 | PERF_GAP_ANALYSIS.md | Hex encoding lookup table in rotating_file | Resolved via writeTextValue import (text_value.zig:42 hex_chars) |
| PERF-028 | PERF_GAP_ANALYSIS.md | Journald comptime guard on dead field-building | journald.zig:29 native_sendv_available=false; :84 comptime guard |

### Pass 3 Duplicates (resolved by other fixes)

| Gap-ID | Resolved By | Explanation |
|--------|-------------|-------------|
| Q-23 | SEC-0006 | rotating_file .str sanitization resolved by shared writeTextValue |
| Q-26 | PERF-022 | UDP mutex scope is the same fix |

---

## Won't Do Items

| Gap-ID | File | Title | Reason |
|--------|------|-------|--------|
| SEC-0004 | GAP_ANALYSIS.md | TCP/UDP plaintext only | TLS/DTLS requires significant effort and C library integration |
| SEC-0016 | GAP_ANALYSIS.md | No auth for TCP/UDP sinks | mTLS/auth is a separate infrastructure effort |
| Q-Rank4 | QUALITY_GAP_ANALYSIS.md | withAttrs/withGroup no-op | Requires allocator-aware context cloning; tracked as issue #8 |
| Q-Rank16 | QUALITY_GAP_ANALYSIS.md | VTable boilerplate 9x | Depends on withAttrs/withGroup implementation (Q-Rank4) |
| PERF-001 | PERF_GAP_ANALYSIS.md | HTTP new-connection-per-record | Connection pooling is separate feature |
| PERF-002 | PERF_GAP_ANALYSIS.md | TCP mutex during retry+sleep | Partially mitigated by circuit breaker; full fix is separate |
| PERF-003 | PERF_GAP_ANALYSIS.md | HTTP mutex during RTT+retry | Partially mitigated by socket timeouts; full fix is separate |
| PERF-006 | PERF_GAP_ANALYSIS.md | Handlers hold mutex during format+I/O | Lock scope reduction is separate optimization |
| PERF-018 | PERF_GAP_ANALYSIS.md | Benchmark lacks statistical rigor | Separate infrastructure improvement |
| PERF-019 | PERF_GAP_ANALYSIS.md | No multi-threaded benchmarks | Separate infrastructure improvement |
| PERF-020 | PERF_GAP_ANALYSIS.md | Metrics false sharing | Addressed with PaddedCounter; further optimization low priority |
| PERF-021 | PERF_GAP_ANALYSIS.md | getPool() mutex on every call | parallel.zig is optional; deferred |
| PERF-025 | PERF_GAP_ANALYSIS.md | Stack allocations 8-25KB per log call | Requires profiling data; risks truncation of large records |
| PERF-027 | PERF_GAP_ANALYSIS.md | Multi-handler re-formats per child | Architecturally expected; pre-formatting needs format negotiation |

---

## Blocked Items

| Gap-ID | File | Title | Blocker | Unblock Steps |
|--------|------|-------|---------|---------------|
| SEC-0008 | GAP_ANALYSIS.md | Supply chain: spice on floating main branch | Upstream spice repo (gitlab.com/devnw/zig/spice) has no tagged release | 1. Tag a release of the spice repository. 2. Update build.zig.zon URL from `/archive/main/` to `/archive/v<tag>/`. 3. Update hash to match tagged archive. |

---

## Remaining Open Items

| Gap-ID | File | Title | Reason |
|--------|------|-------|--------|
| Q-27 | QUALITY_GAP_ANALYSIS.md | deprecatedWriter() in slogz.zig | Partially closed (windows_eventlog.zig fixed); slogz.zig blocked on AnyWriter handler interface refactor |
| PERF-008 | PERF_GAP_ANALYSIS.md | QueuedRecord ~12.5KB per entry | Separate optimization effort; current approach is correct |
| PERF-017 | PERF_GAP_ANALYSIS.md | parallel.zig dead code adds build cost | Intentionally kept as published module |
| PERF-023 | PERF_GAP_ANALYSIS.md | isSensitiveKey() O(k*p) linear scan | Replace with compile-time perfect hash; deferred |
| PERF-026 | PERF_GAP_ANALYSIS.md | Async handler single-record processing | Batch dequeue optimization; deferred |

---

## Tests Executed

| Command | Result |
|---------|--------|
| `zig build test --summary all` | PASS (195/195 tests, 16/16 build steps) |
| `zig fmt --check src/ build.zig` | PASS (format clean) |
| `zig build` | PASS (build clean) |

---

## Security Notes

### Pass 1-2

- **Dangling pointer UB eliminated:** stderrHandler/stderrJsonHandler (SEC-0002) and AsyncHandler.Context.init (Quality Rank 3) -- both use-after-free paths are fixed.
- **HTTPS silent downgrade prevented:** https:// URLs now rejected with error.HttpsNotSupported instead of silently sending plaintext.
- **Header injection prevented:** HTTP custom headers with control characters are skipped.
- **Circuit breaker added:** TCP sink fast-fails after 3 consecutive failures with 30s cooldown.
- **Socket timeouts enforced:** SO_RCVTIMEO/SO_SNDTIMEO applied to both TCP and HTTP sinks.
- **Path traversal blocked:** rotating_file rejects paths with `..` components at init time.
- **Atomic fatal_hook:** Race condition on global fatal_hook eliminated via atomic load/store.
- **Secret serialization:** QueuedRecord serializes secrets as [REDACTED] at queue time; never stored in plaintext in async queue.

### Pass 3

- **Log injection fully mitigated:** sanitize.sanitizeOutput() now applied in ALL handlers including rotating_file.zig (the last holdout). Message writes, attribute keys, and string attribute values are all sanitized.
- **Auto-redaction complete:** redact.isSensitiveKey() now wired into ALL handlers including rotating_file.zig. No handler writes sensitive-key-named attributes in plaintext.
- **Key sanitization complete:** sanitize.sanitizeKey() applied to attribute keys in windows_eventlog.zig (main + stderr fallback) and journald.zig (stderr fallback), closing the last gaps in key sanitization coverage.
- **Syslog control char defense-in-depth:** writeSDString() now escapes control characters (0x00-0x08, 0x0a-0x1f) as \xHH, protecting downstream syslog parsers.
- **Gitleaks coverage extended:** Allowlist now includes json_logging.zig and accept.zig to prevent false positive CI failures.
- **Code deduplication:** writeJsonValue and writeTextValue extracted to shared modules (src/fmt/json_value.zig, src/fmt/text_value.zig), eliminating 4x duplication in both JSON and text formatting paths. This prevents future drift where bug fixes are applied to some handlers but not others.
- **Handler cleanup:** rotating_file close vtable wired, incReconnections caller added, UnsupportedPlatform standardized to FeatureDisabled, UDP mutex scope narrowed.

---

## Remaining Blockers

- **SEC-0008 (spice on floating main):** Requires the upstream `devnw/zig/spice` repository to publish a tagged release. The hash in `build.zig.zon` provides integrity protection, but the URL pattern should reference a stable tag. **Next step:** Tag a release of the spice repository, then update `build.zig.zon` URL to reference the tagged archive.

---

## Platform Issues Updated

### Passes 1-2

| Gap-ID | Issue | Action |
|--------|-------|--------|
| GAP-0001 / SEC-0002 | #19 | closed |
| GAP-0016 / Q-Rank1 | #20 | closed |
| GAP-0022 / Q-Rank7 | #21 | closed |
| GAP-0018 / SEC-0017 | #22 | closed |
| GAP-0017 / Q-Rank8 | #23 | closed |
| GAP-0014 / SEC-0015 | #24 | closed |
| GAP-0020 / Q-Rank13 | #25 | closed |
| GAP-0021 / Q-Rank11 | #26 | closed |
| GAP-0019 | #27 | closed |
| GAP-0024 | #28 | closed |
| (sink attrs) | #7 | closed |
| (TLS/HTTPS) | #5 | closed (won't do, interim fix) |
| (fuzz testing) | #15 | closed (won't do, claim removed) |
| (withAttrs) | #8 | commented (won't do for current scope) |
| (text withAttrs) | #17 | commented (won't do, deferred to #8) |
| (Logger.named) | #2 | closed (pass 2) |
| (DNS resolution) | #6 | closed (pass 2) |
| (multi-handler) | #9 | closed (pass 2) |
| (parallel docs) | #16 | closed (pass 2) |
| (handler tests) | #11 | commented (partial, pass 2) |

### Pass 3

| Gap-ID | Issue | Action |
|--------|-------|--------|
| SEC-0020 | #32 | closed |
| Q-21 | #33 | closed |
| Q-22 | #34 | closed |
| Q-23 | #35 | closed (resolved by SEC-0006 fix) |
| SEC-0006 / SEC-0009 | #36 | closed |
| Q-24 | #37 | closed |
| PERF-022 | #38 | closed |
| Q-25 | #39 | closed |
| PERF-025 | #40 | commented (won't do) |
| PERF-028 | #41 | closed |
| Q-27 (deprecatedWriter) | #1 | commented (partial fix) |

---

## Files Changed

### Pass 1 (23 files, commits ec068d0 through 0ed8afe)

| File | Changes |
|------|---------|
| .gitlab-ci.yml | Build/test/format-check stages added |
| .gitleaks.toml | Allowlist narrowed |
| SECURITY.md | False claims corrected, email fixed |
| src/slogz.zig | Dangling pointer fix, LoggerOptions removed |
| src/logger.zig | Atomic fatal_hook |
| src/handler.zig | BaseHandlerContext dead code removed, FeatureDisabled added |
| src/value.zig | Secret documentation |
| src/internal/clock.zig | FixedClock fix, epochDays dedup |
| src/internal/queue.zig | StoredAttr, serializeValue, waitEmpty CV |
| src/fmt/rfc3339.zig | epochDays consolidation |
| src/handlers/async_handler.zig | Attrs round-trip, deferred thread spawn, CV flush |
| src/handlers/text_handler.zig | sanitizeOutput, isSensitiveKey, hex lookup |
| src/handlers/json_handler.zig | Pre-validation removed, inline NaN check, redaction |
| src/handlers/syslog_rfc5424.zig | @errorName guard, redaction |
| src/handlers/journald.zig | Buffered stderr, sanitization, redaction |
| src/handlers/windows_eventlog.zig | @errorName guard, redaction |
| src/handlers/rotating_file.zig | Path traversal, path_buf2, write buffering, error metrics |
| src/sinks/tcp_sink.zig | Circuit breaker, timeouts, attrs, redaction |
| src/sinks/http_sink.zig | HTTPS rejection, timeouts, header validation, attrs |
| src/sinks/udp_sink.zig | Attrs serialization |
| src/util/sanitize.zig | sanitizeOutput function |
| src/metrics/metrics.zig | incReconnections wired, expanded counters |
| tests/sink_test.zig | Updated for new API |

### Pass 2 (10 files, commit 677630f)

Logger.named() concatenation, DNS hostname resolution for TCP/HTTP sinks, multi_handler.zig fan-out handler, 15 new tests, parallel.zig README docs.

### Pass 3 (key files modified)

| File | Changes |
|------|---------|
| src/fmt/json_value.zig | NEW: shared writeJsonValue() extracted from 4 files |
| src/fmt/text_value.zig | NEW: shared writeTextValue() extracted from 4 files |
| src/handlers/rotating_file.zig | sanitizeOutput, sanitizeKey, isSensitiveKey, writeTextValue import, close vtable |
| src/handlers/windows_eventlog.zig | sanitizeKey on attr keys, sanitizeOutput on stderr fallback, deprecatedWriter removed |
| src/handlers/journald.zig | sanitizeKey on stderr attr keys, comptime guard on field-building, writeTextValue import |
| src/handlers/syslog_rfc5424.zig | writeSDString control char escaping |
| src/handlers/text_handler.zig | writeTextValue import |
| src/handlers/json_handler.zig | writeJsonValue import |
| src/sinks/tcp_sink.zig | writeJsonValue import, incReconnections wired |
| src/sinks/udp_sink.zig | writeJsonValue import, mutex scope narrowed |
| src/sinks/http_sink.zig | writeJsonValue import |
| .gitleaks.toml | Allowlist extended with json_logging.zig and accept.zig |
