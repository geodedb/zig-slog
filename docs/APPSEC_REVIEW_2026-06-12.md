# Application Security Code Review — `zig/slog`

## 1. Scope and Assumptions

**Target:** `gitlab.com/devnw/zig/slog` — a Zig 0.16 structured logging library. Reviewed at HEAD `bd50a7fdbc3e9ce77e66278910bf1b33af045ef3` (branch `main`).

**Reviewed (read directly from HEAD):**

- Redaction/sanitization: `src/util/redact.zig`, `src/util/sanitize.zig`
- Formatters: `src/fmt/{text_record,text_value,json_record,json_value}.zig`
- Handlers: `src/handlers/{rotating_file,syslog_rfc5424,async_handler}.zig` (and grep across text/json/journald/windows/multi/discard)
- Sinks: `src/sinks/{tcp,udp,http}_sink.zig`
- Memory-safety surfaces: `src/internal/queue.zig`, `src/parallel.zig`, `src/handlers/async_handler.zig`
- Entry point: `src/logger.zig`; record limits `src/record.zig`
- Supply chain / CI: `build.zig.zon`, `.gitlab-ci.yml`, `scripts/detect_diamond_deps.py`, `.gitleaks.toml`, `SECURITY.md`
- Active JSON dependency string-escaping: `zig-pkg/json-0.1.4-…/src/emitter.zig`
- Prior tracking: `docs/GAP_ANALYSIS.md`, `docs/GAP_ANALYSIS_RESOLVED.md`

**Method:** Source-to-sink trace of attacker-influenced log content (message, keys, values) through redaction → sanitization → formatting → handler/sink output. Cross-checked every candidate against prior `SEC-*` findings; **only items reproducible in current HEAD are reported.** Confirmed the Zig 0.16 `std.Io.Dir.CreateFileOptions` API and the JSON encoder's escaping behavior against the installed toolchain (`zig 0.16.0`).

**Assumptions:**

- The library's trust model treats **attribute keys** as developer-chosen (usually constants) and **attribute values / messages** as potentially attacker-influenced application data. This matches the redaction/sanitization design.
- "Attacker-controlled" log content means data the application chooses to log that originated from an untrusted source (request fields, error strings, etc.).
- No execution/build was performed; findings are from static review plus toolchain API confirmation.

**Not reviewed in depth:** Windows event-log and journald native syscall paths beyond their formatting/redaction wiring; the full internals of the `json` and `thread_pool` dependencies (only the JSON string-escape path was inspected); `bench/` and `examples/` for non-security behavior.

---

## 2. Executive Summary

- The library's core security posture is **strong and materially improved over prior passes**. Auto-redaction (`isSensitiveKey`) is correctly wired into every formatter; messages and string values are sanitized against CRLF/ANSI log injection in text/syslog paths; the JSON encoder escapes all control bytes (`< 0x20`, including ESC `0x1b`) so JSON sinks are injection-safe; the HTTP sink rejects `https://` (no silent plaintext downgrade) and filters control characters from custom headers; the syslog handler applies RFC5424 `\ " ]` escaping. These were verified present at HEAD, not just claimed.
- **One Medium finding is a regression in a previously-"Closed" control:** the rotating-file handler creates log files with **no explicit permission mode** (`rotating_file.zig:112`), so on POSIX they default to `0o666 & ~umask` (typically world-readable `0o644`). `GAP_ANALYSIS.md` records SEC-0034 as "Closed (file permissions set to 0o600)," but that mode is absent in current code — log files containing PII/secrets are world-readable. **(APPSEC-01)**
- **One Medium finding is an unmet acceptance criterion:** `validatePath` blocks only `..`; it does not prevent the log path from being a **symlink** to a sensitive location, and absolute paths are accepted. SEC-0007's criterion "symlinks in the path do not allow escaping" was never satisfied. **(APPSEC-02)**
- **Two Low findings:** a redaction blind spot for keys longer than 64 bytes (`isSensitiveKey` scans only the first 64) **(APPSEC-03)**, and silent whole-record loss when a record's rendered form exceeds the 8KB handler buffer while the record-size budget is 64KB **(APPSEC-04)**.
- No memory-unsafety, UB, integer-overflow-to-corruption, or unbounded-allocation issue reachable from attacker-controlled log content was found: the queue copies into fixed-size buffers, all writers are bounds-checked `.fixed` streams, and the bounded queue uses a drop-oldest policy.
- Plaintext transport on TCP/UDP sinks and lack of TLS/mTLS are **accepted, documented "Won't Do"** decisions (SEC-0004/0016/0026) appropriate to a library's scope; re-stated here as residual risk, not new findings.

**Overall confidence:** High for the redaction/sanitization/injection analysis (traced source-to-sink and confirmed encoder behavior). High for APPSEC-01/APPSEC-02 (confirmed against the Zig 0.16 API). Medium for the exploitability framing of APPSEC-03 (depends on key provenance).

---

## 3. Findings Table

| ID | Severity | Confidence | Title | Location | OWASP 2025 | Status |
|----|----------|-----------|-------|----------|-----------|--------|
| APPSEC-01 | Medium | High | Rotating log files created world-readable (no explicit mode; SEC-0034 regression) | `src/handlers/rotating_file.zig:112` | A02 Security Misconfiguration | Open (new at HEAD) |
| APPSEC-02 | Medium | High | Log path symlink-following / absolute-path write not constrained | `src/handlers/rotating_file.zig:89-99, 112` | A01 Broken Access Control | Open (unmet criterion) |
| APPSEC-03 | Low | Medium | Auto-redaction blind spot for keys longer than 64 bytes | `src/util/redact.zig:81-100` | A09 Logging/Alerting Failures | Open (new) |
| APPSEC-04 | Low | Medium | Silent whole-record drop when rendered size exceeds 8KB buffer | `src/handlers/rotating_file.zig:271-276`, `src/handlers/text_handler.zig:50` | A09 / A10 | Open (new) |
| INFO-01 | Info | High | TCP/UDP sinks plaintext; no transport encryption/auth | `src/sinks/{tcp,udp}_sink.zig` | A02 / A04 | Accepted (Won't Do, documented) |

---

## 4. Finding Details

### APPSEC-01 — Rotating log files created world-readable (SEC-0034 regression) — Medium

**Evidence.** `src/handlers/rotating_file.zig:112-119`:

```zig
self.file = std.Io.Dir.cwd().createFile(io, path, .{
    .truncate = false,
}) catch |err| { ... };
```

No `permissions` field is passed. The Zig 0.16 `std.Io.Dir.CreateFileOptions` struct defaults `permissions: Permissions = .default_file`, and on POSIX `Permissions.default_file = 0o666` (confirmed in `…/0.16.0/lib/std/Io/File.zig:368` and `Dir.zig:586-628`). After the process umask (commonly `022`) the on-disk mode is typically `0o644` — **world-readable**.

`docs/GAP_ANALYSIS.md:74` records SEC-0034 as **Closed** with remediation "Explicit mode 0o600 passed to createFile," and `docs/GAP_ANALYSIS_RESOLVED.md:551` repeats it. `git log -S "0o600"/".mode"/"permissions" -- src/handlers/rotating_file.zig` shows the mode-bearing code last appeared around the `fa0de64` ("complete zig 0.16.0 migration") commit and is **not present at HEAD** — the explicit mode was dropped during the 0.16 API migration while the tracking doc still claims closure.

**Attack scenario (scoped, non-destructive).** A service logs records containing PII / session identifiers / internal hostnames to `/var/log/app/app.log` via the rotating handler. Any local user (or any compromised low-privilege process / co-tenant on a shared host) can `cat` the log and its rotated backups (`app.log.1`, `.2`, …, created via `rename`, inheriting the same permissive mode). This is the canonical sensitive-data-at-rest exposure the redaction feature exists to mitigate, undone at the file-permission layer.

**Impact.** Local disclosure of potentially sensitive log content to unprivileged users. Severity Medium: requires local access and sensitive content in logs; no remote vector.

**Root cause.** Permission mode lost during the Zig 0.16 `std.fs` → `std.Io.Dir` migration; not re-added; tracking doc not reconciled against code.

**Remediation.**

```zig
self.file = std.Io.Dir.cwd().createFile(io, path, .{
    .truncate = false,
    .permissions = @enumFromInt(0o600), // owner-only; widen deliberately if shared reads are required
}) catch |err| { ... };
```

Use the `Permissions` enum form appropriate to the target (`File.Permissions` is a non-exhaustive enum on POSIX; `0o600` for owner-only, or `0o640` if a log-reader group is intended). Consider making the mode a `RotationOptions` field so operators can choose. Note that for **already-existing** files `createFile` does not change mode — document that operators should also restrict the directory, or `chmod` on first open.

**Regression tests / verification.**

- Add a test that opens the file and asserts `stat().mode & 0o077 == 0` (no group/other bits) on POSIX.
- Manual: `umask 022; <run handler>; ls -l app.log` → expect `-rw-------`.
- Reconcile `GAP_ANALYSIS.md` SEC-0034 status with code reality.

**Mappings.** CWE-276 (Incorrect Default Permissions), CWE-732. OWASP A02:2025. CIS Controls v8.1.2: 3.3 (data access control lists), 4.1 (secure configuration / hardening).

---

### APPSEC-02 — Log path symlink-following and unconstrained absolute writes — Medium

**Evidence.** `src/handlers/rotating_file.zig:89-99`:

```zig
fn validatePath(path: []const u8) !void {
    if (path.len == 0) return error.WriteFailed;
    if (std.mem.indexOf(u8, path, "..") != null) return error.WriteFailed;
}
```

The only checks are non-empty and "contains no `..`". `openFile` then `createDirPath`s the dirname and `createFile`s the path via `std.Io.Dir.cwd()` (`:106-119`) with default options. The Zig 0.16 `CreateFileOptions` exposes `resolve_beneath: bool = false` and the toolchain supports `follow_symlinks` semantics (confirmed in `…/std/Io/Dir.zig:586-629`), neither of which is used. SEC-0007's acceptance criterion (`docs/GAP_ANALYSIS.md:433`) explicitly lists "Symlinks in the path do not allow escaping the intended directory" — that box is unticked, yet SEC-0007 is marked **Closed**.

**Attack scenario.** If an attacker can influence the configured log path (env var, config file, deployment template — the threat model SEC-0007 itself assumes) they can:

1. Supply an **absolute** path (`/etc/cron.d/x`, a fifo, a device node) — `..` filtering does not stop absolute writes; or
2. Pre-create a **symlink** at the intended log location pointing at a target file; `createFile` with default options follows it and the handler appends attacker-influenced log lines to the symlink target (log-content injection into a sensitive file). The append-mode write plus rotation `rename` can also clobber/relocate the target.

**Impact.** Arbitrary-location file write / append of partially attacker-influenced content, contingent on config influence. Medium (not Critical) because it requires control of the path configuration, which in many deployments is operator-trusted.

**Root cause.** Path validation is substring-based (`..`) rather than canonicalization- and capability-based; symlink-following is left at the OS default.

**Remediation.**

- Reject absolute paths unless explicitly opted in; reject paths whose canonical (realpath) form escapes a configured base directory.
- Open the base log directory once as a `Dir` and create files **relative** to it with `resolve_beneath = true` (returns `error.AccessDenied` on escape) and, where supported, non-following semantics for the final component.
- At minimum, set `.exclusive`/no-follow on first create or `lstat` the path and refuse if it is a symlink.

**Regression tests.**

- Test: pre-create a symlink at the target → handler init/open returns an error (or writes to the real intended inode, never the link target).
- Test: absolute path outside the configured base is rejected.

**Mappings.** CWE-22 (Path Traversal), CWE-59 (Link Following), CWE-61. OWASP A01:2025. CIS v8.1.2: 3.3, 4.1.

---

### APPSEC-03 — Auto-redaction blind spot for keys longer than 64 bytes — Low

**Evidence.** `src/util/redact.zig:81-100`: `isSensitiveKey` lowercases and scans only `key[0..@min(key.len, 64)]` (`lower_buf: [64]u8`). A sensitive pattern (e.g. `api_key`, `password`) whose first character sits at offset ≥ 64 is never matched, so the value is **not** redacted. The formatters call `isSensitiveKey(attr.key)` on the raw key (`fmt/text_record.zig:76`, `fmt/json_record.zig:106`, `syslog_rfc5424.zig:226`), while the displayed key is independently truncated to 64 bytes by `sanitizeKey`. `record.zig` caps the whole record at 64KB but imposes no per-key length limit, so a 64-byte-prefixed sensitive key is well within budget.

**Attack scenario / realistic trigger.** This is primarily a **defense-in-depth blind spot** rather than a remotely-triggered vuln, because keys are normally developer constants. The realistic failure: a developer uses a long namespaced key such as a 60-character module/path prefix followed by `_api_key`; auto-redaction silently fails and the secret value is logged in cleartext. If key names are ever derived from untrusted input, an attacker could deliberately position the token past byte 64 to defeat the safety net.

**Impact.** Secret/PII value logged in cleartext despite a key the user reasonably expects to be auto-redacted. Low: requires an unusually long key and the value-side caller relying on auto-redaction rather than `Attr.secret`.

**Root cause.** Fixed 64-byte stack scan window in `isSensitiveKey` for performance, without a fallback for longer keys.

**Remediation.** Scan the entire key (the function already operates on a slice; lowercase in chunks or compare case-insensitively without a fixed buffer):

```zig
pub fn isSensitiveKey(key: []const u8) bool {
    if (key.len < min_pattern_len) return false;
    for (0..key.len) |pos| {
        const remaining = key.len - pos;
        inline for (sensitive_keys) |pattern| {
            if (remaining >= pattern.len and
                std.ascii.eqlIgnoreCase(key[pos..][0..pattern.len], pattern))
                return true;
        }
    }
    return false;
}
```

This removes the 64-byte cap and avoids the lowercase scratch buffer entirely.

**Regression tests.** `try expect(isSensitiveKey("a" ** 64 ++ "password"));` and a JSON/text formatter test asserting the value is `[REDACTED]` for such a key.

**Mappings.** CWE-532 (Insertion of Sensitive Information into Log). OWASP A09:2025. CIS v8.1.2: 8.x audit-log handling, 3.x data protection.

---

### APPSEC-04 — Silent whole-record drop when rendered size exceeds 8KB buffer — Low

**Evidence.** `logger.log` admits records up to `MAX_RECORD_SIZE = 64 * 1024` (`record.zig:14, 51-52`). The text and rotating-file handlers render into an **8KB fixed buffer** (`text_handler.zig:50`, `rotating_file.zig:271`: `var buf: [8192]u8`). When the rendered line exceeds 8KB, `writeTextRecord` to the `.fixed` writer fails with `error.NoSpaceLeft`, and the handler executes `... catch return error.WriteFailed` (`rotating_file.zig:274`), discarding the **entire** record. (UDP already drops over-MTU records by design at `udp_sink.zig:74-77`; TCP/HTTP/JSON use 16KB buffers, still below the 64KB budget.)

**Attack scenario.** An application logs an attacker-influenced large value (e.g. a several-KB request body or error blob, within the 64KB record budget). The record silently vanishes from the file/console log. An attacker who can make a security-relevant event carry a large attribute can suppress that specific audit record without any error surfaced to the application beyond a generic `WriteFailed`/metrics counter.

**Impact.** Loss of audit/log records (availability + audit integrity). Bounds-safe — Zig's `.fixed` writer is checked, so there is **no buffer overflow or memory unsafety**; the issue is silent data loss. Low.

**Root cause.** Handler format buffers (8KB) are smaller than the maximum admissible record size (64KB); over-budget renders fail closed by dropping the whole line rather than truncating.

**Remediation.** Align the format-buffer size with `MAX_RECORD_SIZE` (e.g. size the buffer to 64KB, or grow/stream into the write buffer), or on `NoSpaceLeft` emit a truncated record plus an explicit `truncated=true` marker rather than dropping. Increment a dedicated `dropped`/`truncated` metric (the rotating handler currently only bumps `incErrors()`), and consider surfacing it.

**Regression tests.** Log a record whose rendered size is ~16KB and assert the file contains a (possibly truncated) line and a truncation indicator, not nothing.

**Mappings.** CWE-778 (Insufficient Logging), CWE-755. OWASP A09/A10:2025. CIS v8.1.2: 8.2/8.3 (audit log collection/management).

---

### INFO-01 — Plaintext TCP/UDP transport, no transport auth — Info (accepted)

`tcp_sink.zig` / `udp_sink.zig` transmit JSON log records in cleartext with no TLS/DTLS or peer authentication. This is tracked as SEC-0004/0016/0026/0029 and accepted **Won't Do** with documented rationale (TLS exceeds current library scope; Zig stdlib TLS maturing). The HTTP sink correctly **rejects** `https://` rather than silently downgrading (`http_sink.zig:62-66`), which is the right fail-closed behavior. Re-stated here as residual risk for operators: route these sinks only over trusted networks or an encrypted tunnel (stunnel/WireGuard/service mesh). No action required of the library beyond the existing documentation.

---

## 5. Secure Design Notes (positive controls verified at HEAD)

- **Auto-redaction is wired everywhere.** `isSensitiveKey(attr.key)` is invoked against the *raw* key before value emission in text (`fmt/text_record.zig:76`), JSON (`fmt/json_record.zig:106`), and syslog (`syslog_rfc5424.zig:226`) — ordering is correct (no `sanitizeKey`-induced bypass). `.secret`-typed values render `[REDACTED]` in every value writer (`text_value.zig:55`, `json_value.zig:32`, `syslog`).
- **Queue redacts at enqueue.** `QueuedRecord.serializeValue` writes `[REDACTED]` for `.secret` before storing (`internal/queue.zig:127-130`), and a test asserts the plaintext secret is absent from the stored buffer (`:578-602`). No secret plaintext lingers in the async ring buffer.
- **Log-injection neutralized on both encodings.** Text path escapes `\n \r \t` and all `0x00–0x1f` (incl. ESC `0x1b`) via `sanitizeOutput` (`sanitize.zig:148-160`) applied to message, logger, msg_id, and string values. JSON path relies on the `json-0.1.4` encoder, which escapes `" \ \n \r \t \b \f` and every byte `< 0x20` as `\u00XX` (confirmed `emitter.zig:222-258`). Keys are character-restricted to `[A-Za-z0-9_.-]` by `sanitizeKey` before emission. Syslog applies RFC5424 `\ " ]`+control escaping (`syslog_rfc5424.zig:269-283`).
- **HTTP sink hardening.** `https://` rejected at init (no silent plaintext); custom headers with control chars are skipped (`http_sink.zig:160-161`, `containsControlChars` covers `<0x20` and `0x7f`); request line is built from fixed option fields, not from log content.
- **Memory safety.** Bounded drop-oldest queue (`internal/queue.zig`), fixed-size owned copies (no pointer-lifetime hazards across the async boundary), all writers are bounds-checked `.fixed` streams, `min i64` negation handled explicitly (`:90-98`), UTF-8 sequence validation in `sanitizeUtf8`, and an `@intFromError == 0` guard before `@errorName` to avoid UB on corrupt error values.
- **Path traversal `..` blocked** and dual path buffers prevent rename aliasing (`rotating_file.zig:189-200`).
- **Supply chain.** Both deps pinned by **commit + content hash** in `build.zig.zon`; CI includes SAST, dependency scanning, secret scanning, gitleaks, and SBOM generate/scan; the Zig toolchain is installed with a **SHA-256 verified against the signed `index.json`** (`.gitlab-ci.yml` `.install-zig`); `scripts/detect_diamond_deps.py` guards against the same package name resolving to two hashes (a real Zig-0.16 link-time hazard). `.gitleaks.toml` allowlist is appropriately narrow (specific example/test files only).

---

## 6. Coverage Gaps and Questions

- **Dependency internals.** Only the JSON encoder's string-escape path was inspected in `json-0.1.4`; the parser, `thread_pool`, and other modules were not audited. The diamond-dep guard and hash pinning mitigate substitution risk but not a malicious upstream commit at the pinned hash. (CIS 16.x / A03.)
- **Native platform handlers.** `journald` and `windows_eventlog` syscall paths were verified for redaction/sanitization wiring via grep but not exhaustively traced for platform-specific escaping behavior.
- **Value-side secret detection is intentionally absent.** A secret placed under a non-sensitive key (`Attr.string("note", "Bearer eyJ…")`) is never auto-redacted — this is by design (caller responsibility) and consistent across the codebase; flagged as a residual user-education item, not a defect. Confirm this is the intended contract in user docs.
- **Threat model not provided.** No `docs/THREAT_MODEL.md`. The severity of APPSEC-01/02 hinges on whether log paths and log content can be influenced by untrusted parties in target deployments — please confirm.
- **Runtime not executed.** Findings are static + toolchain-API-confirmed; APPSEC-04's drop behavior was inferred from buffer sizing and the `catch return error.WriteFailed` pattern, not observed at runtime.
- **Tracking-doc drift.** SEC-0034 (and the symlink criterion of SEC-0007) are recorded as Closed but are not satisfied in HEAD. A broader reconciliation of `GAP_ANALYSIS.md`/`_RESOLVED.md` against current code is advisable to surface any other claimed-but-reverted fixes.

---

## 7. Prioritized Next Actions

1. **APPSEC-01 (Medium):** Pass `.permissions = @enumFromInt(0o600)` (or a `RotationOptions` mode field) to `createFile` in `rotating_file.zig`; add a stat-based permission test; reconcile SEC-0034's status in the gap docs. ~30 min.
2. **APPSEC-02 (Medium):** Constrain the log path — reject absolute/escaping paths via canonicalization, open relative to a base `Dir` with `resolve_beneath = true`, and refuse symlinked final components; add symlink/absolute-path rejection tests. Close SEC-0007's outstanding criterion. ~2–3 h.
3. **APPSEC-03 (Low):** Remove the 64-byte scan cap in `isSensitiveKey`; add a long-key redaction test. ~20 min.
4. **APPSEC-04 (Low):** Size handler format buffers to `MAX_RECORD_SIZE` (or truncate-with-marker instead of dropping) and add a dedicated dropped/truncated metric + test. ~1 h.
5. **Process:** Run a one-time audit reconciling every `**Closed**` SEC-* item in `GAP_ANALYSIS.md` against HEAD to catch any other fixes lost in the 0.16 migration (APPSEC-01 proves at least one regressed).
6. **Docs (no code):** Restate the INFO-01 plaintext-transport residual risk and the value-side "use `Attr.secret` for secrets" contract prominently in user-facing docs.

No memory-safety, injection, deserialization, or supply-chain compromise was confirmed in the reviewed scope. The findings above are the complete set reproducible at HEAD `bd50a7f`; the codebase is otherwise in good security shape, with the redaction and log-injection controls correctly implemented and verified end-to-end.
