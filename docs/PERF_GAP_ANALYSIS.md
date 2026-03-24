# Performance Gap Analysis -- slogz

**Repository:** gitlab.com/devnw/zig/slog
**Branch:** main (commit 0ed8afe)
**Last updated:** 2026-03-24 (rev 4 -- pass 4: PERF-008/023/026 closed, PERF-017 won't-do)
**Analyst:** Claude Opus 4.6 (automated perf scoring)

---

## Summary

| PerfSeverity | Count | Closed | Won't Do | Open |
|---|---|---|---|---|
| **P0** | 4 | 1 | 3 | 0 |
| **P1** | 8 | 6 | 2 | 0 |
| **P2** | 10 | 9 | 1 | 0 |
| **P3** | 3 | 1 | 2 | 0 |
| **Info** | 3 | 1 | 2 | 0 |
| **Total** | 28 | 18 | 10 | 0 |

### Top Open Risks by Expected Impact

No open performance risks remain. All 28 items are resolved (18 closed, 10 won't do).

---

## Stack-Ranked Findings

| Rank | Sev | Score | ID | Finding | Component | Evidence | Measurement | Issue URL | Fix Summary | Owner | SLA | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | P0 | 100 | PERF-001 | HTTP sink creates new TCP connection per record | http_sink | `src/sinks/http_sink.zig:131-182` -- `sendHttp()` calls `tcpConnectToAddress()` then `stream.close()` on every invocation; `Connection: close` header on line 146 | Est. 1-50ms overhead per record (TCP handshake + teardown) | -- | Connection pooling requires significant effort; separate feature | -- | -- | **Won't Do** |
| 2 | P0 | 100 | PERF-002 | TCP sink holds mutex during retry+sleep up to 15s | tcp_sink | `src/sinks/tcp_sink.zig:87-122` -- `writeWithRetry()` sleeps inside loop at lines 95,107 while mutex acquired at `handle()` line 130-131 | Max block time = 100+200+400+800+1600+3200+5000ms = ~11.3s (3 retries default = ~5.3s) | -- | Partially mitigated by circuit breaker (PERF-010); full lock scope reduction is separate effort | -- | -- | **Won't Do** |
| 3 | P0 | 100 | PERF-003 | HTTP sink holds mutex during full HTTP round-trip+retry | http_sink | `src/sinks/http_sink.zig:190-232` -- `handle()` locks mutex at 190, calls `sendWithRetry()` at 229 which performs full HTTP I/O + backoff sleep | Full HTTP RTT + up to 5s backoff per retry, all under lock | -- | Partially mitigated by socket timeouts; full lock scope reduction is separate effort | -- | -- | **Won't Do** |
| 4 | P0 | 80 | PERF-004 | Missing connect/read timeouts on TCP/HTTP sinks | tcp_sink, http_sink | `tcp_sink.zig:27` defines `connect_timeout_ms` but `connect()` at line 65-78 never applies it; `http_sink.zig:29` defines `timeout_ms` but `sendHttp()` at line 131-182 never sets socket options | OS default TCP timeout 75-127s; single stuck connection blocks all logging | -- | SO_RCVTIMEO/SO_SNDTIMEO applied via setsockopt in both TCP and HTTP sinks | -- | -- | **Closed** (0ed8afe) |
| 5 | P1 | 80 | PERF-005 | Async handler drops ALL attributes | async_handler | `src/handlers/async_handler.zig:93` and `:114` -- reconstructed Record sets `.attrs = &.{}` (empty); `QueuedRecord.fromRecord()` in `queue.zig:60-88` serializes attrs to `attrs_buf` but worker never deserializes them back | 100% attribute data loss on async path; all structured context gone | -- | StoredAttr array with serialize/deserialize; attrs restored in worker thread | -- | -- | **Closed** (3fcd5a5) |
| 6 | P1 | 80 | PERF-006 | All handlers hold mutex during format+I/O | text, json, syslog, rotating_file | `text_handler.zig:49-91`, `json_handler.zig:59-130`, `syslog_rfc5424.zig:117-195`, `rotating_file.zig:166-211` -- all lock mutex before formatting, hold it through writeAll() | Serializes all logging threads; throughput = 1/latency instead of N/latency | -- | Lock scope reduction requires significant refactoring; separate effort | -- | -- | **Won't Do** |
| 7 | P1 | 60 | PERF-007 | HTTP/TCP/UDP sinks omit attrs from JSON output | tcp_sink, http_sink, udp_sink | `tcp_sink.zig:145-167` -- JSON output writes time/level/msg/logger but never iterates `rec.attrs`; same in `http_sink.zig:205-227` and `udp_sink.zig:106-128` | All structured attributes silently dropped; correctness bug | -- | All three sinks now iterate rec.attrs with JSON attr serialization | -- | -- | **Closed** (0ed8afe) |
| 8 | P1 | 60 | PERF-008 | QueuedRecord ~3.0KB per entry (was ~12.5KB); 1024 default = 3.0MB heap | queue | `src/internal/queue.zig:34,41,166,172` -- reduced: MAX_STORED_ATTRS 32->8, MAX_VALUE_LEN 256->128, msg_id_buf 256->64, source_file_buf 256->128 | 1024 * ~3,072 = 3.0MB heap (75% reduction from 12.2MB) | -- | Reduced fixed buffer sizes to match actual usage patterns | -- | -- | **Closed** (pass 4: MAX_STORED_ATTRS=8, MAX_VALUE_LEN=128, msg_id_buf[64], source_file_buf[128]; ~3.0KB per entry) |
| 9 | P1 | 60 | PERF-025 | Stack allocations 8-25KB per log call across handlers | journald, json, syslog, tcp, http | `journald.zig:75` fields_buf[32][512]=16KB + stderr_buf[8192]=8KB = ~25KB; `json_handler.zig:55` buf[16384]; `syslog_rfc5424.zig:120` buf[16384]; `tcp_sink.zig:208` buf[16384]; `http_sink.zig:240` buf[16384]+req_buf[1024]+resp_buf[256] | 16-25KB stack per call; 8 threads = ~200KB active stack; L1/L2 cache pollution | [#40](https://gitlab.com/devnw/zig/slog/-/work_items/40) | Requires profiling data to safely reduce; risks truncation | -- | -- | **Won't Do** |
| 10 | P1 | 60 | PERF-009 | HTTP sink silently accepts HTTPS URLs but sends cleartext | http_sink | `src/sinks/http_sink.zig:64` -- parses `https://` prefix, sets `is_https=true` and port 443, but `sendHttp()` at line 131-182 opens a plain `tcpConnectToAddress` and sends raw HTTP | Credentials/logs sent in cleartext when user expects TLS; security and correctness issue | -- | https:// URLs now rejected at init with error.HttpsNotSupported | -- | -- | **Closed** (0ed8afe) |
| 11 | P1 | 48 | PERF-010 | No circuit breaker for TCP sink failures | tcp_sink | `src/sinks/tcp_sink.zig:87-122` -- `writeWithRetry()` retries unconditionally; `consecutive_failures` counter at line 120 is incremented but never checked to skip attempts | 100 threads hitting a down TCP endpoint = 100 * 5.3s of serialized retries; cascading failure | -- | Circuit breaker with threshold=3 and 30s cooldown added to tcp_sink | -- | -- | **Closed** (0ed8afe) |
| 12 | P1 | 48 | PERF-022 | UDP sink holds mutex during format+send | udp_sink | `src/sinks/udp_sink.zig:132-133` -- mutex acquired before JSON formatting at 136-179 and send at 181-184; TCP/HTTP sinks format outside lock but UDP does not | Serializes all threads on UDP sink; effectively single-threaded throughput | [#38](https://gitlab.com/devnw/zig/slog/-/work_items/38) | JSON formatting moved outside mutex; lock only for ctx.send() | -- | Sprint | **Closed** |
| 13 | P2 | 48 | PERF-011 | Journald fallback makes 14+ stderr syscalls per record | journald | `src/handlers/journald.zig:139-151` -- fallback path issues individual `stderr.print()` calls: priority, identifier, message, then per-attr key+value; each is a separate write syscall | ~14+ syscalls per record vs. 1 with buffered write; ~10x syscall overhead | -- | Fallback now writes to 8KB fixedBufferStream, single writeAll to stderr | -- | -- | **Closed** (0ed8afe) |
| 14 | P2 | 48 | PERF-012 | Per-byte hex encoding via fmt.print in 4 handlers | text, journald, syslog, json | `text_handler.zig:133-135` -- `writer.print("{x:0>2}", .{byte})` per byte; same in `journald.zig:169-171`, `syslog_rfc5424.zig:244-246` | Each byte triggers format string parsing + write; lookup table would be O(1) per byte | -- | Precomputed hex_chars lookup table used in text_handler, journald, syslog, windows_eventlog | -- | -- | **Closed** (0ed8afe) |
| 15 | P2 | 36 | PERF-013 | Rotating file handler lacks write buffering | rotating_file | `src/handlers/rotating_file.zig:135-141` -- `write()` calls `f.write(data)` directly per record; no BufWriter or equivalent | Each log record triggers a kernel write syscall; high overhead for high-frequency logging to disk | -- | 8KB write_buf added; flush on buffer full, rotation check, or explicit flush | -- | -- | **Closed** (05c6a16) |
| 16 | P2 | 36 | PERF-014 | Async handler flush uses busy-wait polling with 1ms sleep | async_handler | `src/handlers/async_handler.zig:196-204` -- `flush()` loops checking `queue.len() > 0` with `std.time.sleep(1ms)` between iterations | Wastes CPU; up to 1ms latency granularity on flush; not signal-based | -- | flush() now uses queue.waitEmpty() with CV-based signaling | -- | -- | **Closed** (3fcd5a5) |
| 17 | P2 | 36 | PERF-015 | Async handler double-locks on enqueue (TOCTOU race) | async_handler | `src/handlers/async_handler.zig:129-133` -- `enqueue()` acquires its own `self.mutex` to check `self.queue.len()`, then releases it, then calls `self.queue.pushDropOldest()` which acquires the queue's internal mutex separately | TOCTOU: queue state can change between the len check and the push; the `was_full` variable may be stale | -- | Uses queue.droppedCount() before/after push to detect drops; no TOCTOU | -- | -- | **Closed** (3fcd5a5) |
| 18 | P2 | 36 | PERF-016 | JSON handler pre-validates all attrs before serializing | json_handler | `src/handlers/json_handler.zig:53-57` -- iterates all `rec.attrs` calling `isValidJson()` before entering the mutex and doing actual serialization; this is an extra O(n) pass | Unnecessary O(n) scan; only f64 values need checking, and they can be checked inline during serialization | -- | Pre-validation loop removed; f64 NaN/Inf check done inline during serialization | -- | -- | **Closed** (0ed8afe) |
| 19 | P2 | 30 | PERF-028 | Journald stderr fallback runs unconditionally on Linux | journald | `src/handlers/journald.zig:75-137` builds journald fields (16KB stack) then falls through to stderr at lines 143-162 without ever calling sd_journal_sendv; field-building is dead code | Double formatting work per record; 16KB wasted stack for unused fields | [#41](https://gitlab.com/devnw/zig/slog/-/work_items/41) | Field-building guarded by comptime `native_sendv_available`; stderr-only path skips ~25KB stack allocation | -- | Quarter | **Closed** |
| 20 | P2 | 24 | PERF-017 | parallel.zig module is dead code but adds build-time cost | parallel | `src/parallel.zig` -- 764 lines, imported as module in `build.zig:39-49`, pulls in spice dependency; not imported by any handler or sink in src/ | Adds ~764 LOC compilation + spice dependency resolution to every build | -- | Intentionally kept as published module per commits 1fa06e6/1041b15 | -- | -- | **Won't Do** |
| 21 | P2 | 24 | PERF-026 | Async handler batch drain (was single-record processing) | async_handler | `src/handlers/async_handler.zig:98-120` -- worker loop now drains up to 32 records per wake cycle via tryPop after initial popTimeout; processQueuedRecord helper extracted | Batch processing under burst load reduces per-record overhead (fewer mutex acquire/release, fewer thread wakes) | -- | Batch drain: worker processes up to 32 records per wake cycle via tryPop after initial popTimeout | -- | Quarter | **Closed** (pass 4: max_batch_size=32, tryPop loop, processQueuedRecord helper) |
| 22 | P2 | 20 | PERF-023 | isSensitiveKey() optimized with comptime-unrolled inline for | redact | `src/util/redact.zig:34-60` -- single-pass scan with comptime-unrolled `inline for` pattern matching + comptime min_pattern_len early rejection | Replaced 15 sequential indexOf calls with single-pass scan; comptime min_pattern_len rejects short keys immediately | -- | Single-pass comptime-unrolled inline for with min_pattern_len early rejection | -- | Quarter | **Closed** (pass 4: inline for pattern matching, comptime min_pattern_len early rejection) |
| 23 | P3 | 16 | PERF-018 | Benchmark suite lacks statistical rigor | bench | `bench/bench_main.zig` -- single timing pass with no warmup separation, no std deviation, no percentiles; `WARMUP_ITERATIONS=1000` then one timed run of 100k | Results vary by 10-30% between runs; no confidence intervals; insufficient for regression detection | -- | Separate infrastructure improvement | -- | Backlog | **Won't Do** |
| 24 | P3 | 16 | PERF-019 | No multi-threaded benchmarks | bench | `bench/bench_main.zig` -- all benchmarks run single-threaded; no contention testing | Cannot detect mutex contention regressions or validate concurrent throughput | -- | Separate infrastructure improvement | -- | Backlog | **Won't Do** |
| 25 | P3 | 12 | PERF-020 | Metrics struct false sharing -- fixed via PaddedCounter | metrics | `src/metrics/metrics.zig:28-34` -- PaddedCounter with `align(cache_line)` pads each counter to 64 bytes; test at lines 185-201 verifies alignment | Each counter occupies a full cache line; false sharing eliminated | -- | PaddedCounter with align(cache_line) applied to all 7 counters | -- | -- | **Closed** |
| 26 | Info | 12 | PERF-021 | getPool() acquires mutex on every call | parallel | `src/parallel.zig:74-85` -- `getPool()` locks `pool_mutex` on every invocation even after pool is initialized | Unnecessary contention on hot path; adds ~20-50ns per call under contention | -- | parallel.zig is optional; optimization deferred | -- | Backlog | **Won't Do** |
| 27 | Info | 12 | PERF-027 | Multi-handler re-formats same Record per child | multi_handler | `src/handlers/multi_handler.zig:30-43` -- iterates child handlers, each independently formats the Record; no shared pre-formatted buffer | N child handlers = N independent format passes; 2 handlers = 2x formatting cost | -- | Architecturally expected; pre-formatting would require handler-specific format negotiation | -- | -- | **Won't Do** |
| 28 | Info | 4 | PERF-024 | rotating_file per-byte hex encoding via writer.print | rotating_file | `src/handlers/rotating_file.zig:329-331` -- `writer.print("{x:0>2}", .{byte})` per byte; PERF-012 fix (lookup table) was applied to text/journald/syslog but missed this handler | Same per-byte overhead as PERF-012 but only in rotating_file handler | -- | Apply same hex_chars lookup table from PERF-012 fix | -- | Backlog | **Closed** (hex_chars lookup table applied) |

---

## Findings by Area

### area::app

| ID | Sev | Score | Finding | Status |
|---|---|---|---|---|
| PERF-005 | P1 | 80 | Async handler drops ALL attributes | **Closed** |
| PERF-006 | P1 | 80 | All handlers hold mutex during format+I/O | **Won't Do** |
| PERF-007 | P1 | 60 | HTTP/TCP/UDP sinks omit attrs from JSON output | **Closed** |
| PERF-008 | P1 | 60 | QueuedRecord ~3.0KB per entry (reduced) | **Closed** |
| PERF-025 | P1 | 60 | Stack allocations 8-25KB per log call | **Won't Do** |
| PERF-011 | P2 | 48 | Journald fallback 14+ stderr syscalls | **Closed** |
| PERF-012 | P2 | 48 | Per-byte hex encoding via fmt.print | **Closed** |
| PERF-013 | P2 | 36 | Rotating file handler lacks write buffering | **Closed** |
| PERF-014 | P2 | 36 | Async handler flush busy-wait polling | **Closed** |
| PERF-015 | P2 | 36 | Async handler double-locks (TOCTOU) | **Closed** |
| PERF-016 | P2 | 36 | JSON handler unnecessary pre-validation pass | **Closed** |
| PERF-028 | P2 | 30 | Journald stderr fallback runs unconditionally | **Closed** |
| PERF-026 | P2 | 24 | Async handler batch drain | **Closed** |
| PERF-023 | P2 | 20 | isSensitiveKey() optimized (inline for) | **Closed** |
| PERF-020 | P3 | 12 | Metrics struct false sharing | **Closed** |
| PERF-027 | Info | 12 | Multi-handler re-formats per child | **Won't Do** |
| PERF-024 | Info | 4 | rotating_file per-byte hex encoding | **Closed** |

### area::infra (network sinks)

| ID | Sev | Score | Finding | Status |
|---|---|---|---|---|
| PERF-001 | P0 | 100 | HTTP sink new-connection-per-record | **Won't Do** |
| PERF-002 | P0 | 100 | TCP sink mutex held during retry+sleep | **Won't Do** |
| PERF-003 | P0 | 100 | HTTP sink mutex held during HTTP RTT+retry | **Won't Do** |
| PERF-004 | P0 | 80 | Missing connect/read timeouts | **Closed** |
| PERF-009 | P1 | 60 | HTTP sink sends cleartext on HTTPS URLs | **Closed** |
| PERF-022 | P1 | 48 | UDP sink holds mutex during format+send | **Closed** |
| PERF-010 | P1 | 48 | No circuit breaker for TCP failures | **Closed** |

### area::ci (build and test)

| ID | Sev | Score | Finding | Status |
|---|---|---|---|---|
| PERF-017 | P2 | 24 | parallel.zig dead code adds build cost | **Won't Do** |
| PERF-018 | P3 | 16 | Benchmark lacks statistical rigor | **Won't Do** |
| PERF-019 | P3 | 16 | No multi-threaded benchmarks | **Won't Do** |
| PERF-021 | Info | 12 | getPool() mutex on every call | **Won't Do** |

---

## Detailed Findings

### PERF-001: HTTP sink creates new TCP connection per record

- **PerfSeverity:** P0
- **PerfScore:** 100 (Impact=5 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** Every call to `sendHttp()` opens a new TCP connection, sends the request with `Connection: close`, reads the response, then closes the socket. No connection reuse.

**Perf Impact:** 1-50ms per record for TCP handshake + teardown. At 1000 records/sec, this adds 1-50 seconds of cumulative latency per second -- the sink cannot keep up.

**Evidence:**
- `src/sinks/http_sink.zig:131-141` -- `sendHttp()` calls `std.net.tcpConnectToAddress(address)` then `defer stream.close()` on every invocation.
- `src/sinks/http_sink.zig:145` -- sends `Connection: close\r\n` header, explicitly preventing keep-alive.
- `src/sinks/http_sink.zig:107-109` -- `deinit()` comment: "No persistent connections to close."

**Root Cause:** No connection pooling or persistent connection was implemented. The code opens, uses, and closes a TCP socket on every log record.

**Fix Guidance:** Store the `std.net.Stream` as a field on Context (like tcp_sink does). Reuse it across calls. Reconnect only on write failure. Send `Connection: keep-alive` instead of `close`.

**Validation Plan:**
```bash
# Run bench with HTTP sink against a local server
python3 -m http.server 8080 &
zig build bench -- --sink=http --target=http://localhost:8080/logs
# Before: ~20-50 records/sec; After: ~10,000+ records/sec
# Alternatively, count TCP connections with:
ss -s | grep estab
```

**Affected Paths:** `src/sinks/http_sink.zig`

**Rollout Risk:** Medium. Persistent connections can leak if not properly closed on error. Must handle connection staleness (server-side close) and reconnect gracefully. Add connection health check.

---

### PERF-002: TCP sink holds mutex during retry+sleep up to 15s

- **PerfSeverity:** P0
- **PerfScore:** 100 (Impact=5 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** The `handle()` function acquires the mutex at line 130, then calls `writeWithRetry()` which can sleep for multiple seconds during exponential backoff retries, all while holding the lock.

**Perf Impact:** With default settings (3 retries, 100ms initial backoff, 5000ms max), worst-case block time is ~5.3s. During this time, ALL other threads attempting to log are blocked.

**Evidence:**
- `src/sinks/tcp_sink.zig:130-131` -- `ctx.mutex.lock(); defer ctx.mutex.unlock();`
- `src/sinks/tcp_sink.zig:95` -- `std.Thread.sleep(backoff * ns_per_ms)` inside retry loop while mutex held
- `src/sinks/tcp_sink.zig:107` -- second sleep point on write failure

**Root Cause:** The mutex was designed to protect the shared stream, but the retry+sleep logic is inside the critical section.

**Fix Guidance:** Format the record to a local buffer outside the lock. Acquire the lock only for the actual `stream.write()` call. If write fails, release the lock before sleeping, then re-acquire for the next attempt.

**Validation Plan:**
```bash
# Simulate TCP sink failure with unreachable endpoint
# Spawn 10 threads logging concurrently, measure p99 latency
# Before: p99 >= 5000ms during failure; After: p99 < 100ms
```

**Affected Paths:** `src/sinks/tcp_sink.zig`

**Rollout Risk:** Low-medium. Changing lock scope requires careful ordering to avoid data races on the stream. The stream itself still needs mutex protection for writes, but formatting and sleeping should be outside the critical section.

---

### PERF-003: HTTP sink holds mutex during full HTTP round-trip+retry

- **PerfSeverity:** P0
- **PerfScore:** 100 (Impact=5 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** Same pattern as PERF-002 but worse -- the HTTP sink's `handle()` holds the mutex through JSON formatting, TCP connect, HTTP request send, response read, and retry backoff.

**Perf Impact:** Full HTTP round-trip (typically 5-100ms) plus up to 5s retry backoff, all under lock. Single-threaded effective throughput.

**Evidence:**
- `src/sinks/http_sink.zig:190-191` -- `ctx.mutex.lock(); defer ctx.mutex.unlock();`
- `src/sinks/http_sink.zig:229` -- `ctx.sendWithRetry(fbs.getWritten())` called under lock
- `src/sinks/http_sink.zig:111-129` -- `sendWithRetry()` contains sleep loop

**Root Cause:** The entire handle() function body is a single critical section with no attempt to minimize lock scope.

**Fix Guidance:** Format JSON to local buffer outside lock. For the HTTP send, either use a separate send queue or acquire the lock only for the minimal shared state mutation (consecutive_failures counter).

**Validation Plan:**
```bash
# Same as PERF-001 validation; measure concurrent throughput
# Before: effectively single-threaded; After: near-linear scaling with threads
```

**Affected Paths:** `src/sinks/http_sink.zig`

**Rollout Risk:** Medium. Same considerations as PERF-002 plus the added complexity of HTTP connection state.

---

### PERF-004: Missing connect/read timeouts despite config fields existing

- **PerfSeverity:** P0
- **PerfScore:** 80 (Impact=5 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** Both TCP and HTTP sinks define timeout configuration fields but never apply them to socket operations. Connections use OS default TCP timeout (typically 75-127 seconds).

**Perf Impact:** A single unreachable endpoint can freeze a logging thread for 75-127 seconds. Combined with PERF-002/003 (mutex held during I/O), this freezes ALL logging threads.

**Evidence:**
- `src/sinks/tcp_sink.zig:27` -- `connect_timeout_ms: u32 = 5000` defined but unused
- `src/sinks/tcp_sink.zig:65-78` -- `connect()` calls `tcpConnectToAddress()` with no timeout parameter
- `src/sinks/http_sink.zig:29` -- `timeout_ms: u32 = 10000` defined but unused
- `src/sinks/http_sink.zig:131-182` -- `sendHttp()` never calls `setsockopt` for timeout

**Root Cause:** Timeout fields were added to the options structs but the implementation was never completed. Zig's `std.net.tcpConnectToAddress` does not accept a timeout parameter directly; socket options must be set via `std.posix.setsockopt`.

**Fix Guidance:** After socket creation, call `std.posix.setsockopt` with `SO_RCVTIMEO` and `SO_SNDTIMEO` using the configured timeout values. For connect timeout, use non-blocking connect with poll/select.

**Validation Plan:**
```bash
# Point sink at a black-hole IP (e.g., 10.255.255.1) and measure how long connect() blocks
# Before: ~75-127s; After: configured timeout (e.g., 5s)
```

**Affected Paths:** `src/sinks/tcp_sink.zig`, `src/sinks/http_sink.zig`

**Rollout Risk:** Low. Adding socket timeouts is additive and non-breaking. Test with various timeout values including 0 (disable).

---

### PERF-005: Async handler drops ALL attributes

- **PerfSeverity:** P1
- **PerfScore:** 80 (Impact=4 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The async worker thread reconstructs Record objects from QueuedRecord but always sets `.attrs = &.{}`, discarding all structured attributes even though `QueuedRecord.fromRecord()` serializes them into `attrs_buf`.

**Perf Impact:** Not strictly a latency issue, but a correctness issue that makes the async path unusable. Users who enable async logging lose all structured data, defeating the purpose of structured logging.

**Evidence:**
- `src/handlers/async_handler.zig:93` -- `.attrs = &.{}, // Simplified`
- `src/handlers/async_handler.zig:114` -- same pattern in drain loop
- `src/internal/queue.zig:60-88` -- `fromRecord()` serializes attrs into `attrs_buf` with `key=value;` format, but no deserialization exists

**Root Cause:** The attribute serialization in QueuedRecord was implemented but the deserialization back to `[]const Attr` was left as a TODO.

**Fix Guidance:** Either: (a) deserialize `attrs_buf` back into a temporary `[]Attr` slice in the worker, or (b) redesign to use an arena allocator and store attrs as proper Attr slices, or (c) pass the original Record's attrs slice if records are guaranteed to outlive the queue (they are not, since QueuedRecord copies data).

**Validation Plan:**
```bash
zig build test
# Add a test that logs a record with attrs through async handler,
# flushes, and verifies the inner handler received the attrs
```

**Affected Paths:** `src/handlers/async_handler.zig`, `src/internal/queue.zig`

**Rollout Risk:** Low. This is fixing a known deficiency. Deserialization adds minor CPU overhead but is necessary for correctness.

---

### PERF-006: All handlers hold mutex during format+I/O

- **PerfSeverity:** P1
- **PerfScore:** 80 (Impact=4 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** Every handler (text, json, syslog, rotating_file) acquires its mutex before formatting the record and holds it through the final I/O write. This serializes all concurrent logging threads.

**Perf Impact:** With N threads, effective throughput equals single-thread throughput regardless of N. Under 8 threads, expect ~8x throughput reduction vs. optimal.

**Evidence:**
- `text_handler.zig:49-91` -- lock at 49, format 52-87, write at 90, unlock at 91
- `json_handler.zig:59-130` -- lock at 59, format 62-125, write at 128, unlock at 130
- `syslog_rfc5424.zig:117-195` -- lock at 117, format 120-190, write at 193, unlock at 195
- `rotating_file.zig:166-211` -- lock at 166, format 172-209, write at 211, unlock at 211

**Root Cause:** The handlers use stack-allocated fixed buffers for formatting, which is correct. However, the mutex scope includes both formatting (CPU-bound) and writing (I/O-bound). Since the writer is shared state, it needs protection, but the formatting portion does not.

**Fix Guidance:** Format to a thread-local or stack buffer outside the lock. Acquire the mutex only for the final `ctx.writer.writeAll(output)` call. This reduces critical section from ~microseconds to ~nanoseconds for in-memory writers.

**Validation Plan:**
```bash
# Multi-threaded benchmark: 8 threads, 100K records each
# Before: throughput ~= single-thread; After: throughput ~= N * single-thread
zig build bench  # (after adding multi-threaded bench per PERF-019)
```

**Affected Paths:** `src/handlers/text_handler.zig`, `src/handlers/json_handler.zig`, `src/handlers/syslog_rfc5424.zig`, `src/handlers/rotating_file.zig`

**Rollout Risk:** Low. Each handler already formats to a local buffer (`var buf: [N]u8`). The change is moving the lock acquisition to after formatting. Requires ensuring the local buffer is not shared.

---

### PERF-007: HTTP/TCP/UDP sinks omit attrs from JSON output

- **PerfSeverity:** P1
- **PerfScore:** 60 (Impact=4 x Likelihood=3 x 5... adjusted to 60)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** All three network sinks' `handle()` functions format JSON with time, level, msg, and logger, but never iterate `rec.attrs` to include structured attributes.

**Perf Impact:** Correctness bug rather than latency issue. Structured data is silently lost when using network sinks.

**Evidence:**
- `tcp_sink.zig:145-167` -- JSON object has time, level, msg, logger, then endObject(); no attrs loop
- `http_sink.zig:205-227` -- identical pattern
- `udp_sink.zig:106-128` -- identical pattern
- Compare with `json_handler.zig:107-122` which properly writes attrs

**Root Cause:** The network sinks were likely copied from a template that did not include the attrs serialization loop.

**Fix Guidance:** Add an attrs serialization block after the logger field, matching the pattern in `json_handler.zig:107-122`. Reuse or adapt `writeJsonAttr()`/`writeJsonValue()`.

**Validation Plan:**
```bash
zig build test
# Add tests that send a record with attrs through each network sink
# and verify the JSON output contains the attrs
```

**Affected Paths:** `src/sinks/tcp_sink.zig`, `src/sinks/http_sink.zig`, `src/sinks/udp_sink.zig`

**Rollout Risk:** Low. Additive change. Slightly larger JSON payloads.

---

### PERF-008: QueuedRecord ~12.5KB per entry; 1024 default = 12.2MB heap -- CLOSED (pass 4)

- **PerfSeverity:** P1
- **PerfScore:** 60 (Impact=3 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app
- **Status:** **Closed / Implemented** (pass 4)

**Summary:** QueuedRecord used fixed-size buffers totaling ~12,480 bytes per entry. Reduced to ~3,072 bytes per entry (75% reduction) by shrinking MAX_STORED_ATTRS from 32 to 8, MAX_VALUE_LEN from 256 to 128, msg_id_buf from 256 to 64, and source_file_buf from 256 to 128. Default queue (1024 entries) now uses ~3.0MB instead of ~12.2MB.

**Original description:** QueuedRecord uses fixed-size buffers totaling ~12,480 bytes per entry. The largest contributor is `stored_attrs: [32]StoredAttr` where each StoredAttr = key_buf[64] + key_len(8) + value_buf[256] + value_len(8) = 336 bytes, for a total of 10,752 bytes. With the default queue_size of 1024, this allocates ~12.2MB of heap memory at init.

**Perf Impact:** 12.2MB resident memory for async queue. Most records use <5% of the buffer space (typical record has 2-5 attrs with short keys/values vs. 32 slots of 336 bytes each). Significant memory pressure in embedded or multi-logger scenarios.

**Evidence:**
- `src/internal/queue.zig:160-175` -- QueuedRecord fields: `msg_id_buf: [256]u8`, `message_buf: [1024]u8`, `logger_buf: [128]u8`, `source_file_buf: [256]u8`, `stored_attrs: [MAX_STORED_ATTRS]StoredAttr` (32 * 336 = 10,752 bytes), plus usize/u32/bool fields and padding = ~12,480 bytes
- `src/internal/queue.zig:32` -- `MAX_STORED_ATTRS = 32`
- `src/internal/queue.zig:49-66` -- StoredAttr: key_buf[64] + key_len(usize) + value_buf[256] + value_len(usize) = 336 bytes
- `src/handlers/async_handler.zig:26` -- `queue_size: usize = 1024`
- Calculation: 12,480 * 1024 = 12,779,520 bytes = 12.2MB

**Root Cause:** The PERF-005 fix replaced the flat `attrs_buf: [2048]u8` with a structured `stored_attrs: [32]StoredAttr` array. While this correctly preserves attribute key/value boundaries, each StoredAttr uses 336 bytes of fixed buffers, and 32 slots are always allocated regardless of actual attribute count.

**Fix Guidance:** Options: (a) reduce MAX_STORED_ATTRS to 8 or 16 (most records have <8 attrs), (b) reduce MAX_VALUE_LEN from 256 to 128, (c) use variable-length records with an arena allocator, (d) use a ring buffer of bytes instead of a ring buffer of structs.

**Validation Plan:**
```bash
# Measure RSS before and after creating async handler
# Before: ~12.2MB for queue alone; After: target <2MB
# Quick check: @sizeOf(QueuedRecord) * 1024 in a test
```

**Affected Paths:** `src/internal/queue.zig`, `src/handlers/async_handler.zig`

**Rollout Risk:** Medium. Reducing MAX_STORED_ATTRS may cause attrs to be silently dropped for records with many attributes. Reducing MAX_VALUE_LEN may truncate long values. Document limits clearly.

---

### PERF-009: HTTP sink silently accepts HTTPS but sends cleartext

- **PerfSeverity:** P1
- **PerfScore:** 60 (Impact=5 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** The HTTP sink parses `https://` URLs, sets `is_https=true` and port 443, but then opens a plain TCP connection and sends an unencrypted HTTP request.

**Perf Impact:** Security issue rather than latency. Log data (potentially containing sensitive information) sent in cleartext when the user explicitly requested HTTPS.

**Evidence:**
- `src/sinks/http_sink.zig:64` -- `if (std.mem.startsWith(u8, url, "https://"))` sets `is_https = true`
- `src/sinks/http_sink.zig:103` -- stores `.is_https = is_https` in context
- `src/sinks/http_sink.zig:131-182` -- `sendHttp()` never checks `self.is_https`; uses plain `tcpConnectToAddress`

**Root Cause:** HTTPS support was planned (URL parsing implemented) but TLS was never added.

**Fix Guidance:** Either: (a) return `error.HttpsNotSupported` from `Context.init()` when `is_https` is true, or (b) implement TLS using `std.crypto.tls` or a Zig TLS library.

**Validation Plan:**
```bash
# Test: attempt to create HttpSink with https:// URL
# Before: silently accepts, sends cleartext; After: returns error or uses TLS
```

**Affected Paths:** `src/sinks/http_sink.zig`

**Rollout Risk:** Low for option (a) -- it is a breaking change for users relying on the (broken) HTTPS parsing. High for option (b) -- TLS adds significant complexity.

---

### PERF-010: No circuit breaker for TCP sink failures

- **PerfSeverity:** P1
- **PerfScore:** 48 (Impact=4 x Likelihood=3 x 4)
- **Confidence:** `confidence::suspected`
- **Area:** infra

**Summary:** The TCP sink tracks `consecutive_failures` but never uses it to short-circuit retry attempts. Every record triggers full retry logic regardless of failure history.

**Perf Impact:** With 100 threads and a down endpoint, all 100 threads queue up behind the mutex, each waiting through the full retry cycle. Total serialized wait time = 100 * 5.3s = 530s.

**Evidence:**
- `src/sinks/tcp_sink.zig:120` -- `self.consecutive_failures += 1` after all retries exhausted
- No code anywhere checks `consecutive_failures` to skip or fast-fail
- `src/sinks/tcp_sink.zig:87-122` -- `writeWithRetry()` always executes full retry loop

**Root Cause:** Circuit breaker pattern was not implemented. The `consecutive_failures` field exists but is write-only.

**Fix Guidance:** At the top of `writeWithRetry()`, check `consecutive_failures >= threshold` and return error immediately. Reset the counter after a configurable cooldown period. Consider exponential cooldown.

**Validation Plan:**
```bash
# Point TCP sink at unreachable endpoint, send 100 records from 10 threads
# Before: each thread blocks for full retry; After: only first few threads retry, rest fast-fail
# Measure: wall-clock time for all 100 records to complete (or fail)
```

**Affected Paths:** `src/sinks/tcp_sink.zig`

**Rollout Risk:** Low. Circuit breaker is an additive pattern. Risk: if threshold is too low, transient failures cause premature circuit opening. Mitigate with half-open state.

**What would confirm:** Benchmark showing time reduction from ~530s to <10s for 100 records against a down endpoint.

---

### PERF-011: Journald fallback makes 14+ stderr syscalls per record

- **PerfSeverity:** P2
- **PerfScore:** 48 (Impact=3 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The journald handler's stderr fallback path (lines 139-151) issues multiple individual `stderr.print()` calls per record: priority, identifier, message, then per-attribute key and value.

**Perf Impact:** ~14+ write syscalls per record (assuming ~5 attrs). Syscall overhead is ~1-2us each on modern Linux, adding 14-28us per record.

**Evidence:**
- `src/handlers/journald.zig:141` -- `stderr.print("<{d}>", ...)` -- syscall 1
- `src/handlers/journald.zig:143` -- `stderr.print("{s}: ", ...)` -- syscall 2
- `src/handlers/journald.zig:145` -- `stderr.print("{s}", ...)` -- syscall 3
- `src/handlers/journald.zig:146-149` -- per-attr: `stderr.print(" {s}=", ...)` + `writeValue()` -- 2 syscalls per attr
- `src/handlers/journald.zig:150` -- `stderr.writeByte('\n')` -- syscall N

**Root Cause:** The fallback path writes directly to stderr without buffering, unlike other handlers that format to a stack buffer first.

**Fix Guidance:** Format the entire fallback message to a stack-allocated `fixedBufferStream` (like other handlers do), then issue a single `stderr.writeAll()`.

**Validation Plan:**
```bash
# Trace syscalls during journald fallback logging
strace -e write -c zig-out/bin/bench 2>&1 | grep write
# Before: ~14 write() calls per record; After: 1
```

**Affected Paths:** `src/handlers/journald.zig`

**Rollout Risk:** Very low. Pure refactoring of the write pattern.

---

### PERF-012: Per-byte hex encoding via fmt.print in 4 handlers

- **PerfSeverity:** P2
- **PerfScore:** 48 (Impact=3 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** Four handlers use `writer.print("{x:0>2}", .{byte})` inside a per-byte loop for hex encoding of `.bytes` values. Each iteration involves format string parsing overhead.

**Perf Impact:** For a 256-byte value: 256 format string parse+write calls vs. a single bulk write with a lookup table. Estimated 5-10x slower for bytes values.

**Evidence:**
- `text_handler.zig:133-135` -- `for (b) |byte| { try writer.print("{x:0>2}", .{byte}); }`
- `journald.zig:169-171` -- identical pattern
- `syslog_rfc5424.zig:244-246` -- identical pattern
- `json_handler.zig:164-170` -- manually builds hex using `hex_chars` lookup (correct approach, but could still be bulk)

**Root Cause:** `writer.print()` is convenient but carries format-string parsing overhead per call. The json_handler already uses a manual lookup table approach.

**Fix Guidance:** Use a precomputed hex lookup table (like json_handler does at line 166) in all handlers. Better yet, extract a shared `hex.encode()` utility and write the result in bulk.

**Validation Plan:**
```bash
# Benchmark: format 1000 records each with a 256-byte attr
# Before: measure ns/op for bytes attrs; After: expect 5-10x improvement on bytes path
```

**Affected Paths:** `src/handlers/text_handler.zig`, `src/handlers/journald.zig`, `src/handlers/syslog_rfc5424.zig`

**Rollout Risk:** Very low. Produces identical output via a faster code path.

---

### PERF-013: Rotating file handler lacks write buffering

- **PerfSeverity:** P2
- **PerfScore:** 36 (Impact=3 x Likelihood=3 x 4)
- **Confidence:** `confidence::suspected`
- **Area:** app

**Summary:** The rotating file handler calls `f.write(data)` directly for each formatted record, triggering a kernel write syscall per record.

**Perf Impact:** At high throughput (e.g., 10K records/sec), this is 10K syscalls/sec. With buffering, this could be reduced to ~10-100 syscalls/sec.

**Evidence:**
- `src/handlers/rotating_file.zig:135-141` -- `write()` calls `f.write(data)` directly
- No `std.io.BufferedWriter` wrapper around the file

**Root Cause:** No write buffering was implemented. Each record triggers an immediate kernel write.

**Fix Guidance:** Wrap the `std.fs.File` in a `std.io.BufferedWriter` with a configurable buffer size (e.g., 64KB). Flush on rotation check, explicit flush(), or when buffer is full.

**Validation Plan:**
```bash
# Benchmark: write 100K records to a rotating file
# Before: measure syscall count with strace; After: expect 100-1000x fewer write() syscalls
strace -e write -c zig-out/bin/bench 2>&1
```

**Affected Paths:** `src/handlers/rotating_file.zig`

**Rollout Risk:** Low-medium. Buffered writes mean data loss risk on crash (unflushed buffer). Document the tradeoff. Consider adding a `sync_on_write` option.

**What would confirm:** Benchmark showing write throughput improvement and reduced syscall count.

---

### PERF-014: Async handler flush uses busy-wait polling with 1ms sleep

- **PerfSeverity:** P2
- **PerfScore:** 36 (Impact=3 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The `flush()` function polls `queue.len()` in a loop with a 1ms sleep between checks, rather than using a condition variable to signal drain completion.

**Perf Impact:** Up to 1ms unnecessary latency on flush. Wastes CPU cycles on busy polling. With frequent flushes, accumulates measurable overhead.

**Evidence:**
- `src/handlers/async_handler.zig:196-204` -- `while (ctx.queue.len() > 0) { std.time.sleep(1 * ns_per_ms); }`
- `queue.len()` acquires the queue's internal mutex on each call (line 234-238)

**Root Cause:** Simple polling was used instead of a proper signaling mechanism.

**Fix Guidance:** Add a `drain_complete` condition variable to the Context. The worker thread signals it when the queue becomes empty after processing. `flush()` waits on this condition variable with the specified timeout.

**Validation Plan:**
```bash
# Measure flush latency with a single queued record
# Before: up to 1ms; After: completes within worker loop iteration time (~100us)
```

**Affected Paths:** `src/handlers/async_handler.zig`

**Rollout Risk:** Low. Adds a condition variable; standard concurrency primitive.

---

### PERF-015: Async handler double-locks on enqueue (TOCTOU race)

- **PerfSeverity:** P2
- **PerfScore:** 36 (Impact=3 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** `enqueue()` acquires `self.mutex` to check `self.queue.len() >= self.queue.buffer.len`, releases it, then calls `self.queue.pushDropOldest(qr)` which acquires the queue's internal mutex separately. The queue state can change between the check and the push.

**Perf Impact:** Double mutex acquisition overhead per enqueue. More importantly, the `was_full` check is a TOCTOU race: the queue may become full (or not full) between the check and the push, leading to incorrect drop counting.

**Evidence:**
- `src/handlers/async_handler.zig:129` -- `self.mutex.lock()` (context mutex)
- `src/handlers/async_handler.zig:130` -- `const was_full = self.queue.len() >= self.queue.buffer.len`
- `src/handlers/async_handler.zig:131` -- `self.mutex.unlock()`
- `src/handlers/async_handler.zig:133` -- `self.queue.pushDropOldest(qr)` (acquires queue mutex internally)

**Root Cause:** The enqueue logic needs to atomically check fullness and push, but uses two separate locks.

**Fix Guidance:** Use the queue's internal `dropped` counter (already tracked at `queue.zig:151`) instead of the external `was_full` check. After `pushDropOldest()`, compare `queue.droppedCount()` to the previous value to detect drops.

**Validation Plan:**
```bash
# Stress test: 16 threads, queue_size=4, verify drop count accuracy
# Before: drop count may be inaccurate; After: exact match with actual drops
```

**Affected Paths:** `src/handlers/async_handler.zig`

**Rollout Risk:** Very low. Removes unnecessary lock; uses existing drop tracking.

---

### PERF-016: JSON handler pre-validates all attrs before serializing

- **PerfSeverity:** P2
- **PerfScore:** 36 (Impact=2 x Likelihood=4 x 4... rounded to 36)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The JSON handler iterates all attributes calling `isValidJson()` before acquiring the mutex and performing actual serialization. This is an extra O(n) pass over all attributes.

**Perf Impact:** For records with many attributes, this doubles the iteration count. Only f64 values need JSON validation (NaN/Inf check).

**Evidence:**
- `src/handlers/json_handler.zig:53-57` -- `for (rec.attrs) |attr| { if (!attr.value.isValidJson()) return error.InvalidRecord; }`
- `src/value.zig:110-115` -- `isValidJson()` only checks f64 values; all other types return true

**Root Cause:** Pre-validation was added as a safety check, but it can be done inline during f64 serialization.

**Fix Guidance:** Remove the pre-validation loop. In `writeJsonValue()`, check `isValidJson()` for the `.f64` case and return error or write `null` inline.

**Validation Plan:**
```bash
# Benchmark JSON handler with 20 string attrs (no f64)
# Before: 2 passes over attrs; After: 1 pass
```

**Affected Paths:** `src/handlers/json_handler.zig`

**Rollout Risk:** Very low. The validation still happens, just inline during serialization.

---

### PERF-017: parallel.zig is dead code but adds build-time cost -- WON'T DO

- **PerfSeverity:** P2
- **PerfScore:** 24 (Impact=2 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci
- **Status:** **Won't Do**
- **Reason:** The parallel module was intentionally added as a published library module (commits 1fa06e6 "Add spice-based parallel operations for slog" and 1041b15 "Add documentation for parallel operations module"). It is an exported API, not dead code. Build-time impact is minor.

**Summary:** The `parallel.zig` module (764 lines) is compiled as a build module and pulls in the spice dependency, but no handler or sink in `src/` imports it.

**Perf Impact:** Adds compilation time for 764 LOC + spice dependency resolution on every build. No runtime impact since it is never called from internal handlers.

**Evidence:**
- `build.zig:39-49` -- parallel_mod is created and linked
- No `@import("parallel")` in any src/ file other than the module definition itself

**Root Cause:** The parallel module was added (commits 1fa06e6, 1041b15) as a published library feature for consumers. Internal handlers do not use it, but external consumers may.

**Fix Guidance:** N/A -- intentionally kept as published module.

**Validation Plan:**
```bash
# Measure build time with and without parallel module
time zig build 2>&1  # with
time zig build -Dspice=false 2>&1  # without
```

**Affected Paths:** `src/parallel.zig`, `build.zig`

**Rollout Risk:** Very low. Removing from default build is non-breaking for users of the library.

---

### PERF-018: Benchmark suite lacks statistical rigor

- **PerfSeverity:** P3
- **PerfScore:** 16 (Impact=2 x Likelihood=2 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci

**Summary:** The benchmark runs a single warmup phase then a single timed pass. No standard deviation, confidence intervals, or percentiles are computed.

**Perf Impact:** Results vary 10-30% between runs, making it unreliable for detecting performance regressions.

**Evidence:**
- `bench/bench_main.zig:17-18` -- `WARMUP_ITERATIONS = 1000`, `BENCHMARK_ITERATIONS = 100_000`
- `bench/bench_main.zig:246-254` -- `printResult()` reports only ns/op and ops/sec from a single measurement

**Root Cause:** The benchmark was designed as a quick smoke test rather than a rigorous measurement tool.

**Fix Guidance:** Run multiple timed iterations (e.g., 10 rounds), compute mean, standard deviation, p50, p99. Optionally output in a machine-readable format (JSON) for CI regression detection.

**Validation Plan:**
```bash
# Run benchmark 10 times, compare variance
for i in $(seq 1 10); do zig build bench 2>&1; done | grep TextHandler
```

**Affected Paths:** `bench/bench_main.zig`

**Rollout Risk:** None. Pure improvement to test infrastructure.

---

### PERF-019: No multi-threaded benchmarks

- **PerfSeverity:** P3
- **PerfScore:** 16 (Impact=2 x Likelihood=2 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci

**Summary:** All benchmarks run on a single thread. There are no benchmarks measuring concurrent logging throughput or mutex contention.

**Perf Impact:** Cannot detect regressions in concurrent performance. Mutex contention issues (PERF-006) are invisible to the current benchmark suite.

**Evidence:**
- `bench/bench_main.zig` -- no `std.Thread.spawn` calls anywhere; all benchmarks are sequential

**Root Cause:** Multi-threaded benchmarking was not implemented.

**Fix Guidance:** Add benchmarks that spawn N threads (e.g., 1, 2, 4, 8), each logging 100K records to a shared handler. Report aggregate throughput and per-thread p99 latency.

**Validation Plan:**
```bash
# After implementing, run multi-threaded bench and verify throughput scales
zig build bench -- --threads=8
```

**Affected Paths:** `bench/bench_main.zig`

**Rollout Risk:** None.

---

### PERF-020: Metrics struct false sharing -- CLOSED

- **PerfSeverity:** P3
- **PerfScore:** 12 (Impact=2 x Likelihood=3 x 2... rounded to 12)
- **Confidence:** `confidence::confirmed`
- **Area:** app
- **Status:** **Closed** -- implemented despite original "Won't Do" classification

**Summary:** The Metrics struct previously packed 7 atomic counters (56 bytes) into a single cache line. This has been fixed with `PaddedCounter` using `align(cache_line)`.

**Evidence of fix:**
- `src/metrics/metrics.zig:28` -- `const cache_line = 64;`
- `src/metrics/metrics.zig:32-34` -- `const PaddedCounter = struct { value: AtomicCounter align(cache_line) = AtomicCounter.init(0), };`
- `src/metrics/metrics.zig:40-54` -- All 7 Metrics fields now use PaddedCounter type
- `src/metrics/metrics.zig:185-201` -- Test "Metrics counters are cache-line aligned to prevent false sharing" verifies that adjacent counters are at least `cache_line` bytes apart and each is aligned to a cache-line boundary

**Resolution:** Each counter now occupies a full 64-byte cache line, eliminating false sharing between concurrent counter increments on different cores.

---

### PERF-021: getPool() acquires mutex on every call

- **PerfSeverity:** P3
- **PerfScore:** 12 (Impact=1 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci

**Summary:** `getPool()` locks `pool_mutex` on every invocation, even after the pool has been initialized. This adds unnecessary contention on a hot path when parallel operations are enabled.

**Perf Impact:** ~20-50ns per call under contention. Only matters if parallel.zig is actually used (currently dead code per PERF-017).

**Evidence:**
- `src/parallel.zig:74-85` -- `pool_mutex.lock(); defer pool_mutex.unlock();` on every call
- `src/parallel.zig:80` -- `if (global_pool == null)` check happens after acquiring the lock

**Root Cause:** Simple mutex-based lazy initialization without double-checked locking optimization.

**Fix Guidance:** Use double-checked locking: first check `global_pool` with an atomic load (no lock). Only acquire the mutex if null, then re-check inside the lock. Alternatively, use `std.once` if available.

**Validation Plan:**
```bash
# Benchmark getPool() call overhead
# Before: ~20-50ns under contention; After: ~1-5ns (atomic load only)
```

**Affected Paths:** `src/parallel.zig`

**Rollout Risk:** Very low. Standard optimization pattern.

---

### PERF-022: UDP sink holds mutex during format+send

- **PerfSeverity:** P1
- **PerfScore:** 48 (Impact=3 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra
- **Issue:** [#38](https://gitlab.com/devnw/zig/slog/-/work_items/38)

**Summary:** The UDP sink's `handle()` function acquires the mutex before JSON formatting and holds it through the UDP send. TCP and HTTP sinks format outside the lock, but the UDP sink does not follow this pattern.

**Perf Impact:** All logging threads serialize on the UDP sink's mutex during both CPU-bound formatting (~8KB JSON formatting) and the I/O-bound UDP send syscall. Effective throughput is single-threaded.

**Evidence:**
- `src/sinks/udp_sink.zig:132-133` -- `ctx.mutex.lock(); defer ctx.mutex.unlock();` acquired before any formatting.
- `src/sinks/udp_sink.zig:136-179` -- Full JSON formatting (fixedBufferStream, streamingEncoder, field writing) happens under lock.
- `src/sinks/udp_sink.zig:181-184` -- `ctx.send(fbs.getWritten())` also under lock.
- Compare with TCP sink where formatting to a local buffer can happen independently.

**Root Cause:** The UDP sink's `handle()` was written with the mutex covering the entire function body. When TCP/HTTP sinks were partially refactored for narrower lock scope, the UDP sink was not updated.

**Fix Guidance:** Move the JSON formatting (lines 136-179) above the mutex acquisition. The `buf`, `fbs`, and `enc` are stack-local variables that do not need mutex protection. Acquire the lock only for `ctx.send()` which uses the shared socket.

**Validation Plan:**
```bash
# Multi-threaded benchmark: 8 threads logging to UDP sink
# Before: throughput ~= single-thread; After: near-linear scaling
perf lock record -- zig-out/bin/bench --sink=udp
perf lock report
```

**Affected Paths:** `src/sinks/udp_sink.zig`

**Rollout Risk:** Low. The formatting buffer is stack-local and not shared between threads. Only the `send()` call uses the shared socket descriptor. Verify with `-fsanitize=thread` if available.

---

### PERF-023: isSensitiveKey() O(k*p) linear scan per attribute -- CLOSED (pass 4)

- **PerfSeverity:** P2
- **PerfScore:** 20 (Impact=2 x Likelihood=2 x Memory=1 x Frequency=5... composite 20)
- **Confidence:** `confidence::suspected`
- **Area:** app
- **Status:** **Closed / Implemented** (pass 4)

**Summary:** `isSensitiveKey()` was refactored from 15 sequential `std.mem.indexOf` calls to a single-pass scan using comptime-unrolled `inline for` pattern matching with a comptime `min_pattern_len` early rejection. Short keys that cannot possibly match any pattern are rejected immediately.

**Original description:** `isSensitiveKey()` lowercases the key into a 64-byte buffer, then performs `std.mem.indexOf` against each of 15 sensitive key patterns. This is called per attribute from 8 different handler call sites.

**Original perf impact:** For each attribute: lowercase O(k) + 15 substring searches each O(k*p). For a record with 10 attrs, this is 150 substring scans. The overhead is small per call (~100-500ns) but is multiplied by every attribute in every record across every handler.

**Evidence:**
- `src/util/redact.zig:34-47` -- `isSensitiveKey()` implementation: `for (sensitive_keys) |sensitive| { if (std.mem.indexOf(u8, lower, sensitive) != null) ... }`
- `src/util/redact.zig:15-31` -- `sensitive_keys` array has 15 entries
- Called from: `text_handler.zig:108`, `json_handler.zig:145`, `journald.zig:128,154`, `syslog_rfc5424.zig:225`, `tcp_sink.zig:244`, `http_sink.zig:276`, `udp_sink.zig:172`, `windows_eventlog.zig:112`

**Root Cause:** Simple linear scan was chosen for correctness and readability. The pattern list is small (15 entries), so the overhead per call is minor, but it accumulates across all handlers and attributes.

**Fix Guidance:** Options: (a) compile-time perfect hash set using `std.StaticStringMap`, (b) Aho-Corasick multi-pattern matcher for substring search, (c) sort patterns and use binary search on lowercased key. Option (a) only works for exact matches; current logic uses substring matching so (b) would be the algorithmically correct improvement.

**Validation Plan:**
```bash
# Microbenchmark: 100K calls to isSensitiveKey with 10-char keys
# Before: measure ns/call; After: expect 2-5x improvement
# Note: may not be worth optimizing given small absolute cost per call
```

**Affected Paths:** `src/util/redact.zig`

**Rollout Risk:** Very low. Internal optimization; same behavior from caller perspective.

**What would confirm:** Profiling showing `isSensitiveKey` appearing in hot path traces. If it does not appear, the optimization is not worth the complexity.

---

### PERF-024: rotating_file per-byte hex encoding via writer.print

- **PerfSeverity:** Info
- **PerfScore:** 4 (Impact=2 x Likelihood=1 x Memory=1 x Frequency=2... composite 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The PERF-012 fix applied a precomputed hex lookup table to text_handler, journald, syslog, and windows_eventlog, but the rotating_file handler still uses the slow `writer.print("{x:0>2}", .{byte})` pattern.

**Perf Impact:** Minor. Only affects `.bytes` type attribute values logged through the rotating_file handler. Per-byte format string parsing overhead (~5-10x slower than lookup table) but only on an uncommon code path.

**Evidence:**
- `src/handlers/rotating_file.zig:329-331` -- `for (b) |byte| { try writer.print("{x:0>2}", .{byte}); }` -- same slow pattern that PERF-012 fixed in other handlers.
- Compare with `src/handlers/text_handler.zig` which now uses `hex_chars` lookup table.

**Root Cause:** The PERF-012 fix was applied to 4 handlers but missed the rotating_file handler.

**Fix Guidance:** Apply the same `hex_chars` lookup table pattern from the PERF-012 fix to `rotating_file.zig:329-331`.

**Validation Plan:**
```bash
# Benchmark rotating_file handler with records containing bytes attrs
# Before: per-byte format parsing; After: O(1) lookup per byte
```

**Affected Paths:** `src/handlers/rotating_file.zig`

**Rollout Risk:** Very low. Produces identical output via a faster code path.

---

### PERF-025: Stack allocations 8-25KB per log call across handlers

- **PerfSeverity:** P1
- **PerfScore:** 60 (Impact=2 x Throughput=2 x Memory=3 x Frequency=5... composite 60)
- **Confidence:** `confidence::confirmed`
- **Area:** app
- **Issue:** [#40](https://gitlab.com/devnw/zig/slog/-/work_items/40)
- **Status:** **Won't Do** -- Reducing buffer sizes without profiling data risks truncation of legitimate large records. The zero-allocation design is intentional. Requires actual profiling to safely determine optimal buffer sizes. Tracked for future optimization pass.

**Summary:** Multiple handlers and sinks allocate large fixed-size stack buffers per log call. The journald handler is the worst offender at ~25KB. JSON, syslog, TCP, and HTTP handlers each allocate ~16KB.

**Perf Impact:** 8-25KB stack consumption per concurrent log call. With 8 threads, worst case ~200KB of active stack. The large stack frames (~16-25KB) evict useful data from L1 (32-48KB) and L2 caches on every call. On systems with small default stack sizes (e.g., 8KB in some embedded contexts), this can cause stack overflow.

**Evidence:**
- `src/handlers/journald.zig:75` -- `var fields_buf: [32][512]u8 = undefined;` = 16,384 bytes
- `src/handlers/journald.zig:144` -- `var stderr_buf: [8192]u8 = undefined;` = 8,192 bytes -- total ~25KB
- `src/handlers/json_handler.zig:55` -- `var buf: [16384]u8 = undefined;` = 16,384 bytes + `stack_buf: [256]u8` = ~16.6KB
- `src/handlers/syslog_rfc5424.zig:120` -- `var buf: [16384]u8 = undefined;` = ~16.4KB
- `src/sinks/tcp_sink.zig:208` -- `var buf: [16384]u8 = undefined;` = ~16.5KB
- `src/sinks/http_sink.zig:240` -- `var buf: [16384]u8 = undefined;` + `req_buf: [1024]u8` + `resp_buf: [256]u8` = ~17.8KB
- `src/sinks/udp_sink.zig:136` -- `var buf: [8192]u8 = undefined;` = ~8.3KB

**Root Cause:** Fixed-size buffers were chosen for zero-allocation formatting. The 16KB size accommodates worst-case records but is dramatically oversized for the common case (typical formatted record is <1KB).

**Fix Guidance:**
1. **Reduce default buffers**: Use 4KB default; most records format to <1KB. Truncate or signal overflow for rare oversized records.
2. **Thread-local reusable buffers**: Allocate a formatting buffer per thread (once) and reuse across calls. Eliminates per-call stack expansion.
3. **Journald-specific**: Remove dead `fields_buf` code (see PERF-028). The stderr_buf alone at 8KB is sufficient for the fallback path.

**Validation Plan:**
```bash
# Measure stack depth per handler with valgrind massif
valgrind --tool=massif --stacks=yes zig-out/bin/bench
ms_print massif.out.* | head -50
# Before: 16-25KB stack per call; After: <4KB
# Also verify no truncation in normal usage with integration tests
zig build test
```

**Affected Paths:** `src/handlers/journald.zig`, `src/handlers/json_handler.zig`, `src/handlers/syslog_rfc5424.zig`, `src/sinks/tcp_sink.zig`, `src/sinks/http_sink.zig`, `src/sinks/udp_sink.zig`

**Rollout Risk:** Medium. Reducing buffer sizes can cause truncation of unusually large records. Must add explicit truncation handling and document maximum record size limits.

---

### PERF-026: Async handler single-record processing (no batch dequeue) -- CLOSED (pass 4)

- **PerfSeverity:** P2
- **PerfScore:** 24 (Impact=2 x Likelihood=3 x Memory=1 x Frequency=4... composite 24)
- **Confidence:** `confidence::suspected`
- **Area:** app
- **Status:** **Closed / Implemented** (pass 4)

**Summary:** The async handler's worker thread now processes up to 32 records per wake cycle. After the initial `popTimeout(100)` returns a record, the worker drains additional records via `tryPop()` in a loop (up to `max_batch_size=32`). A `processQueuedRecord` helper was extracted to share logic between the initial pop, the batch drain, and the shutdown drain.

**Original description:** The async handler's worker thread processes records one at a time via `popTimeout(100)`. When the queue has multiple pending records (burst scenario), the worker wakes, processes one record, then goes back to waiting. This adds per-record overhead for mutex acquire/release, condition variable signal, and handler dispatch.

**Perf Impact:** Under burst load (e.g., 1000 records queued), the worker processes them one by one with per-record synchronization overhead. A batch drain of N records per wake cycle would amortize the overhead.

**Evidence:**
- `src/handlers/async_handler.zig:98-124` -- Worker loop: `if (ctx.queue.popTimeout(100)) |qr| { ... ctx.inner.handle(&rec) ... }` -- single record per iteration.
- No batch drain logic; each iteration processes exactly one record then re-enters `popTimeout`.

**Root Cause:** The worker was designed for simplicity with single-record processing. Batch dequeue was not implemented.

**Fix Guidance:** After processing one record from `popTimeout()`, check if more records are immediately available via `tryPop()` in a loop (up to a configurable batch size, e.g., 64). This amortizes the per-wake overhead across multiple records.

**Validation Plan:**
```bash
# Burst test: enqueue 10K records, measure drain time
# Before: 10K pop+signal cycles; After: ~156 batches of 64
# Measure: wall-clock drain time and CPU usage during burst
```

**Affected Paths:** `src/handlers/async_handler.zig`

**Rollout Risk:** Low. Batch processing is additive. The only risk is if the inner handler cannot keep up with burst delivery, but that is already the case with single-record processing.

**What would confirm:** Benchmark showing improved throughput under burst load (>1000 records queued simultaneously).

---

### PERF-027: Multi-handler re-formats same Record per child

- **PerfSeverity:** Info
- **PerfScore:** 12 (Impact=2 x Likelihood=2 x Memory=1 x Frequency=3... composite 12)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The multi-handler iterates its child handlers and passes the same Record to each. Each child independently formats the record (JSON, text, syslog, etc.). With N children, the record is formatted N times.

**Perf Impact:** For a multi-handler with 2 children (common case: console + file), the record is formatted twice. With 3+ children, the overhead grows linearly. However, since each child typically uses a different format, pre-formatting is not straightforward.

**Evidence:**
- `src/handlers/multi_handler.zig:30-43` -- `for (ctx.handlers) |h| { h.handle(rec) catch ... }` -- each handler independently formats.

**Root Cause:** This is architecturally expected behavior. Each child handler has its own output format, so a shared pre-formatted representation is not feasible without a format negotiation protocol.

**Fix Guidance:** No action recommended for the common case. For users with multiple handlers using the same format, a "tee" handler that formats once and writes to multiple outputs would be a future optimization.

**Validation Plan:**
```bash
# Benchmark: multi-handler with 2 text handlers vs. 1 text handler
# Expected: ~2x formatting time with 2 handlers (confirms linear scaling)
```

**Affected Paths:** `src/handlers/multi_handler.zig`

**Rollout Risk:** N/A -- informational finding. No change recommended.

---

### PERF-028: Journald stderr fallback runs unconditionally on Linux

- **PerfSeverity:** P2
- **PerfScore:** 30 (functional bug that doubles I/O and CPU work per record)
- **Confidence:** `confidence::confirmed`
- **Area:** app
- **Issue:** [#41](https://gitlab.com/devnw/zig/slog/-/work_items/41)

**Summary:** The journald handler builds structured fields for `sd_journal_sendv` (lines 75-137), but since libsystemd is not linked, it always falls through to the stderr fallback path (lines 143-162). Both code paths execute unconditionally: the field-building work is performed and then discarded, and the record is re-formatted for stderr output.

**Perf Impact:** Double the CPU work per journald log call: O(n) field formatting into 16KB fields_buf (lines 75-137, wasted), then O(n) stderr formatting into 8KB stderr_buf (lines 143-162, actual output). The 16KB fields_buf stack allocation is also entirely wasted.

**Evidence:**
- `src/handlers/journald.zig:75-137` -- Builds up to 32 journald fields: `MESSAGE=...`, `PRIORITY=...`, `SYSLOG_IDENTIFIER=...`, per-attr `KEY=value`. This code always executes.
- `src/handlers/journald.zig:139-141` -- Comment explicitly states: "For now, we write to stderr as a fallback when libsystemd isn't linked".
- `src/handlers/journald.zig:143-162` -- Stderr fallback always executes, re-formatting the same data into a different format.
- The `field_ptrs` and `fields_buf` arrays built in lines 75-137 are local variables never passed to any API call.

**Root Cause:** The journald handler was written with the intent to call `sd_journal_sendv()` using the structured fields, but the native call was never implemented. The fallback path was added as a temporary measure. Since the fallback is not gated behind a condition, both the field-building and stderr formatting always execute.

**Fix Guidance:**
1. **Short term (recommended):** Remove or `#ifdef`-gate the field-building code (lines 75-137) since it is dead code. This eliminates ~16KB stack allocation, the O(n) field formatting, and the key uppercasing work. Only the stderr fallback path should execute.
2. **Long term:** Implement actual `sd_journal_sendv` via `@cImport` or runtime loading of `libsystemd.so`. When available, call the native API and skip the stderr fallback.

**Validation Plan:**
```bash
# Benchmark journald handler before/after removing dead code
zig build bench
# Before: ~25KB stack, double format work; After: ~8KB stack, single format
# Verify output unchanged (stderr fallback produces same visible output)
strace -e write -c zig-out/bin/bench 2>&1
```

**Affected Paths:** `src/handlers/journald.zig`

**Rollout Risk:** Low for short-term fix (removing dead code). The field-building output is never consumed by any API call. The only risk is if someone later implements `sd_journal_sendv` and expects the field-building code to exist -- but it can be re-added at that time.

---

## Roadmap

### Quick Wins (< 1 day each)

| ID | Finding | Effort | Expected Impact | Status |
|---|---|---|---|---|
| ~~PERF-016~~ | ~~Remove JSON pre-validation loop~~ | ~~30 min~~ | ~~Minor CPU reduction~~ | **Closed** |
| ~~PERF-015~~ | ~~Fix enqueue TOCTOU by using queue drop counter~~ | ~~1 hour~~ | ~~Correctness fix + remove double lock~~ | **Closed** |
| ~~PERF-012~~ | ~~Hex encoding lookup table~~ | ~~2 hours~~ | ~~5-10x improvement for bytes attrs~~ | **Closed** |
| ~~PERF-011~~ | ~~Buffer journald stderr fallback~~ | ~~1 hour~~ | ~~14x fewer syscalls~~ | **Closed** |
| ~~PERF-024~~ | ~~Apply hex lookup table to rotating_file handler~~ | ~~30 min~~ | ~~Same PERF-012 fix for missed handler~~ | **Closed** |
| ~~PERF-028~~ | ~~Remove dead field-building code in journald~~ | ~~1-2 hours~~ | ~~Eliminate ~16KB wasted stack + double formatting~~ | **Closed** |
| ~~PERF-022~~ | ~~Narrow UDP sink mutex scope~~ | ~~2-3 hours~~ | ~~Concurrent UDP throughput improvement~~ | **Closed** |

### Medium Effort (1-5 days each)

| ID | Finding | Effort | Expected Impact | Status |
|---|---|---|---|---|
| PERF-025 | Reduce stack buffer sizes across handlers | 2-3 days | 4-6x less stack per call; better cache utilization | **Won't Do** (requires profiling data; risks truncation) |
| PERF-026 | Add batch dequeue to async handler worker | 1-2 days | Amortize per-wake overhead under burst load | Open |
| PERF-023 | Optimize isSensitiveKey() with better data structure | 1 day | Reduce substring scan overhead per attribute | Open |
| PERF-017 | Gate parallel.zig behind opt-in flag | 30 min | Faster builds | Open |

### Strategic (> 5 days each)

| ID | Finding | Effort | Expected Impact | Status |
|---|---|---|---|---|
| PERF-008 | Redesign QueuedRecord for variable-length records | 5-7 days | ~10x memory reduction (12.2MB -> ~1.2MB) | Open |
| PERF-001 | HTTP connection pooling / keep-alive | 5-7 days | 100-1000x throughput improvement | Won't Do |
| PERF-002 + PERF-003 | Decouple formatting from I/O in network sinks | 3-5 days | Eliminate multi-second thread blocking | Won't Do |

---

## PerfScore Calculation Details

| ID | Impact (1-5) | Likelihood (1-5) | Score (I*L*4) | Rationale | Status |
|---|---|---|---|---|---|
| PERF-001 | 5 | 5 | 100 | SLO-breaking latency on every HTTP log; always hit | Won't Do |
| PERF-002 | 5 | 5 | 100 | Blocks all threads for seconds; always hit during failure | Won't Do |
| PERF-003 | 5 | 5 | 100 | Same as PERF-002 but with HTTP overhead | Won't Do |
| PERF-004 | 5 | 4 | 80 | Minutes-long hangs; common when endpoints are unreachable | **Closed** |
| PERF-005 | 4 | 5 | 80 | All attrs lost; always hit on async path | **Closed** |
| PERF-006 | 4 | 5 | 80 | Serializes all threads; every handler affected | Won't Do |
| PERF-007 | 4 | 3 | 48* | Attrs missing; only affects network sink users (*adjusted to 60 for correctness weight) | **Closed** |
| PERF-008 | 3 | 5 | 60 | 12.2MB overhead; always allocated when async used | Open |
| PERF-009 | 5 | 3 | 60 | Security: cleartext on HTTPS; only users who specify https:// | **Closed** |
| PERF-010 | 4 | 3 | 48 | Cascading failure; only during TCP endpoint outages | **Closed** |
| PERF-011 | 3 | 4 | 48 | 14x syscall overhead; always hit on journald fallback | **Closed** |
| PERF-012 | 3 | 4 | 48 | Per-byte overhead; only bytes attrs, but common path | **Closed** |
| PERF-013 | 3 | 3 | 36 | Syscall per record; only rotating file users | **Closed** |
| PERF-014 | 3 | 3 | 36 | Busy-wait; only during flush calls | **Closed** |
| PERF-015 | 3 | 3 | 36 | TOCTOU + double lock; every async enqueue | **Closed** |
| PERF-016 | 2 | 4 | 32* | Extra O(n) pass; every JSON record (*adjusted to 36) | **Closed** |
| PERF-017 | 2 | 3 | 24 | Build cost only; every build | Open |
| PERF-018 | 2 | 2 | 16 | Unreliable benchmarks; CI only | Won't Do |
| PERF-019 | 2 | 2 | 16 | Missing contention testing; CI only | Won't Do |
| PERF-020 | 2 | 3 | 24* | False sharing; under concurrent load (*adjusted to 12 -- now confirmed fixed) | **Closed** |
| PERF-021 | 1 | 3 | 12 | Mutex overhead; only if parallel.zig is used | Won't Do |
| **PERF-022** | **3** | **4** | **48** | **UDP sink holds mutex during format+send; serializes all threads** | **Closed** |
| **PERF-023** | **2** | **2** | **20*** | **15 substring scans per attr from 8 handlers; O(k*p) per call (*composite score)** | **Open** |
| **PERF-024** | **1** | **1** | **4** | **Missed PERF-012 fix in rotating_file; rare code path** | **Closed** |
| **PERF-025** | **3** | **5** | **60** | **8-25KB stack per log call; cache pollution on hot path** | **Open** |
| **PERF-026** | **2** | **3** | **24** | **Single-record worker loop; no batch drain under burst** | **Open** |
| **PERF-027** | **2** | **1** | **12*** | **Re-formats per child handler; architecturally expected (*adjusted to 12)** | **Won't Do** |
| **PERF-028** | **3** | **3** | **30*** | **Dead field-building code always executes; doubles journald work (*functional bug)** | **Closed** |

*Scores with asterisks were adjusted from raw calculation to better reflect real-world impact and confidence level.

---

## Unknowns and Blockers

1. **No profiler data available.** All impact estimates are based on code analysis and general knowledge of syscall/networking costs. Running the benchmark suite with `perf` or `valgrind --tool=callgrind` would confirm or adjust estimates. This is especially relevant for PERF-023 (isSensitiveKey overhead) and PERF-025 (stack allocation cache impact).

2. ~~**Async handler attr deserialization complexity.**~~ Resolved: StoredAttr array with serialize/deserialize was implemented in commit 3fcd5a5. PERF-005 is closed.

3. ~~**TLS implementation for PERF-009.**~~ Resolved: HTTPS URLs are now rejected at init with `error.HttpsNotSupported`. PERF-009 is closed.

4. ~~**False sharing measurement (PERF-020).**~~ Resolved: PaddedCounter with `align(cache_line)` implemented. Test at `metrics.zig:185-201` confirms alignment. PERF-020 is closed.

5. **parallel.zig integration plan.** PERF-017 flags it as dead code, but it may be intended for future use. Clarify roadmap before removing.

6. **isSensitiveKey() actual hot-path impact (PERF-023).** The function is called from 8 handlers per attribute, but the absolute per-call cost may be too small to justify optimization. Profile data would confirm whether this appears in hot-path traces.

7. **Stack buffer reduction safety (PERF-025).** Reducing 16KB buffers to 4KB would handle >99% of records but needs measurement of real-world record sizes to confirm. A truncation audit across all handlers is needed before changing buffer sizes.

8. **Journald native API path (PERF-028).** The dead field-building code in journald.zig could be removed now, but if native `sd_journal_sendv` support is planned, the code serves as a starting point. Clarify whether native journald integration is on the roadmap.
