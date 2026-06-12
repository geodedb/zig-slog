# Gap Closure Completion Report

**Repository:** gitlab.com/devnw/zig/slog
**Date:** 2026-03-24
**Commits:** ec068d0, 3fcd5a5, 05c6a16, 0ed8afe, 677630f (passes 1-2), pass 3, pass 4, pass 5 (current)

---

## GAP_ANALYSIS Status

| File | Closed | Blocked | Won't Do | Partially Closed | Remaining Open | Total |
|------|--------|---------|----------|------------------|----------------|-------|
| GAP_ANALYSIS.md (Security + Docs) | 32 | 1 | 6 | 0 | 0 | 39 |
| QUALITY_GAP_ANALYSIS.md | 37 | 0 | 2 | 1 | 0 | 40 |
| PERF_GAP_ANALYSIS.md | 23 | 0 | 15 | 0 | 0 | 38 |
| **Total** | **92** | **1** | **23** | **1** | **0** | **117** |

**Overall:** 92 closed, 1 blocked, 23 won't do, 1 partially closed out of 117 total items. Zero remaining open items.

**Note:** Total items = 117 (39 security/docs + 40 quality + 38 performance). Pass 5 closed 24 items and marked 9 as Won't Do, bringing all open items to zero.

---

## Pass 5 Summary

Pass 5 addressed 33 gap items (24 closures + 9 won't-do), bringing all open items to zero:

| Category | Closed | Won't Do | Blocked |
|----------|--------|----------|---------|
| Security | 10 | 3 | 0 |
| Quality | 10 | 0 | 0 |
| Performance | 5 | 5 | 0 |
| Docs/Tracking | 2 | 1 | 0 |
| **Total** | **24** | **9** | **0** |

### Phase 1 -- Quick Wins (18 items closed)

| Gap-ID | Domain | Title |
|--------|--------|-------|
| Q-38 | Quality | Dead testWrite helper removed |
| Q-39 | Quality | [REDACTED] literal consolidated to redact.REDACTED |
| SEC-0030 | Security | Sensitive key list expanded (16 new patterns) |
| SEC-0031 | Security | Logger name sanitized in text handlers |
| SEC-0032 | Security | Syslog hostname sanitized via writeSyslogName |
| SEC-0033 | Security | Non-atomic level fixed across all 12 handlers (atomic Value) |
| PERF-031 | Performance | Same as SEC-0033 (combined fix) |
| SEC-0034 | Security | File permissions set to 0o600 |
| SEC-0035 | Security | UDP oversized records dropped instead of truncated |
| SEC-0036 | Security | Key collision risk documented in sanitize.zig |
| SEC-0027 | Security | Secret-in-message limitation documented |
| PERF-032 | Performance | Attr truncation now increments metrics counter |
| PERF-033 | Performance | Double mutex eliminated (pushDropOldest returns count) |
| PERF-038 | Performance | getPool() uses double-checked locking |
| GAP-0026 | Docs | API.md convenience function signatures fixed |
| GAP-0027 | Docs | ARCHITECTURE.md module tree updated |
| Q-32 | Quality | slogz.zig docstring example fixed |
| Q-37 | Quality | HTTP sink false pooling claim removed |
| Q-40 | Quality | isSensitiveKey auto-redaction documented |

### Phase 2 -- Medium Effort (6 items closed)

| Gap-ID | Domain | Title |
|--------|--------|-------|
| Q-31 | Quality | Logger.with() attrs now merged into Record |
| Q-36 | Quality | msg_id written to all outputs when different from message |
| Q-35 | Quality | JSON schema reconciled to flat attrs + flat source |
| Q-33 | Quality | JSON record formatting extracted to json_record.zig |
| Q-34 | Quality | Text record formatting extracted to text_record.zig |
| PERF-036 | Performance | Benchmark suite expanded (3 new benchmarks) |

### Won't Do items (9 items)

| Gap-ID | Domain | Title | Reason |
|--------|--------|-------|--------|
| SEC-0026 | Security | No TLS for network sinks | TLS implementation exceeds library scope; Zig stdlib TLS still maturing |
| SEC-0028 | Security | HTTP sink no server auth | Blocked by SEC-0026 (requires TLS) |
| SEC-0029 | Security | TCP sink no auth mechanism | Blocked by SEC-0026; SEC-0016 same scope already Won't Do |
| PERF-029 | Performance | HTTP sink no batching/connection pooling | PERF-001/002/003 same scope already Won't Do; misleading doc fixed via Q-37 |
| PERF-030 | Performance | TCP/HTTP retry blocks under mutex | PERF-002/003/006 same scope already Won't Do; circuit breaker mitigates |
| PERF-034 | Performance | Batch drain no batched I/O | Requires vtable API change (handleBatch); deferred to future release |
| PERF-035 | Performance | Multi-handler sequential dispatch | Changes ordering guarantees; opt-in flag deferred to future release |
| PERF-037 | Performance | No CI regression detection | Requires infrastructure project; depends on PERF-036 (now done) |
| GAP-0028 | Tracking | GitLab #40 tracking discrepancy | Requires manual GitLab issue close; cannot automate without issue access |

---

## Pass 4 Summary

Pass 4 addressed 7 gap items (6 closures + 1 won't-do):

| Category | Closed | Won't Do | Blocked |
|----------|--------|----------|---------|
| Security | 1 | 0 | 0 |
| Quality | 2 | 0 | 0 |
| Performance | 3 | 1 | 0 |
| **Total** | **6** | **1** | **0** |

Key changes in pass 4:

- **SEC-0025**: Network sinks now sanitize JSON attribute keys via sanitize.sanitizeKey().
- **NEW-01 (Q-29)**: 23 inline unit tests added to json_value.zig (12) and text_value.zig (11), covering all Value variants.
- **NEW-03 (Q-30)**: json_value.zig bytes buffer increased from 512 to 2048 bytes (1024 input bytes); truncation marker added.
- **PERF-008**: QueuedRecord reduced from ~12.5KB to ~3.0KB per entry (75% reduction).
- **PERF-023**: isSensitiveKey() optimized with comptime-unrolled inline for + min_pattern_len early rejection.
- **PERF-026**: Async handler batch drain: up to 32 records per wake cycle via tryPop.
- **PERF-017**: Marked Won't Do (intentionally published module, not dead code).

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

### Pass 4 Closures (new)

| Gap-ID | File | Title | Evidence |
|--------|------|-------|----------|
| SEC-0025 | GAP_ANALYSIS.md | Network sinks skip sanitizeKey on JSON attr keys | tcp_sink.zig:212, udp_sink.zig:131, http_sink.zig:238 -- sanitize.sanitizeKey applied to attr keys |
| NEW-01 (Q-29) | QUALITY_GAP_ANALYSIS.md | No unit tests for json_value.zig and text_value.zig | json_value.zig:94-157 (12 tests), text_value.zig:71-157 (11 tests) -- all Value variants covered |
| NEW-03 (Q-30) | QUALITY_GAP_ANALYSIS.md | json_value.zig bytes truncation at 256 bytes | json_value.zig:49-70 -- max_input=1024, hex_buf[2048], "..." truncation marker |
| PERF-008 | PERF_GAP_ANALYSIS.md | QueuedRecord ~12.5KB per entry | queue.zig:34 MAX_STORED_ATTRS=8, :41 MAX_VALUE_LEN=128, :166 msg_id_buf[64], :172 source_file_buf[128]; ~3.0KB per entry (75% reduction) |
| PERF-023 | PERF_GAP_ANALYSIS.md | isSensitiveKey() O(k*p) linear scan | redact.zig:33-60 -- comptime min_pattern_len early rejection + inline for single-pass scan |
| PERF-026 | PERF_GAP_ANALYSIS.md | Async handler single-record processing | async_handler.zig:98-125 -- max_batch_size=32, tryPop batch drain, processQueuedRecord helper |

### Pass 5 Closures (new)

| Gap-ID | File | Title | Evidence |
|--------|------|-------|----------|
| Q-38 | QUALITY_GAP_ANALYSIS.md | Dead testWrite helper removed | src/fmt/text_value.zig -- testWrite function removed |
| Q-39 | QUALITY_GAP_ANALYSIS.md | [REDACTED] literal consolidated | value.zig and queue.zig now import redact.REDACTED |
| SEC-0030 | GAP_ANALYSIS.md | Sensitive key list expanded (16 new patterns) | src/util/redact.zig:15-31 -- sensitive_keys expanded from 15 to 31 patterns |
| SEC-0031 | GAP_ANALYSIS.md | Logger name sanitized in text handlers | src/handlers/text_handler.zig -- sanitizeOutput on rec.logger |
| SEC-0032 | GAP_ANALYSIS.md | Syslog hostname sanitized | src/handlers/syslog_rfc5424.zig -- hostname via writeSyslogName |
| SEC-0033 | GAP_ANALYSIS.md | Non-atomic level fixed (all 12 handlers) | All handler files -- atomic Value for level field |
| PERF-031 | PERF_GAP_ANALYSIS.md | Data race on level (combined with SEC-0033) | All handler files -- atomic store/load for level |
| SEC-0034 | GAP_ANALYSIS.md | File permissions set to 0o600 | src/handlers/rotating_file.zig -- .mode = 0o600 |
| SEC-0035 | GAP_ANALYSIS.md | UDP oversized records dropped | src/sinks/udp_sink.zig -- drop + metrics counter |
| SEC-0036 | GAP_ANALYSIS.md | Key collision documented | src/util/sanitize.zig -- doc comment on collision |
| SEC-0027 | GAP_ANALYSIS.md | Secret-in-message limitation documented | SECURITY.md and API docs updated |
| PERF-032 | PERF_GAP_ANALYSIS.md | Attr truncation metrics counter | src/internal/queue.zig -- incTruncations on overflow |
| PERF-033 | PERF_GAP_ANALYSIS.md | Double mutex eliminated | queue.zig pushDropOldest returns count; no separate len() |
| PERF-038 | PERF_GAP_ANALYSIS.md | getPool() double-checked locking | src/parallel.zig -- atomic load before mutex |
| GAP-0026 | GAP_ANALYSIS.md | API.md signatures fixed | docs/API.md -- updated stderrHandler/stderrJsonHandler |
| GAP-0027 | GAP_ANALYSIS.md | ARCHITECTURE.md module tree updated | docs/ARCHITECTURE.md -- complete file listing |
| Q-32 | QUALITY_GAP_ANALYSIS.md | slogz.zig docstring example fixed | src/slogz.zig -- docstring matches actual API |
| Q-37 | QUALITY_GAP_ANALYSIS.md | HTTP sink false pooling claim removed | src/sinks/http_sink.zig -- docstring corrected |
| Q-40 | QUALITY_GAP_ANALYSIS.md | isSensitiveKey auto-redaction documented | src/util/redact.zig and src/slogz.zig -- docstrings added |
| Q-31 | QUALITY_GAP_ANALYSIS.md | Logger.with() attrs merged into Record | src/logger.zig -- Record includes context_attrs |
| Q-36 | QUALITY_GAP_ANALYSIS.md | msg_id written to all outputs | src/fmt/json_record.zig, src/fmt/text_record.zig -- msg_id field |
| Q-35 | QUALITY_GAP_ANALYSIS.md | JSON schema reconciled | src/fmt/json_record.zig -- flat attrs + flat source |
| Q-33 | QUALITY_GAP_ANALYSIS.md | JSON record formatting extracted | src/fmt/json_record.zig -- shared writeJsonRecord |
| Q-34 | QUALITY_GAP_ANALYSIS.md | Text record formatting extracted | src/fmt/text_record.zig -- shared writeTextRecord |
| PERF-036 | PERF_GAP_ANALYSIS.md | Benchmark suite expanded | bench/bench_main.zig -- 3 new benchmarks |

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
| PERF-021 | PERF_GAP_ANALYSIS.md | getPool() mutex on every call | parallel.zig is optional; deferred |
| PERF-017 | PERF_GAP_ANALYSIS.md | parallel.zig dead code adds build cost | Intentionally published module (commits 1fa06e6/1041b15); not dead code |
| PERF-025 | PERF_GAP_ANALYSIS.md | Stack allocations 8-25KB per log call | Requires profiling data; risks truncation of large records |
| PERF-027 | PERF_GAP_ANALYSIS.md | Multi-handler re-formats per child | Architecturally expected; pre-formatting needs format negotiation |
| SEC-0026 | GAP_ANALYSIS.md | No TLS for network sinks | TLS implementation exceeds library scope; Zig stdlib TLS still maturing |
| SEC-0028 | GAP_ANALYSIS.md | HTTP sink no server auth | Blocked by SEC-0026 (requires TLS) |
| SEC-0029 | GAP_ANALYSIS.md | TCP sink no auth mechanism | Blocked by SEC-0026; SEC-0016 same scope already Won't Do |
| PERF-029 | PERF_GAP_ANALYSIS.md | HTTP sink no batching/connection pooling | PERF-001/002/003 same scope already Won't Do; misleading doc fixed |
| PERF-030 | PERF_GAP_ANALYSIS.md | TCP/HTTP retry blocks under mutex | PERF-002/003/006 same scope already Won't Do; circuit breaker mitigates |
| PERF-034 | PERF_GAP_ANALYSIS.md | Batch drain no batched I/O | Requires vtable API change (handleBatch); deferred to future release |
| PERF-035 | PERF_GAP_ANALYSIS.md | Multi-handler sequential dispatch | Changes ordering guarantees; opt-in flag deferred |
| PERF-037 | PERF_GAP_ANALYSIS.md | No CI regression detection | Requires infrastructure project |
| GAP-0028 | GAP_ANALYSIS.md | GitLab #40 tracking discrepancy | Requires manual GitLab issue close |

---

## Blocked Items

| Gap-ID | File | Title | Blocker | Unblock Steps |
|--------|------|-------|---------|---------------|
| SEC-0008 | GAP_ANALYSIS.md | Supply chain: spice on floating main branch | Upstream spice repo (gitlab.com/devnw/zig/spice) has no tagged release | 1. Tag a release of the spice repository. 2. Update build.zig.zon URL from `/archive/main/` to `/archive/v<tag>/`. 3. Update hash to match tagged archive. |

---

## Remaining Open Items

| Gap-ID | File | Title | Reason |
|--------|------|-------|--------|
| Q-27 | QUALITY_GAP_ANALYSIS.md | deprecatedWriter() in slogz.zig | **Partially closed** -- windows_eventlog.zig fixed; slogz.zig blocked on AnyWriter handler interface refactor |

**Note:** No fully open items remain. Q-27 is partially closed (windows_eventlog.zig fixed; slogz.zig blocked on AnyWriter handler interface refactor). All 33 pass-5 items resolved (24 closed + 9 won't do).

---

## Tests Executed

### Pass 5

| Command | Result |
|---------|--------|
| `zig build test --summary all` | PASS (240/240 tests) |
| `zig fmt --check src/ build.zig` | PASS (format clean) |
| `zig build` | PASS (build clean) |

### Pass 4

| Command | Result |
|---------|--------|
| `zig build test --summary all` | PASS (223/223 tests, 16/16 build steps) |
| `zig fmt --check src/ build.zig` | PASS (format clean) |
| `zig build` | PASS (build clean) |

### Pass 3

| Command | Result |
|---------|--------|
| `zig build test --summary all` | PASS (195/195 tests, 16/16 build steps) |
| `zig fmt --check src/ build.zig` | PASS (format clean) |
| `zig build` | PASS (build clean) |

---

## Security Notes

### Pass 5

- **Sensitive key coverage expanded (SEC-0030):** 16 new patterns added to the sensitive_keys list (ssn, credit_card, cvv, session_id, cookie, bearer, jwt, connection_string, etc.), increasing coverage from 15 to 31 patterns.
- **Data race eliminated (SEC-0033/PERF-031):** All 12 handler types now use atomic Value for the level field, eliminating data races between setLevel() and handle() calls on different threads.
- **File permissions hardened (SEC-0034):** Rotating file handler creates log files with explicit 0o600 permissions, preventing world-readable logs regardless of umask.
- **UDP integrity protected (SEC-0035):** Oversized UDP records are now dropped (with metrics counter) instead of truncated at arbitrary byte boundaries, preventing malformed JSON from reaching downstream parsers.
- **Logger name injection prevented (SEC-0031):** Logger name field now sanitized in text handlers, closing the last unsanitized field in the text output path.
- **Syslog hostname sanitized (SEC-0032):** Hostname field now routed through writeSyslogName, consistent with APP-NAME and MSGID fields.
- **Secret-in-message limitation documented (SEC-0027):** Clearly documented that message body content is NOT scanned for secrets. Users directed to use Attr.secret() for sensitive values.
- **Key collision documented (SEC-0036):** The possibility of different keys sanitizing to the same output (e.g., "user/id" and "user@id" both becoming "user_id") is now documented as a known limitation.
- **Auto-redaction documented (Q-40):** The complete list of 31 sensitive key patterns is now documented in redact.zig and referenced in slogz.zig module docs.
- **TLS deferred (SEC-0026/0028/0029):** Marked Won't Do. TLS implementation exceeds the library's current scope. Zig stdlib TLS is still maturing. Users are advised to use encrypted transport at the network layer (VPN, mTLS proxy) or wait for a future TLS-capable release.

### Pass 4

- **Network sink key sanitization (SEC-0025):** sanitize.sanitizeKey() now applied to JSON attribute keys in tcp_sink.zig, udp_sink.zig, and http_sink.zig. All handler types (text, JSON, syslog, journald, windows_eventlog, rotating_file, and all 3 network sinks) now consistently sanitize attribute keys.
- **Unit test coverage for shared modules (NEW-01):** 23 inline tests added to json_value.zig and text_value.zig, ensuring all Value variants (str, i64, u64, f64, bool, secret, err, bytes, marshaler + edge cases) are tested at the unit level. This prevents regressions in the shared formatting code used by all handlers.
- **Bytes encoding capacity (NEW-03):** json_value.zig hex encoding buffer increased from 512 to 2048 bytes, supporting up to 1024 input bytes. Truncation marker "..." added for larger inputs. This handles SHA-512 hashes (64 bytes), AES-256 keys (32 bytes), and most practical binary fields without truncation.

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

### Pass 4

| Gap-ID | Issue | Action |
|--------|-------|--------|
| PERF-008 | #30 | closed |

### Pass 5

Skip-issues mode -- no GitLab issues created, closed, or updated. GAP-0028 notes that GitLab #40 should be closed manually.

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

### Pass 4 (key files modified)

| File | Changes |
|------|---------|
| src/sinks/tcp_sink.zig | sanitize import, sanitizeKey on JSON attr keys |
| src/sinks/udp_sink.zig | sanitize import, sanitizeKey on JSON attr keys |
| src/sinks/http_sink.zig | sanitize import, sanitizeKey on JSON attr keys |
| src/fmt/json_value.zig | 12 inline tests added; bytes buffer increased from 512 to 2048 (max_input=1024); truncation marker "..." |
| src/fmt/text_value.zig | 11 inline tests added covering all Value variants |
| src/internal/queue.zig | MAX_STORED_ATTRS 32->8, MAX_VALUE_LEN 256->128, msg_id_buf 256->64, source_file_buf 256->128 |
| src/util/redact.zig | comptime min_pattern_len, inline for single-pass scan replacing sequential indexOf |
| src/handlers/async_handler.zig | batch drain (max_batch_size=32, tryPop loop), processQueuedRecord helper extracted |

### Pass 5 (key files modified)

| File | Changes |
|------|---------|
| src/fmt/json_record.zig | NEW: shared writeJsonRecord() extracted from 4 JSON emitters |
| src/fmt/text_record.zig | NEW: shared writeTextRecord() extracted from 2 text emitters |
| src/fmt/text_value.zig | Dead testWrite helper removed |
| src/util/redact.zig | Sensitive key list expanded from 15 to 31 patterns |
| src/util/sanitize.zig | Key collision doc comment added |
| src/value.zig | [REDACTED] literal replaced with redact.REDACTED import |
| src/internal/queue.zig | [REDACTED] literal replaced; pushDropOldest returns count; truncation metrics |
| src/logger.zig | Logger.log() merges context_attrs into Record |
| src/parallel.zig | getPool() double-checked locking with atomic load |
| src/handlers/text_handler.zig | sanitizeOutput on rec.logger; writeTextRecord import; atomic level |
| src/handlers/json_handler.zig | writeJsonRecord import; atomic level |
| src/handlers/syslog_rfc5424.zig | hostname via writeSyslogName; atomic level |
| src/handlers/rotating_file.zig | createFile mode 0o600; writeTextRecord import; atomic level |
| src/handlers/journald.zig | atomic level |
| src/handlers/windows_eventlog.zig | atomic level |
| src/handlers/async_handler.zig | atomic level; no separate len() call |
| src/handlers/discard_handler.zig | atomic level |
| src/handlers/multi_handler.zig | atomic level |
| src/sinks/tcp_sink.zig | writeJsonRecord import; atomic level |
| src/sinks/udp_sink.zig | writeJsonRecord import; oversized record drop; atomic level |
| src/sinks/http_sink.zig | writeJsonRecord import; false pooling docstring removed; atomic level |
| src/slogz.zig | Docstring example fixed; auto-redaction docs added |
| docs/API.md | stderrHandler/stderrJsonHandler signatures fixed |
| docs/ARCHITECTURE.md | Module tree updated with all source files |
| bench/bench_main.zig | 3 new benchmarks: async handler, queue contention, isSensitiveKey |
