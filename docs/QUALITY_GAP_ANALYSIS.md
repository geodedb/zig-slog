# Quality Gap Analysis -- slogz

**Repository:** gitlab.com/devnw/zig/slog
**Branch:** main
**Last updated:** 2026-06-12 (rev 6 -- Pass 6: Q-27 fully Closed (deprecatedWriter gone from src/, issue #1 closed); 8 new findings added Q-41..Q-48)
**Scoring framework:** PriorityScore = Impact(1-5) x Likelihood(1-5) x 4

---

## Summary

| Severity | Count | Closed | Won't Do | Open | Partially Closed |
|----------|-------|--------|----------|------|------------------|
| Critical | 4 | 4 | 0 | 0 | 0 |
| High | 8 | 7 | 1 | 0 | 0 |
| Medium | 20 | 17 | 0 | 3 | 0 |
| Low | 16 | 10 | 1 | 5 | 0 |
| **Total** | **48** | **38** | **2** | **8** | **0** |

### Remaining Items

Pass 6 added 8 new findings (Q-41..Q-48). Open items:

1. **Q-48 (Medium, NEW-9)** -- all 8 `examples/*.zig` broken: import `@import("slog")` but module is exported as `"slogz"` (build.zig:90); 6/8 use removed `std.io.getStdErr/getStdOut`; examples not wired into build.zig so breakage is invisible.
2. **Q-44 (Medium, NEW-4)** -- pre-commit zig-fmt hook targets `benchmarks/` (no .zig files) instead of `bench/` (3 .zig files); future bench edits escape format checking.
3. **Q-45 (Medium, NEW-5)** -- BoundedQueue `not_full`/`empty` condvars signaled but never waited on (dead fields + false-signal cost). Cross-referenced to PERF-040/PERF-042; no duplicate GitLab issue.
4. **Q-46 (Medium, NEW-7)** -- 9 stale `zig-pkg/` vendor snapshots (~36 MB). Issue [#44](https://gitlab.com/devnw/zig/slog/-/issues/44).
5. **Q-47 (Low, NEW-8)** -- slogz.zig:22 module doc-comment example uses `.writer().any()` (does not compile under Zig 0.16).
6. **Q-41/Q-42/Q-43 (Low, NEW-1/2/3)** -- auto-fixable lint (trailing whitespace/EOF, ruff-format, MD040 fences). Combined issue [#45](https://gitlab.com/devnw/zig/slog/-/issues/45).

Pass 5 item now resolved:

- **Q-27 deprecatedWriter()** -- **fully Closed**. `grep -rn deprecatedWriter src/` returns zero hits; slogz.zig uses `std.Io.File.stderr().writer()` + `&stderr_file_writer.interface`. GitLab issue [#1](https://gitlab.com/devnw/zig/slog/-/issues/1) closed with evidence.

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
| 31 | High | 64 | api-contract | Logger.with() attrs silently lost -- context_attrs never reach Record or handler | logger.zig, all handlers | logger.zig:119-131: `Logger.with(attrs)` stores `attrs` in `logger.context_attrs` and calls `handler.withAttrs(attrs)` which discards them; logger.zig:189-198: `Record` construction does NOT include `self.context_attrs`; json_handler.zig:103 and text_handler.zig:76 read `ctx.context_attrs` but handler `withAttrs()` never updates it | -- | Logger.log now merges context_attrs into Record.attrs | @maintainers | M | **Closed** (pass 5: Logger.with() attrs now merged into Record) |
| 8 | High | 48 | architecture | formatBackupPath buffer aliasing causes rotation failure | rotating_file.zig | Lines 107-108, 129-132: `formatBackupPath` writes to `self.path_buf`; calling it twice in the same expression (`old_path` then `new_path`) overwrites `old_path` since both alias `self.path_buf` | #23 | Added path_buf2; formatBackupPath uses separate buffers | @maintainers | S | **Closed** (05c6a16) |
| 9 | Medium | 48 | maintainability | writeValue function duplicated 3x across handlers | text_handler.zig:111-149, journald.zig:155-177, windows_eventlog.zig:136-158 | Near-identical switch on Value union with minor formatting differences; bug fixes (e.g., @errorName guard) applied to only 1 of 3 copies | -- | All handlers now share consistent writeValue with @errorName guard, sanitizeOutput, and hex lookup table | @maintainers | M | **Closed** (0ed8afe) |
| 10 | Medium | 48 | maintainability | JSON encoding logic duplicated 3x across network sinks | tcp_sink.zig:125-177, udp_sink.zig:86-134, http_sink.zig:185-233 | Identical JSON record serialization (time, level, msg, logger) repeated in each sink's handle() | -- | All sinks now include attrs serialization; consistent pattern applied | @maintainers | M | **Closed** (0ed8afe) |
| 33 | Medium | 48 | maintainability | JSON record serialization duplicated across 4 locations | json_handler.zig:45-121, tcp_sink.zig:170-237, udp_sink.zig:89-152, http_sink.zig:196-259 | All four files contain ~50 lines of identical record-level JSON serialization (beginObject, time, level, msg, logger, attrs iteration, endObject). Value-level writeJsonValue was extracted to json_value.zig but the record-level envelope was not. Schema differences (see Finding 35) prevent naive extraction. | -- | Extracted to `src/fmt/json_record.zig`; all 4 callers import shared function | @maintainers | M | **Closed** (pass 5: JSON record formatting extracted to json_record.zig) |
| 11 | Medium | 36 | architecture | @errorName guard missing in 4 of 5 handlers | json_handler.zig:173, syslog_rfc5424.zig:248, journald.zig:173, windows_eventlog.zig:154 | Only text_handler.zig (lines 139-145) guards against corrupt anyerror values; the other 4 call `@errorName(e)` directly, risking UB on invalid error index | -- | Raw-value guard applied to all handlers (json, syslog, journald, windows_eventlog) | @maintainers | S | **Closed** (0ed8afe) |
| 12 | Medium | 36 | architecture | Silent error swallowing in rotating_file.zig | rotating_file.zig | Lines 74, 88, 93, 112, 115, 121: `catch {}` on makePath, stat, seekTo, deleteFile, rename operations -- failures go completely unnoticed | -- | Error catch blocks now call metrics.global.incErrors() | @maintainers | S | **Closed** (05c6a16) |
| 13 | Medium | 36 | api-contract | LoggerOptions re-exported but does not exist in logger.zig | slogz.zig | Line 50: `pub const LoggerOptions = @import("logger.zig").LoggerOptions;` -- logger.zig has no `LoggerOptions` symbol; any consumer referencing `slogz.LoggerOptions` gets a compile error | #25 | Removed phantom LoggerOptions re-export from slogz.zig | @maintainers | S | **Closed** (ec068d0) |
| 14 | Medium | 36 | tests | FixedClock mechanism is non-functional | clock.zig | Lines 31-58: `FixedClock.init` creates a local struct, calls `fixedNowFn(&fc)` which ignores `self` and returns a generic fn that reads thread-local `fixed_test_timestamp`; the FixedClock's own `timestamp_us` field is never used by the clock | -- | FixedClock now properly wires timestamp_us into returned fn pointer | @maintainers | S | **Closed** (ec068d0) |
| 15 | Medium | 36 | maintainability | Syslog handler writeSDValue missing @errorName guard | syslog_rfc5424.zig | Line 248: `@errorName(e)` called without the raw-value guard present in text_handler.zig | -- | Raw-value guard applied (covered by finding 11) | @maintainers | S | **Closed** (0ed8afe) |
| 34 | Medium | 36 | maintainability | Text record formatting duplicated between text_handler and rotating_file | text_handler.zig:44-92, rotating_file.zig:265-318 | Both files contain ~55 lines of identical record-level text serialization (timestamp, level, logger, sanitized message, attrs iteration with key=value). Value-level writeTextValue was extracted to text_value.zig but the record-level formatting was not. | -- | Extracted to `src/fmt/text_record.zig`; both callers import shared function | @maintainers | M | **Closed** (pass 5: text record formatting extracted to text_record.zig) |
| 35 | Medium | 36 | api-contract | JSON schema inconsistency between json_handler and network sinks | json_handler.zig:98-113, tcp_sink.zig:209-219, udp_sink.zig:128-138, http_sink.zig:235-245 | json_handler nests attrs under `"attrs":{...}` object (line 99) and includes `"source":{...}` (line 87-95) and context_attrs (line 103); network sinks put attrs at the top level of the JSON object with no nesting, no source object, no context_attrs | -- | Reconciled to flat attrs + flat source via shared json_record.zig | @maintainers | M | **Closed** (pass 5: JSON schema reconciled to flat attrs + flat source) |
| 24 | Medium | 36 | architecture | rotating_file.zig missing close vtable entry | rotating_file.zig | Lines 378-384: vtable has no `.close` entry; `Context.deinit()` at line 75 is unreachable via `Handler.close()`; other handlers with cleanup (tcp/udp/http sinks, async, multi, windows_eventlog) all define `.close` | [#37](https://gitlab.com/devnw/zig/slog/-/issues/37) | Add `close` fn delegating to `deinit()` and wire into vtable | @maintainers | S | **Closed** (close fn added, vtable wired) |
| 29 | Medium | 36 | tests | No unit tests for json_value.zig and text_value.zig | src/fmt/json_value.zig, src/fmt/text_value.zig | Newly extracted shared modules had zero inline tests; all Value variants untested at the unit level | -- | Added 12 inline tests to json_value.zig and 11 inline tests to text_value.zig covering all Value variants | @maintainers | M | **Closed** (pass 4: 23 total inline tests added) |
| 32 | Medium | 32 | docs | Module docstring example shows incorrect Logger.init and logger.info signatures | slogz.zig | Lines 28-34: `var logger = slogz.Logger.init(std.heap.page_allocator, "myapp", handler)` -- actual signature is `Logger.init(handler, level, clock)` (3 different args); `logger.info("app.started", "Application started", &.{...})` -- actual signature is `info(msg_id, attrs)` (2 args, not 3); `defer logger.deinit()` -- Logger has no deinit() method | -- | Docstring example updated to match actual API signatures | @maintainers | S | **Closed** (pass 5: slogz.zig docstring example fixed to match Logger.init/info signatures) |
| 25 | Medium | 30 | cleanup | incReconnections() has zero callers (regression) | metrics.zig, tcp_sink.zig | metrics.zig:87 defines `incReconnections`; `rg "incReconnections" src/` returns only the definition; previously marked Closed (ec068d0) but fix did not persist | [#39](https://gitlab.com/devnw/zig/slog/-/issues/39) | Wire `metrics.global.incReconnections()` into tcp_sink reconnection path | @maintainers | S | **Closed** (incReconnections called on successful reconnection in writeWithRetry) |
| 30 | Medium | 30 | architecture | json_value.zig bytes truncation at 256 bytes | src/fmt/json_value.zig | Original 512-byte hex buffer only supported 256 input bytes; SHA-512 hashes, AES keys, and typical binary fields exceed this | -- | Buffer increased from 512 to 2048 bytes (1024 input bytes); truncation marker "..." appended for inputs beyond 1024 bytes | @maintainers | S | **Closed** (pass 4: max_input=1024, hex_buf[2048], "..." truncation marker) |
| 36 | Medium | 24 | api-contract | msg_id field present in Record but absent from all JSON/text outputs | record.zig:23, json_handler.zig:45-121, text_handler.zig:44-92, tcp/udp/http sinks, rotating_file.zig | Record.msg_id is populated by Logger.log (logger.zig:192) but no handler writes it: json_handler writes `"msg":rec.message` (line 78) not msg_id; text_handler writes `rec.message` (line 73); network sinks write `rec.message`. Only syslog_rfc5424 uses msg_id (line 158-159). i18n message lookup ID is lost in all other outputs. | -- | msg_id written to all outputs when different from message | @maintainers | S | **Closed** (pass 5: msg_id written to all JSON/text outputs when non-empty and differs from message) |
| 16 | Low | 32 | maintainability | VTable boilerplate duplicated across 9+ handlers | All handler files | Every handler defines identical withAttrs/withGroup/setLevel/flush stubs with the same no-op pattern | -- | Depends on withAttrs implementation; separate effort | @maintainers | M | **Won't Do** |
| 40 | Low | 24 | docs | isSensitiveKey auto-redaction behavior not documented in public API | redact.zig:45-69, all handlers | `isSensitiveKey()` checks 15 patterns (password, token, api_key, etc.) and auto-redacts matching attr keys in all handlers (json_handler.zig:143, text_handler.zig:108, rotating_file.zig:309, tcp_sink.zig:214, udp_sink.zig:133, http_sink.zig:240). No public documentation lists the patterns or explains the behavior. Users may be surprised by auto-redaction. | -- | Docstring added to redact.zig listing all sensitive patterns; auto-redaction section added to slogz.zig module docs | @maintainers | S | **Closed** (pass 5: isSensitiveKey auto-redaction documented in redact.zig and slogz.zig) |
| 26 | Low | 18 | perf | UDP sink serializes under mutex unlike TCP/HTTP | udp_sink.zig | Lines 132-133: `ctx.mutex.lock()` before JSON formatting; tcp_sink.zig:207 and http_sink.zig:239 format outside mutex then lock only for send | -- | JSON formatting moved outside mutex; lock only for ctx.send() | @maintainers | S | **Closed** |
| 37 | Medium | 16 | docs | HTTP sink docstring claims "Connection pooling" but implementation creates per-request connections | http_sink.zig | Line 10: `//! - Connection pooling (simplified)` in docstring; Line 127-133: `sendHttp()` creates fresh TCP connection per call via `tcpConnectToAddress`/`tcpConnectToHost`, sends with `Connection: close` header (line 146), and `defer stream.close()`. No connection reuse. | -- | False "Connection pooling" claim removed from docstring | @maintainers | S | **Closed** (pass 5: HTTP sink false pooling claim removed) |
| 17 | Low | 16 | cleanup | rotating_file.zig imports text_handler but never uses it | rotating_file.zig | Line 22: `const text_handler = @import("text_handler.zig");` -- symbol `text_handler` is never referenced | -- | Unused text_handler import removed | @maintainers | S | **Closed** (05c6a16) |
| 18 | Low | 16 | cleanup | epochDays / ymdToEpochDay duplicated in clock.zig and rfc3339.zig | clock.zig:111-129, rfc3339.zig:139-155 | Identical algorithm (Howard Hinnant epoch-day conversion) copy-pasted | -- | clock.zig now imports from rfc3339.zig; duplication removed | @maintainers | S | **Closed** (ec068d0) |
| 27 | Low | 12 | cleanup | deprecatedWriter() API usage at 3 call sites | slogz.zig, windows_eventlog.zig | `grep -rn deprecatedWriter src/` returns zero hits; slogz.zig:162-169 uses `std.Io.File.stderr().writer(...)` + `&stderr_file_writer.interface` | [#1](https://gitlab.com/devnw/zig/slog/-/issues/1) (Closed) | Replaced with current Zig 0.16 writer API; AnyWriter handler-interface refactor complete | @maintainers | S | **Closed** (pass 6: deprecatedWriter fully removed from src/; #1 closed) |
| 38 | Low | 8 | cleanup | Dead testWrite helper in text_value.zig | src/fmt/text_value.zig | Lines 62-68: `fn testWrite(value: Value) ![]const u8` defined but never called; all 11 inline tests below use their own `var buf`/`fbs` pattern instead. | -- | Dead testWrite function removed | @maintainers | S | **Closed** (pass 5: dead testWrite helper removed from text_value.zig) |
| 39 | Low | 8 | cleanup | "[REDACTED]" string literal duplicated across 3 locations | redact.zig:12, value.zig:25, queue.zig:122 | `redact.zig:12` defines `pub const REDACTED = "[REDACTED]"`; `value.zig:25` has `return "[REDACTED]"` in `Secret.redacted()`; `queue.zig:122` has `const redacted = "[REDACTED]"`. These should all reference `redact.REDACTED`. | -- | value.zig and queue.zig now import redact.REDACTED | @maintainers | S | **Closed** (pass 5: [REDACTED] literal consolidated to redact.REDACTED in value.zig and queue.zig) |
| 28 | Low | 8 | architecture | error.UnsupportedPlatform not in HandlerError | journald.zig, windows_eventlog.zig | journald.zig:67, windows_eventlog.zig:96: `return error.UnsupportedPlatform` in functions returning `HandlerError!void`; `UnsupportedPlatform` not in `HandlerError` error set | [#26](https://gitlab.com/devnw/zig/slog/-/issues/26) (Closed) | Use `error.FeatureDisabled` or add to `HandlerError` | @maintainers | S | **Closed** (#26) |
| 19 | Low | 8 | cleanup | BaseHandlerContext defined but never used | handler.zig | Lines 91-120: `pub const BaseHandlerContext` is defined with init/enabled/prefixedKey but no handler imports or uses it | -- | Removed BaseHandlerContext dead code from handler.zig | @maintainers | S | **Closed** (ec068d0) |
| 20 | Low | 8 | cleanup | Metrics.incReconnections() never called | metrics.zig | Line 74: `pub fn incReconnections` defined but grep finds zero callers across the entire codebase | -- | Wired into tcp_sink.zig reconnection logic | @maintainers | S | **Closed** (ec068d0) |
| 21 | Critical | 100 | maintainability | writeJsonValue() duplicated verbatim across 4 files | json_handler.zig, tcp_sink.zig, udp_sink.zig, http_sink.zig | json_handler.zig:152, tcp_sink.zig:164, udp_sink.zig:89, http_sink.zig:187: identical `fn writeJsonValue(enc: anytype, value: Value) !void` with same switch arms | [#33](https://gitlab.com/devnw/zig/slog/-/issues/33) | Extracted to `src/fmt/json_value.zig`; all 4 files import shared function | @maintainers | M | **Closed** |
| 22 | High | 60 | maintainability | writeValue() behavioral drift across 4 text-mode copies | text_handler.zig, journald.zig, windows_eventlog.zig, rotating_file.zig | text_handler.zig:131 uses `{d:.6}` for floats; journald.zig:176 and windows_eventlog.zig:150 use `{d}`; rotating_file.zig:316 uses raw `writeAll` instead of `sanitizeOutput`; marshaler text is `<marshaler>` vs `?` | [#34](https://gitlab.com/devnw/zig/slog/-/issues/34) | Extracted to `src/fmt/text_value.zig` with canonical behavior (f64:.6, 0x hex, `<marshaler>`); all 4 handlers import shared function | @maintainers | M | **Closed** |
| 23 | High | 60 | architecture | rotating_file.zig missing sanitizeOutput() on .str values | rotating_file.zig | Line 316: `.str => \|s\| try writer.writeAll(s)` -- no `sanitizeOutput()` call; all other text handlers sanitize strings | [#35](https://gitlab.com/devnw/zig/slog/-/issues/35) | Replace `writer.writeAll(s)` with `sanitize.sanitizeOutput(writer, s)` | @maintainers | S | **Closed** (sanitizeOutput applied to .str in writeValue) |
| 45 | Medium | 48 | architecture | BoundedQueue `not_full`/`empty` condvars signaled but never waited on (NEW-5) | src/internal/queue.zig | Defined at queue.zig:272 (`not_full`) and :274 (`empty`); signaled/broadcast at :357,:372,:401 (`not_full.signal`) and :358,:373,:402 (`empty.broadcast`); `grep ".wait(" src/internal/queue.zig` returns zero matches -- no consumer ever waits on either, so both fields are dead and every enqueue pays a needless signal/broadcast syscall | _PERF-040/PERF-042_ | Remove dead `not_full`/`empty` condvars + their signal/broadcast calls, OR wire real waiters if backpressure is intended | @maintainers | S | **Open** (cross-ref PERF-040/042; no duplicate Q issue) |
| 44 | Medium | 36 | ci-cd | pre-commit zig-fmt hook targets `benchmarks/` (no .zig) instead of `bench/` (NEW-4) | .pre-commit-config.yaml | Line 122: `args: [src/, build.zig, tests/, benchmarks/, examples/]` -- `benchmarks/` holds only a `results/` dir (0 .zig files); the real bench sources live in `bench/` (`bench_main.zig`, `compare.zig`, `scale_bench.zig`); future edits to `bench/*.zig` are never format-checked | -- | Change `benchmarks/` to `bench/` in the zig-fmt hook args | @maintainers | S | **Open** |
| 46 | Medium | 36 | deps | 9 stale zig-pkg/ vendor snapshots (~36 MB) (NEW-7) | zig-pkg/ | 3x `json-0.1.0-*`, 4x `thread_pool-0.2.0-*`, 2x `uri-0.1.0-*` accumulated across dep-convergence commits; only `json-0.1.4`/`thread_pool-0.2.4`/`uri-0.1.4` are live | [#44](https://gitlab.com/devnw/zig/slog/-/issues/44) | Remove the 9 superseded snapshots after confirming build.zig.zon references only live hashes | @maintainers | S | **Open** |
| 48 | Medium | 36 | api-contract | All 8 examples/*.zig broken; not wired into build (NEW-9) | examples/*.zig, build.zig | All 8 examples `@import("slog")` but the module is exported as `"slogz"` (build.zig:90); 6/8 also use removed `std.io.getStdErr`/`getStdOut`; examples are not referenced in build.zig at all, so the breakage never surfaces in CI | _gap-sync may file_ | Rename import to `"slogz"`, update to Zig 0.16 writer APIs, and wire examples into build.zig so they compile in CI | @maintainers | M | **Open** (gap-sync owns issue creation; no existing examples issue found) |
| 47 | Low | 24 | docs | slogz.zig:22 module doc-comment example uses `.writer().any()` (NEW-8) | src/slogz.zig | Line 22: doc-comment example `std.Io.File.stderr().writer().any()` does not compile under Zig 0.16; correct form is `&writer.interface` | -- | Update doc-comment example to the compiling form | @maintainers | S | **Open** |
| 41 | Low | 16 | cleanup | Trailing whitespace + EOF normalization (NEW-1) | .gitlab/issue_templates/Bug Report.md, .gitlab/issue_templates/Question.md, SECURITY.md | 6 trailing-whitespace lines in Bug Report, 2 in Question; SECURITY.md ends with a double trailing newline (end-of-file-fixer normalizes). All pre-commit auto-fixable | [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) | `pre-commit run trailing-whitespace end-of-file-fixer --all-files` | @maintainers | S | **Open** |
| 43 | Low | 12 | cleanup | markdownlint MD040 unlabeled code fences (NEW-3) | docs/ARCHITECTURE.md, docs/API.md, .gitlab/issue_templates/Bug Report.md | 20 bare fences in ARCHITECTURE.md, 25 in API.md, 3 in Bug Report template -- no language label, breaks highlighting and trips MD040 | [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) | Add language labels (zig/text/json) to bare fences | @maintainers | S | **Open** |
| 42 | Low | 8 | cleanup | scripts/detect_diamond_deps.py fails ruff-format (NEW-2) | scripts/detect_diamond_deps.py | `ruff format --check scripts/detect_diamond_deps.py` reports formatting drift; blocks the Python pre-commit hook | [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) | `ruff format scripts/detect_diamond_deps.py` | @maintainers | S | **Open** |

**Notes:**

- Finding 15 (syslog @errorName guard) is a sub-instance of finding 11; they share a root cause and should be fixed together.
- Findings 21-22 are deeper analyses of the same code areas as findings 9-10 (which addressed consistency but not deduplication).
- Finding 23 is a sub-instance of finding 22 (text-mode drift), tracked separately for severity/security traceability.
- Finding 25 is a regression of finding 20; the previous fix (ec068d0) did not persist.
- Finding 27 overlaps with existing issue #1; no new issue created.
- Finding 28 overlaps with existing issue #26 (Closed); no new issue created.
- Finding 29 (NEW-01) addresses missing unit test coverage for the shared json_value.zig and text_value.zig modules extracted in pass 3.
- Finding 30 (NEW-03) addresses the json_value.zig bytes encoding buffer being too small for common binary fields (SHA-512, AES keys).
- Finding 31 refines Finding 4: the handler-level withAttrs no-op was marked Won't Do, but the Logger-level integration bug (context_attrs never propagated to Record) is an independent fix. Logger.log could include context_attrs in the Record without changing handler implementations.
- Finding 33 deepens Finding 10: attrs serialization was added but the record-level envelope (time/level/msg/logger) remains duplicated.
- Finding 34 deepens Finding 9: writeTextValue was extracted but the record-level formatting (timestamp/level/logger/message/attrs loop) remains duplicated.
- Finding 35 is a schema-level consequence of Finding 33's duplication -- the duplicated code diverged in structure.
- Finding 37 is a documentation-only fix (one-line docstring correction).
- **Pass 6 (2026-06-12):** 8 new findings added. Q-41 (NEW-1), Q-42 (NEW-2), Q-43 (NEW-3) are auto-fixable lint, all tracked under combined GitLab issue [#45](https://gitlab.com/devnw/zig/slog/-/issues/45). Q-46 (NEW-7) tracked under [#44](https://gitlab.com/devnw/zig/slog/-/issues/44).
- **Q-45 (NEW-5)** shares a root cause with perf findings PERF-040/PERF-042 (dead BoundedQueue condvars). Per cross-team agreement, the Q finding is recorded here but **no duplicate GitLab issue** is created -- the PERF issues are authoritative.
- **Q-48 (NEW-9)** examples breakage: GitLab issue creation is owned by the gap-sync agent. A search (`glab issue list --search examples`) found only #31 (an API.md docstring issue), not an examples-broken issue, so no duplicate was created from this pass.
- **Q-44 (NEW-4)** has no GitLab issue (single-line config fix); tracked in this document only.
- **Q-27** moved from Partially Closed to fully Closed; GitLab issue #1 closed with evidence.

---

## Findings by Category

### api-contract

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 1 | AsyncHandler drops ALL record attributes | 100 | Closed |
| 4 | withAttrs/withGroup universally no-op | 80 | Won't Do |
| 6 | Network sinks drop all attributes from JSON output | 64 | Closed |
| 31 | Logger.with() attrs silently lost (context_attrs never reach Record) | 64 | **Closed** (pass 5) |
| 13 | LoggerOptions re-exported but does not exist | 36 | Closed |
| 35 | JSON schema inconsistency between json_handler and network sinks | 36 | **Closed** (pass 5) |
| 36 | msg_id field present in Record but absent from all JSON/text outputs | 24 | **Closed** (pass 5) |
| 48 | All 8 examples/*.zig broken (wrong module name + removed APIs) | 36 | **Open** (NEW-9) |

### architecture

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 2 | stderrHandler / stderrJsonHandler dangling pointers | 80 | Closed |
| 45 | BoundedQueue not_full/empty condvars dead (signaled, never waited) | 48 | **Open** (NEW-5; xref PERF-040/042) |
| 3 | AsyncHandler.Context.init dangling pointer to thread | 80 | Closed |
| 8 | formatBackupPath buffer aliasing | 48 | Closed |
| 11 | @errorName guard missing in 4 of 5 handlers | 36 | Closed |
| 12 | Silent error swallowing in rotating_file | 36 | Closed |
| 23 | rotating_file missing sanitizeOutput() on .str | 60 | Closed |
| 24 | rotating_file missing close vtable entry | 36 | Closed |
| 28 | error.UnsupportedPlatform not in HandlerError | 8 | Closed |
| 30 | json_value.zig bytes truncation at 256 bytes | 30 | Closed |

### ci-cd

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 5 | CI pipeline has no build or test stage | 80 | Closed |
| 44 | pre-commit zig-fmt hook targets benchmarks/ not bench/ | 36 | **Open** (NEW-4) |

### deps

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 46 | 9 stale zig-pkg/ vendor snapshots (~36 MB) | 36 | **Open** (NEW-7, #44) |

### perf

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 7 | QueuedRecord i64 serialization broken | 64 | Closed |
| 26 | UDP sink serializes under mutex | 18 | Closed |

### maintainability

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 21 | writeJsonValue() duplicated 4x | 100 | Closed |
| 22 | writeValue() behavioral drift 4x | 60 | Closed |
| 9 | writeValue duplicated 3x | 48 | Closed |
| 10 | JSON encoding duplicated 3x in sinks | 48 | Closed |
| 33 | JSON record serialization duplicated 4x | 48 | **Closed** (pass 5) |
| 34 | Text record formatting duplicated 2x | 36 | **Closed** (pass 5) |
| 16 | VTable boilerplate duplicated 9x | 32 | Won't Do |
| 15 | Syslog writeSDValue missing @errorName guard | 36 | Closed |

### tests

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 14 | FixedClock mechanism non-functional | 36 | Closed |
| 29 | No unit tests for json_value.zig and text_value.zig | 36 | Closed |

### docs

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 32 | Module docstring example shows incorrect API signatures | 32 | **Closed** (pass 5) |
| 37 | HTTP sink docstring claims "Connection pooling" falsely | 16 | **Closed** (pass 5) |
| 40 | isSensitiveKey auto-redaction behavior undocumented | 24 | **Closed** (pass 5) |
| 47 | slogz.zig:22 doc-comment example uses non-compiling .writer().any() | 24 | **Open** (NEW-8) |

### cleanup

| Rank | Finding | PriorityScore | Status |
|------|---------|---------------|--------|
| 25 | incReconnections() zero callers (regression) | 30 | Closed |
| 27 | deprecatedWriter() usage (3 call sites) | 12 | **Partially Closed** |
| 17 | rotating_file dead import | 16 | Closed |
| 18 | epochDays / ymdToEpochDay duplicated | 16 | Closed |
| 19 | BaseHandlerContext dead code | 8 | Closed |
| 20 | Metrics.incReconnections() dead code | 8 | Closed |
| 38 | Dead testWrite helper in text_value.zig | 8 | **Closed** (pass 5) |
| 39 | "[REDACTED]" literal duplicated 3x | 8 | **Closed** (pass 5) |
| 41 | Trailing whitespace + EOF normalization | 16 | **Open** (NEW-1, #45) |
| 43 | markdownlint MD040 unlabeled code fences | 12 | **Open** (NEW-3, #45) |
| 42 | scripts/detect_diamond_deps.py fails ruff-format | 8 | **Open** (NEW-2, #45) |

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
| 32 | Module docstring incorrect API signatures | S | Update slogz.zig lines 28-34 to match actual Logger.init(handler, level, clock) and logger.info(msg_id, attrs) | **Closed** (pass 5) |
| 37 | HTTP sink false "Connection pooling" docstring | S | Remove or correct the claim at http_sink.zig:10 | **Closed** (pass 5) |
| 38 | Dead testWrite helper | S | Remove text_value.zig:62-68 | **Closed** (pass 5) |
| 39 | "[REDACTED]" literal duplicated 3x | S | Import from redact.zig in value.zig and queue.zig | **Closed** (pass 5) |
| 36 | msg_id absent from JSON/text output | S | Add "msg_id" key to JSON and text output when non-empty and different from message | **Closed** (pass 5) |
| 40 | isSensitiveKey auto-redaction undocumented | S | Add docstrings listing the 15 sensitive key patterns | **Closed** (pass 5) |
| 44 | pre-commit zig-fmt hook wrong dir | S | Change `benchmarks/` to `bench/` in .pre-commit-config.yaml:122 | **Open** (NEW-4) |
| 45 | BoundedQueue dead condvars | S | Remove `not_full`/`empty` + their signals (or wire waiters); xref PERF-040/042 | **Open** (NEW-5) |
| 46 | 9 stale zig-pkg vendor snapshots | S | Delete 9 superseded `0.1.0`/`0.2.0` snapshots after build.zig.zon check | **Open** (NEW-7, #44) |
| 47 | slogz.zig doc-comment non-compiling example | S | Replace `.writer().any()` with `&writer.interface` at slogz.zig:22 | **Open** (NEW-8) |
| 41 | Trailing whitespace + EOF | S | `pre-commit run trailing-whitespace end-of-file-fixer --all-files` | **Open** (NEW-1, #45) |
| 42 | ruff-format drift | S | `ruff format scripts/detect_diamond_deps.py` | **Open** (NEW-2, #45) |
| 43 | MD040 unlabeled fences | S | Add language labels to bare fences in ARCHITECTURE.md/API.md/Bug Report | **Open** (NEW-3, #45) |

### Medium (1-5 days)

| Rank | Finding | Effort | Notes | Status |
|------|---------|--------|-------|--------|
| 21 | writeJsonValue() duplicated 4x | M | Extracted to `src/fmt/json_value.zig`; 4 files updated | **Closed** |
| 22 | writeValue() behavioral drift 4x | M | Extracted to `src/fmt/text_value.zig`; canonical behavior applied | **Closed** |
| 31 | Logger.with() attrs lost | M | Logger.log now merges context_attrs into Record.attrs | **Closed** (pass 5) |
| 33 | JSON record serialization duplicated 4x | M | Extracted to `src/fmt/json_record.zig`; schema reconciled | **Closed** (pass 5) |
| 34 | Text record formatting duplicated 2x | M | Extracted to `src/fmt/text_record.zig` | **Closed** (pass 5) |
| 35 | JSON schema inconsistency | M | Reconciled to flat attrs + flat source via shared json_record.zig | **Closed** (pass 5) |
| 48 | All 8 examples/*.zig broken + not wired into build | M | Rename `@import("slog")` to `"slogz"`, migrate to Zig 0.16 writer APIs, add example build steps to build.zig so CI compiles them | **Open** (NEW-9; gap-sync owns issue) |

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
- **Finding 31 (Logger.with attrs lost):** Confirmed at logger.zig:119-131 -- `Logger.with(attrs)` sets `context_attrs = attrs` and calls `handler.withAttrs(attrs)` which discards them; logger.zig:189-198 constructs Record with `attrs: attrs` (the call-site attrs), NOT `self.context_attrs`. json_handler.zig:103 reads `ctx.context_attrs` (always `&.{}`); text_handler.zig:76 reads `ctx.context_attrs` (always `&.{}`). The attrs passed to `Logger.with()` are stored in the Logger struct but never reach the Record or the handler context.
- **Finding 32 (docstring wrong):** Confirmed at slogz.zig:28-34 -- `Logger.init(std.heap.page_allocator, "myapp", handler)` vs actual `Logger.init(handler: Handler, level: Level, clock: Clock)` at logger.zig:70; `logger.info("app.started", "Application started", &.{...})` shows 3 args vs actual 2-arg signature at logger.zig:260; `defer logger.deinit()` references nonexistent method.
- **Finding 33 (JSON record duplication):** Confirmed by comparing json_handler.zig:45-121, tcp_sink.zig:170-237, udp_sink.zig:89-152, http_sink.zig:196-259 -- all four serialize time/level/msg/logger/attrs with identical patterns (same variable names, same order, same error handling).
- **Finding 34 (text record duplication):** Confirmed by comparing text_handler.zig:44-92 and rotating_file.zig:265-318 -- identical pattern: timestamp via rfc3339.formatTimestamp, level via asText(), logger name, sanitized message, attrs loop with key=value.
- **Finding 35 (JSON schema inconsistency):** Confirmed: json_handler.zig:98-113 wraps attrs in `enc.writeKey("attrs"); enc.beginObject()...enc.endObject()` with context_attrs and prefix support; tcp_sink.zig:210-219, udp_sink.zig:128-138, http_sink.zig:235-245 write attrs at top level with no nesting, no prefix, no context_attrs. json_handler.zig:87-95 includes `"source"` object; network sinks do not.
- **Finding 36 (msg_id absent):** Confirmed -- searched all handler `handle()` functions: none writes `rec.msg_id` to output. json_handler.zig:78 writes `rec.message`; text_handler.zig:73 writes `rec.message`; tcp_sink.zig:201 writes `rec.message`. Only syslog_rfc5424.zig:158-159 uses `rec.msg_id`.
- **Finding 37 (false connection pooling):** Confirmed at http_sink.zig:10 docstring says "Connection pooling (simplified)"; sendHttp() at line 127-133 creates fresh TCP connection per call, sends `Connection: close` header at line 146, and `defer stream.close()` closes immediately after response.
- **Finding 38 (dead testWrite):** Confirmed at text_value.zig:62-68 -- `fn testWrite` defined; all 11 tests below (lines 71-162) use inline `var buf`/`var fbs` instead.
- **Finding 39 (REDACTED duplication):** Confirmed -- `redact.zig:12` defines `pub const REDACTED = "[REDACTED]"`; `value.zig:25` has independent `return "[REDACTED]"`; `queue.zig:122` has independent `const redacted = "[REDACTED]"`.
- **Finding 40 (auto-redaction undocumented):** Confirmed -- `redact.zig:45` `isSensitiveKey` is called by json_handler.zig:143, text_handler.zig:108, rotating_file.zig:309, tcp_sink.zig:214, udp_sink.zig:133, http_sink.zig:240. The list of 15 sensitive patterns at redact.zig:15-31 is not referenced in any public documentation or module docstring.
- **Finding 41 (NEW-1 trailing ws/EOF):** Confirmed -- `grep -nP ' +$' '.gitlab/issue_templates/Bug Report.md'` = 6 lines, `Question.md` = 2 lines; `tail -c 20 SECURITY.md | od -c` shows trailing `\n \n` (double newline at EOF).
- **Finding 42 (NEW-2 ruff-format):** Confirmed -- `scripts/detect_diamond_deps.py` exists and fails `ruff format --check`.
- **Finding 43 (NEW-3 MD040):** Confirmed -- `grep -cP '^```\s*$'` returns 20 (docs/ARCHITECTURE.md), 25 (docs/API.md), 3 (Bug Report template) bare fences.
- **Finding 44 (NEW-4 hook dir):** Confirmed at .pre-commit-config.yaml:122 -- `args: [src/, build.zig, tests/, benchmarks/, examples/]`; `find benchmarks -name '*.zig'` = 0 files (only a `results/` dir), `find bench -name '*.zig'` = 3 files (bench_main.zig, compare.zig, scale_bench.zig).
- **Finding 45 (NEW-5 dead condvars):** Confirmed in src/internal/queue.zig -- `not_full` defined at :272, `empty` at :274; `not_full.signal` at :357/:372/:401, `empty.broadcast` at :358/:373/:402; `grep '.wait(' src/internal/queue.zig` returns zero matches. Only `not_empty` is ever waited on (:351 `not_empty.waitUncancelable`). Cross-referenced to PERF-040/PERF-042.
- **Finding 46 (NEW-7 stale snapshots):** Confirmed -- `ls -d zig-pkg/*` shows 12 dirs: 3x json-0.1.0, 1x json-0.1.4, 4x thread_pool-0.2.0, 1x thread_pool-0.2.4, 2x uri-0.1.0, 1x uri-0.1.4. `du -sh` totals 46 MB; the 9 stale `0.1.0`/`0.2.0` dirs sum to ~36.1 MB (4x 8.4 MB thread_pool dominate).
- **Finding 47 (NEW-8 doc-comment):** Confirmed at slogz.zig:22 -- doc-comment line `//!     std.Io.File.stderr().writer().any(),`; the compiled stderr handler (slogz.zig:162-169) uses `&stderr_file_writer.interface`, confirming `.writer().any()` is not the valid 0.16 form.
- **Finding 48 (NEW-9 broken examples):** Confirmed -- all 8 `examples/*.zig` use `const slog = @import("slog")`; build.zig:90 exports the module as `"slogz"`. `grep -ln "getStdErr\|getStdOut" examples/*.zig` = 6 files. `grep -n examples build.zig` returns nothing (examples not wired into the build graph).

---

## Methodology

- **Scanner output:** Phase 3 deep review findings provided as input, plus new audit findings from 2026-03-24 deep review.
- **Verification:** Each finding verified by reading source files at the cited paths and lines.
- **Scoring:** PriorityScore = Impact(1-5) x Likelihood(1-5) x 4. Impact considers severity of failure mode. Likelihood considers how often the code path is exercised.
- **Deduplication:** Findings 11 and 15 share a root cause (@errorName guard inconsistency). Findings 21/22 deepen 9/10 (consistency was applied but duplication remains). Finding 23 is a specific instance within finding 22. Finding 25 is a regression of finding 20. Finding 31 refines Finding 4 with an independent Logger-side fix path. Finding 33 deepens Finding 10 (record-level vs value-level). Finding 34 deepens Finding 9 (record-level vs value-level).
- **Issue tracking:** GitLab issues created via `glab issue create`. Pass 6 created [#44](https://gitlab.com/devnw/zig/slog/-/issues/44) (Q-46 stale vendor snapshots) and [#45](https://gitlab.com/devnw/zig/slog/-/issues/45) (combined Q-41/42/43 auto-fixable lint), and closed [#1](https://gitlab.com/devnw/zig/slog/-/issues/1) (Q-27 deprecatedWriter). Q-45 (NEW-5) intentionally has no issue (cross-referenced to PERF-040/PERF-042). Q-48 (NEW-9) issue creation is owned by the gap-sync agent. Q-44 and Q-47 are tracked in this document only.
