# Gap Closure Pass 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all 15 actionable open gaps from audit pass 6 (SEC-0034/0037/0038/0039, PERF-039/040/041/042/043, Q-41..Q-48) with TDD, one commit per gap.

**Architecture:** Fix the broken benchmark regression gate first so perf fixes are measurable. Then restore multi_handler to sequential dispatch, rebuild the async queue around real condvar waits with shutdown signaling, and land the rotating-file security hardening (permissions, path constraints) plus redaction/truncation fixes. Mechanical quality fixes last.

**Tech Stack:** Zig 0.16.0 (`std.Io` model: `std.Io.Mutex`, `std.Io.Condition` — NO timed condvar wait exists; `std.Io.Dir.CreateFileOptions` has `permissions: Permissions = .default_file` and `resolve_beneath: bool = false`; `std.Io.File.Permissions.fromMode(0o600)`; `Stat.permissions.toMode()`; `Reader.allocRemaining(allocator, .limited(n))`).

**Canonical commands** (run from repo root `/data/home/benji/src/gl/gitlab.com/devnw/zig/slog`):

```bash
zig fmt --check src/ build.zig tests/ bench/ examples/   # format gate
zig build check                                          # compile gate
zig build test --summary all                             # 261/262 pass, 1 skip expected at baseline
zig build scale-bench                                    # JSON to stdout
```

**Commit policy:** Every commit goes through pre-commit hooks (zig fmt, markdownlint, etc.). Run `zig fmt src/ tests/ bench/ examples/ build.zig` before each commit. Conventional-commit messages enforced (commitizen). All work directly on `main` (repo convention).

---

## Task 1: PERF-043 — Fix `compare-bench` (broken regression gate)

**Files:**

- Modify: `bench/compare.zig:49-56` (readFile) and end of file (add tests)
- Modify: `build.zig` (~line 394, add compare tests to test step)

**Background:** `readAlloc(allocator, len)` in Zig 0.16 reads EXACTLY `len` bytes (`readSliceAll`) and returns `error.EndOfStream` for any file smaller than `len`. The fix is `allocRemaining` with a `Limit`.

- [ ] **Step 1: Reproduce the failure**

```bash
zig build scale-bench 2>/dev/null > /tmp/current.json
zig build compare-bench -- benchmarks/results/baseline.json /tmp/current.json; echo "exit=$?"
```

Expected: error mentioning `EndOfStream` (or silent failure), non-functional comparison.

- [ ] **Step 2: Fix readFile**

In `bench/compare.zig`, replace the `readFile` body:

```zig
fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const io = getIo();
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var read_buf: [8192]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    return try reader.interface.allocRemaining(allocator, .limited(10 * 1024 * 1024));
}
```

- [ ] **Step 3: Add a self-test that flags a known regression**

At the end of `bench/compare.zig`, add tests against the existing parsing/compare helpers (read the file first; reuse the real fixture shape from `benchmarks/results/baseline.json` — a `"tiers"` array of objects with `name` and the metric keys from the `metrics` table). The test must:

1. Feed `extractTiers` a fixture JSON string with one tier where `text_ns_op` = 100.
2. Feed a "current" fixture where `text_ns_op` = 200 (a 100% regression, threshold 20%).
3. Assert the comparison logic reports a regression for that metric, and reports none when both fixtures are identical.

If the comparison logic is inlined in `main`, extract it into a testable `fn compareTiers(baseline: []const TierValues, current: []const TierValues, threshold_pct: i64) usize` (returns regression count) and have `main` call it. Example test skeleton (adapt names to the actual extracted function):

```zig
const fixture_base =
    \\{"tiers":[{"name":"100K","text_ns_op":100,"json_ns_op":100}]}
;
const fixture_regressed =
    \\{"tiers":[{"name":"100K","text_ns_op":200,"json_ns_op":100}]}
;

test "compare detects regression beyond threshold" {
    const base = extractTiers(fixture_base);
    const curr = extractTiers(fixture_regressed);
    try std.testing.expect(compareTiers(base.slice(), curr.slice(), 20) > 0);
}

test "compare passes identical results" {
    const base = extractTiers(fixture_base);
    const curr = extractTiers(fixture_base);
    try std.testing.expectEqual(@as(usize, 0), compareTiers(base.slice(), curr.slice(), 20));
}
```

- [ ] **Step 4: Wire compare.zig tests into `zig build test`**

In `build.zig`, after the compare-bench executable block (~line 394), add:

```zig
// Compare-bench self-tests (PERF-043: gate must not silently re-break)
const compare_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("bench/compare.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
const run_compare_tests = b.addRunArtifact(compare_tests);
test_step.dependOn(&run_compare_tests.step);
```

- [ ] **Step 5: Verify**

```bash
zig build test --summary all          # all pass incl. new compare tests
zig build scale-bench 2>/dev/null > /tmp/current.json
zig build compare-bench -- benchmarks/results/baseline.json /tmp/current.json; echo "exit=$?"
```

Expected: compare-bench now parses both files and prints per-metric deltas. Exit 1 is EXPECTED right now (real regressions PERF-039..042 are still unfixed) — the gate working is the success criterion.

- [ ] **Step 6: Commit**

```bash
zig fmt bench/ build.zig
git add bench/compare.zig build.zig
git commit -m "fix(bench): restore compare-bench under Zig 0.16 (PERF-043)

readAlloc(len) reads exactly len bytes in Zig 0.16 and EndOfStreams on
smaller files; use allocRemaining with a 10MB limit. Add comparator
self-tests so the regression gate cannot silently break again.

Closes PERF-043. GitLab #53."
```

---

## Task 2: PERF-039 — multi_handler sequential dispatch (restore ~200x regression)

**Files:**

- Modify: `src/handlers/multi_handler.zig:35-61` (handle fn)
- Test: existing tests in `tests/handler_test.zig` + `src/handlers/multi_handler.zig` must stay green

**Background:** Baseline multi_handler was 67 ns/op; current is ~12,800 ns/op because `parallel.dispatchHandlers` submits to the thread pool for ANY ≥2 handlers (~12µs wake/WaitGroup overhead). PERF-035 deliberately deferred parallel multi-handler dispatch for ordering reasons; the spice→thread-pool migration silently activated it. Fix: multi_handler dispatches sequentially; `parallel.dispatchHandlers` remains a public opt-in API for consumers (unchanged).

- [ ] **Step 1: Capture the pre-fix number**

```bash
zig build scale-bench 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(t['name'], 'multi_handler_ns =', t['multi_handler_ns']) for t in d['tiers']]"
```

Expected: ~12,000-13,000 ns at every tier.

- [ ] **Step 2: Replace handle() with sequential dispatch**

In `src/handlers/multi_handler.zig` replace the whole `handle` function (and delete the now-unused `MAX_PARALLEL_HANDLERS` const):

```zig
fn handle(ctx_ptr: *anyopaque, rec: *const Record) HandlerError!void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));

    const current_level: Level = @enumFromInt(ctx.level.load(.acquire));
    if (!rec.level.atLeast(current_level)) return;

    // Sequential dispatch (PERF-039): preserves the ordering guarantees
    // PERF-035 protected and avoids thread-pool wake overhead (~12us)
    // that dwarfs per-handler cost. Consumers who want parallel fan-out
    // can call parallel.dispatchHandlers directly.
    var first_err: ?HandlerError = null;
    for (ctx.handlers) |h| {
        h.handle(rec) catch |err| {
            if (first_err == null) first_err = err;
        };
    }
    if (first_err) |err| return err;
}
```

If `const parallel = @import("../parallel.zig");` becomes unused after this, remove the import. Check with `zig build check`.

- [ ] **Step 3: Verify tests and benchmark**

```bash
zig build test --summary all   # all multi_handler tests green
zig build scale-bench 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(t['name'], 'multi_handler_ns =', t['multi_handler_ns']) for t in d['tiers']]"
```

Expected: multi_handler_ns ≤ ~100 at every tier (baseline 67, acceptance ≤ 10% above baseline is ideal; anything < 200 ns confirms the 200x regression is gone).

- [ ] **Step 4: Commit**

```bash
zig fmt src/
git add src/handlers/multi_handler.zig
git commit -m "fix(perf): multi_handler dispatches sequentially (PERF-039)

Thread-pool dispatch for >=2 handlers cost ~12us per record vs 67ns
sequential -- a ~200x regression introduced by the spice->thread-pool
migration (97c5c59), contradicting PERF-035's deferral rationale.
parallel.dispatchHandlers remains available as an explicit opt-in.

Closes PERF-039. GitLab #49."
```

---

## Task 3: PERF-040 — Worker waits on condvar instead of 1ms sleep-poll

**Files:**

- Modify: `src/internal/queue.zig` (BoundedQueue: add `shutdown` field, `popWait`, `shutdownWake`)
- Modify: `src/handlers/async_handler.zig:104-125` (workerThread), deinit (~lines 85-99)
- Test: queue tests in `src/internal/queue.zig` (bottom of file), `tests/handler_test.zig`

**Background:** `std.Io.Condition` has `waitUncancelable(io, &mutex)` / `signal` / `broadcast` but NO timed wait. The worker's only reason for a timeout was to re-check `running` — replace with an explicit shutdown wake. This removes both the 1ms tail-latency poll and the up-to-100ms shutdown delay.

- [ ] **Step 1: Write failing tests**

In `src/internal/queue.zig` test section, add:

```zig
test "BoundedQueue popWait returns items and null after shutdownWake" {
    var queue = try BoundedQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit(std.testing.allocator);

    _ = queue.pushDropOldest(42);
    try std.testing.expectEqual(@as(?u32, 42), queue.popWait());

    queue.shutdownWake();
    try std.testing.expectEqual(@as(?u32, null), queue.popWait());
}

test "BoundedQueue popWait drains remaining items after shutdown" {
    var queue = try BoundedQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit(std.testing.allocator);

    _ = queue.pushDropOldest(1);
    _ = queue.pushDropOldest(2);
    queue.shutdownWake();
    // Items pushed before shutdown are still delivered.
    try std.testing.expectEqual(@as(?u32, 1), queue.popWait());
    try std.testing.expectEqual(@as(?u32, 2), queue.popWait());
    try std.testing.expectEqual(@as(?u32, null), queue.popWait());
}
```

NOTE: at this task's point `pushDropOldest` still returns `usize` — the `_ =` discard works for both the old and new (Task 5) signature, so these tests survive Task 5 unchanged.

- [ ] **Step 2: Run tests to verify they fail**

```bash
zig build test --summary all 2>&1 | head -30
```

Expected: compile error — `popWait`/`shutdownWake` not defined.

- [ ] **Step 3: Implement popWait/shutdownWake in BoundedQueue**

Add field after `dropped: usize,` (line ~269):

```zig
        /// Set by shutdownWake; popWait returns null once the queue drains.
        shutdown: bool,
```

and in `init` add `.shutdown = false,` to the struct literal.

Add the two methods after `popTimeout`:

```zig
        /// Pop an item, blocking on the not_empty condition until an item
        /// is available or `shutdownWake` has been called. After shutdown,
        /// remaining items are still returned; null means shut down AND empty.
        pub fn popWait(self: *Self) ?T {
            self.mutex.lockUncancelable(io());
            defer self.mutex.unlock(io());

            while (self.count == 0) {
                if (self.shutdown) return null;
                self.not_empty.waitUncancelable(io(), &self.mutex);
            }

            const item = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;
            return item;
        }

        /// Wake all popWait waiters and make popWait return null once the
        /// queue is drained. Idempotent.
        pub fn shutdownWake(self: *Self) void {
            self.mutex.lockUncancelable(io());
            defer self.mutex.unlock(io());
            self.shutdown = true;
            self.not_empty.broadcast(io());
        }
```

- [ ] **Step 4: Switch the async worker to popWait**

In `src/handlers/async_handler.zig`, replace `workerThread`:

```zig
    fn workerThread(ctx: *Context) void {
        while (true) {
            const qr = ctx.queue.popWait() orelse break;
            processQueuedRecord(ctx, qr);

            // Batch drain: process additional queued records without
            // re-waiting, up to max_batch_size per wake cycle.
            var batch: usize = 1;
            while (batch < max_batch_size) : (batch += 1) {
                if (ctx.queue.tryPop()) |batch_qr| {
                    processQueuedRecord(ctx, batch_qr);
                } else break;
            }
        }

        // Drain any records that raced in around shutdown.
        while (ctx.queue.tryPop()) |qr| {
            processQueuedRecord(ctx, qr);
        }
    }
```

In `deinit` (read lines 80-99 first), insert `self.queue.shutdownWake();` AFTER `running` is set false (if `running` exists there) and BEFORE the `t.join()` loop. If the `running` atomic is now unused anywhere (grep `running` in the file), remove the field and its stores; otherwise leave it.

- [ ] **Step 5: Check remaining popTimeout callers**

```bash
grep -rn "popTimeout" src/ tests/
```

If the async worker was the only non-test caller, KEEP `popTimeout` (it has timed-wait semantics tests may use) — do not delete it in this task; Task 4 documents it.

- [ ] **Step 6: Run full tests**

```bash
zig build test --summary all
```

Expected: all pass including the two new queue tests, async handler tests green (flush/shutdown tests especially).

- [ ] **Step 7: Commit**

```bash
zig fmt src/
git add src/internal/queue.zig src/handlers/async_handler.zig
git commit -m "fix(perf): async worker waits on condvar, not 1ms sleep-poll (PERF-040)

Add BoundedQueue.popWait (condvar wait on not_empty) and shutdownWake
(broadcast + drain-then-null). The worker thread now wakes immediately
on enqueue instead of up to 1ms late, and shuts down without the
100ms popTimeout cycle. Zig 0.16 std.Io.Condition has no timed wait;
shutdown signaling replaces the timeout entirely.

Closes PERF-040. GitLab #50."
```

---

## Task 4: PERF-042 / Q-45 — Remove dead condvars; document timed-wait polling

**Files:**

- Modify: `src/internal/queue.zig` (remove `not_full` and `empty` fields and ALL their signal/broadcast calls; document polling in pushBlocking/popTimeout/waitEmpty doc comments)

**Background:** `not_full` and `empty` are signaled on every pop but no code ever waits on them — pure overhead. The timed paths (`pushBlocking`, `popTimeout`, `waitEmpty`) must keep deadline semantics, and Zig 0.16 has no timed condvar wait, so they legitimately keep the 1ms poll — but that design must be documented, and the dead signals removed. This is the explicitly sanctioned fallback recorded in PERF_GAP_ANALYSIS.md ("remove the dead signals and accept (and document) the 1ms polling design").

- [ ] **Step 1: Remove dead condvar fields**

In `BoundedQueue`:

- Delete fields `not_full: std.Io.Condition,` and `empty: std.Io.Condition,` (lines ~272-274) and their doc comment.
- Delete `.not_full = std.Io.Condition.init,` and `.empty = std.Io.Condition.init,` from `init`.
- Delete every `self.not_full.signal(io());` (in `pop`, `tryPop`, `popTimeout`) and every `if (self.count == 0) self.empty.broadcast(io());` (same three fns).

KEEP `not_empty` everywhere — it is consumed by `pop` and `popWait`.

- [ ] **Step 2: Document the polling design on the timed paths**

Update the doc comments:

```zig
        /// Push item, blocking if full (with timeout).
        ///
        /// Timed wait is implemented as a 1ms poll loop: Zig 0.16
        /// std.Io.Condition has no timed wait primitive, and an untimed
        /// condvar wait could block a producer forever if the consumer
        /// dies. Accepted design -- see PERF-042.
        pub fn pushBlocking(self: *Self, item: T, timeout_ms: u32) QueueError!void {
```

```zig
        /// Pop with timeout.
        ///
        /// Timed wait is a 1ms poll loop (no timed condvar wait in Zig
        /// 0.16 std.Io). Prefer popWait + shutdownWake for consumers
        /// that can use shutdown signaling -- see PERF-040/PERF-042.
        pub fn popTimeout(self: *Self, timeout_ms: u32) ?T {
```

```zig
        /// Wait until the queue is empty or the timeout expires.
        /// Returns true if the queue is empty, false on timeout.
        ///
        /// Timed wait is a 1ms poll loop (no timed condvar wait in Zig
        /// 0.16 std.Io). Accepted design -- see PERF-042.
        pub fn waitEmpty(self: *Self, timeout_ms: u32) bool {
```

- [ ] **Step 3: Verify**

```bash
grep -n "not_full\|\.empty\b" src/internal/queue.zig   # expect no condvar hits (field gone)
zig build test --summary all                            # all green
```

- [ ] **Step 4: Commit**

```bash
zig fmt src/
git add src/internal/queue.zig
git commit -m "fix(perf): remove dead not_full/empty condvars from BoundedQueue (PERF-042)

The two condvars were signaled on every pop but never waited on --
pure overhead with no latency benefit. Timed paths (pushBlocking,
popTimeout, waitEmpty) keep the 1ms poll because Zig 0.16
std.Io.Condition has no timed wait; the design is now documented
at each site.

Closes PERF-042 and Q-45. GitLab #52."
```

---

## Task 5: PERF-041 — Single locked op per drop_oldest enqueue

**Files:**

- Modify: `src/internal/queue.zig` (pushDropOldest returns PushResult)
- Modify: `src/handlers/async_handler.zig:153-170` (enqueue)
- Test: queue tests + any `pushDropOldest` callers in tests

**Background:** enqueue currently does droppedCount() + pushDropOldest() + droppedCount() = 3 mutex round-trips. Make pushDropOldest report the drop itself.

- [ ] **Step 1: Write the failing test**

In `src/internal/queue.zig` tests:

```zig
test "pushDropOldest reports drop and length in one call" {
    var queue = try BoundedQueue(u32).init(std.testing.allocator, 2);
    defer queue.deinit(std.testing.allocator);

    var r = queue.pushDropOldest(1);
    try std.testing.expectEqual(@as(usize, 1), r.len);
    try std.testing.expect(!r.dropped);

    r = queue.pushDropOldest(2);
    try std.testing.expectEqual(@as(usize, 2), r.len);
    try std.testing.expect(!r.dropped);

    r = queue.pushDropOldest(3); // capacity 2: drops oldest
    try std.testing.expectEqual(@as(usize, 2), r.len);
    try std.testing.expect(r.dropped);
}
```

- [ ] **Step 2: Run to verify failure**

```bash
zig build test --summary all 2>&1 | head -20
```

Expected: compile error (`r.len` on usize / no PushResult).

- [ ] **Step 3: Implement**

In `BoundedQueue`, above `pushDropOldest`:

```zig
        pub const PushResult = struct {
            /// Queue length after the push.
            len: usize,
            /// True if this push evicted the oldest item.
            dropped: bool,
        };

        /// Push item, dropping oldest if full.
        /// Returns post-push length and whether an item was evicted, so
        /// callers need no separate len()/droppedCount() mutex trips.
        pub fn pushDropOldest(self: *Self, item: T) PushResult {
            self.mutex.lockUncancelable(io());
            defer self.mutex.unlock(io());

            var dropped = false;
            if (self.count == self.buffer.len) {
                self.head = (self.head + 1) % self.buffer.len;
                self.count -= 1;
                self.dropped += 1;
                dropped = true;
            }

            self.buffer[self.tail] = item;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;
            self.not_empty.signal(io());
            return .{ .len = self.count, .dropped = dropped };
        }
```

(Replaces the old `usize`-returning version and its comment.)

- [ ] **Step 4: Update enqueue**

In `src/handlers/async_handler.zig` `enqueue`, replace the drop_oldest branch:

```zig
        if (self.drop_oldest) {
            // Single locked operation: pushDropOldest reports both the
            // post-push length and whether it evicted an item (PERF-041).
            const result = self.queue.pushDropOldest(qr);
            if (result.dropped) {
                metrics.global.incDropped(1);
            }
            metrics.global.setQueueSize(result.len);
        } else {
```

- [ ] **Step 5: Fix remaining callers**

```bash
grep -rn "pushDropOldest" src/ tests/
```

Update every caller: `_ = queue.pushDropOldest(x);` stays valid; any caller binding the old `usize` return must use `.len`.

- [ ] **Step 6: Verify + measure**

```bash
zig build test --summary all
zig build scale-bench 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(t['name'], 'async_enqueue_ns =', t['async_enqueue_ns']) for t in d['tiers']]"
```

Expected: tests green; async_enqueue_ns drops noticeably (~600ns less than the ~4400ns pre-fix; exact value machine-dependent — record it).

- [ ] **Step 7: Commit**

```bash
zig fmt src/
git add src/internal/queue.zig src/handlers/async_handler.zig
git commit -m "fix(perf): single locked op per drop_oldest enqueue (PERF-041)

pushDropOldest now returns {len, dropped}, eliminating the two extra
droppedCount() mutex round-trips per enqueue (~600ns under
std.Io.Mutex).

Closes PERF-041. GitLab #51."
```

---

## Task 6: SEC-0034 — Rotating log files created 0o600

**Files:**

- Modify: `src/handlers/rotating_file.zig:112-114` (createFile call)
- Test: new test in `src/handlers/rotating_file.zig` test section (follow the existing tests' tmp-file conventions at the bottom of the file — they create files under a temp path and clean up; mirror that)

- [ ] **Step 1: Write the failing test**

Read the existing test section of `rotating_file.zig` (lines ~300+) first and copy its setup/cleanup conventions (temp path naming, `defer` cleanup with `deleteFile`). Then add:

```zig
test "log file is created owner-only (0o600)" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = ".zig-cache/tmp/sec0034-perm-test.log";
    // Fresh file required: createFile does not chmod existing files.
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    var ctx = try Context.init(
        std.testing.allocator,
        .{ .path = path },
        .info,
        Clock.system(),
    );
    defer ctx.deinit();

    const st = try ctx.file.?.stat(io);
    // No group/other bits.
    try std.testing.expectEqual(
        @as(std.posix.mode_t, 0),
        st.permissions.toMode() & 0o077,
    );
}
```

(If existing tests use a different temp-dir helper, use that instead; the assertion is the contract.)

- [ ] **Step 2: Run to verify it fails**

```bash
zig build test --summary all 2>&1 | grep -A3 "owner-only"
```

Expected: FAIL — mode has group/other bits (0o644 under umask 022).

- [ ] **Step 3: Implement**

In `openFile` (line ~112):

```zig
        self.file = std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = false,
            // SEC-0034: owner-only. Log files may contain PII/secrets;
            // default_file (0o666 & ~umask) is world-readable. Note:
            // createFile does not change the mode of an existing file.
            .permissions = .fromMode(0o600),
        }) catch |err| {
```

- [ ] **Step 4: Verify**

```bash
zig build test --summary all      # new test passes, rotation tests green
```

- [ ] **Step 5: Commit**

```bash
zig fmt src/
git add src/handlers/rotating_file.zig
git commit -m "fix(security): create rotating log files with 0o600 (SEC-0034)

The explicit mode was lost in the Zig 0.16 std.fs->std.Io.Dir
migration (fa0de64), leaving log files world-readable under default
umask. Re-add owner-only permissions and a stat-based regression test.

Closes SEC-0034 regression. GitLab #43. APPSEC-01."
```

---

## Task 7: SEC-0037 — Constrain log path: reject absolute by default, resolve_beneath

**Files:**

- Modify: `src/handlers/rotating_file.zig` — `RotationOptions` (~line 30), `validatePath` (~line 89), `openFile` createFile call
- Test: new tests in `src/handlers/rotating_file.zig`

**Design:** Relative paths (the default) are sandboxed beneath the process cwd via `resolve_beneath = true` (Linux 5.6+ `RESOLVE_BENEATH`; silently unsupported elsewhere — documented). Absolute paths are rejected unless the operator opts in with `allow_absolute_path = true` (they bypass the sandbox by definition). A symlink inside the sandbox pointing outside it fails with `AccessDenied` under RESOLVE_BENEATH.

- [ ] **Step 1: Write failing tests**

```zig
test "absolute log path is rejected by default" {
    const result = Context.init(
        std.testing.allocator,
        .{ .path = "/tmp/sec0037-absolute.log" },
        .info,
        Clock.system(),
    );
    try std.testing.expectError(error.WriteFailed, result);
}

test "absolute log path allowed with explicit opt-in" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/tmp/sec0037-optin.log";
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    var ctx = try Context.init(
        std.testing.allocator,
        .{ .path = path, .allow_absolute_path = true },
        .info,
        Clock.system(),
    );
    ctx.deinit();
}

test "symlink escaping the sandbox is rejected" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const io = std.Io.Threaded.global_single_threaded.io();
    const link_path = ".zig-cache/tmp/sec0037-escape-link.log";
    std.Io.Dir.cwd().deleteFile(io, link_path) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, link_path) catch {};
    // Symlink inside the sandbox pointing outside it.
    try std.Io.Dir.cwd().symLink(io, "/etc/hostname", link_path, .{});

    const result = Context.init(
        std.testing.allocator,
        .{ .path = link_path },
        .info,
        Clock.system(),
    );
    try std.testing.expectError(error.WriteFailed, result);
}
```

(Verify the exact `symLink` method name on `std.Io.Dir` in the installed stdlib — `grep -n "pub fn symLink" /data/home/benji/.zvm/0.16.0/lib/std/Io/Dir.zig` — and adjust the call if the signature differs. If RESOLVE_BENEATH is unavailable on the kernel, the third test may need `error.SkipZigTest` based on a runtime check; host kernel is 6.12 so it is available here and in CI.)

- [ ] **Step 2: Run to verify failures**

```bash
zig build test --summary all 2>&1 | grep -B1 -A3 "sec0037\|absolute\|symlink"
```

Expected: `allow_absolute_path` doesn't exist (compile error) — that's the failing state.

- [ ] **Step 3: Implement**

`RotationOptions`:

```zig
pub const RotationOptions = struct {
    path: []const u8,
    max_bytes: usize = 10 * 1024 * 1024, // 10MB default
    max_backups: u8 = 5,
    max_age_days: u16 = 30,
    /// Allow absolute log paths. Off by default (SEC-0037): absolute
    /// paths bypass the resolve-beneath sandbox and are only safe when
    /// the operator fully controls the configured path.
    allow_absolute_path: bool = false,
};
```

`validatePath` (change signature; update the `init` call site `try validatePath(options.path);` → `try validatePath(options);`):

```zig
    /// Validates the configured log path (SEC-0037):
    /// - non-empty
    /// - no ".." traversal segments
    /// - absolute paths require explicit allow_absolute_path opt-in
    fn validatePath(options: RotationOptions) !void {
        const path = options.path;
        if (path.len == 0) {
            return error.WriteFailed;
        }
        if (std.mem.indexOf(u8, path, "..") != null) {
            return error.WriteFailed;
        }
        if (std.fs.path.isAbsolute(path) and !options.allow_absolute_path) {
            return error.WriteFailed;
        }
    }
```

`openFile` createFile call (extends Task 6's version):

```zig
        self.file = std.Io.Dir.cwd().createFile(io, path, .{
            .truncate = false,
            // SEC-0034: owner-only. Log files may contain PII/secrets.
            .permissions = .fromMode(0o600),
            // SEC-0037: keep relative paths (and any symlinks in them)
            // beneath the cwd sandbox. Maps to RESOLVE_BENEATH on
            // Linux 5.6+; silently unsupported elsewhere. Absolute
            // paths are operator-opt-in and exempt by definition.
            .resolve_beneath = !std.fs.path.isAbsolute(path),
        }) catch |err| {
```

- [ ] **Step 4: Verify**

```bash
zig build test --summary all
```

All three new tests pass; ALL existing rotation tests must stay green (they use relative paths — if any test uses an absolute temp path, set `.allow_absolute_path = true` in that test's options and note it).

- [ ] **Step 5: Commit**

```bash
zig fmt src/
git add src/handlers/rotating_file.zig
git commit -m "fix(security): sandbox rotating-file log paths (SEC-0037)

Reject absolute paths unless allow_absolute_path is set, and open
relative paths with resolve_beneath so symlinks cannot escape the
cwd sandbox (RESOLVE_BENEATH, Linux 5.6+). Closes the unmet SEC-0007
symlink acceptance criterion.

Closes SEC-0037. GitLab #46. APPSEC-02."
```

---

## Task 8: SEC-0038 — isSensitiveKey scans the whole key

**Files:**

- Modify: `src/util/redact.zig:78-102`
- Test: tests in `src/util/redact.zig`

- [ ] **Step 1: Write failing tests**

```zig
test "isSensitiveKey matches patterns past 64 bytes" {
    const long_key = "a" ** 64 ++ "password";
    try std.testing.expect(isSensitiveKey(long_key));
}

test "isSensitiveKey long benign key is not redacted" {
    const long_benign = "b" ** 100;
    try std.testing.expect(!isSensitiveKey(long_benign));
}
```

- [ ] **Step 2: Run to verify the first fails**

```bash
zig build test --summary all 2>&1 | grep -B1 -A3 "64 bytes"
```

Expected: FAIL (pattern starts at offset 64, outside the scan window).

- [ ] **Step 3: Implement — remove the 64-byte buffer entirely**

Replace the body of `isSensitiveKey`:

```zig
pub fn isSensitiveKey(key: []const u8) bool {
    if (key.len < min_pattern_len) return false;

    // Single-pass scan over the FULL key (SEC-0038: no 64-byte cap).
    // Case-insensitive compare per pattern; the inline for unrolls each
    // pattern check at comptime. Patterns are lowercase ASCII.
    for (0..key.len) |pos| {
        const remaining = key.len - pos;
        inline for (sensitive_keys) |pattern| {
            if (remaining >= pattern.len and
                std.ascii.eqlIgnoreCase(key[pos..][0..pattern.len], pattern))
            {
                return true;
            }
        }
    }
    return false;
}
```

(Delete the `lower_buf` block. Keep the doc comment, updating the implementation note to mention case-insensitive full-key scan.)

- [ ] **Step 4: Verify**

```bash
zig build test --summary all      # new + existing redact/formatter tests green
```

- [ ] **Step 5: Commit**

```bash
zig fmt src/
git add src/util/redact.zig
git commit -m "fix(security): isSensitiveKey scans the full key (SEC-0038)

The 64-byte lowercase scratch window meant sensitive patterns at
offset >=64 were never matched, silently disabling auto-redaction for
long namespaced keys. Scan the whole key with case-insensitive
comparison; no scratch buffer needed.

Closes SEC-0038. GitLab #47. APPSEC-03."
```

---

## Task 9: SEC-0039 — Truncate-with-marker instead of silent record drop

**Files:**

- Modify: `src/metrics/metrics.zig` (add truncated counter + incTruncated + Prometheus line; mirror the `incRotations` pattern exactly — read the file first)
- Modify: `src/handlers/text_handler.zig:50-57`
- Modify: `src/handlers/rotating_file.zig:270-276`
- Test: new test in `tests/handler_test.zig` (or the handlers' own test sections — follow where existing text-handler output tests live)

- [ ] **Step 1: Write the failing test**

Find the existing text-handler output test (grep `"text"` in `tests/handler_test.zig`) and mirror its writer-capture setup:

```zig
test "oversized record is truncated with marker, not dropped" {
    var out_buf: [16384]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&out_buf);
    var ctx = slogz.text.Context.init(&writer, .info, slogz.Clock.system());
    const handler = slogz.text.init(&ctx);

    // A single attr value larger than the 8KB format buffer.
    const big = "x" ** 10000;
    const rec = slogz.Record{
        .time_utc_us = 0,
        .level = .info,
        .msg_id = "big.event",
        .message = "oversized",
        .logger = "test",
        .source_file = null,
        .source_line = 0,
        .attrs = &.{slogz.Attr.string("payload", big)},
    };

    try handler.handle(&rec);

    const out = writer.buffered();
    try std.testing.expect(out.len > 0); // NOT silently dropped
    try std.testing.expect(std.mem.indexOf(u8, out, "[TRUNCATED]") != null);
    try std.testing.expectEqual(@as(u8, '\n'), out[out.len - 1]);
}
```

(Adapt the `Record` construction to the actual field set in `src/record.zig` — read it; if `source_file` is `?[]const u8` etc. match exactly. If `handler.handle` is reached via `Handler.handle(&rec)`, use that form.)

- [ ] **Step 2: Run to verify it fails**

```bash
zig build test --summary all 2>&1 | grep -B1 -A5 "oversized"
```

Expected: FAIL with `error.WriteFailed` (the current `catch return error.WriteFailed` drops the record).

- [ ] **Step 3: Add the metrics counter**

In `src/metrics/metrics.zig`, mirror `incRotations` exactly: add a `truncated` counter field next to the existing counters, an `incTruncated` method, a line in the Prometheus render (e.g. `slogz_records_truncated_total`), and extend the existing metrics test that asserts rendered output (find it via `grep -n "renderPrometheus" src/metrics/metrics.zig`).

```zig
    pub fn incTruncated(self: *Metrics) void {
        _ = self.truncated.fetchAdd(1, .monotonic);
    }
```

(Match the actual counter type/pattern used by the sibling counters — copy `incRotations`'s shape verbatim with the new name.)

- [ ] **Step 4: Implement truncation in text_handler**

Replace lines 50-57 of `src/handlers/text_handler.zig`:

```zig
    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    // SEC-0039: a record can be up to record.MAX_RECORD_SIZE (64KB) but
    // the format buffer is 8KB. On overflow, emit what fit plus an
    // explicit truncation marker instead of silently dropping the record.
    var truncated = false;
    writeTextRecord(&fbs, rec, ctx.prefix) catch {
        truncated = true;
    };

    var output: []const u8 = fbs.buffered();
    if (truncated) {
        const marker = " [TRUNCATED]\n";
        const keep = @min(output.len, buf.len - marker.len);
        @memcpy(buf[keep..][0..marker.len], marker);
        output = buf[0 .. keep + marker.len];
        metrics.global.incTruncated();
    }

    ctx.writer.writeAll(output) catch return error.WriteFailed;
    metrics.global.addBytesWritten(output.len);
```

- [ ] **Step 5: Implement the same in rotating_file**

Replace lines ~270-276 of `src/handlers/rotating_file.zig` (`handle`):

```zig
    // Format the record (SEC-0039: truncate with marker, never drop).
    var buf: [8192]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    var truncated = false;
    writeTextRecord(&fbs, rec, "") catch {
        truncated = true;
    };

    var output: []const u8 = fbs.buffered();
    if (truncated) {
        const marker = " [TRUNCATED]\n";
        const keep = @min(output.len, buf.len - marker.len);
        @memcpy(buf[keep..][0..marker.len], marker);
        output = buf[0 .. keep + marker.len];
        metrics.global.incTruncated();
    }

    ctx.write(output) catch return error.WriteFailed;
```

- [ ] **Step 6: Verify**

```bash
zig build test --summary all
```

New test passes; existing handler/metrics tests green.

- [ ] **Step 7: Commit**

```bash
zig fmt src/ tests/
git add src/handlers/text_handler.zig src/handlers/rotating_file.zig src/metrics/metrics.zig tests/handler_test.zig
git commit -m "fix(security): truncate oversized records with marker (SEC-0039)

Records up to 64KB were admitted but text/rotating handlers render
into 8KB buffers; overflow silently dropped the whole record -- an
audit-integrity gap (an attacker who can inflate a security event's
attributes could suppress it). Emit the truncated line plus an
explicit ' [TRUNCATED]' marker and count it via a new
slogz_records_truncated_total metric.

Closes SEC-0039. GitLab #48. APPSEC-04."
```

---

## Task 10: Q-48 / GAP-0027 — Fix all 8 examples and wire them into the build

**Files:**

- Modify: all 8 `examples/*.zig`
- Modify: `build.zig` (add examples step, hook into check)

**Transformation rules (apply per file):**

1. `const slog = @import("slog");` → `const slog = @import("slogz");` (keep the local alias `slog` so example bodies don't churn).
2. Replace every Zig 0.15 writer construction:
   - `std.io.getStdErr().writer().any()` feeding a text/json Context → use the public helpers:

     ```zig
     var ctx: slog.text.Context = undefined;
     const handler = slog.stderrHandler(&ctx, .info);
     ```

     (and `slog.json.Context` + `slog.stderrJsonHandler(&ctx, .info)` for JSON examples). This is the documented API.md pattern and avoids manual writer plumbing.
   - If an example genuinely needs stdout, use:

     ```zig
     var out_buf: [4096]u8 = undefined;
     var out_writer = std.Io.File.stdout().writer(
         std.Io.Threaded.global_single_threaded.io(),
         &out_buf,
     );
     defer out_writer.interface.flush() catch {};
     var ctx = slog.json.Context.init(&out_writer.interface, .info, slog.Clock.system());
     const handler = slog.json.init(&ctx);
     ```

3. `file_rotation.zig` and `tcp_sink.zig` don't use stderr writers but verify their API calls against current `slogz.zig` exports (e.g. `RotationOptions` field names — note `allow_absolute_path` from Task 7 if the example uses an absolute path; prefer a relative path).
4. Compile each one as you go: `zig build examples` (after Step 2 below).

- [ ] **Step 1: Read all 8 examples**

```bash
cat examples/*.zig
```

- [ ] **Step 2: Wire examples into build.zig**

After the docs step (before the closing `}` of `build()`):

```zig
    // Examples: compile-checked so API drift is caught in CI (Q-48).
    const examples_step = b.step("examples", "Build all examples");
    const example_names = [_][]const u8{
        "basic_text",     "json_logging",   "file_rotation", "async_logging",
        "secret_redaction", "metrics_export", "i18n_logging",  "tcp_sink",
    };
    inline for (example_names) |name| {
        const example_exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "slogz", .module = slogz_mod },
                },
            }),
        });
        examples_step.dependOn(&example_exe.step);
    }
    check_step.dependOn(examples_step);
```

- [ ] **Step 3: Fix each example per the transformation rules**

Work file by file; after each: `zig build examples 2>&1 | head -20` until clean.

- [ ] **Step 4: Verify everything**

```bash
zig build examples            # exit 0
zig build check               # exit 0 (now includes examples)
zig build test --summary all  # green
zig-out/bin/basic_text 2>&1 | head -5   # smoke-run one example if installed; otherwise skip
```

- [ ] **Step 5: Commit**

```bash
zig fmt examples/ build.zig
git add examples/ build.zig
git commit -m "fix(examples): port all 8 examples to Zig 0.16 and slogz module name (Q-48)

Examples imported the module as 'slog' (exported name is 'slogz') and
used removed std.io.getStdErr APIs, and were never compiled by any
build step -- breakage was invisible. Port to the documented
stderrHandler/stderrJsonHandler patterns and add a 'zig build
examples' step wired into 'zig build check' so CI compiles them.

Closes Q-48 / GAP-0027. GitLab #42."
```

---

## Task 11: Q-44 + Q-41/42/43 — Pre-commit config fix and lint batch

**Files:**

- Modify: `.pre-commit-config.yaml:122`
- Modify: `.gitlab/issue_templates/Bug Report.md`, `.gitlab/issue_templates/Question.md`, `SECURITY.md` (auto-fixed)
- Modify: `scripts/detect_diamond_deps.py` (ruff format)
- Modify: `docs/ARCHITECTURE.md`, `docs/API.md` (MD040 fence languages)

- [ ] **Step 1: Fix the zig-fmt hook target (Q-44)**

In `.pre-commit-config.yaml` line 122 change:

```yaml
    args: [src/, build.zig, tests/, benchmarks/, examples/]
```

to:

```yaml
    args: [src/, build.zig, tests/, bench/, examples/]
```

- [ ] **Step 2: Run the auto-fixers (Q-41, Q-42)**

```bash
pre-commit run trailing-whitespace --all-files || true
pre-commit run end-of-file-fixer --all-files || true
ruff format scripts/detect_diamond_deps.py
```

- [ ] **Step 3: Fix MD040 fences (Q-43)**

```bash
pre-commit run markdownlint --all-files || true   # --fix handles some
```

Then manually add languages to remaining bare ``` fences in `docs/ARCHITECTURE.md` (20), `docs/API.md` (25), `.gitlab/issue_templates/Bug Report.md` (1): use ` ```zig ` for Zig code blocks, ` ```text ` for output/diagrams. Verify:

```bash
pre-commit run markdownlint --all-files
```

Expected: Passed.

- [ ] **Step 4: Full hook run + tests**

```bash
pre-commit run --all-files   # everything passes (zig hooks may take a minute)
zig build test --summary all
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(quality): fix pre-commit zig-fmt target and lint batch (Q-41..Q-44)

- zig-fmt hook now checks bench/ (was pointing at benchmarks/, which
  has no .zig files) (Q-44)
- trailing whitespace / EOF fixes in issue templates and SECURITY.md (Q-41)
- ruff format scripts/detect_diamond_deps.py (Q-42)
- MD040 language tags on all bare code fences in docs (Q-43)

Closes Q-41, Q-42, Q-43, Q-44. GitLab #45."
```

---

## Task 12: Q-46 — Remove stale zig-pkg vendor snapshots

**Files:**

- Delete: `zig-pkg/json-0.1.0-*` (3 dirs), `zig-pkg/thread_pool-0.2.0-*` (4 dirs), `zig-pkg/uri-0.1.0-*` (2 dirs)

- [ ] **Step 1: Confirm live hashes**

```bash
grep -A2 'json\|thread_pool' build.zig.zon | grep hash
ls -d zig-pkg/*/
```

Live: `json-0.1.4-tOue4cGpCwBArfMl05wHmwv39pKM9-tjODxrMFm_sIk3`, `thread_pool-0.2.4-11B1BnyUdgCUNlqgBwHNvE4plLwP1s1MAyCjODPafrpo`, and the `uri-0.1.4-*` transitive. Everything at version 0.1.0/0.2.0 is stale.

- [ ] **Step 2: Delete stale snapshots**

```bash
git rm -r --quiet zig-pkg/json-0.1.0-* zig-pkg/thread_pool-0.2.0-* zig-pkg/uri-0.1.0-*
```

- [ ] **Step 3: Verify the build still resolves**

```bash
python3 scripts/detect_diamond_deps.py build.zig.zon   # clean
zig build check && zig build test --summary all        # green
du -sh zig-pkg/                                        # ~10MB (was ~46MB)
```

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(deps): remove 9 stale zig-pkg vendor snapshots (Q-46)

3x json-0.1.0, 4x thread_pool-0.2.0, 2x uri-0.1.0 accumulated across
dependency-convergence commits; only the 0.1.4/0.2.4 snapshots
referenced by build.zig.zon remain. Recovers ~36MB and shrinks the
auditable surface.

Closes Q-46. GitLab #44."
```

---

## Task 13: Q-47 + CHANGELOG — Fix slogz doc-comment example, refresh CHANGELOG

**Files:**

- Modify: `src/slogz.zig:20-26` (doc comment)
- Modify: `CHANGELOG.md` ([Unreleased] Planned section + add Fixed entries for this pass)

- [ ] **Step 1: Fix the doc-comment example**

In `src/slogz.zig` replace the example block (lines ~20-26):

```zig
//! var text_ctx: slogz.text.Context = undefined;
//! const handler = slogz.stderrHandler(&text_ctx, .info);
```

replacing:

```zig
//! var text_ctx = slogz.text.Context.init(
//!     std.Io.File.stderr().writer().any(),
//!     .info,
//!     slogz.Clock.system(),
//! );
//! const handler = slogz.text.init(&text_ctx);
```

(The `.any()` form does not exist in Zig 0.16; the stderrHandler helper is the documented pattern.)

- [ ] **Step 2: Refresh CHANGELOG.md**

In `[Unreleased]`:

- Remove from Planned: "Multi-handler fan-out" (shipped: `src/handlers/multi_handler.zig`) and "DNS hostname resolution" (shipped: `tcp_sink.zig` `IpAddress.resolve`). Keep "TLS/HTTPS support" and "Log sampling and rate limiting".
- Add under `### Fixed` (create the subsection if missing) one bullet per pass-6 fix: compare-bench gate (PERF-043), multi_handler sequential dispatch (PERF-039), async queue condvar wake + single-lock enqueue (PERF-040/041/042), rotating-file 0o600 permissions (SEC-0034), log-path sandboxing (SEC-0037), full-key redaction scan (SEC-0038), truncation marker (SEC-0039), examples ported to Zig 0.16 (Q-48).

- [ ] **Step 3: Verify and commit**

```bash
zig build check && zig build test --summary all
zig fmt src/
git add src/slogz.zig CHANGELOG.md
git commit -m "docs: fix slogz doc-comment example and refresh CHANGELOG (Q-47)

The module doc example used .writer().any(), which does not compile
under Zig 0.16; show the stderrHandler helper instead. Move shipped
items (multi-handler, DNS resolution) out of CHANGELOG Planned and
record the pass-6 fixes.

Closes Q-47. Part of GAP-0027/#42 (CHANGELOG checkbox)."
```

---

## Task 14: Final verification — full gates + benchmark comparison

**Files:** none modified (verification only; baseline regeneration if green)

- [ ] **Step 1: Full local gates**

```bash
zig fmt --check src/ build.zig tests/ bench/ examples/
zig build check
zig build test --summary all
pre-commit run --all-files
```

All must pass (test count will be HIGHER than 261 due to new tests; 1 skip expected).

- [ ] **Step 2: Benchmark regression check via the restored gate**

```bash
zig build scale-bench 2>/dev/null > /tmp/post-fix.json
zig build compare-bench -- benchmarks/results/baseline.json /tmp/post-fix.json; echo "exit=$?"
```

Expected: multi_handler and async_enqueue back near baseline. text/json may remain ~15-25% above baseline (PERF-044, accepted std.Io.Mutex cost — documented Won't Do/Monitor). If compare-bench exits 1 ONLY on text/json metrics attributable to PERF-044, that is the documented accepted state — record the exact numbers for the gap doc update.

- [ ] **Step 3: Regenerate the stored baseline (post-fix reference)**

Per PERF_GAP_ANALYSIS.md item 5 ("baseline should be regenerated once PERF-039..043 are fixed"):

```bash
zig build scale-bench 2>/dev/null > benchmarks/results/baseline.json
git add benchmarks/results/baseline.json
git commit -m "chore(bench): regenerate baseline after pass-6 perf fixes

New reference captured post PERF-039..043 on Zig 0.16; the prior
baseline (2026-03-30) predated the std.Io migration. PERF-044
(std.Io.Mutex cost) is accepted and now inside the baseline."
```

- [ ] **Step 4: Report**

Summarize per-gap status (closed / blocked / deviations) for the verifier and reporter phases.

---

## Self-Review Notes

- **Spec coverage:** SEC-0034→T6, SEC-0037→T7, SEC-0038→T8, SEC-0039→T9, PERF-039→T2, PERF-040→T3, PERF-041→T5, PERF-042/Q-45→T4, PERF-043→T1, Q-41/42/43/44→T11, Q-46→T12, Q-47→T13, Q-48/GAP-0027→T10, CHANGELOG (part of #42)→T13, baseline regen→T14. Won't-Do items (SEC-0040, SEC-0041, PERF-044) need no code task — reporter closes them with documented reasons.
- **Type consistency:** `PushResult` defined in T5 and used only there + async_handler; `popWait`/`shutdownWake` defined T3, used T3; `allow_absolute_path` defined T7, referenced T10 note.
- **Known judgment points for implementers:** exact existing test conventions in rotating_file.zig (T6/T7), Record field shape (T9 test), metrics counter type (T9 — copy incRotations), `symLink` signature (T7), per-example API drift (T10). In each case the plan says to read the authoritative source first; the contracts (assertions/behavior) are fixed.
