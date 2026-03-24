# Quality Gap Analysis -- slogz

**Repository:** gitlab.com/devnw/zig/slog
**Branch:** main
**Last updated:** 2026-03-24 (rev 3 -- pass 4: NEW-01, NEW-03 closed)
**Scoring framework:** PriorityScore = Impact(1-5) x Likelihood(1-5) x 4

---

## Summary

| Severity | Count | Closed | Won't Do | Open | Partially Closed |
|----------|-------|--------|----------|------|------------------|
| Critical | 4 | 4 | 0 | 0 | 0 |
| High | 7 | 6 | 1 | 0 | 0 |
| Medium | 12 | 12 | 0 | 0 | 0 |
| Low | 7 | 5 | 1 | 0 | 1 |
| **Total** | **30** | **27** | **2** | **0** | **1** |

### Top Open Risks

1. **deprecatedWriter() in slogz.zig** (PriorityScore 12) -- **Partially Closed**; windows_eventlog.zig fixed, slogz.zig blocked on AnyWriter handler interface refactor.

---

## Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | Issue URL | Fix Summary | Owner | Effort | Status |
|------|----------|---------------|----------|---------|-----------|----------|-----------|-------------|-------|--------|--------|
| 1 | Critical | 100 | api-contract | AsyncHandler drops ALL record attributes | async_handler.zig | Lines 93, 114: `.attrs = &.{}` hardcoded in both worker loop and drain loop | #20 | QueuedRecord now serializes/deserializes all attrs via StoredAttr | @maintainers | M | **Closed** (3fcd5a5) |
| 2 | Critical | 80 | architecture | stderrHandler / stderrJsonHandler return dangling pointers | slogz.zig | Lines 107-130: `text.init(&ctx)` captures pointer to stack-local `ctx`; returned struct copy is at different address | #19 | API changed to accept *Context out-param; caller owns memory | @maintainers | S | **Closed** (ec068d0) |
| 3 | Critical | 80 | architecture | AsyncHandler.Context.init thread receives dangling pointer | async_handler.zig | Line 59: `std.Thread.spawn(.{}, workerThread, .{&ctx})` -- `ctx` is stack-local in `init`, returned by value; thread gets stale pointer | -- | Thread spawn deferred to startWorker(); caller owns Context | @maintainers | S | **Closed** (3fcd5a5) |
| 4 | High | 80 | api-contract | withAttrs/withGroup universally no-op across all 9 handlers | text_handler.zig, json_handler.zig, syslog_rfc5424.zig, journald.zig, windows_eventlog.zig, async_handler.zig, rotating_file.zig, discard_handler.zig, tcp/udp/http sinks | All withAttrs/withGroup fns discard their arguments and return the same handler | #8,#17 | Requires allocator-aware context cloning; separate effort | @maintainers | L | **Won't Do** |
| 5 | High | 80 | ci-cd | CI pipeline has no build or test stage | .gitlab-ci.yml | Lines 37-40: `stages: [security, sbom, release]` -- no `build` or `test` stage; comment on line 5 says "requires Zig 0.15.x which is not yet released" | #22 | Build, test, format-check stages added with Zig 0.15.2 image | @maintainers | M | **Closed** (ec068d0) |
| 6 | High | 64 | api-contract | Network sinks (TCP, UDP, HTTP) drop all record attributes from JSON output | tcp_sink.zig, udp_sink.zig, http_sink.zig | tcp_sink.zig:125-167, udp_sink.zig:86-128, http_sink.zig:185-227: handle() serializes time/level/msg/logger but never iterates `rec.attrs` | #7 | All three sinks now iterate rec.attrs with JSON serialization | @maintainers | S | **Closed** (0ed8afe) |
| 7 | High | 64 | perf | QueuedRecord i64 serialization broken -- integer values become empty strings | queue.zig | Lines 74-79: `formatInt` result is discarded (`_ = len`), then `break :blk ""` always returns empty string | #21 | Replaced with serializeValue() using std.fmt.bufPrint | @maintainers | S | **Closed** (3fcd5a5) |
| 8 | High | 48 | architecture | formatBackupPath buffer aliasing causes rotation failure | rotating_file.zig | Lines 107-108, 129-132: `formatBackupPath` writes to `self.path_buf`; calling it twice in the same expression (`old_path` then `new_path`) overwrites `old_path` since both alias `self.path_buf` | #23 | Added path_buf2; formatBackupPath uses separate buffers | @maintainers | S | **Closed** (05c6a16) |
| 9 | Medium | 48 | maintainability | writeValue function duplicated 3x across handlers | text_handler.zig:111-149, journald.zig:155-177, windows_eventlog.zig:136-158 | Near-identical switch on Value union with minor formatting differences; bug fixes (e.g., @errorName guard) applied to only 1 of 3 copies | -- | All handlers now share consistent writeValue with @errorName guard, sanitizeOutput, and hex lookup table | @maintainers | M | **Closed** (0ed8afe) |
| 10 | Medium | 48 | maintainability | JSON encoding logic duplicated 3x across network sinks | tcp_sink.zig:125-177, udp_sink.zig:86-134, http_sink.zig:185-233 | Identical JSON record serialization (time, level, msg, logger) repeated in each sink's handle() | -- | All sinks now include attrs serialization; consistent pattern applied | @maintainers | M | **Closed** (0ed8afe) |
| 11 | Medium | 36 | architecture | @errorName guard missing in 4 of 5 handlers | json_handler.zig:173, syslog_rfc5424.zig:248, journald.zig:173, windows_eventlog.zig:154 | Only text_handler.zig (lines 139-145) guards against corrupt anyerror values; the other 4 call `@errorName(e)` directly, risking UB on invalid error index | -- | Raw-value guard applied to all handlers (json, syslog, journald, windows_eventlog) | @maintainers | S | **Closed** (0ed8afe) |
| 12 | Medium | 36 | architecture | Silent error swallowing in rotating_file.zig | rotating_file.zig | Lines 74, 88, 93, 112, 115, 121: `catch {}` on makePath, stat, seekTo, deleteFile, rename operations -- failures go completely unnoticed | -- | Error catch blocks now call metrics.global.incErrors() | @maintainers | S | **Closed** (05c6a16) |
| 13 | Medium | 36 | api-contract | LoggerOptions re-exported but does not exist in logger.zig | slogz.zig | Line 50: `pub const LoggerOptions = @import("logger.zig").LoggerOptions;` -- logger.zig has no `LoggerOptions` symbol; any consumer referencing `slogz.LoggerOptions` gets a compile error | #25 | Removed phantom LoggerOptions re-export from slogz.zig | @maintainers | S | **Closed** (ec068d0) |
| 14 | Medium | 36 | tests | FixedClock mechanism is non-functional | clock.zig | Lines 31-58: `FixedClock.init` creates a local struct, calls `fixedNowFn(&fc)` which ignores `self` and returns a generic fn that reads thread-local `fixed_test_timestamp`; the FixedClock's own `timestamp_us` field is never used by the clock | -- | FixedClock now properly wires timestamp_us into returned fn pointer | @maintainers | S | **Closed** (ec068d0) |
| 15 | Medium | 36 | maintainability | Syslog handler writeSDValue missing @errorName guard | syslog_rfc5424.zig | Line 248: `@errorName(e)` called without the raw-value guard present in text_handler.zig | -- | Raw-value guard applied (covered by finding 11) | @maintainers | S | **Closed** (0ed8afe) |
| 16 | Low | 32 | maintainability | VTable boilerplate duplicated across 9+ handlers | All handler files | Every handler defines identical withAttrs/withGroup/setLevel/flush stubs with the same no-op pattern | -- | Depends on withAttrs implementation; separate effort | @maintainers | M | **Won't Do** |
| 17 | Low | 16 | cleanup | rotating_file.zig imports text_handler but never uses it | rotating_file.zig | Line 22: `const text_handler = @import("text_handler.zig");` -- symbol `text_handler` is never referenced | -- | Unused text_handler import removed | @maintainers | S | **Closed** (05c6a16) |
| 18 | Low | 16 | cleanup | epochDays / ymdToEpochDay duplicated in clock.zig and rfc3339.zig | clock.zig:111-129, rfc3339.zig:139-155 | Identical algorithm (Howard Hinnant epoch-day conversion) copy-pasted | -- | clock.zig now imports from rfc3339.zig; duplication removed | @maintainers | S | **Closed** (ec068d0) |
| 19 | Low | 8 | cleanup | BaseHandlerContext defined but never used | handler.zig | Lines 91-120: `pub const BaseHandlerContext` is defined with init/enabled/prefixedKey but no handler imports or uses it | -- | Removed BaseHandlerContext dead code from handler.zig | @maintainers | S | **Closed** (ec068d0) |
| 20 | Low | 8 | cleanup | Metrics.incReconnections() never called | metrics.zig | Line 74: `pub fn incReconnections` defined but grep finds zero callers across the entire codebase | -- | Wired into tcp_sink.zig reconnection logic | @maintainers | S | **Closed** (ec068d0) |
| 21 | Critical | 100 | maintainability | writeJsonValue() duplicated verbatim across 4 files | json_handler.zig, tcp_sink.zig, udp_sink.zig, http_sink.zig | json_handler.zig:152, tcp_sink.zig:164, udp_sink.zig:89, http_sink.zig:187: identical `fn writeJsonValue(enc: anytype, value: Value) !void` with same switch arms | [#33](https://gitlab.com/devnw/zig/slog/-/issues/33) | Extracted to `src/fmt/json_value.zig`; all 4 files import shared function | @maintainers | M | **Closed** |
| 22 | High | 60 | maintainability | writeValue() behavioral drift across 4 text-mode copies | text_handler.zig, journald.zig, windows_eventlog.zig, rotating_file.zig | text_handler.zig:131 uses `{d:.6}` for floats; journald.zig:176 and windows_eventlog.zig:150 use `{d}`; rotating_file.zig:316 uses raw `writeAll` instead of `sanitizeOutput`; marshaler text is `<marshaler>` vs `?` | [#34](https://gitlab.com/devnw/zig/slog/-/issues/34) | Extracted to `src/fmt/text_value.zig` with canonical behavior (f64:.6, 0x hex, `<marshaler>`); all 4 handlers import shared function | @maintainers | M | **Closed** |
| 23 | High | 60 | architecture | rotating_file.zig missing sanitizeOutput() on .str values | rotating_file.zig | Line 316: `.str => \|s\| try writer.writeAll(s)` -- no `sanitizeOutput()` call; all other text handlers sanitize strings | [#35](https://gitlab.com/devnw/zig/slog/-/issues/35) | Replace `writer.writeAll(s)` with `sanitize.sanitizeOutput(writer, s)` | @maintainers | S | **Closed** (sanitizeOutput applied to .str in writeValue) |
| 24 | Medium | 36 | architecture | rotating_file.zig missing close vtable entry | rotating_file.zig | Lines 378-384: vtable has no `.close` entry; `Context.deinit()` at line 75 is unreachable via `Handler.close()`; other handlers with cleanup (tcp/udp/http sinks, async, multi, windows_eventlog) all define `.close` | [#37](https://gitlab.com/devnw/zig/slog/-/issues/37) | Add `close` fn delegating to `deinit()` and wire into vtable | @maintainers | S | **Closed** (close fn added, vtable wired) |
| 25 | Medium | 30 | cleanup | incReconnections() has zero callers (regression) | metrics.zig, tcp_sink.zig | metrics.zig:87 defines `incReconnections`; `rg "incReconnections" src/` returns only the definition; previously marked Closed (ec068d0) but fix did not persist | [#39](https://gitlab.com/devnw/zig/slog/-/issues/39) | Wire `metrics.global.incReconnections()` into tcp_sink reconnection path | @maintainers | S | **Closed** (incReconnections called on successful reconnection in writeWithRetry) |
| 26 | Low | 18 | perf | UDP sink serializes under mutex unlike TCP/HTTP | udp_sink.zig | Lines 132-133: `ctx.mutex.lock()` before JSON formatting; tcp_sink.zig:207 and http_sink.zig:239 format outside mutex then lock only for send | -- | JSON formatting moved outside mutex; lock only for ctx.send() | @maintainers | S | **Closed** |
| 27 | Low | 12 | cleanup | deprecatedWriter() API usage at 3 call sites | slogz.zig, windows_eventlog.zig | slogz.zig:114, slogz.zig:128: `std.fs.File.stderr().deprecatedWriter().any()`; windows_eventlog.zig:135: `std.fs.File.stderr().deprecatedWriter()` | [#1](https://gitlab.com/devnw/zig/slog/-/issues/1) | Replace with current Zig 0.15 writer API | @maintainers | S | **Partially Closed** (windows_eventlog.zig fixed; slogz.zig blocked on AnyWriter handler interface refactor) |
| 28 | Low | 8 | architecture | error.UnsupportedPlatform not in HandlerError | journald.zig, windows_eventlog.zig | journald.zig:67, windows_eventlog.zig:96: `return error.UnsupportedPlatform` in functions returning `HandlerError!void`; `UnsupportedPlatform` not in `HandlerError` error set | [#26](https://gitlab.com/devnw/zig/slog/-/issues/26) (Closed) | Use `error.FeatureDisabled` or add to `HandlerError` | @maintainers | S | **Closed** (#26) |
| 29 | Medium | 36 | tests | No unit tests for json_value.zig and text_value.zig | src/fmt/json_value.zig, src/fmt/text_value.zig | Newly extracted shared modules had zero inline tests; all Value variants untested at the unit level | -- | Added 12 inline tests to json_value.zig and 11 inline tests to text_value.zig covering all Value variants | @maintainers | M | **Closed** (pass 4: 23 total inline tests added) |
| 30 | Medium | 30 | architecture | json_value.zig bytes truncation at 256 bytes | src/fmt/json_value.zig | Original 512-byte hex buffer only supported 256 input bytes; SHA-512 hashes, AES keys, and typical binary fields exceed this | -- | Buffer increased from 512 to 2048 bytes (1024 input bytes); truncation marker "..." appended for inputs beyond 1024 bytes | @maintainers | S | **Closed** (pass 4: max_input=1024, hex_buf[2048], "..." truncation marker) |

**Notes:**
- Finding 15 (syslog @errorName guard) is a sub-instance of finding 11; they share a root cause and should be fixed together.
- Findings 21-22 are deeper analyses of the same code areas as findings 9-10 (which addressed consistency but not deduplication).
- Finding 23 is a sub-instance of finding 22 (text-mode drift), tracked separately for severity/security traceability.
- Finding 25 is a regression of finding 20; the previous fix (ec068d0) did not persist.
- Finding 27 overlaps with existing issue #1; no new issue created.
- Finding 28 overlaps with existing issue #26 (Closed); no new issue created.
- Finding 29 (NEW-01) addresses missing unit test coverage for the shared json_value.zig and text_value.zig modules extracted in pass 3.
- Finding 30 (NEW-03) addresses the json_value.zig bytes encoding buffer being too small for common binary fields (SHA-512, AES keys).

---

## Findings by Category

### api-contract
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 1 | AsyncHandler drops ALL record attributes | 100 | Closed |
| 4 | withAttrs/withGroup universally no-op | 80 | Won't Do |
| 6 | Network sinks drop all attributes from JSON output | 64 | Closed |
| 13 | LoggerOptions re-exported but does not exist | 36 | Closed |

### architecture
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 2 | stderrHandler / stderrJsonHandler dangling pointers | 80 | Closed |
| 3 | AsyncHandler.Context.init dangling pointer to thread | 80 | Closed |
| 8 | formatBackupPath buffer aliasing | 48 | Closed |
| 11 | @errorName guard missing in 4 of 5 handlers | 36 | Closed |
| 12 | Silent error swallowing in rotating_file | 36 | Closed |
| 23 | rotating_file missing sanitizeOutput() on .str | 60 | **Closed** |
| 24 | rotating_file missing close vtable entry | 36 | **Closed** |
| 28 | error.UnsupportedPlatform not in HandlerError | 8 | Closed |
| 30 | json_value.zig bytes truncation at 256 bytes | 30 | **Closed** |

### ci-cd
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 5 | CI pipeline has no build or test stage | 80 | Closed |

### perf
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 7 | QueuedRecord i64 serialization broken | 64 | Closed |
| 26 | UDP sink serializes under mutex | 18 | **Closed** |

### maintainability
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 21 | writeJsonValue() duplicated 4x | 100 | **Closed** |
| 22 | writeValue() behavioral drift 4x | 60 | **Closed** |
| 9 | writeValue duplicated 3x | 48 | Closed |
| 10 | JSON encoding duplicated 3x in sinks | 48 | Closed |
| 16 | VTable boilerplate duplicated 9x | 32 | Won't Do |
| 15 | Syslog writeSDValue missing @errorName guard | 36 | Closed |

### tests
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 14 | FixedClock mechanism non-functional | 36 | Closed |
| 29 | No unit tests for json_value.zig and text_value.zig | 36 | **Closed** |

### cleanup
| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 25 | incReconnections() zero callers (regression) | 30 | **Closed** |
| 27 | deprecatedWriter() usage (3 call sites) | 12 | **Partially Closed** |
| 17 | rotating_file dead import | 16 | Closed |
| 18 | epochDays / ymdToEpochDay duplicated | 16 | Closed |
| 19 | BaseHandlerContext dead code | 8 | Closed |
| 20 | Metrics.incReconnections() dead code | 8 | Closed |

---

## Roadmap

### Quick Wins (< 1 day)

| Rank | Finding | Effort | Notes | Status |
|------|---------|--------|-------|--------|
| 23 | rotating_file missing sanitizeOutput() | S | One-line fix: replace `writeAll(s)` with `sanitizeOutput(writer, s)` at line 316 | **Closed** |
| 24 | rotating_file missing close vtable entry | S | Add `close` fn + vtable entry; mirrors pattern in other handlers | **Closed** |
| 25 | incReconnections() zero callers (regression) | S | Add `metrics.global.incReconnections()` at tcp_sink reconnection point | **Closed** |
| 26 | UDP sink serializes under mutex | S | JSON formatting moved outside mutex | **Closed** |
| 27 | deprecatedWriter() usage | S | Replace with current Zig 0.15 writer API at 3 call sites | **Partially Closed** |

### Medium (1-5 days)

| Rank | Finding | Effort | Notes | Status |
|------|---------|--------|-------|--------|
| 21 | writeJsonValue() duplicated 4x | M | Extracted to `src/fmt/json_value.zig`; 4 files updated | **Closed** |
| 22 | writeValue() behavioral drift 4x | M | Extracted to `src/fmt/text_value.zig`; canonical behavior applied | **Closed** |

### Strategic (> 5 days)

| Rank | Finding | Effort | Notes |
|------|---------|--------|-------|
| 4 | withAttrs/withGroup no-op across all handlers | L | Requires allocator-aware context cloning for all 9 handler types; significant API surface change |

---

## Confidence Notes

All findings are tagged **confidence::confirmed** -- each was verified by reading the source code directly. Specific confirmation notes:

- **Finding 1 (attrs dropped):** Confirmed at async_handler.zig:93 and :114 -- hardcoded `&.{}`.
- **Finding 2 (dangling ptr):** Confirmed at slogz.zig:108-116 -- `var ctx` is stack-local, `text.init(&ctx)` stores pointer, struct returned by value copies ctx to new address.
- **Finding 3 (thread dangling ptr):** Confirmed at async_handler.zig:44-61 -- `var ctx = Context{...}; ctx.thread = std.Thread.spawn(.{}, workerThread, .{&ctx})` then `return ctx;` moves ctx.
- **Finding 6 (sink attrs):** Confirmed in tcp_sink.zig:125-167, udp_sink.zig:86-128, http_sink.zig:185-227 -- no `rec.attrs` iteration present.
- **Finding 7 (i64 broken):** Confirmed at queue.zig:74-79 -- `formatInt` return stored in `len`, but `_ = len;` discards it and `break :blk ""` always returns empty.
- **Finding 8 (buffer aliasing):** Confirmed at rotating_file.zig:107-108 -- both `formatBackupPath(i)` and `formatBackupPath(i+1)` write to same `self.path_buf`.
- **Finding 13 (LoggerOptions):** Confirmed -- `grep -r LoggerOptions logger.zig` returns zero matches; symbol does not exist.
- **Finding 14 (FixedClock):** Confirmed at clock.zig:44-53 -- `fixedNowFn` ignores `self`, returns fn that reads threadlocal; `timestamp_us` field is unused.
- **Finding 17 (dead import):** Confirmed at rotating_file.zig:22 -- `const text_handler = @import("text_handler.zig");` with zero references.
- **Finding 21 (writeJsonValue 4x):** Confirmed by reading all four definitions: json_handler.zig:152, tcp_sink.zig:164, udp_sink.zig:89, http_sink.zig:187 -- identical switch arms across all Value variants.
- **Finding 22 (writeValue drift):** Confirmed: text_handler.zig:131 uses `{d:.6}` for floats vs journald.zig:176 uses `{d}`; rotating_file.zig:330 uses `{x:0>2}` for bytes vs text_handler.zig:139 uses hex_chars lookup; journald.zig:195 marshaler is `?` vs text_handler.zig:153 is `<marshaler>`.
- **Finding 23 (sanitizeOutput missing):** Confirmed at rotating_file.zig:316 -- `.str => |s| try writer.writeAll(s)` with no sanitization; all other text handlers call `sanitize.sanitizeOutput()`.
- **Finding 24 (close vtable missing):** Confirmed at rotating_file.zig:378-384 -- vtable has 5 entries (handle, withAttrs, withGroup, setLevel, flush) but no `.close`; `Context.deinit()` exists at line 75.
- **Finding 25 (incReconnections regression):** Confirmed -- `rg "incReconnections" src/` returns only the definition at metrics.zig:87; no call sites.
- **Finding 26 (UDP mutex scope):** Confirmed at udp_sink.zig:132-133 -- mutex locked before formatting; tcp_sink.zig:207 and http_sink.zig:239 format outside mutex.
- **Finding 27 (deprecatedWriter):** Confirmed at slogz.zig:114, slogz.zig:128, windows_eventlog.zig:135.
- **Finding 28 (UnsupportedPlatform):** Confirmed at journald.zig:67 and windows_eventlog.zig:96; `HandlerError` at handler.zig:15-24 does not include `UnsupportedPlatform`.

---

## Methodology

- **Scanner output:** Phase 3 deep review findings provided as input, plus new audit findings from 2026-03-24 deep review.
- **Verification:** Each finding verified by reading source files at the cited paths and lines.
- **Scoring:** PriorityScore = Impact(1-5) x Likelihood(1-5) x 4. Impact considers severity of failure mode. Likelihood considers how often the code path is exercised.
- **Deduplication:** Findings 11 and 15 share a root cause (@errorName guard inconsistency). Findings 21/22 deepen 9/10 (consistency was applied but duplication remains). Finding 23 is a specific instance within finding 22. Finding 25 is a regression of finding 20.
- **Issue tracking:** GitLab issues created via `glab issue create` for findings with PriorityScore >= 30. Existing issues referenced where overlap exists (#1, #26).
