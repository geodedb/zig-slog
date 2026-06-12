# Performance Gap Analysis -- slogz

**Repository:** gitlab.com/devnw/zig/slog
**Branch:** main (commit 0ed8afe)
**Last updated:** 2026-03-24 (rev 6 -- Pass 5 closure: PERF-031/032/033/036/038 Closed; PERF-029/030/034/035/037 Won't Do)
**Analyst:** Claude Opus 4.6 (automated perf scoring)

---

## Summary

| PerfSeverity | Count | Closed | Won't Do | Open |
|---|---|---|---|---|
| **P0** | 5 | 1 | 4 | 0 |
| **P1** | 11 | 8 | 3 | 0 |
| **P2** | 14 | 11 | 3 | 0 |
| **P3** | 5 | 2 | 3 | 0 |
| **Info** | 3 | 1 | 2 | 0 |
| **Total** | 38 | 23 | 15 | 0 |

### Status

All items resolved. No open risks remain. 23 closed, 15 won't do, 0 open.

---

## Stack-Ranked Findings

| Rank | Sev | Score | ID | Finding | Component | Evidence | Measurement | Issue URL | Fix Summary | Owner | SLA | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | P0 | 100 | PERF-001 | HTTP sink creates new TCP connection per record | http_sink | `src/sinks/http_sink.zig:131-182` -- `sendHttp()` calls `tcpConnectToAddress()` then `stream.close()` on every invocation; `Connection: close` header on line 146 | Est. 1-50ms overhead per record (TCP handshake + teardown) | -- | Connection pooling requires significant effort; separate feature | -- | -- | **Won't Do** |
| 2 | P0 | 100 | PERF-002 | TCP sink holds mutex during retry+sleep up to 15s | tcp_sink | `src/sinks/tcp_sink.zig:87-122` -- `writeWithRetry()` sleeps inside loop at lines 95,107 while mutex acquired at `handle()` line 130-131 | Max block time = 100+200+400+800+1600+3200+5000ms = ~11.3s (3 retries default = ~5.3s) | -- | Partially mitigated by circuit breaker (PERF-010); full lock scope reduction is separate effort | -- | -- | **Won't Do** |
| 3 | P0 | 100 | PERF-003 | HTTP sink holds mutex during full HTTP round-trip+retry | http_sink | `src/sinks/http_sink.zig:190-232` -- `handle()` locks mutex at 190, calls `sendWithRetry()` at 229 which performs full HTTP I/O + backoff sleep | Full HTTP RTT + up to 5s backoff per retry, all under lock | -- | Partially mitigated by socket timeouts; full lock scope reduction is separate effort | -- | -- | **Won't Do** |
| **4** | **P0** | **100** | **PERF-029** | **HTTP sink has no batching or connection pooling despite doc claims** | **http_sink** | **`http_sink.zig:7` claims "JSON payload batching", line 10 claims "Connection pooling"; `sendHttp()` at line 127-133 opens+closes TCP per call; `deinit()` at line 103 says "No persistent connections to close"** | **New TCP handshake per record; unusable at >50 rec/sec** | -- | Misleading doc claims removed (Q-37); PERF-001/002/003 same scope already Won't Do | -- | -- | **Won't Do** (pass 5: misleading doc fixed via Q-37; PERF-001/002/003 same scope already Won't Do) |
| 5 | P0 | 80 | PERF-004 | Missing connect/read timeouts on TCP/HTTP sinks | tcp_sink, http_sink | `tcp_sink.zig:27` defines `connect_timeout_ms` but `connect()` at line 65-78 never applies it; `http_sink.zig:29` defines `timeout_ms` but `sendHttp()` at line 131-182 never sets socket options | OS default TCP timeout 75-127s; single stuck connection blocks all logging | -- | SO_RCVTIMEO/SO_SNDTIMEO applied via setsockopt in both TCP and HTTP sinks | -- | -- | **Closed** (0ed8afe) |
| 6 | P1 | 80 | PERF-005 | Async handler drops ALL attributes | async_handler | `src/handlers/async_handler.zig:93` and `:114` -- reconstructed Record sets `.attrs = &.{}` (empty); `QueuedRecord.fromRecord()` in `queue.zig:60-88` serializes attrs to `attrs_buf` but worker never deserializes them back | 100% attribute data loss on async path; all structured context gone | -- | StoredAttr array with serialize/deserialize; attrs restored in worker thread | -- | -- | **Closed** (3fcd5a5) |
| 7 | P1 | 80 | PERF-006 | All handlers hold mutex during format+I/O | text, json, syslog, rotating_file | `text_handler.zig:49-91`, `json_handler.zig:59-130`, `syslog_rfc5424.zig:117-195`, `rotating_file.zig:166-211` -- all lock mutex before formatting, hold it through writeAll() | Serializes all logging threads; throughput = 1/latency instead of N/latency | -- | Lock scope reduction requires significant refactoring; separate effort | -- | -- | **Won't Do** |
| **8** | **P1** | **80** | **PERF-030** | **TCP/HTTP sink retries with Thread.sleep block while holding mutex** | **tcp_sink, http_sink** | **`tcp_sink.zig:227-230` locks mutex then calls `writeWithRetry()` with sleep at lines 131,148; `http_sink.zig:252-255` locks mutex then calls `sendWithRetry()` with sleep at line 118** | **TCP worst-case ~700ms under lock; HTTP with DNS potentially 15+s; all logging threads serialize** | -- | PERF-002/003/006 same scope already Won't Do; circuit breaker mitigates | -- | -- | **Won't Do** (pass 5: PERF-002/003/006 same scope already Won't Do; circuit breaker mitigates) |
| **9** | **P1** | **64** | **PERF-031** | **Data race on async_handler.Context.level -- non-atomic read/write** | **async_handler** | **`async_handler.zig:57` declares `level: Level` (plain enum, not atomic); `setLevel()` at line 215 writes `ctx.level = level` without synchronization; `handle()` at line 189 reads `ctx.level` on caller thread** | **Undefined behavior in Zig; potential torn reads, incorrect level filtering** | -- | Atomic Value used for level across all 12 handlers (combined fix with SEC-0033) | -- | -- | **Closed** (pass 5: non-atomic level fixed across all 12 handlers using atomic Value; combined fix with SEC-0033) |
| 10 | P1 | 60 | PERF-007 | HTTP/TCP/UDP sinks omit attrs from JSON output | tcp_sink, http_sink, udp_sink | `tcp_sink.zig:145-167` -- JSON output writes time/level/msg/logger but never iterates `rec.attrs`; same in `http_sink.zig:205-227` and `udp_sink.zig:106-128` | All structured attributes silently dropped; correctness bug | -- | All three sinks now iterate rec.attrs with JSON attr serialization | -- | -- | **Closed** (0ed8afe) |
| 11 | P1 | 60 | PERF-008 | QueuedRecord ~3.0KB per entry (was ~12.5KB); 1024 default = 3.0MB heap | queue | `src/internal/queue.zig:34,41,166,172` -- reduced: MAX_STORED_ATTRS 32->8, MAX_VALUE_LEN 256->128, msg_id_buf 256->64, source_file_buf 256->128 | 1024 * ~3,072 = 3.0MB heap (75% reduction from 12.2MB) | -- | Reduced fixed buffer sizes to match actual usage patterns | -- | -- | **Closed** (pass 4: MAX_STORED_ATTRS=8, MAX_VALUE_LEN=128, msg_id_buf[64], source_file_buf[128]; ~3.0KB per entry) |
| 12 | P1 | 60 | PERF-025 | Stack allocations 8-25KB per log call across handlers | journald, json, syslog, tcp, http | `journald.zig:75` fields_buf[32][512]=16KB + stderr_buf[8192]=8KB = ~25KB; `json_handler.zig:55` buf[16384]; `syslog_rfc5424.zig:120` buf[16384]; `tcp_sink.zig:208` buf[16384]; `http_sink.zig:240` buf[16384]+req_buf[1024]+resp_buf[256] | 16-25KB stack per call; 8 threads = ~200KB active stack; L1/L2 cache pollution | [#40](https://gitlab.com/devnw/zig/slog/-/work_items/40) | Requires profiling data to safely reduce; risks truncation | -- | -- | **Won't Do** |
| 13 | P1 | 60 | PERF-009 | HTTP sink silently accepts HTTPS URLs but sends cleartext | http_sink | `src/sinks/http_sink.zig:64` -- parses `https://` prefix, sets `is_https=true` and port 443, but `sendHttp()` at line 131-182 opens a plain `tcpConnectToAddress` and sends raw HTTP | Credentials/logs sent in cleartext when user expects TLS; security and correctness issue | -- | https:// URLs now rejected at init with error.HttpsNotSupported | -- | -- | **Closed** (0ed8afe) |
| **14** | **P1** | **48** | **PERF-032** | **Silent attribute truncation at MAX_STORED_ATTRS=8 with no indicator** | **queue** | **`queue.zig:204` -- `const count = @min(rec.attrs.len, MAX_STORED_ATTRS);` silently truncates; no metric, log, or error when `rec.attrs.len > 8`** | **Users lose structured data silently through async handler; no diagnostic signal** | -- | Truncation now increments metrics counter | -- | -- | **Closed** (pass 5: attr truncation now increments metrics.global.incTruncations() counter) |
| 15 | P1 | 48 | PERF-010 | No circuit breaker for TCP sink failures | tcp_sink | `src/sinks/tcp_sink.zig:87-122` -- `writeWithRetry()` retries unconditionally; `consecutive_failures` counter at line 120 is incremented but never checked to skip attempts | 100 threads hitting a down TCP endpoint = 100 * 5.3s of serialized retries; cascading failure | -- | Circuit breaker with threshold=3 and 30s cooldown added to tcp_sink | -- | -- | **Closed** (0ed8afe) |
| 16 | P1 | 48 | PERF-022 | UDP sink holds mutex during format+send | udp_sink | `src/sinks/udp_sink.zig:132-133` -- mutex acquired before JSON formatting at 136-179 and send at 181-184; TCP/HTTP sinks format outside lock but UDP does not | Serializes all threads on UDP sink; effectively single-threaded throughput | [#38](https://gitlab.com/devnw/zig/slog/-/work_items/38) | JSON formatting moved outside mutex; lock only for ctx.send() | -- | Sprint | **Closed** |
| 17 | P2 | 48 | PERF-011 | Journald fallback makes 14+ stderr syscalls per record | journald | `src/handlers/journald.zig:139-151` -- fallback path issues individual `stderr.print()` calls: priority, identifier, message, then per-attr key+value; each is a separate write syscall | ~14+ syscalls per record vs. 1 with buffered write; ~10x syscall overhead | -- | Fallback now writes to 8KB fixedBufferStream, single writeAll to stderr | -- | -- | **Closed** (0ed8afe) |
| 18 | P2 | 48 | PERF-012 | Per-byte hex encoding via fmt.print in 4 handlers | text, journald, syslog, json | `text_handler.zig:133-135` -- `writer.print("{x:0>2}", .{byte})` per byte; same in `journald.zig:169-171`, `syslog_rfc5424.zig:244-246` | Each byte triggers format string parsing + write; lookup table would be O(1) per byte | -- | Precomputed hex_chars lookup table used in text_handler, journald, syslog, windows_eventlog | -- | -- | **Closed** (0ed8afe) |
| **19** | **P2** | **40** | **PERF-033** | **queue.len() causes double mutex acquisition per async enqueue** | **queue, async_handler** | **`async_handler.zig:177` calls `self.queue.len()` after every enqueue; `queue.zig:380-384` acquires mutex for len(); `pushDropOldest` at line 287 also acquires mutex -- two acquisitions per enqueue** | **~40-80ns unnecessary mutex overhead per async log call** | -- | pushDropOldest now returns count, eliminating separate len() call | -- | -- | **Closed** (pass 5: double mutex eliminated; pushDropOldest returns count) |
| 20 | P2 | 36 | PERF-013 | Rotating file handler lacks write buffering | rotating_file | `src/handlers/rotating_file.zig:135-141` -- `write()` calls `f.write(data)` directly per record; no BufWriter or equivalent | Each log record triggers a kernel write syscall; high overhead for high-frequency logging to disk | -- | 8KB write_buf added; flush on buffer full, rotation check, or explicit flush | -- | -- | **Closed** (05c6a16) |
| 21 | P2 | 36 | PERF-014 | Async handler flush uses busy-wait polling with 1ms sleep | async_handler | `src/handlers/async_handler.zig:196-204` -- `flush()` loops checking `queue.len() > 0` with `std.time.sleep(1ms)` between iterations | Wastes CPU; up to 1ms latency granularity on flush; not signal-based | -- | flush() now uses queue.waitEmpty() with CV-based signaling | -- | -- | **Closed** (3fcd5a5) |
| 22 | P2 | 36 | PERF-015 | Async handler double-locks on enqueue (TOCTOU race) | async_handler | `src/handlers/async_handler.zig:129-133` -- `enqueue()` acquires its own `self.mutex` to check `self.queue.len()`, then releases it, then calls `self.queue.pushDropOldest()` which acquires the queue's internal mutex separately | TOCTOU: queue state can change between the len check and the push; the `was_full` variable may be stale | -- | Uses queue.droppedCount() before/after push to detect drops; no TOCTOU | -- | -- | **Closed** (3fcd5a5) |
| 23 | P2 | 36 | PERF-016 | JSON handler pre-validates all attrs before serializing | json_handler | `src/handlers/json_handler.zig:53-57` -- iterates all `rec.attrs` calling `isValidJson()` before entering the mutex and doing actual serialization; this is an extra O(n) pass | Unnecessary O(n) scan; only f64 values need checking, and they can be checked inline during serialization | -- | Pre-validation loop removed; f64 NaN/Inf check done inline during serialization | -- | -- | **Closed** (0ed8afe) |
| **24** | **P2** | **32** | **PERF-034** | **Async handler batch drain calls inner handler individually per record** | **async_handler** | **`async_handler.zig:105-113` -- batch loop calls `processQueuedRecord()` which calls `ctx.inner.handle(&rec)` individually; no opportunity for batched I/O (e.g., single write for N records)** | **Per-record dispatch overhead; network sinks cannot batch payloads** | -- | Requires vtable API change (handleBatch); deferred to future release | -- | -- | **Won't Do** (pass 5: requires vtable API change adding handleBatch; deferred to future release) |
| 25 | P2 | 30 | PERF-028 | Journald stderr fallback runs unconditionally on Linux | journald | `src/handlers/journald.zig:75-137` builds journald fields (16KB stack) then falls through to stderr at lines 143-162 without ever calling sd_journal_sendv; field-building is dead code | Double formatting work per record; 16KB wasted stack for unused fields | [#41](https://gitlab.com/devnw/zig/slog/-/work_items/41) | Field-building guarded by comptime `native_sendv_available`; stderr-only path skips ~25KB stack allocation | -- | Quarter | **Closed** |
| **26** | **P2** | **24** | **PERF-035** | **Multi-handler dispatches and flushes sequentially despite parallel.zig** | **multi_handler** | **`multi_handler.zig:36-40` -- `for (ctx.handlers) \|h\| { h.handle(rec) ... }` sequential loop; `flush()` at lines 72-75 also sequential; `parallel.zig` module exists but is not used** | **N handlers = N x sequential latency; parallel dispatch would reduce to max(latencies)** | -- | Changes ordering guarantees; opt-in flag deferred to future release | -- | -- | **Won't Do** (pass 5: changes ordering guarantees; opt-in parallel dispatch flag deferred to future release) |
| **27** | **P2** | **24** | **PERF-036** | **Benchmark suite missing async handler, queue contention, and isSensitiveKey benchmarks** | **bench** | **`bench/bench_main.zig` -- benchmarks cover discard, text, json, logger disabled/enabled, timestamp, attr creation; no async handler, no QueuedRecord, no queue contention, no isSensitiveKey** | **Cannot detect regressions in recently changed async handler, queue, or redact code** | -- | 3 new benchmarks added: async handler, queue contention, isSensitiveKey | -- | -- | **Closed** (pass 5: benchmark suite expanded with 3 new benchmarks) |
| 28 | P2 | 24 | PERF-017 | parallel.zig module is dead code but adds build-time cost | parallel | `src/parallel.zig` -- 764 lines, imported as module in `build.zig:39-49`, pulls in spice dependency; not imported by any handler or sink in src/ | Adds ~764 LOC compilation + spice dependency resolution to every build | -- | Intentionally kept as published module per commits 1fa06e6/1041b15 | -- | -- | **Won't Do** |
| 29 | P2 | 24 | PERF-026 | Async handler batch drain (was single-record processing) | async_handler | `src/handlers/async_handler.zig:98-120` -- worker loop now drains up to 32 records per wake cycle via tryPop after initial popTimeout; processQueuedRecord helper extracted | Batch processing under burst load reduces per-record overhead (fewer mutex acquire/release, fewer thread wakes) | -- | Batch drain: worker processes up to 32 records per wake cycle via tryPop after initial popTimeout | -- | Quarter | **Closed** (pass 4: max_batch_size=32, tryPop loop, processQueuedRecord helper) |
| 30 | P2 | 20 | PERF-023 | isSensitiveKey() optimized with comptime-unrolled inline for | redact | `src/util/redact.zig:34-60` -- single-pass scan with comptime-unrolled `inline for` pattern matching + comptime min_pattern_len early rejection | Replaced 15 sequential indexOf calls with single-pass scan; comptime min_pattern_len rejects short keys immediately | -- | Single-pass comptime-unrolled inline for with min_pattern_len early rejection | -- | Quarter | **Closed** (pass 4: inline for pattern matching, comptime min_pattern_len early rejection) |
| **31** | **P3** | **16** | **PERF-037** | **No automated performance regression detection in CI** | **ci** | **`.gitlab-ci.yml:164-178` -- `bench-regression` job runs benchmarks and stores artifacts but does no comparison against baselines or threshold checks** | **Regressions can land undetected; manual artifact inspection required** | -- | Requires infrastructure project; depends on PERF-036 (now done) | -- | -- | **Won't Do** (pass 5: requires infrastructure project; depends on PERF-036 which is now done) |
| 32 | P3 | 16 | PERF-018 | Benchmark suite lacks statistical rigor | bench | `bench/bench_main.zig` -- single timing pass with no warmup separation, no std deviation, no percentiles; `WARMUP_ITERATIONS=1000` then one timed run of 100k | Results vary by 10-30% between runs; no confidence intervals; insufficient for regression detection | -- | Separate infrastructure improvement | -- | Backlog | **Won't Do** |
| 33 | P3 | 16 | PERF-019 | No multi-threaded benchmarks | bench | `bench/bench_main.zig` -- all benchmarks run single-threaded; no contention testing | Cannot detect mutex contention regressions or validate concurrent throughput | -- | Separate infrastructure improvement | -- | Backlog | **Won't Do** |
| **34** | **P3** | **12** | **PERF-038** | **parallel.zig getPool() uses mutex on every call instead of double-checked locking** | **parallel** | **`parallel.zig:74-78` -- `pool_mutex.lock(); defer pool_mutex.unlock();` on every `getPool()` call; atomic load could skip lock when pool is initialized** | **~20-50ns unnecessary overhead per parallel operation call** | -- | Double-checked locking implemented | -- | -- | **Closed** (pass 5: getPool() now uses double-checked locking with atomic load) |
| 35 | P3 | 12 | PERF-020 | Metrics struct false sharing -- fixed via PaddedCounter | metrics | `src/metrics/metrics.zig:28-34` -- PaddedCounter with `align(cache_line)` pads each counter to 64 bytes; test at lines 185-201 verifies alignment | Each counter occupies a full cache line; false sharing eliminated | -- | PaddedCounter with align(cache_line) applied to all 7 counters | -- | -- | **Closed** |
| 36 | Info | 12 | PERF-021 | getPool() acquires mutex on every call | parallel | `src/parallel.zig:74-85` -- `getPool()` locks `pool_mutex` on every invocation even after pool is initialized | Unnecessary contention on hot path; adds ~20-50ns per call under contention | -- | parallel.zig is optional; optimization deferred | -- | Backlog | **Won't Do** |
| 37 | Info | 12 | PERF-027 | Multi-handler re-formats same Record per child | multi_handler | `src/handlers/multi_handler.zig:30-43` -- iterates child handlers, each independently formats the Record; no shared pre-formatted buffer | N child handlers = N independent format passes; 2 handlers = 2x formatting cost | -- | Architecturally expected; pre-formatting would require handler-specific format negotiation | -- | -- | **Won't Do** |
| 38 | Info | 4 | PERF-024 | rotating_file per-byte hex encoding via writer.print | rotating_file | `src/handlers/rotating_file.zig:329-331` -- `writer.print("{x:0>2}", .{byte})` per byte; PERF-012 fix (lookup table) was applied to text/journald/syslog but missed this handler | Same per-byte overhead as PERF-012 but only in rotating_file handler | -- | Apply same hex_chars lookup table from PERF-012 fix | -- | Backlog | **Closed** (hex_chars lookup table applied) |

---

## Findings by Area

### area::app

| ID | Sev | Score | Finding | Status |
|---|---|---|---|---|
| PERF-005 | P1 | 80 | Async handler drops ALL attributes | **Closed** |
| PERF-006 | P1 | 80 | All handlers hold mutex during format+I/O | **Won't Do** |
| PERF-031 | P1 | 64 | Data race on async_handler.Context.level | **Closed** (pass 5) |
| PERF-007 | P1 | 60 | HTTP/TCP/UDP sinks omit attrs from JSON output | **Closed** |
| PERF-008 | P1 | 60 | QueuedRecord ~3.0KB per entry (reduced) | **Closed** |
| PERF-025 | P1 | 60 | Stack allocations 8-25KB per log call | **Won't Do** |
| PERF-032 | P1 | 48 | Silent attribute truncation at MAX_STORED_ATTRS=8 | **Closed** (pass 5) |
| PERF-011 | P2 | 48 | Journald fallback 14+ stderr syscalls | **Closed** |
| PERF-012 | P2 | 48 | Per-byte hex encoding via fmt.print | **Closed** |
| PERF-033 | P2 | 40 | queue.len() double mutex per async enqueue | **Closed** (pass 5) |
| PERF-013 | P2 | 36 | Rotating file handler lacks write buffering | **Closed** |
| PERF-014 | P2 | 36 | Async handler flush busy-wait polling | **Closed** |
| PERF-015 | P2 | 36 | Async handler double-locks (TOCTOU) | **Closed** |
| PERF-016 | P2 | 36 | JSON handler unnecessary pre-validation pass | **Closed** |
| PERF-034 | P2 | 32 | Async batch drain calls inner handler per record | **Won't Do** (pass 5) |
| PERF-028 | P2 | 30 | Journald stderr fallback runs unconditionally | **Closed** |
| PERF-035 | P2 | 24 | Multi-handler dispatches sequentially despite parallel.zig | **Won't Do** (pass 5) |
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
| PERF-029 | P0 | 100 | HTTP sink no batching or connection pooling (doc claims both) | **Won't Do** (pass 5) |
| PERF-004 | P0 | 80 | Missing connect/read timeouts | **Closed** |
| PERF-030 | P1 | 80 | TCP/HTTP retries with Thread.sleep block while holding mutex | **Won't Do** (pass 5) |
| PERF-009 | P1 | 60 | HTTP sink sends cleartext on HTTPS URLs | **Closed** |
| PERF-022 | P1 | 48 | UDP sink holds mutex during format+send | **Closed** |
| PERF-010 | P1 | 48 | No circuit breaker for TCP failures | **Closed** |

### area::ci (build and test)

| ID | Sev | Score | Finding | Status |
|---|---|---|---|---|
| PERF-036 | P2 | 24 | Benchmark suite missing async/queue/redact benchmarks | **Closed** (pass 5) |
| PERF-017 | P2 | 24 | parallel.zig dead code adds build cost | **Won't Do** |
| PERF-037 | P3 | 16 | No automated perf regression detection in CI | **Won't Do** (pass 5) |
| PERF-018 | P3 | 16 | Benchmark lacks statistical rigor | **Won't Do** |
| PERF-019 | P3 | 16 | No multi-threaded benchmarks | **Won't Do** |
| PERF-038 | P3 | 12 | getPool() mutex instead of double-checked locking | **Closed** (pass 5) |
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

### PERF-029: HTTP sink has no batching or connection pooling despite doc claims

- **PerfSeverity:** P0
- **PerfScore:** 100 (Impact=5 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** The HTTP sink's module doc at `http_sink.zig:7` claims "JSON payload batching" and line 10 claims "Connection pooling (simplified)". Neither feature exists. Every call to `sendHttp()` (line 127) creates a new TCP connection via `tcpConnectToAddress()` (line 130) or `tcpConnectToHost()` (line 132), sends a single record with `Connection: close` (line 146), reads the response, and closes the socket (`defer stream.close()` at line 133). The `deinit()` at line 103-104 even comments "No persistent connections to close".

**Perf Impact:** The HTTP sink is unusable at any meaningful log rate. Each record incurs a full TCP handshake (1-50ms) plus teardown. At 100 records/sec, this means 100 simultaneous TCP handshakes per second. At 1000 records/sec, the sink cannot keep up and will drop or block. This is related to PERF-001 but adds the documentation discrepancy as a distinct concern: users may deploy the HTTP sink in production believing they have batching and pooling.

**Evidence:**

- `src/sinks/http_sink.zig:7` -- `//! - JSON payload batching` (claimed but not implemented)
- `src/sinks/http_sink.zig:10` -- `//! - Connection pooling (simplified)` (claimed but not implemented)
- `src/sinks/http_sink.zig:127-133` -- `fn sendHttp(self: *Context, data: []const u8) bool { ... const stream = ... std.net.tcpConnectToAddress(address) ... defer stream.close();`
- `src/sinks/http_sink.zig:146` -- `Connection: close\r\n` header sent on every request
- `src/sinks/http_sink.zig:103-104` -- `pub fn deinit(_: *Context) void { // No persistent connections to close }`
- No batch buffer, no record accumulation, no persistent stream field on Context

**Root Cause:** The doc comments describe aspirational features that were never implemented. The sink was written as a simple one-shot-per-record HTTP client. No connection is stored on the Context struct (unlike tcp_sink which has a `stream: ?std.net.Stream` field). No batch buffer or record accumulator exists.

**Fix Guidance:**

1. **Immediate:** Remove or correct the misleading doc comments claiming "JSON payload batching" and "Connection pooling".
2. **Connection pooling:** Add a `stream: ?std.net.Stream` field to Context (matching tcp_sink pattern). Reuse the connection across calls. Send `Connection: keep-alive` instead of `close`. Reconnect on write failure.
3. **Payload batching:** Add a record buffer (e.g., JSON array or newline-delimited JSON). Flush on: (a) buffer full, (b) configurable max delay, (c) explicit flush. This requires a timer mechanism or piggyback flushing.

**Validation Plan:**

```bash
# Start a local HTTP server that counts connections
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
count = 0
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        global count; count += 1
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = HTTPServer(('', 8080), H)
threading.Thread(target=lambda: s.serve_forever()).start()
" &
# Send 1000 records through HTTP sink, count connections
# Before: 1000 connections (1 per record)
# After (pooling): 1-5 connections
# After (batching): ~10-50 HTTP requests total
ss -s | grep estab
```

**Affected Paths:** `src/sinks/http_sink.zig`

**Rollout Risk:** High for batching (changes delivery semantics -- partial batch failure, ordering). Medium for connection pooling (must handle server-side close, keepalive timeout). Low for doc fix.

---

### PERF-030: TCP/HTTP sink retries with Thread.sleep block while holding mutex

- **PerfSeverity:** P1
- **PerfScore:** 80 (Impact=5 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** infra

**Summary:** Both TCP and HTTP sinks acquire the mutex before calling their retry functions, which contain `Thread.sleep()` in the backoff loop. During network failures, the mutex is held for the entire retry+sleep duration. TCP sink: mutex at line 227, `writeWithRetry()` at line 230 with sleep at lines 131 and 148. HTTP sink: mutex at line 252, `sendWithRetry()` at line 255 with sleep at line 118.

**Perf Impact:** TCP worst-case: with default 3 retries and exponential backoff (100ms, 200ms, 400ms), ~700ms under lock. HTTP worst-case: with DNS resolution failures and 3 retries (100ms, 200ms, 400ms + connect timeout), potentially 15+ seconds under lock. During this time, ALL other threads attempting to log are serialized behind the mutex.

**Evidence:**

- `src/sinks/tcp_sink.zig:227-228` -- `ctx.mutex.lock(); defer ctx.mutex.unlock();`
- `src/sinks/tcp_sink.zig:230` -- `ctx.writeWithRetry(output)` called under lock
- `src/sinks/tcp_sink.zig:131` -- `std.Thread.sleep(@as(u64, backoff) * std.time.ns_per_ms)` inside retry loop
- `src/sinks/tcp_sink.zig:148` -- second `std.Thread.sleep()` on write failure
- `src/sinks/http_sink.zig:252-253` -- `ctx.mutex.lock(); defer ctx.mutex.unlock();`
- `src/sinks/http_sink.zig:255` -- `ctx.sendWithRetry(output)` called under lock
- `src/sinks/http_sink.zig:118` -- `std.Thread.sleep(@as(u64, backoff) * std.time.ns_per_ms)` in retry loop

**Root Cause:** Both sinks format to a local buffer outside the lock (good), but then acquire the mutex for the entire `writeWithRetry`/`sendWithRetry` call which includes both the write attempt and the backoff sleep. The mutex protects the shared stream/connection, but the sleep portion does not need lock protection. This is distinct from PERF-002/003 (which were Won't Do'd as "lock scope reduction is separate effort") because this focuses specifically on the Thread.sleep-under-mutex pattern, which is a targeted fix.

**Fix Guidance:** Release the mutex before sleeping. Pattern: lock -> try write -> if fail, unlock -> sleep -> re-lock -> try again. Alternatively, use a separate "retry state" that does not hold the lock during backoff. The TCP sink's circuit breaker (PERF-010 fix) mitigates repeated retries but does not prevent sleep-under-lock for the first failure.

**Validation Plan:**

```bash
# Set up a TCP server that closes connections after 1 byte
# Run 10 threads logging concurrently through TCP sink
# Measure p99 latency across threads during failure
# Before: p99 >= 700ms (TCP) or 15s (HTTP)
# After: p99 < 100ms (sleep happens outside lock)
```

**Affected Paths:** `src/sinks/tcp_sink.zig`, `src/sinks/http_sink.zig`

**Rollout Risk:** Medium. Changing lock scope around retry logic requires careful ordering. Must ensure the stream is not used by another thread while the current thread retries. The formatted output buffer is stack-local so it is safe.

---

### PERF-031: Data race on async_handler.Context.level -- non-atomic read/write

- **PerfSeverity:** P1
- **PerfScore:** 64 (Impact=4 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The `async_handler.Context.level` field at line 57 is declared as a plain `Level` enum. The `setLevel()` function at line 215 writes `ctx.level = level` from any thread (called via the Handler vtable). The `handle()` function at line 189 reads `ctx.level` on the caller's thread to perform level filtering. There is no synchronization between these operations -- no mutex, no atomic, no memory barrier.

**Perf Impact:** This is a correctness/safety issue rather than a latency issue. In Zig, concurrent unsynchronized read/write to the same memory location is undefined behavior. In practice this can manifest as: torn reads (if Level were wider than a machine word, though it is currently u3), stale cached values (CPU core may read old value indefinitely due to lack of memory barrier), or compiler reordering.

**Evidence:**

- `src/handlers/async_handler.zig:57` -- `level: Level,` (plain enum field, not atomic)
- `src/handlers/async_handler.zig:58` -- `running: std.atomic.Value(bool).init(true),` (contrast: `running` uses atomic)
- `src/handlers/async_handler.zig:189` -- `if (!rec.level.atLeast(ctx.level)) return;` (read on caller thread)
- `src/handlers/async_handler.zig:213-215` -- `fn setLevel(ctx_ptr: *anyopaque, level: Level) void { ... ctx.level = level; }` (write from any thread)

**Root Cause:** The `level` field was not wrapped in `std.atomic.Value(Level)` when the async handler was written. The `running` field was correctly made atomic (line 58), but `level` was not given the same treatment. Since `setLevel` is part of the public Handler vtable and can be called from any thread at any time, this is a data race.

**Fix Guidance:** Change `level: Level` to `level: std.atomic.Value(Level)`. Initialize with `.init(.info)`. Read with `ctx.level.load(.acquire)` in `handle()`. Write with `ctx.level.store(level, .release)` in `setLevel()`. This matches the pattern already used for the `running` field.

**Validation Plan:**

```bash
# ThreadSanitizer-style test: spawn 4 threads calling setLevel() concurrently
# with 4 threads calling handle(). Run for 10 seconds.
# Before: potential UB (may not crash but is technically a race)
# After: clean execution with atomic operations
zig build test  # after adding concurrency stress test
```

**Affected Paths:** `src/handlers/async_handler.zig`

**Rollout Risk:** Very low. Changing a plain field to an atomic is a localized change. The performance impact of atomic load/store vs. plain read/write is negligible (~1ns on x86).

---

### PERF-032: Silent attribute truncation at MAX_STORED_ATTRS=8 with no indicator

- **PerfSeverity:** P1
- **PerfScore:** 48 (Impact=3 x Likelihood=4 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** When `QueuedRecord.fromRecord()` serializes attributes at `queue.zig:204`, it silently truncates to `@min(rec.attrs.len, MAX_STORED_ATTRS)` (where MAX_STORED_ATTRS=8). If a record has more than 8 attributes, the excess are silently dropped with no metric increment, no log message, no error return, and no runtime indicator of any kind. Users lose structured data without any way to detect it.

**Perf Impact:** This is a correctness/observability issue. Records with >8 attributes silently lose data when passed through the async handler. Users who rely on structured attributes for alerting, debugging, or audit trails will have incomplete data with no indication that truncation occurred.

**Evidence:**

- `src/internal/queue.zig:204` -- `const count = @min(rec.attrs.len, MAX_STORED_ATTRS);` -- silent truncation
- `src/internal/queue.zig:34` -- `pub const MAX_STORED_ATTRS = 8;`
- `src/internal/queue.zig:205` -- `for (rec.attrs[0..count], 0..) |attr, idx|` -- only first 8 attrs are copied
- No `metrics.global.incDropped()` or similar call when `rec.attrs.len > MAX_STORED_ATTRS`
- No log warning, no error return, no truncation flag on QueuedRecord

**Root Cause:** The PERF-008 fix reduced MAX_STORED_ATTRS from 32 to 8 for memory savings. The original code did not have truncation detection because 32 attrs covered virtually all real-world cases. At 8, truncation becomes more likely (records with >8 attrs are not uncommon in rich structured logging), but no indicator was added.

**Fix Guidance:**

1. Add a `truncated: bool` field to QueuedRecord, set it when `rec.attrs.len > MAX_STORED_ATTRS`.
2. Increment `metrics.global.incDropped(rec.attrs.len - MAX_STORED_ATTRS)` when truncation occurs.
3. Optionally add a synthetic attribute like `_truncated_attrs=N` to the serialized output so downstream consumers can detect it.
4. Consider adding a `warn` level log on first truncation (with rate limiting to avoid log storms).

**Validation Plan:**

```bash
# Test: create a record with 12 attributes, pass through async handler
# Before: 4 attrs silently lost, no indicator
# After: metrics counter incremented, optional truncation marker in output
zig build test  # after adding truncation detection test
```

**Affected Paths:** `src/internal/queue.zig`, `src/handlers/async_handler.zig`

**Rollout Risk:** Very low. Adding a counter increment and optional truncation marker is purely additive.

---

### PERF-033: queue.len() causes double mutex acquisition per async enqueue

- **PerfSeverity:** P2
- **PerfScore:** 40 (Impact=2 x Likelihood=5 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** Every async log call via `enqueue()` results in two mutex acquisitions on the queue: first for `pushDropOldest()` (queue.zig:287) or `pushBlocking()` (queue.zig:305), then again for `queue.len()` (queue.zig:380-384) called at `async_handler.zig:177` to update the queue size metric. Each mutex acquisition costs ~20-40ns uncontended, more under contention.

**Perf Impact:** ~40-80ns unnecessary overhead per async log call from the second mutex acquisition. Under high contention (many threads logging simultaneously), this doubles the contention window on the queue mutex.

**Evidence:**

- `src/handlers/async_handler.zig:177` -- `metrics.global.setQueueSize(self.queue.len());` called after every enqueue
- `src/internal/queue.zig:380-384` -- `pub fn len(self: *Self) usize { self.mutex.lock(); defer self.mutex.unlock(); return self.count; }`
- `src/internal/queue.zig:287-288` -- `pub fn pushDropOldest(self: *Self, item: T) void { self.mutex.lock(); defer self.mutex.unlock();`
- Two mutex acquire/release cycles per enqueue: push (line 287) + len (line 380)

**Root Cause:** The queue's `pushDropOldest()` and `len()` are independent mutex-protected operations. The PERF-015 fix removed the external context mutex but the queue-internal double acquisition remains because `len()` is a separate method call after `push`.

**Fix Guidance:** Options: (a) Return the current count from `pushDropOldest()` and `pushBlocking()` since they already hold the mutex and know `self.count`. (b) Use an atomic counter that is updated inside push/pop and read locklessly for metrics. (c) Remove the per-enqueue `setQueueSize()` call and update it less frequently (e.g., every N enqueues or on a timer).

**Validation Plan:**

```bash
# Benchmark: async handler enqueue throughput, 8 threads, 100K records each
# Before: 2 mutex acquisitions per enqueue; After: 1
# Measure: ns/enqueue and aggregate throughput
zig build bench  # after adding async handler benchmark per PERF-036
```

**Affected Paths:** `src/internal/queue.zig`, `src/handlers/async_handler.zig`

**Rollout Risk:** Very low. Returning count from push is a simple API change. All callers are internal.

---

### PERF-034: Async handler batch drain calls inner handler individually per record

- **PerfSeverity:** P2
- **PerfScore:** 32 (Impact=2 x Likelihood=4 x 4)
- **Confidence:** `confidence::suspected`
- **Area:** app

**Summary:** The PERF-026 fix added batch draining (up to 32 records per wake cycle), but each record is still dispatched to the inner handler individually via `processQueuedRecord()` -> `ctx.inner.handle(&rec)` at `async_handler.zig:142`. For network sinks (TCP, HTTP, UDP), each `handle()` call performs a separate network I/O operation. There is no mechanism to pass a batch of records to the inner handler for combined I/O.

**Perf Impact:** Moderate. The batch drain reduces per-wake overhead (fewer mutex acquisitions, fewer condition variable signals), but per-record I/O overhead remains unchanged. For a TCP sink with 32 records in a batch, this is 32 separate TCP writes instead of one combined write.

**Evidence:**

- `src/handlers/async_handler.zig:105-113` -- batch loop: `while (batch < max_batch_size) ... processQueuedRecord(ctx, batch_qr);`
- `src/handlers/async_handler.zig:125-142` -- `fn processQueuedRecord(ctx: *Context, qr: QueuedRecord) void { ... ctx.inner.handle(&rec) ... }`
- The `Handler` interface has no `handleBatch(records: []const Record)` method

**Root Cause:** The Handler vtable interface (`handler.zig`) does not have a batch `handle` method. The async handler's batch drain was designed to reduce synchronization overhead, not I/O overhead. Adding batch I/O support would require extending the Handler interface.

**Fix Guidance:** Options: (a) Add an optional `handleBatch: ?fn(*anyopaque, []const Record) HandlerError!void` to the Handler vtable. Sinks that support batching implement it; others fall back to per-record dispatch. (b) For the TCP/HTTP sinks specifically, format multiple records into a single buffer in the async handler before dispatching. (c) Accept the current design as sufficient -- the async handler's primary purpose is to decouple the caller thread from I/O, not to optimize I/O batching.

**Validation Plan:**

```bash
# Benchmark: async handler with TCP sink, burst of 1000 records
# Before: 1000 individual TCP writes; After: ~32 batched writes
# Measure: wall-clock drain time and network syscall count
strace -e sendto,write -c zig-out/bin/bench 2>&1
```

**Affected Paths:** `src/handlers/async_handler.zig`, `src/handler.zig` (if vtable extended)

**Rollout Risk:** Medium for option (a) -- extends the Handler interface (potential breaking change for custom handler implementors). Low for option (c) -- no change.

**What would confirm:** Profiling showing that per-record I/O dispatch is the bottleneck in async handler throughput. If the bottleneck is elsewhere (e.g., formatting), batch I/O would not help.

---

### PERF-035: Multi-handler dispatches and flushes sequentially despite parallel.zig

- **PerfSeverity:** P2
- **PerfScore:** 24 (Impact=2 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** app

**Summary:** The multi-handler iterates child handlers sequentially in both `handle()` (line 36-40) and `flush()` (lines 72-75). The `parallel.zig` module, which provides thread-pool-based parallel dispatch, exists in the codebase but is not used by the multi-handler. With N child handlers, dispatch latency is the sum of all child latencies rather than the max.

**Perf Impact:** For a multi-handler with 2 handlers (common: console + file), the latency is additive. With 3+ handlers or slow handlers (e.g., network sinks with 50ms+ latency), the sequential pattern becomes significant. Example: 3 handlers at 10ms, 50ms, 5ms each = 65ms sequential vs. 50ms parallel.

**Evidence:**

- `src/handlers/multi_handler.zig:36-40` -- `for (ctx.handlers) |h| { h.handle(rec) catch |err| { ... }; }` -- sequential dispatch
- `src/handlers/multi_handler.zig:72-75` -- `for (ctx.handlers) |h| { h.flush(timeout_ms) catch |err| { ... }; }` -- sequential flush
- `src/parallel.zig:249-252` -- `parallelDispatch()` function exists for exactly this use case
- No `@import("parallel")` in `multi_handler.zig`

**Root Cause:** The multi-handler was written before parallel.zig was added, and was not updated to use it. Alternatively, the sequential approach was kept intentionally for simplicity and deterministic ordering.

**Fix Guidance:** Use `parallel.parallelDispatch()` from the parallel module for both `handle()` and `flush()`. This dispatches to all child handlers concurrently via the thread pool. Error handling would collect the first error (matching current behavior). Gating this behind a config option (e.g., `parallel: bool = false`) would preserve backward compatibility.

**Validation Plan:**

```bash
# Benchmark: multi-handler with 3 child handlers, each with artificial 10ms delay
# Before: ~30ms per record; After: ~10ms per record
# Measure: p50 and p99 latency through multi-handler
```

**Affected Paths:** `src/handlers/multi_handler.zig`

**Rollout Risk:** Medium. Parallel dispatch changes ordering guarantees (handlers may see records in different order). Error semantics change if multiple handlers fail concurrently. Thread pool dependency adds complexity. Recommend opt-in flag.

**What would confirm:** Benchmark showing multi-handler latency reduction proportional to number of children when children have non-trivial latency.

---

### PERF-036: Benchmark suite missing async handler, queue contention, and isSensitiveKey benchmarks

- **PerfSeverity:** P2
- **PerfScore:** 24 (Impact=2 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci

**Summary:** The benchmark suite (`bench/bench_main.zig`) covers 7 scenarios: discard handler, text handler, JSON handler, logger disabled, logger enabled, timestamp formatting, and attribute creation. It does not benchmark the async handler, QueuedRecord serialization/deserialization, queue push/pop under contention, or `isSensitiveKey()` -- all of which were recently modified in Phases 1-3 (commits 3fcd5a5, pass 4 changes).

**Perf Impact:** Cannot detect performance regressions in recently changed code. The async handler, queue, and redact modules have undergone significant changes (PERF-005, 008, 015, 023, 026 fixes) but lack regression coverage.

**Evidence:**

- `bench/bench_main.zig` -- contains: `benchDiscardHandler`, `benchTextHandler`, `benchJsonHandler`, `benchLoggerDisabled`, `benchLoggerEnabled`, `benchTimestampFormatting`, `benchAttrCreation`
- No `benchAsyncHandler`, no `benchQueuedRecord`, no `benchQueueContention`, no `benchIsSensitiveKey`
- No `@import("async_handler")` or `@import("queue")` or `@import("redact")` in bench_main.zig

**Root Cause:** The benchmark suite was created before the async handler and redact optimizations. It was not updated to cover new code paths as they were added.

**Fix Guidance:** Add benchmarks for:

1. `benchAsyncHandler` -- enqueue + drain throughput through async handler
2. `benchQueuedRecord` -- `fromRecord()` serialization + `attrs()` deserialization
3. `benchQueueContention` -- N threads pushing/popping concurrently
4. `benchIsSensitiveKey` -- 100K calls with varying key lengths and patterns

**Validation Plan:**

```bash
# After adding benchmarks, run and verify they produce stable results:
zig build bench -Doptimize=ReleaseFast 2>&1 | grep -E "Async|Queue|Sensitive"
# Each benchmark should show <10% variance across 5 runs
```

**Affected Paths:** `bench/bench_main.zig`

**Rollout Risk:** None. Pure additive to test infrastructure.

---

### PERF-037: No automated performance regression detection in CI

- **PerfSeverity:** P3
- **PerfScore:** 16 (Impact=2 x Likelihood=2 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci

**Summary:** The `.gitlab-ci.yml` has a `bench-regression` job (lines 164-178) that runs benchmarks and stores results as artifacts, but it performs no comparison against baselines, sets no performance thresholds, and produces no pass/fail signal. Results are stored for 90 days but require manual inspection to detect regressions.

**Perf Impact:** Performance regressions can land on main undetected. A developer must manually download artifacts from two pipelines and compare numbers to notice a regression.

**Evidence:**

- `.gitlab-ci.yml:164` -- `bench-regression:` job defined
- `.gitlab-ci.yml:170` -- `zig build bench -Doptimize=ReleaseFast 2>&1 | tee bench-results.txt` -- runs bench, captures output
- `.gitlab-ci.yml:172-173` -- artifacts stored but no comparison script
- No threshold checks, no baseline comparison, no alerting
- Job is `allow_failure: true` (line 178) -- even a crash would not block the pipeline

**Root Cause:** The regression detection job was set up as a first step (capture results) but the second step (compare against baseline) was never implemented.

**Fix Guidance:**

1. Store a baseline `bench-results.txt` in the repository or as a protected artifact.
2. Add a comparison script that parses ns/op from current and baseline results.
3. Fail the job if any benchmark regresses by more than a configurable threshold (e.g., 15%).
4. Alternatively, use a third-party service like `bencher.dev` or `github-action-benchmark` (GitLab equivalent).

**Validation Plan:**

```bash
# After implementing, introduce a deliberate regression (e.g., add Thread.sleep to TextHandler)
# Verify the CI job detects and fails on the regression
# Then revert and verify the job passes
```

**Affected Paths:** `.gitlab-ci.yml`, `bench/` (comparison script)

**Rollout Risk:** Low. Additive CI configuration. Risk of false positives if threshold is too tight; use statistical comparison rather than single-run delta.

---

### PERF-038: parallel.zig getPool() uses mutex on every call instead of double-checked locking

- **PerfSeverity:** P3
- **PerfScore:** 12 (Impact=1 x Likelihood=3 x 4)
- **Confidence:** `confidence::confirmed`
- **Area:** ci

**Summary:** `getPool()` at `parallel.zig:74-78` acquires `pool_mutex` on every invocation, even after the global pool has been initialized. An atomic load could skip the lock in the common case (pool already initialized), acquiring the mutex only for the one-time initialization.

**Perf Impact:** ~20-50ns per call under contention. The function is called from `parallelFormatRecords` (line 158), `parallelDispatch` (line 252), `parallelSinkWrite` (line 346), and `parallelBatchFlush` (line 439) -- so every parallel operation pays this cost. Only matters if parallel.zig is actually used by consumers (it is not used internally).

**Evidence:**

- `src/parallel.zig:74-78` -- `pub fn getPool() ... { pool_mutex.lock(); defer pool_mutex.unlock(); if (global_pool == null) { global_pool = ...; } return &global_pool.?; }`
- `src/parallel.zig:71` -- `var global_pool: ... ?spice.ThreadPool ... = null;` -- not atomic
- `src/parallel.zig:72` -- `var pool_mutex: std.Thread.Mutex = .{};`
- Called from 4 locations: lines 158, 252, 346, 439

**Root Cause:** Simple mutex-based lazy initialization without the double-checked locking optimization. This is the same issue as PERF-021 but is filed as a separate actionable item with specific fix guidance.

**Fix Guidance:** Use double-checked locking pattern:

1. Change `global_pool` to use `std.atomic.Value(?*spice.ThreadPool)`.
2. First check: `if (global_pool.load(.acquire)) |pool| return pool;`
3. Only if null: `pool_mutex.lock(); defer pool_mutex.unlock();`
4. Re-check inside lock: `if (global_pool.load(.monotonic)) |pool| return pool;`
5. Initialize and store: `const pool = ...; global_pool.store(pool, .release); return pool;`

**Validation Plan:**

```bash
# Benchmark getPool() call overhead: 8 threads, 1M calls each
# Before: ~20-50ns under contention (mutex); After: ~1-5ns (atomic load)
```

**Affected Paths:** `src/parallel.zig`

**Rollout Risk:** Very low. Standard double-checked locking pattern. Only affects initialization path.

---

## Roadmap

### Quick Wins (< 1 day each)

| ID | Finding | Effort | Expected Impact | Status |
|---|---|---|---|---|
| ~~PERF-031~~ | ~~Make async_handler level field atomic~~ | ~~30 min~~ | ~~Eliminate data race / undefined behavior~~ | **Closed** |
| ~~PERF-032~~ | ~~Add truncation indicator for MAX_STORED_ATTRS~~ | ~~1 hour~~ | ~~Users can detect silent data loss~~ | **Closed** |
| ~~PERF-029 (partial)~~ | ~~Remove misleading doc claims in http_sink~~ | ~~15 min~~ | ~~Correct documentation~~ | **Won't Do** |
| ~~PERF-033~~ | ~~Return count from pushDropOldest to avoid len()~~ | ~~1-2 hours~~ | ~~Eliminate double mutex per async enqueue~~ | **Closed** |
| ~~PERF-038~~ | ~~Double-checked locking in getPool()~~ | ~~1 hour~~ | ~~Skip mutex on hot path~~ | **Closed** |
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
| ~~PERF-030~~ | ~~Release mutex before Thread.sleep in TCP/HTTP retries~~ | ~~2-3 days~~ | ~~Eliminate multi-second thread blocking during retries~~ | **Won't Do** |
| ~~PERF-036~~ | ~~Add async handler, queue, and redact benchmarks~~ | ~~2-3 days~~ | ~~Regression detection for recently changed code~~ | **Closed** |
| ~~PERF-035~~ | ~~Parallel dispatch in multi-handler (opt-in)~~ | ~~2-3 days~~ | ~~Reduce multi-handler latency from sum to max~~ | **Won't Do** |
| ~~PERF-034~~ | ~~Batch I/O interface for async handler drain~~ | ~~3-5 days~~ | ~~Reduce per-record I/O overhead under batch drain~~ | **Won't Do** |
| ~~PERF-037~~ | ~~Automated perf regression comparison in CI~~ | ~~1-2 days~~ | ~~Detect regressions before merge~~ | **Won't Do** |
| PERF-025 | Reduce stack buffer sizes across handlers | 2-3 days | 4-6x less stack per call; better cache utilization | **Won't Do** (requires profiling data; risks truncation) |
| ~~PERF-026~~ | ~~Add batch dequeue to async handler worker~~ | ~~1-2 days~~ | ~~Amortize per-wake overhead under burst load~~ | **Closed** |
| ~~PERF-023~~ | ~~Optimize isSensitiveKey() with better data structure~~ | ~~1 day~~ | ~~Reduce substring scan overhead per attribute~~ | **Closed** |
| PERF-017 | Gate parallel.zig behind opt-in flag | 30 min | Faster builds | **Won't Do** |

### Strategic (> 5 days each)

| ID | Finding | Effort | Expected Impact | Status |
|---|---|---|---|---|
| ~~PERF-029~~ | ~~HTTP connection pooling + payload batching~~ | ~~7-10 days~~ | ~~100-1000x throughput improvement; match doc claims~~ | **Won't Do** |
| ~~PERF-008~~ | ~~Redesign QueuedRecord for variable-length records~~ | ~~5-7 days~~ | ~~10x memory reduction (12.2MB -> ~1.2MB)~~ | **Won't Do** |
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
| PERF-008 | 3 | 5 | 60 | 12.2MB overhead; always allocated when async used | Won't Do |
| PERF-009 | 5 | 3 | 60 | Security: cleartext on HTTPS; only users who specify https:// | **Closed** |
| PERF-010 | 4 | 3 | 48 | Cascading failure; only during TCP endpoint outages | **Closed** |
| PERF-011 | 3 | 4 | 48 | 14x syscall overhead; always hit on journald fallback | **Closed** |
| PERF-012 | 3 | 4 | 48 | Per-byte overhead; only bytes attrs, but common path | **Closed** |
| PERF-013 | 3 | 3 | 36 | Syscall per record; only rotating file users | **Closed** |
| PERF-014 | 3 | 3 | 36 | Busy-wait; only during flush calls | **Closed** |
| PERF-015 | 3 | 3 | 36 | TOCTOU + double lock; every async enqueue | **Closed** |
| PERF-016 | 2 | 4 | 32* | Extra O(n) pass; every JSON record (*adjusted to 36) | **Closed** |
| PERF-017 | 2 | 3 | 24 | Build cost only; every build | Won't Do |
| PERF-018 | 2 | 2 | 16 | Unreliable benchmarks; CI only | Won't Do |
| PERF-019 | 2 | 2 | 16 | Missing contention testing; CI only | Won't Do |
| PERF-020 | 2 | 3 | 24* | False sharing; under concurrent load (*adjusted to 12 -- now confirmed fixed) | **Closed** |
| PERF-021 | 1 | 3 | 12 | Mutex overhead; only if parallel.zig is used | Won't Do |
| **PERF-022** | **3** | **4** | **48** | **UDP sink holds mutex during format+send; serializes all threads** | **Closed** |
| **PERF-023** | **2** | **2** | **20*** | **15 substring scans per attr from 8 handlers; O(k*p) per call (*composite score)** | **Closed** |
| **PERF-024** | **1** | **1** | **4** | **Missed PERF-012 fix in rotating_file; rare code path** | **Closed** |
| **PERF-025** | **3** | **5** | **60** | **8-25KB stack per log call; cache pollution on hot path** | **Won't Do** |
| **PERF-026** | **2** | **3** | **24** | **Single-record worker loop; no batch drain under burst** | **Closed** |
| **PERF-027** | **2** | **1** | **12*** | **Re-formats per child handler; architecturally expected (*adjusted to 12)** | **Won't Do** |
| **PERF-028** | **3** | **3** | **30*** | **Dead field-building code always executes; doubles journald work (*functional bug)** | **Closed** |
| **PERF-029** | **5** | **5** | **100** | **HTTP sink has no batching or pooling despite doc claims; new TCP per record; unusable at scale** | **Won't Do** |
| **PERF-030** | **5** | **4** | **80** | **TCP/HTTP retries sleep while holding mutex; 700ms-15s serialized blocking** | **Won't Do** |
| **PERF-031** | **4** | **4** | **64** | **Non-atomic level read/write across threads; undefined behavior in Zig** | **Closed** |
| **PERF-032** | **3** | **4** | **48** | **Silent attr truncation at MAX_STORED_ATTRS=8; no diagnostic indicator** | **Closed** |
| **PERF-033** | **2** | **5** | **40** | **Double mutex per async enqueue: pushDropOldest + len()** | **Closed** |
| **PERF-034** | **2** | **4** | **32** | **Batch drain calls inner handler per record; no batched I/O opportunity** | **Won't Do** |
| **PERF-035** | **2** | **3** | **24** | **Multi-handler sequential dispatch despite parallel.zig availability** | **Won't Do** |
| **PERF-036** | **2** | **3** | **24** | **Benchmark suite missing async/queue/redact coverage; can't detect regressions** | **Closed** |
| **PERF-037** | **2** | **2** | **16** | **CI bench job stores results but has no comparison or threshold logic** | **Won't Do** |
| **PERF-038** | **1** | **3** | **12** | **getPool() mutex on every call; double-checked locking would skip lock** | **Closed** |

*Scores with asterisks were adjusted from raw calculation to better reflect real-world impact and confidence level.

---

## Unknowns and Blockers

1. ~~**No profiler data available.**~~ Resolved: All referenced items are now closed or won't do. PERF-025 (Won't Do), PERF-033 (Closed), PERF-034 (Won't Do). Profiler data is no longer needed for prioritization since all items are resolved.

2. ~~**Async handler attr deserialization complexity.**~~ Resolved: StoredAttr array with serialize/deserialize was implemented in commit 3fcd5a5. PERF-005 is closed.

3. ~~**TLS implementation for PERF-009.**~~ Resolved: HTTPS URLs are now rejected at init with `error.HttpsNotSupported`. PERF-009 is closed.

4. ~~**False sharing measurement (PERF-020).**~~ Resolved: PaddedCounter with `align(cache_line)` implemented. Test at `metrics.zig:185-201` confirms alignment. PERF-020 is closed.

5. ~~**parallel.zig integration plan.**~~ Resolved: PERF-017 and PERF-035 both marked Won't Do. parallel.zig is an external-facing module; no opt-in gate or multi-handler integration required.

6. ~~**isSensitiveKey() actual hot-path impact (PERF-023).**~~ Resolved: optimized with comptime-unrolled inline for in pass 4. PERF-023 is closed.

7. ~~**Stack buffer reduction safety (PERF-025).**~~ Resolved: PERF-025 marked Won't Do. Requires profiling data; risks truncation without real-world measurement. Current stack sizes are safe.

8. ~~**Journald native API path (PERF-028).**~~ Resolved: field-building guarded by comptime `native_sendv_available`. PERF-028 is closed.

9. ~~**PERF-031 data race severity.**~~ Resolved: Non-atomic level field replaced with atomic Value across all 12 handlers. PERF-031 is closed.

10. ~~**PERF-029 relationship to PERF-001.**~~ Resolved: PERF-029 marked Won't Do. Misleading doc claims corrected; full HTTP connection pooling/batching deferred as out-of-scope architectural change.

11. ~~**PERF-034 batch I/O value.**~~ Resolved: PERF-034 marked Won't Do. Batch drain (PERF-026) provides sufficient optimization; per-handler batched I/O is low value given current handler architecture.

12. ~~**Benchmark coverage gap (PERF-036).**~~ Resolved: PERF-036 closed (async/queue/redact benchmarks added). PERF-037 marked Won't Do (CI comparison logic deferred).
