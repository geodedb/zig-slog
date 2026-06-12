# Security Gap Analysis -- slogz (Zig Structured Logging Library)

**Repository:** gitlab.com/devnw/zig/slog
**Branch:** main (commit bd50a7f)
**Last updated:** 2026-06-12 (rev 8 -- AppSec review pass: SEC-0034 REOPENED as Zig 0.16 migration regression; SEC-0037/0038/0039/0040/0041 added; SEC-0008 Closed by removal of spice dependency)
**Analyst:** AppSec Code Review (`docs/APPSEC_REVIEW_2026-06-12.md`) + Claude Opus 4.8 (automated scoring); prior Phase 3 Adversarial Review
**Methodology:** Risk Score = Impact(1-5) x Likelihood(1-5) x 4

---

## Summary

| Severity | Count | Closed | Blocked | Won't Do | Open |
|----------|-------|--------|---------|----------|------|
| Critical | 2 | 2 | 0 | 0 | 0 |
| High | 8 | 6 | 0 | 2 | 0 |
| Medium | 15 | 10 | 0 | 3 | 2 |
| Low | 14 | 11 | 0 | 1 | 2 |
| Info | 2 | 1 | 0 | 0 | 1 |
| **Total** | **41** | **30** | **0** | **6** | **5** |

### Open Items (Stack-Ranked by Risk Score)

1. **SEC-0034** (Medium, Score 36) -- **REGRESSION.** Rotating log files created world-readable; the 0o600 mode (claimed Closed in pass 5) was lost in the Zig 0.16 migration (commit `fa0de64`). `rotating_file.zig:112`. Maps to APPSEC-01. Issue [#43](https://gitlab.com/devnw/zig/slog/-/issues/43).
2. **SEC-0037** (Medium, Score 36) -- Log path symlink-following + unconstrained absolute writes; SEC-0007's symlink acceptance criterion never met. `rotating_file.zig:89-99,112`. Maps to APPSEC-02. Issue [#46](https://gitlab.com/devnw/zig/slog/-/issues/46).
3. **SEC-0039** (Low, Score 16) -- Silent whole-record drop when a >8 KB rendered record hits the 8 KB handler buffer (64 KB record budget); audit-integrity loss. `text_handler.zig:50`, `rotating_file.zig:271-276`. Maps to APPSEC-04. Issue [#48](https://gitlab.com/devnw/zig/slog/-/issues/48).
4. **SEC-0040** (Low, Score 16) -- CI catalog components pinned to mutable version tags (`@v1.7.1`) not commit SHAs. `.gitlab-ci.yml:11-24`. Accepted-risk candidate (see Won't Do rationale).
5. **SEC-0038** (Low, Score 12) -- `isSensitiveKey` scans only the first 64 bytes of a key; redaction bypass for long keys. `src/util/redact.zig:81-100`. Maps to APPSEC-03. Issue [#47](https://gitlab.com/devnw/zig/slog/-/issues/47).

(**SEC-0041** -- Info/Low, Score 4 -- vendored thread_pool scripts committed mode 0777; informational, recorded under Findings by Area.)

### Immediate Actions Required

- **No secrets are currently leaked** -- no rotation required.
- **SEC-0034 is the priority item:** an explicit `0o600` permission mode must be re-added to `createFile` in `rotating_file.zig` (lost in the Zig 0.16 migration). Until fixed, rotating log files and their backups are world-readable on default-umask POSIX hosts.
- **SEC-0008 is Closed by removal:** the `spice` dependency was deleted entirely (commit `97c5c59`) and replaced by `thread_pool` pinned by commit SHA + content hash. The prior Blocked status is obsolete. GitLab issue #29 closed with evidence. Moved to GAP_ANALYSIS_RESOLVED.md.
- **Process action:** run a one-time reconciliation of every `**Closed**` SEC-* item against HEAD to catch any other fixes lost in the 0.16 migration (SEC-0034 proves at least one regressed).
- Plaintext TCP/UDP transport (SEC-0004/0016/0026/0029) remains accepted Won't Do (TLS exceeds library scope); restated as residual risk only.

---

## Stack-Ranked Findings

| Rank | ID | Severity | Risk Score | Finding | Component | CWE / OWASP | Evidence | Fix | Owner | Due | Status |
|------|-----|----------|-----------|---------|-----------|-------------|----------|-----|-------|-----|--------|
| 1 | SEC-0001 | Critical | 80 | HTTPS URLs sent over plaintext TCP | http_sink.zig | CWE-319 / A02:2021 | http_sink.zig:64-104,131-141 | Reject https:// URLs at init time | -- | 2026-03-30 | **Closed** (0ed8afe) |
| 2 | SEC-0003 | High | 64 | HTTP header injection via unvalidated headers | http_sink.zig | CWE-113 / A03:2021 | http_sink.zig:157-161 | Skip headers with control characters | -- | 2026-04-22 | **Closed** (0ed8afe) |
| 3 | SEC-0005 | High | 64 | isSensitiveKey() dead code; no auto-redaction | redact.zig | CWE-532 / A09:2021 | redact.zig:34-48 | isSensitiveKey wired into all handlers | -- | 2026-04-22 | **Closed** (0ed8afe) |
| 4 | SEC-0006 | High | 64 | Log injection via unsanitized messages -- FIXED (pass 3) | rotating_file.zig | CWE-117 / A03:2021 | rotating_file.zig:298,305,312 | sanitize.sanitizeOutput + sanitizeKey in rotating_file | -- | 2026-04-23 | **Closed** (pass 3: sanitize import, sanitizeOutput on message, sanitizeKey on attr keys, writeTextValue for values) |
| 5 | SEC-0002 | Critical | 60 | stderrHandler returns dangling pointer (UB) | slogz.zig | CWE-416 / A04:2021 | slogz.zig:107-117 | API changed to accept *Context out-param | -- | 2026-03-30 | **Closed** (ec068d0) |
| 6 | SEC-0004 | High | 60 | TCP/UDP sinks transmit plaintext only | tcp_sink.zig, udp_sink.zig | CWE-319 / A02:2021 | tcp_sink.zig:65-78, udp_sink.zig:48-52 | TLS requires significant effort | -- | -- | **Won't Do** |
| 7 | SEC-0007 | High | 48 | Path traversal in rotating file handler | rotating_file.zig | CWE-22 / A01:2021 | rotating_file.zig:69-84 | Path traversal validation added at init | -- | 2026-04-22 | **Closed** (05c6a16) |
| 8 | SEC-0008 | High | 48 | Supply chain: spice on floating main branch | build.zig.zon | CWE-1357 / A06:2021 | build.zig.zon (spice removed) | spice removed entirely; replaced by thread_pool pinned by commit SHA + hash | -- | 2026-06-12 | **Closed** (97c5c59 -- dependency removed; issue #29 closed) |
| 9 | SEC-0009 | High | 48 | Rotating file handler missing isSensitiveKey() auto-redaction -- FIXED (pass 3) | rotating_file.zig | CWE-532 / A09:2021 | rotating_file.zig:305-312 | isSensitiveKey() check added in attr loop | -- | 2026-04-23 | **Closed** (pass 3: isSensitiveKey check + redact.REDACTED output in rotating_file attr loop) |
| 10 | SEC-0010 | Medium | 48 | Text handler string values unescaped | text_handler.zig | CWE-117 / A03:2021 | text_handler.zig:113-119 | sanitize.sanitizeOutput for string values | -- | 2026-06-21 | **Closed** (0ed8afe) |
| 11 | SEC-0011 | Medium | 32 | Global fatal_hook race condition | logger.zig | CWE-362 / A04:2021 | logger.zig:26 | Atomic get/setFatalHook | -- | 2026-06-21 | **Closed** (ec068d0) |
| 12 | SEC-0012 | Medium | 24 | Secret values plaintext in memory | value.zig | CWE-316 / A02:2021 | value.zig:12-22 | Documented as known limitation | -- | 2026-06-21 | **Closed** (ec068d0) |
| 13 | SEC-0013 | Medium | 24 | Async handler drops secret attributes silently | queue.zig | CWE-532 / A09:2021 | queue.zig:72-81 | Secrets redacted at serialization time | -- | 2026-06-21 | **Closed** (3fcd5a5) |
| 14 | SEC-0014 | Medium | 24 | Gitleaks blanket exclusion of examples/tests | .gitleaks.toml | CWE-798 / A07:2021 | .gitleaks.toml:9-12 | Narrowed to specific demo file | -- | 2026-06-21 | **Closed** (ec068d0) |
| 15 | SEC-0015 | Medium | 20 | SECURITY.md false claims (fuzz, no ext deps) | SECURITY.md | N/A | SECURITY.md:35,37 | Claims corrected in SECURITY.md | -- | 2026-06-21 | **Closed** (ec068d0) |
| 16 | SEC-0016 | Medium | 20 | No authentication for TCP/UDP network sinks | tcp_sink.zig, udp_sink.zig | CWE-306 / A07:2021 | tcp_sink.zig (all), udp_sink.zig (all) | mTLS/auth requires significant effort | -- | -- | **Won't Do** |
| 17 | SEC-0017 | Medium | 20 | No CI build/test pipeline active | .gitlab-ci.yml | N/A | .gitlab-ci.yml:5 | Build, test, format-check stages added | -- | 2026-06-21 | **Closed** (ec068d0) |
| 18 | SEC-0018 | Low | 16 | HTTP status check too permissive | http_sink.zig | CWE-754 / A04:2021 | http_sink.zig:177 | Proper status line parsing at index 9 | -- | 2026-09-19 | **Closed** (0ed8afe) |
| 19 | SEC-0019 | Low | 12 | Journald fallback unsanitized stderr | journald.zig | CWE-117 / A09:2021 | journald.zig:140-150 | Buffered output with sanitizeOutput | -- | 2026-09-19 | **Closed** (0ed8afe) |
| 20 | SEC-0020 | Medium | 24 | Windows Event Log stderr fallback missing sanitizeOutput() | windows_eventlog.zig | CWE-117 / A03:2021 | windows_eventlog.zig:107,145 | sanitizeOutput applied to stderr fallback; deprecatedWriter removed | -- | 2026-06-21 | **Closed** (pass 3: buffered sanitized stderr output with sanitizeOutput and sanitizeKey) |
| 21 | SEC-0021 | Low | 12 | Journald stderr fallback unsanitized attribute keys | journald.zig | CWE-117 / A03:2021 | journald.zig:166 | sanitizeKey() applied to stderr fallback attr keys | -- | 2026-09-21 | **Closed** (pass 3: sanitize.sanitizeKey(&stderr_key_buf, attr.key) at journald.zig:166) |
| 22 | SEC-0022 | Low | 12 | Windows Event Log unsanitized attribute keys | windows_eventlog.zig | CWE-117 / A03:2021 | windows_eventlog.zig:113 | sanitizeKey() applied to attr keys | -- | 2026-09-21 | **Closed** (pass 3: sanitize.sanitizeKey(&key_buf, attr.key) at windows_eventlog.zig:113) |
| 23 | SEC-0023 | Low | 8 | Syslog writeSDString no control char escaping | syslog_rfc5424.zig | CWE-117 / A03:2021 | syslog_rfc5424.zig:268-284 | Control chars < 0x20 escaped as \\xHH, tab preserved per RFC5424 | -- | 2026-09-21 | **Closed** (pass 3: control chars 0x00-0x08, 0x0a-0x1f escaped as \\xHH via hex_chars lookup; tab preserved) |
| 24 | SEC-0024 | Info | 4 | Gitleaks allowlist incomplete | .gitleaks.toml | CWE-798 / A07:2021 | .gitleaks.toml:8-13 | allowlist entries added for json_logging.zig and accept.zig | -- | Backlog | **Closed** (pass 3: .gitleaks.toml paths extended with json_logging.zig and tests/accept.zig) |
| 25 | SEC-0025 | Medium | 24 | Network sinks skip sanitizeKey on JSON attr keys | tcp_sink.zig, udp_sink.zig, http_sink.zig | CWE-117 / A03:2021 | tcp_sink.zig:212, udp_sink.zig:131, http_sink.zig:238 | sanitize import and sanitizeKey call added in all three sinks' attr loops | -- | 2026-03-24 | **Closed** (pass 4: sanitize.sanitizeKey applied to attr keys in tcp_sink.zig:212, udp_sink.zig:131, http_sink.zig:238) |
| 26 | SEC-0026 | High | 64 | All network sinks transmit cleartext -- no TLS support | tcp_sink.zig, udp_sink.zig, http_sink.zig | CWE-319 / A02:2021 | http_sink.zig:66-69, tcp_sink.zig:75-80, udp_sink.zig:50-55 | Implement TLS wrapper or document prominently | TBD | 2026-04-23 | **Won't Do** (pass 5: TLS implementation exceeds library scope; Zig stdlib TLS still maturing) |
| 27 | SEC-0027 | Medium | 36 | Secrets in message body bypass all redaction | all handlers | CWE-532 / A09:2021 | text_handler.zig:73, redact.zig:45-68 | Limitation documented in API docs and SECURITY.md | -- | 2026-06-22 | **Closed** (pass 5: documented as known limitation) |
| 28 | SEC-0028 | Medium | 36 | HTTP sink does not validate server identity | http_sink.zig | CWE-295 / A02:2021 | http_sink.zig:66-69, 75-80 | Requires TLS with certificate validation | TBD | 2026-06-22 | **Won't Do** (pass 5: blocked by SEC-0026; requires TLS which is Won't Do) |
| 29 | SEC-0029 | Medium | 24 | TCP sink has no authentication mechanism | tcp_sink.zig | CWE-306 / A07:2021 | tcp_sink.zig:27-34 | Add optional auth token/mTLS to TcpOptions | TBD | 2026-06-22 | **Won't Do** (pass 5: blocked by SEC-0026; SEC-0016 same scope already Won't Do) |
| 30 | SEC-0030 | Low | 16 | Sensitive key list incomplete -- missing common patterns | redact.zig | CWE-532 / A09:2021 | redact.zig:15-31 | 16 new patterns added (ssn, credit_card, cvv, session, cookie, bearer, jwt, connection_string, etc.) | -- | 2026-09-21 | **Closed** (pass 5: sensitive_keys expanded from 15 to 31 patterns) |
| 31 | SEC-0031 | Low | 16 | Logger name and source_file not sanitized in text handler | text_handler.zig | CWE-117 / A03:2021 | text_handler.zig:67-69 | sanitizeOutput applied to rec.logger in text handlers | -- | 2026-09-21 | **Closed** (pass 5: logger name sanitized via writeSyslogName in text handlers) |
| 32 | SEC-0032 | Low | 16 | Syslog hostname written raw, bypassing writeSyslogName | syslog_rfc5424.zig | CWE-117 / A03:2021 | syslog_rfc5424.zig:136 vs 141 | hostname now sanitized via writeSyslogName | -- | 2026-09-21 | **Closed** (pass 5: hostname routed through writeSyslogName) |
| 33 | SEC-0033 | Low | 16 | Data race on Level field in setLevel across handlers | text_handler.zig, json_handler.zig, all handlers | CWE-362 / A04:2021 | text_handler.zig:149-151, rotating_file.zig:335-337 | Atomic Value used for level across all 12 handlers | -- | 2026-09-21 | **Closed** (pass 5: non-atomic level fixed across all 12 handlers using atomic Value; combined fix with PERF-031) |
| 34 | SEC-0034 | Medium | 36 | Rotating log files created world-readable (0o600 mode lost in Zig 0.16 migration) | rotating_file.zig | CWE-276,732 / A02:2025 | rotating_file.zig:112 | Re-add explicit `.permissions = 0o600` to createFile | -- | 2026-09-10 | **Open / REGRESSION** (pass 5 fix reverted by fa0de64; #43; APPSEC-01) |
| 35 | SEC-0035 | Low | 16 | UDP truncation produces malformed JSON | udp_sink.zig | CWE-404 / A09:2021 | udp_sink.zig:80 | Oversized records dropped instead of truncated | -- | 2026-09-21 | **Closed** (pass 5: UDP oversized records dropped with metrics counter instead of truncated) |
| 36 | SEC-0036 | Low | 8 | JSON key collision via duplicate keys or sanitize-to-same-string | json_handler.zig, sanitize.zig | CWE-20 / A03:2021 | sanitize.zig:17-27, json_handler.zig:123-148 | Collision risk documented in sanitize.zig | -- | 2026-09-21 | **Closed** (pass 5: key collision documented as known limitation in sanitize.zig) |
| 37 | SEC-0037 | Medium | 36 | Log path symlink-following / unconstrained absolute writes (SEC-0007 criterion unmet) | rotating_file.zig | CWE-22,59,61 / A01:2025 | rotating_file.zig:89-99,112 | Reject absolute/escaping paths; open relative to base Dir with resolve_beneath; refuse symlinked final component | -- | 2026-09-10 | **Open** (#46; APPSEC-02) |
| 38 | SEC-0038 | Low | 12 | Auto-redaction blind spot for keys longer than 64 bytes | redact.zig | CWE-532 / A09:2025 | redact.zig:81-100 | Scan entire key; remove 64-byte cap and scratch buffer | -- | 2026-12-09 | **Open** (#47; APPSEC-03) |
| 39 | SEC-0039 | Low | 16 | Silent whole-record drop when rendered size exceeds 8KB handler buffer | text_handler.zig, rotating_file.zig | CWE-778,755 / A09,A10:2025 | text_handler.zig:50, rotating_file.zig:271-276 | Size format buffers to MAX_RECORD_SIZE or truncate-with-marker; add dropped/truncated metric | -- | 2026-12-09 | **Open** (#48; APPSEC-04) |
| 40 | SEC-0040 | Low | 16 | CI catalog components pinned to mutable version tags, not commit SHAs | .gitlab-ci.yml | CWE-1357,494 / A06,A08:2025 | .gitlab-ci.yml:11-24 | Pin `@v1.7.1` includes to commit SHAs (or accept risk for first-party catalog) | -- | -- | **Won't Do** (accepted risk: first-party `devnw/ci-catalog`; recorded for visibility) |
| 41 | SEC-0041 | Info | 4 | Vendored thread_pool scripts committed mode 0777 | zig-pkg/ | CWE-732 / A05:2025 | zig-pkg/ (vendored thread_pool snapshot) | Tighten committed file modes; stale snapshots tracked by QUALITY NEW-7 | -- | Backlog | **Open** (informational; cross-ref QUALITY NEW-7) |

---

### Phase 3 Verified Safe (Info -- No Action Required)

| ID | Finding | Verification | Status |
|----|---------|-------------|--------|
| SEC-0020 (verify) | isSensitiveKey checks original key, sanitizeKey for output | Ordering is correct: `isSensitiveKey(attr.key)` at text_handler.zig:108 checks original key before `sanitizeKey` at line 103 writes sanitized form. No bypass possible. | **Verified Safe** |
| SEC-0017 (verify) | fatal_hook atomic access | `getFatalHook()` uses `@atomicLoad(.acquire)` at logger.zig:35; `setFatalHook()` uses `@atomicStore(.release)` at logger.zig:40. Correctly implemented. | **Verified Safe** |
| SEC-0019 (verify) | CI Zig binary SHA-256 verification | CI pipeline correctly verifies Zig binary integrity via SHA-256 hash check. | **Verified Safe** |

---

## Detailed Findings

---

### SEC-0001: HTTPS URLs accepted but sent over plaintext TCP

- **Severity:** Critical
- **Risk Score:** 80 (Impact: 4 x Likelihood: 5 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internet-facing
- **CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)
- **OWASP:** A02:2021 Cryptographic Failures

**Summary:** The HTTP sink parses `https://` URLs, sets `is_https = true` and `port = 443`, but `sendHttp()` always opens a raw TCP connection. No TLS handshake occurs. Users who configure HTTPS endpoints believe their log data is encrypted when it is not.

**Impact:** Log data -- potentially containing PII, session tokens, internal hostnames, and application state -- is transmitted in cleartext over the network. A passive network observer or MITM attacker can read and modify all log traffic. Because the URL says `https://`, the user has no indication that encryption is absent.

**Likelihood:** Trivially exploitable. Any network observer between the application and the log endpoint can intercept traffic. No authentication or special access required. Pre-auth, remote.

**Evidence:**

- `src/sinks/http_sink.zig:64-65` -- `is_https = true` set for HTTPS URLs
- `src/sinks/http_sink.zig:131-141` -- `sendHttp()` uses `std.net.tcpConnectToAddress()` (plain TCP) regardless of `is_https`
- `src/sinks/http_sink.zig:93-104` -- `is_https` stored in Context but never referenced in send path

```zig
// http_sink.zig:131-141 -- always plain TCP, is_https ignored
fn sendHttp(self: *Context, data: []const u8) bool {
    const address = std.net.Address.parseIp4(self.host, self.port) catch {
        return false;
    };
    const stream = std.net.tcpConnectToAddress(address) catch {
        return false;
    };
    defer stream.close();
    // ... sends HTTP request over plain TCP
```

**Attack Scenario:** An application configures `HttpOptions{ .url = "https://logs.corp.example.com/ingest" }`. The developer believes TLS protects the log stream. An attacker on the same network segment captures all log data in plaintext, including any sensitive attributes, internal hostnames, user identifiers, and error details.

**Fix Guidance:**

1. When `is_https == true`, perform a TLS handshake using `std.crypto.tls.Client` or an imported TLS library after TCP connect.
2. Validate server certificates against system CA store.
3. If TLS support is not yet implemented, **reject `https://` URLs at `Context.init()` time** with a clear error so users are not silently downgraded to plaintext.

**Acceptance Criteria:**

- [ ] `Context.init()` with an `https://` URL either establishes a TLS connection or returns a compile-time or runtime error
- [ ] Plain TCP is used only for `http://` URLs
- [ ] A test verifies that `is_https == true` triggers TLS or error

**How to Verify:** Capture traffic with `tcpdump -i lo -w /tmp/slog.pcap -s0 port 443`, send a log record to an HTTPS endpoint, and verify the pcap shows a TLS handshake (not plaintext HTTP).

**SLA:** 7 days (2026-03-30)

---

### SEC-0002: stderrHandler returns dangling pointer (use-after-free)

- **Severity:** Critical
- **Risk Score:** 60 (Impact: 5 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (any caller of convenience API)
- **CWE:** CWE-416 (Use After Free)
- **OWASP:** A04:2021 Insecure Design

**Summary:** `stderrHandler()` creates a local `var ctx` on the stack, passes `&ctx` to `text.init()` which stores the pointer as `*anyopaque`, then returns a struct containing a *copy* of `ctx`. The handler's internal pointer still references the now-dead stack frame. Any subsequent use of the returned handler dereferences a dangling pointer.

**Impact:** Undefined behavior including data corruption, crashes, or potentially controllable memory corruption. Since this is the primary convenience API, it affects the most common usage pattern.

**Likelihood:** Requires a caller to use the convenience API (likely for new users). The UB may not always manifest depending on stack reuse patterns, but it is guaranteed to be incorrect. Scored at 3 because the bug requires the specific calling pattern, but that pattern is the documented/intended usage.

**Evidence:**

- `src/slogz.zig:107-117` -- `stderrHandler` creates local `ctx`, returns struct with copy

```zig
// slogz.zig:107-117
pub fn stderrHandler(level: Level) struct { ctx: text.Context, handler: Handler } {
    var ctx = text.Context.init(          // ctx is on the stack
        std.fs.File.stderr().deprecatedWriter().any(),
        level,
        Clock.system(),
    );
    return .{
        .ctx = ctx,                        // copied to return value (new address)
        .handler = text.init(&ctx),        // handler.ctx points to OLD stack address
    };
}
```

- `src/slogz.zig:120-130` -- identical pattern in `stderrJsonHandler`

**Attack Scenario:** A user follows the convenience API pattern. The returned `handler` field contains a `ctx` pointer to a dead stack frame. When a log record is written, the handler dereferences the dangling pointer. Depending on what has been allocated in that stack region, this causes crashes or data corruption. In a security-sensitive context, controlled stack manipulation could exploit this for code execution.

**Fix Guidance:** Either:

1. Return only the `Context` and require the caller to call `init(&result.ctx)` after assignment, or
2. Take the address of the returned struct's `.ctx` field after it is placed at its final address, or
3. Accept an allocator and heap-allocate the context.

**Acceptance Criteria:**

- [ ] `stderrHandler()` returns a handler whose `ctx` pointer is valid for the lifetime of the returned context
- [ ] A test exercises the returned handler by writing a record and verifying correct output (no UB under AddressSanitizer)
- [ ] Same fix applied to `stderrJsonHandler()`

**How to Verify:** Compile with `-fsanitize=address` (or Zig's equivalent safety checks) and call `stderrHandler().handler.handle(&rec)`. Under current code, this should trigger a use-after-free detection.

**SLA:** 7 days (2026-03-30)

---

### SEC-0003: HTTP header injection via unvalidated custom headers

- **Severity:** High
- **Risk Score:** 64 (Impact: 4 x Likelihood: 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internet-facing (if attacker controls header values)
- **CWE:** CWE-113 (Improper Neutralization of CRLF Sequences in HTTP Headers)
- **OWASP:** A03:2021 Injection

**Summary:** The HTTP sink writes user-supplied header names and values directly to the TCP stream without any validation. Headers containing `\r\n` allow HTTP response splitting / request smuggling.

**Impact:** An attacker who can influence header values (e.g., through configuration injection, environment variables, or programmatic API) can inject arbitrary HTTP headers or even inject a second HTTP request, potentially poisoning caches or manipulating upstream log aggregators.

**Likelihood:** Requires attacker to control header configuration values. In many deployments, headers are set from environment variables or config files, which are common injection vectors. Scored at 4 because the attack requires specific control over configuration.

**Evidence:**

- `src/sinks/http_sink.zig:157-161` -- Headers written directly to stream with no validation

```zig
// http_sink.zig:157-161
for (self.options.headers) |header| {
    _ = stream.write(header.name) catch return false;
    _ = stream.write(": ") catch return false;
    _ = stream.write(header.value) catch return false;   // no CRLF check
    _ = stream.write("\r\n") catch return false;
}
```

**Fix Guidance:**

1. Validate both header names and values in `HttpOptions` or at `Context.init()` time.
2. Reject any header name/value containing `\r`, `\n`, or other control characters (bytes < 0x20 except HT).
3. Validate header names match the RFC 7230 token rule.

**Acceptance Criteria:**

- [ ] Header names and values are validated against RFC 7230 at init or write time
- [ ] Headers containing CR, LF, or NUL are rejected with an error
- [ ] Test verifies that malicious headers are rejected

**How to Verify:** Create an `HttpOptions` with a header value containing `\r\nX-Injected: evil` and verify it is rejected.

**SLA:** 30 days (2026-04-22)

---

### SEC-0004: TCP/UDP sinks transmit in plaintext only

- **Severity:** High
- **Risk Score:** 60 (Impact: 4 x Likelihood: 3 x 4 + rounding)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal network (typical deployment)
- **CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)
- **OWASP:** A02:2021 Cryptographic Failures

**Summary:** TCP and UDP sinks have no TLS/DTLS support. All log data is transmitted in plaintext. Unlike the HTTP sink (SEC-0001), these sinks do not claim to support encryption, but they also provide no option for it.

**Impact:** Log data on the network is readable by any observer. In environments with compliance requirements (PCI-DSS, HIPAA, SOC2), plaintext log transport may violate data-in-transit encryption requirements.

**Likelihood:** Scored at 3 -- requires network position to intercept. Lower than SEC-0001 because no false sense of security exists (no `tls://` option claimed).

**Evidence:**

- `src/sinks/tcp_sink.zig:65-78` -- `connect()` uses raw TCP only
- `src/sinks/udp_sink.zig:48-52` -- raw UDP socket with no encryption

**Fix Guidance:**

1. Add an optional TLS wrapper for TCP sink (e.g., `TcpOptions.tls: bool = false`).
2. Document that UDP sink is inherently plaintext and should only be used on trusted networks.
3. At minimum, add prominent documentation warnings about plaintext transmission.

**Acceptance Criteria:**

- [ ] TCP sink supports optional TLS via configuration
- [ ] Documentation clearly states plaintext risk for both sinks
- [ ] UDP sink documentation recommends trusted network only

**SLA:** 30 days (2026-04-22)

---

### SEC-0005: isSensitiveKey() is dead code -- no auto-redaction occurs

- **Severity:** High
- **Risk Score:** 64 (Impact: 4 x Likelihood: 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** All handlers (internet-facing if logs are shipped)
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures

**Summary:** `redact.zig` defines `isSensitiveKey()` with a comprehensive list of sensitive key patterns (password, token, api_key, etc.), but no handler ever calls this function. Attributes with sensitive key names are logged in plaintext unless the caller explicitly uses `Attr.secret()`. The auto-redaction feature is fully implemented but completely unwired.

**Impact:** Applications that log attributes like `Attr.string("password", user_password)` or `Attr.string("api_key", key)` will have these values written in plaintext to all log outputs. This is the exact scenario `isSensitiveKey()` was designed to prevent.

**Likelihood:** High. Developers commonly log request parameters, configuration values, and error contexts that include sensitive keys. The existence of `isSensitiveKey()` suggests this was anticipated. The fact that it is unwired means the safety net does not function. Scored at 4 because it requires a developer to use `Attr.string()` instead of `Attr.secret()` for sensitive data, which is the natural/common pattern.

**Evidence:**

- `src/util/redact.zig:34-48` -- `isSensitiveKey()` defined and tested
- No call to `isSensitiveKey` in any handler (text_handler.zig, json_handler.zig, syslog_rfc5424.zig, rotating_file.zig, journald.zig)

**Fix Guidance:**

1. In each handler's `writeAttr`/`writeValue` function, check `redact.isSensitiveKey(attr.key)` before writing the value.
2. If the key is sensitive, output `[REDACTED]` instead of the actual value.
3. Consider making auto-redaction configurable (opt-out rather than opt-in) for maximum safety.

**Acceptance Criteria:**

- [ ] `Attr.string("password", "secret123")` is redacted to `password=[REDACTED]` in output
- [ ] All handlers (text, JSON, syslog, rotating_file, journald) call `isSensitiveKey()`
- [ ] Test verifies auto-redaction for each handler type

**How to Verify:** Log `Attr.string("api_key", "test_value")` through each handler and verify the output contains `[REDACTED]` instead of `test_value`.

**SLA:** 30 days (2026-04-22)

---

### SEC-0006: Log injection via unsanitized messages -- REOPENED

- **Severity:** High
- **Risk Score:** 64 (Impact: 4 x Likelihood: 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internet-facing (if messages contain user input)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection
- **Status:** **Closed / Implemented** (pass 3)
- **Issue:** [#36 (confidential)](https://gitlab.com/devnw/zig/slog/-/issues/36) -- Closed

**Summary:** The text handler, syslog handler, journald handler, and windows_eventlog handler were fixed in pass 1 (commit 0ed8afe). In pass 3, rotating_file.zig was fixed to use `sanitize.sanitizeOutput()` on messages (line 298), `sanitize.sanitizeKey()` on attribute keys (line 305), and shared `writeTextValue()` for attribute values (line 312).

**Prior status claimed:** "Closed (0ed8afe) -- sanitize.sanitizeOutput() applied in text, syslog, rotating_file, journald"
**Actual status:** rotating_file.zig lines 298, 303, and 316 contain NO sanitization calls.

**Impact:** Log forgery, SIEM evasion, audit trail manipulation via rotating log files. Rotating files are a primary production handler for disk-based logging and are commonly shipped to SIEMs and compliance archives.

**Likelihood:** High. Log messages frequently contain user-supplied data (request paths, usernames, error messages from external services). Scored at 4 because many applications pass user-controlled strings into log messages.

**Evidence:**

- `src/handlers/rotating_file.zig:298` -- `writer.writeAll(rec.message)` (NO sanitizeOutput)
- `src/handlers/rotating_file.zig:303` -- `writer.writeAll(attr.key)` (NO sanitizeKey)
- `src/handlers/rotating_file.zig:316` -- `.str => |s| try writer.writeAll(s)` (NO sanitizeOutput on string values)

```zig
// rotating_file.zig:298 -- message NOT sanitized
writer.writeAll(rec.message) catch return error.WriteFailed;

// rotating_file.zig:300-306 -- attr keys NOT sanitized
for (rec.attrs) |attr| {
    writer.writeByte(' ') catch return error.WriteFailed;
    writer.writeAll(attr.key) catch return error.WriteFailed;  // NO sanitizeKey
    writer.writeByte('=') catch return error.WriteFailed;
    writeValue(writer, attr.value) catch return error.WriteFailed;
}

// rotating_file.zig:316 -- string values NOT sanitized
.str => |s| try writer.writeAll(s),  // NO sanitizeOutput
```

**Comparison -- all other handlers are fixed:**

- `text_handler.zig:73`: `sanitize.sanitizeOutput(writer, rec.message)` -- FIXED
- `text_handler.zig:103`: `sanitize.sanitizeKey(&key_buf, attr.key)` -- FIXED
- `text_handler.zig:122`: `sanitize.sanitizeOutput(writer, s)` for strings -- FIXED
- `syslog_rfc5424.zig:189`: `sanitize.sanitizeOutput(writer, rec.message)` -- FIXED
- `journald.zig:151`: `sanitize.sanitizeOutput(stderr_writer, rec.message)` -- FIXED
- `windows_eventlog.zig:107`: `sanitize.sanitizeOutput(writer, rec.message)` -- FIXED

**Fix Guidance:**

1. Replace `writer.writeAll(rec.message)` with `sanitize.sanitizeOutput(writer, rec.message)` at line 298.
2. Replace `writer.writeAll(attr.key)` with `sanitize.sanitizeKey()` usage at line 303.
3. Replace `.str => |s| try writer.writeAll(s)` with `.str => |s| try sanitize.sanitizeOutput(writer, s)` at line 316.

**Acceptance Criteria:**

- [ ] `rotating_file.zig` calls `sanitize.sanitizeOutput()` on `rec.message`
- [ ] `rotating_file.zig` calls `sanitize.sanitizeKey()` on attribute keys
- [ ] `rotating_file.zig` calls `sanitize.sanitizeOutput()` on string attribute values
- [ ] Test verifies injection attempt produces single log line in rotating file output

**SLA:** 30 days (2026-04-23)

---

### SEC-0007: Path traversal in rotating file handler

- **Severity:** High
- **Risk Score:** 48 (Impact: 4 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (requires configuration control)
- **CWE:** CWE-22 (Improper Limitation of a Pathname to a Restricted Directory)
- **OWASP:** A01:2021 Broken Access Control

**Summary:** The rotating file handler accepts an arbitrary path from `RotationOptions.path` without validation. It creates directories with `makePath` and creates/renames files using `std.fs.cwd()`. Paths containing `../` can write log files (and create directories) outside the intended log directory.

**Impact:** If an attacker can influence the log path configuration, they can write files to arbitrary locations on the filesystem, potentially overwriting critical files or creating files in sensitive directories.

**Likelihood:** Requires attacker control of the `path` configuration value. In many deployments this comes from environment variables or config files. Scored at 3 because it requires configuration injection.

**Evidence:**

- `src/handlers/rotating_file.zig:69-84` -- `openFile()` uses path directly

```zig
// rotating_file.zig:69-84
fn openFile(self: *Context) !void {
    const path = self.options.path;
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.cwd().makePath(dir) catch {};  // creates arbitrary dirs
    }
    self.file = std.fs.cwd().createFile(path, .{  // creates file at arbitrary path
        .truncate = false,
    }) catch |err| { ... };
```

**Fix Guidance:**

1. Validate `path` at `Context.init()` time: reject paths containing `..` components.
2. Resolve the path to an absolute canonical form and verify it is within the expected log directory.
3. Consider using `openDirAbsolute` with restricted options instead of `cwd()`.

**Acceptance Criteria:**

- [ ] Paths containing `..` are rejected at init time with an error
- [ ] Symlinks in the path do not allow escaping the intended directory
- [ ] Test verifies path traversal attempt is rejected

**SLA:** 30 days (2026-04-22)

---

### SEC-0008: Supply chain risk -- spice dependency on floating main branch

- **Severity:** High
- **Risk Score:** 48 (Impact: 4 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Build-time (supply chain)
- **CWE:** CWE-1357 (Reliance on Insufficiently Trustworthy Component)
- **OWASP:** A06:2021 Vulnerable and Outdated Components
- **Status:** **Closed (resolved by removal)** -- the `spice` dependency was deleted entirely (commit `97c5c59`) and replaced by `thread_pool`, pinned by commit SHA + content hash in `build.zig.zon`. The prior Blocked status (awaiting an upstream spice tagged release) is obsolete. GitLab issue [#29](https://gitlab.com/devnw/zig/slog/-/issues/29) closed with evidence. See GAP_ANALYSIS_RESOLVED.md.

**Summary:** The `spice` dependency in `build.zig.zon` tracked the `main` branch of `gitlab.com/devnw/zig/spice` instead of a pinned tagged release. **Resolved by removal:** `spice` is gone from `build.zig.zon`; the remaining deps (`json`, `thread_pool`) are pinned by `git+...#<commit-sha>` plus content `hash`. The original analysis follows for the record.

**Impact:** A compromised or accidentally broken main branch in the spice repository could inject malicious or buggy code into slog builds. The hash must be manually updated, but the URL pattern encourages fetching from an unstable branch.

**Likelihood:** Requires compromise of the spice repository or an accidental breaking change on main. Scored at 3 because this is an internal dependency (same org), but the pattern is still risky.

**Evidence:**

- `build.zig.zon:19-22`

```zon
.spice = .{
    .url = "https://gitlab.com/devnw/zig/spice/-/archive/main/spice-main.tar.gz",
    .hash = "spice-0.0.0-HnDb58jJAACojBd1dquGT-Ngc6TORlC6izlAKf0f4Rno",
},
```

- Compare with json dependency on line 16-17 which correctly uses `/v0.1.0/`

**Fix Guidance:**

1. Tag a release of the spice repository.
2. Update `build.zig.zon` to reference the tagged release URL (e.g., `.../archive/v0.1.0/spice-v0.1.0.tar.gz`).
3. Update the hash to match the tagged archive.

**Acceptance Criteria:**

- [ ] `spice` dependency URL references a tagged release, not `main`
- [ ] Hash is updated to match the tagged release archive

**SLA:** 30 days (2026-04-22)

---

### SEC-0009: Rotating file handler missing isSensitiveKey() auto-redaction -- REOPENED

- **Severity:** High
- **Risk Score:** 48 (Impact: 4 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (log files on disk)
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures
- **Status:** **Closed / Implemented** (pass 3)
- **Issue:** [#36 (confidential)](https://gitlab.com/devnw/zig/slog/-/issues/36) -- Closed

**Summary:** In pass 3, rotating_file.zig now calls `redact.isSensitiveKey(attr.key)` in the attribute loop (line 309) and outputs `redact.REDACTED` for matching keys, consistent with all other handlers. The `.secret` value type also remains correctly handled via the shared `writeTextValue()` function.

**Prior status claimed:** "Closed (05c6a16) -- rotating_file.zig -- writeValue with .secret handling"
**Actual status:** `.secret` type handling works, but `isSensitiveKey()` auto-redaction is completely absent. Every other handler checks `isSensitiveKey()` before writing attribute values.

**Impact:** Applications that log attributes like `Attr.string("password", user_password)` or `Attr.string("api_key", key)` will have these values written in plaintext to rotating log files on disk. Every other handler auto-redacts these. The rotating file handler is the sole exception, making it a silent credential exposure vector.

**Likelihood:** Scored at 3 because it requires use of the rotating file handler with sensitive-key-named attributes using `Attr.string()` instead of `Attr.secret()`. This is the natural/common pattern, however.

**Evidence:**

- `src/handlers/rotating_file.zig:300-306` -- attribute loop with NO isSensitiveKey check

```zig
// rotating_file.zig:300-306 -- NO isSensitiveKey() check
for (rec.attrs) |attr| {
    writer.writeByte(' ') catch return error.WriteFailed;
    writer.writeAll(attr.key) catch return error.WriteFailed;
    writer.writeByte('=') catch return error.WriteFailed;
    writeValue(writer, attr.value) catch return error.WriteFailed;
    // password=hunter2 is written in plaintext
}
```

**Comparison -- all other handlers check isSensitiveKey():**

- `text_handler.zig:108`: `if (redact.isSensitiveKey(attr.key))` -- PRESENT
- `json_handler.zig:145`: `if (redact.isSensitiveKey(attr.key))` -- PRESENT
- `syslog_rfc5424.zig:225`: `if (redact.isSensitiveKey(attr.key))` -- PRESENT
- `journald.zig:128,154`: `if (redact.isSensitiveKey(attr.key))` -- PRESENT
- `windows_eventlog.zig:112`: `if (redact.isSensitiveKey(attr.key))` -- PRESENT
- `rotating_file.zig`: **ABSENT**

**Note:** The `.secret` value type IS correctly handled at line 341: `.secret => try writer.writeAll(redact.REDACTED)`. The gap is specifically the `isSensitiveKey()` auto-redaction for attributes created with `Attr.string()` that happen to have sensitive key names.

**Fix Guidance:**

1. Add `if (redact.isSensitiveKey(attr.key))` check in the attribute loop at line 300-306.
2. If the key is sensitive, output `redact.REDACTED` instead of calling `writeValue()`.

**Acceptance Criteria:**

- [ ] `Attr.string("password", "hunter2")` outputs `password=[REDACTED]` in rotating file output
- [ ] `Attr.string("api_key", "sk_live_abc")` outputs `api_key=[REDACTED]` in rotating file output
- [ ] `Attr.secret("key", "value")` continues to output `key=[REDACTED]` (existing behavior preserved)
- [ ] Test verifies isSensitiveKey auto-redaction in rotating file handler

**SLA:** 30 days (2026-04-23)

---

### SEC-0010: Text handler string values unescaped (log injection via attribute values)

- **Severity:** Medium
- **Risk Score:** 48 (Impact: 3 x Likelihood: 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internet-facing (if attribute values contain user input)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection

**Summary:** The text handler writes string attribute values with optional quoting for spaces/equals, but does not escape newlines or control characters. An attacker-controlled attribute value can inject fake log lines.

**Impact:** Similar to SEC-0006 but via attribute values rather than message text. Enables log line injection, SIEM confusion, and audit trail manipulation.

**Likelihood:** Slightly lower than SEC-0006 because attribute values are less commonly user-controlled than messages. Scored at 4 because structured logging encourages logging request parameters as attributes.

**Evidence:**

- `src/handlers/text_handler.zig:113-119`

```zig
// text_handler.zig:113-119
.str => |s| {
    const needs_quote = std.mem.indexOfScalar(u8, s, ' ') != null or
        std.mem.indexOfScalar(u8, s, '=') != null;
    if (needs_quote) try writer.writeByte('"');
    try writer.writeAll(s);  // newlines/control chars pass through
    if (needs_quote) try writer.writeByte('"');
},
```

**Fix Guidance:** Escape `\n`, `\r`, `\\`, `"`, and control characters within string values before output.

**Acceptance Criteria:**

- [ ] String values containing `\n` are escaped in output
- [ ] Test verifies no raw newline in formatted output

**SLA:** 90 days (2026-06-21)

---

### SEC-0011: Global fatal_hook race condition

- **Severity:** Medium
- **Risk Score:** 32 (Impact: 4 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Admin-only (requires concurrent fatal logging + hook modification)
- **CWE:** CWE-362 (Concurrent Execution Using Shared Resource with Improper Synchronization)
- **OWASP:** A04:2021 Insecure Design

**Summary:** `fatal_hook` is a global mutable variable (`pub var`) accessed without any synchronization. If one thread writes `fatal_hook` while another thread reads it during a fatal log event, the resulting function pointer could be corrupt, leading to a jump to an invalid address.

**Impact:** Crash or potentially controlled code execution if the race produces a valid but attacker-chosen function pointer.

**Likelihood:** Low in practice -- requires concurrent fatal logging and hook modification, which is a rare sequence. Scored at 2.

**Evidence:**

- `src/logger.zig:26` -- `pub var fatal_hook: *const fn (*const Record) void = defaultFatalHook;`
- `src/logger.zig:148-149` -- Read of `fatal_hook` without lock

**Fix Guidance:** Use `std.atomic.Value(*const fn (*const Record) void)` for atomic read/write, or protect with a module-level mutex.

**Acceptance Criteria:**

- [ ] `fatal_hook` read/write uses atomic operations
- [ ] Concurrent read+write does not produce UB

**SLA:** 90 days (2026-06-21)

---

### SEC-0012: Secret values stored as plaintext in memory

- **Severity:** Medium
- **Risk Score:** 24 (Impact: 3 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (requires memory access)
- **CWE:** CWE-316 (Cleartext Storage of Sensitive Information in Memory)
- **OWASP:** A02:2021 Cryptographic Failures

**Summary:** The `Secret` struct stores its value as a plain `[]const u8` slice. While handlers correctly output `[REDACTED]`, the plaintext value remains in memory and could be exposed through core dumps, memory scanners, or debugger access.

**Impact:** Limited -- requires local access to process memory. Secrets are correctly redacted in all log output paths (except rotating_file per SEC-0009).

**Likelihood:** Requires process memory access (debugger, core dump, `/proc/pid/mem`). Scored at 2.

**Evidence:**

- `src/value.zig:12-22`

```zig
pub const Secret = struct {
    value: []const u8,  // plaintext in memory
    // ...
};
```

**Fix Guidance:**

1. Document this as a known limitation in API docs.
2. Consider zeroing the value after the Secret is consumed, though Zig's optimizer may elide the zeroing.
3. For defense-in-depth, consider XOR-masking the value with a random key generated at Secret.init time.

**Acceptance Criteria:**

- [ ] Limitation is documented in API documentation
- [ ] Consider implementing memory scrubbing if feasible

**SLA:** 90 days (2026-06-21)

---

### SEC-0013: Async handler drops secret attributes silently

- **Severity:** Medium
- **Risk Score:** 24 (Impact: 3 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal (logging pipeline)
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures

**Summary:** The async handler's `QueuedRecord.fromRecord()` serializes attributes into a flat buffer. The `.secret` type falls into the `else => ""` branch, so secret attributes are serialized as empty strings. When the worker thread reconstructs the record, it uses `attrs = &.{}` (empty), dropping all attributes entirely (including secrets). The net effect is that secret attributes are invisible in async output, but the serialization path could expose secret values if the implementation is "fixed" to include them without also preserving the `.secret` type tag.

**Impact:** Currently, secrets are dropped (not exposed) in async logging. However, a naive fix to "include all attributes" could expose secrets if the type tag is lost during serialization. The current behavior is a defense-in-depth failure.

**Likelihood:** Low direct exploitability. Scored at 2 because the current behavior accidentally protects secrets by dropping them.

**Evidence:**

- `src/internal/queue.zig:72-81` -- `fromRecord()` serializes value types
- `src/handlers/async_handler.zig:93` -- `.attrs = &.{}` in reconstructed record

**Fix Guidance:**

1. When serializing attributes in `QueuedRecord`, preserve the type tag for each value.
2. For `.secret` values, serialize only the `[REDACTED]` marker, never the plaintext.
3. When deserializing in the worker thread, reconstruct attributes with proper types.

**Acceptance Criteria:**

- [ ] Async handler output includes all attributes
- [ ] Secret attributes are redacted in async output (not exposed, not dropped)

**SLA:** 90 days (2026-06-21)

---

### SEC-0014: Gitleaks blanket exclusion of examples and tests directories

- **Severity:** Medium
- **Risk Score:** 24 (Impact: 3 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Build-time / repository
- **CWE:** CWE-798 (Use of Hard-coded Credentials)
- **OWASP:** A07:2021 Identification and Authentication Failures

**Summary:** The `.gitleaks.toml` configuration excludes the entire `examples/` and `tests/` directories from secret scanning. While this is intended to allow demo credentials in `secret_redaction.zig`, it also exempts any accidentally committed real secrets in any file within those directories.

**Impact:** Real secrets accidentally committed to test or example files would not be detected by gitleaks. The broad exclusion pattern (`examples/.*` and `tests/.*`) covers all current and future files.

**Likelihood:** Low -- requires accidental secret commit to test/example files. Scored at 2.

**Evidence:**

- `.gitleaks.toml:9-12`

```toml
[allowlist]
paths = [
    '''examples/.*''',
    '''tests/.*''',
]
```

**Fix Guidance:** Narrow the exclusion to only the specific file(s) that contain intentional demo credentials:

```toml
paths = [
    '''examples/secret_redaction\.zig''',
]
```

**Acceptance Criteria:**

- [ ] Gitleaks exclusion covers only specific demo files, not entire directories
- [ ] `tests/` directory is scanned by gitleaks

**SLA:** 90 days (2026-06-21)

---

### SEC-0015: SECURITY.md contains false claims about fuzz testing and dependency posture

- **Severity:** Medium
- **Risk Score:** 20 (Impact: 2 x Likelihood: 5 x 2)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** N/A (documentation)
- **CWE:** N/A
- **OWASP:** N/A

**Summary:** SECURITY.md makes two false claims: (1) "Fuzz testing for parser inputs" -- no fuzz tests exist anywhere in the repository. (2) "No external C dependencies (stdlib only)" -- libsystemd (a C library) is linked when journald is enabled, and external Zig packages (json, spice) are fetched.

**Impact:** Users and auditors relying on SECURITY.md for security posture assessment are misled. This undermines trust if discovered during a security audit.

**Likelihood:** Certain to be encountered by anyone reading SECURITY.md. Scored high on likelihood but low on impact.

**Evidence:**

- `SECURITY.md:35` -- "No external C dependencies (stdlib only)"
- `SECURITY.md:37` -- "Fuzz testing for parser inputs"
- No fuzz test files exist in the repository
- `build.zig.zon:14-23` -- external dependencies exist

**Fix Guidance:**

1. Remove the fuzz testing claim or implement fuzz testing.
2. Update the dependency claim to: "No external C dependencies in default configuration (libsystemd optional for journald feature). External Zig dependencies: json, spice."

**Acceptance Criteria:**

- [ ] All claims in SECURITY.md are accurate
- [ ] Either fuzz tests exist or the claim is removed

**SLA:** 90 days (2026-06-21)

---

### SEC-0016: No authentication mechanism for TCP/UDP network sinks

- **Severity:** Medium
- **Risk Score:** 20 (Impact: 2 x Likelihood: 5 x 2)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal network
- **CWE:** CWE-306 (Missing Authentication for Critical Function)
- **OWASP:** A07:2021 Identification and Authentication Failures

**Summary:** TCP and UDP sinks connect and send data without any authentication mechanism. Any network endpoint accepting connections on the configured port will receive log data. There is no support for mTLS, API keys, or any other authentication.

**Impact:** In a compromised network, an attacker could redirect log traffic to a rogue endpoint by DNS poisoning or ARP spoofing, capturing all log data. Also, the log aggregator has no way to verify the identity of the log source.

**Likelihood:** Requires network-level attack or misconfiguration. Common in many logging setups but the risk is well-understood.

**Evidence:**

- `src/sinks/tcp_sink.zig` -- no authentication options in `TcpOptions`
- `src/sinks/udp_sink.zig` -- no authentication options in `UdpOptions`

**Fix Guidance:**

1. Document the lack of authentication as a known limitation.
2. Add optional TLS client certificate (mTLS) support for TCP sink.
3. Consider adding an optional `Authorization` or custom auth header for HTTP sink.

**Acceptance Criteria:**

- [ ] Documentation clearly states the authentication limitation
- [ ] TCP sink supports optional mTLS (longer term)

**SLA:** 90 days (2026-06-21)

---

### SEC-0017: No CI build/test pipeline active

- **Severity:** Medium
- **Risk Score:** 20 (Impact: 2 x Likelihood: 5 x 2)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Development pipeline
- **CWE:** N/A
- **OWASP:** N/A

**Summary:** The `.gitlab-ci.yml` only includes security scanning, SBOM, and release stages. There is no build or test stage. A stale comment claims Zig 0.15 is not yet released, but it is. The 168 unit tests only run locally.

**Impact:** Code changes can be merged without automated test execution. Regressions, including security regressions, can reach the main branch undetected.

**Evidence:**

- `.gitlab-ci.yml:5` -- "NOTE: Build/test skipped - requires Zig 0.15.x which is not yet released."
- `.gitlab-ci.yml:37-40` -- Only stages: security, sbom, release

**Fix Guidance:** Add a `build` stage running `zig build test` with a Zig 0.15+ container image.

**Acceptance Criteria:**

- [ ] CI pipeline includes a job running `zig build test`
- [ ] Pipeline fails on test failure
- [ ] Stale Zig version comment is removed

**SLA:** 90 days (2026-06-21)

---

### SEC-0018: HTTP status check too permissive (" 2" substring match)

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal (HTTP sink)
- **CWE:** CWE-754 (Improper Check for Unusual or Exceptional Conditions)
- **OWASP:** A04:2021 Insecure Design

**Summary:** The HTTP sink checks for a successful response by searching for the substring `" 2"` anywhere in the response. This matches legitimate 2xx statuses but could also match other content in the response body or headers (e.g., a header containing " 2").

**Impact:** Low -- a false positive match means the sink thinks it succeeded when the server returned an error. Log data may be silently lost.

**Likelihood:** Requires a specific response pattern. Low in practice.

**Evidence:**

- `src/sinks/http_sink.zig:177`

```zig
if (std.mem.indexOf(u8, status_line, " 2")) |_| {
    return true;
}
```

**Fix Guidance:** Parse the HTTP/1.1 status line properly: check that bytes 9-12 of the response are a 3-digit code starting with `2`.

**Acceptance Criteria:**

- [ ] Status code is parsed from the correct position in the HTTP response line
- [ ] Only actual 2xx codes are treated as success

**SLA:** 180 days (2026-09-19)

---

### SEC-0019: Journald fallback writes unsanitized data to stderr

- **Severity:** Low
- **Risk Score:** 12 (Impact: 2 x Likelihood: 3 x 2)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (stderr output)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures

**Summary:** The journald handler's stderr fallback (which is currently the only active code path since sd_journal_sendv is not called) writes `rec.message` and attribute values directly to stderr without sanitization. This is a subset of SEC-0006 but specific to the journald handler.

**Impact:** Log injection via stderr output. Lower severity because journald output is typically consumed locally.

**Likelihood:** Requires user-controlled message content reaching the journald handler. Scored at 3 because it is the same vector as SEC-0006 in a different handler.

**Evidence:**

- `src/handlers/journald.zig:140-150` -- direct write of rec.message and attr values to stderr

```zig
// journald.zig:140-150
const stderr = std.fs.File.stderr().deprecatedWriter();
stderr.print("<{d}>", .{priority}) catch {};
// ...
stderr.print("{s}", .{rec.message}) catch {};  // unsanitized
for (rec.attrs) |attr| {
    stderr.print(" {s}=", .{attr.key}) catch {};
    writeValue(stderr, attr.value) catch {};    // unsanitized
}
```

**Fix Guidance:** Apply the same message sanitization as recommended in SEC-0006 to the journald fallback path.

**Acceptance Criteria:**

- [ ] Journald stderr fallback sanitizes message and attribute values
- [ ] Newlines and control characters are escaped

**SLA:** 180 days (2026-09-19)

---

### SEC-0020: Windows Event Log stderr fallback missing sanitizeOutput()

- **Severity:** Medium
- **Risk Score:** 24 (Impact: 3 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (stderr output)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection
- **Issue:** [#32](https://gitlab.com/devnw/zig/slog/-/issues/32)
- **Gap-ID:** GAP-0036

**Summary:** The Windows Event Log handler's stderr fallback writes `message` directly to stderr at line 136 without applying `sanitize.sanitizeOutput()`. This is the same class of vulnerability as SEC-0019 (journald fallback unsanitized stderr), which was already fixed in commit 0ed8afe. The journald handler now uses `sanitize.sanitizeOutput()` at `journald.zig:151`, but the equivalent fix was not applied to `windows_eventlog.zig`.

**Impact:** Log injection via stderr output. An attacker who can influence log messages can inject fake log lines, corrupt log structure, or manipulate log analysis tools. Medium severity because stderr is typically consumed locally and the Windows Event Log handler is a fallback path.

**Likelihood:** Requires user-controlled message content reaching the windows_eventlog handler. Scored at 2 because the windows_eventlog handler is platform-specific and the stderr fallback is a secondary output path.

**Evidence:**

- `src/handlers/windows_eventlog.zig:136` -- message written directly to stderr without sanitization

```zig
// windows_eventlog.zig:134-136 -- stderr fallback, message not sanitized
// Fallback: write to stderr
const stderr = std.fs.File.stderr().deprecatedWriter();
stderr.print("[{s}] {s}: {s}\n", .{ rec.level.asText(), ctx.source_name, message }) catch {};
```

- Compare with `src/handlers/journald.zig:151` which was fixed (SEC-0019):

```zig
// journald.zig:151 -- correctly uses sanitizeOutput
sanitize.sanitizeOutput(stderr_writer, rec.message) catch {};
```

**Fix Guidance:**

1. Apply `sanitize.sanitizeOutput()` to the message parameter in the stderr fallback, consistent with the journald fix.
2. Use a buffered approach (like journald.zig:143-162) to reduce syscalls and ensure atomic writes.

**Acceptance Criteria:**

- [ ] `windows_eventlog.zig` stderr fallback applies `sanitize.sanitizeOutput()` to message content
- [ ] Control characters (0x00-0x1F) are escaped in stderr fallback output
- [ ] Approach is consistent with the journald fallback fix (SEC-0019)
- [ ] Test verifies log injection attempt produces sanitized output

**SLA:** 90 days (2026-06-21)

---

### SEC-0021: Journald stderr fallback unsanitized attribute keys

- **Severity:** Low
- **Risk Score:** 12 (Impact: 2 x Likelihood: 2 x 3)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (stderr output)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection

**Summary:** The journald handler's stderr fallback path sanitizes messages (line 151) and checks `isSensitiveKey()` (line 154), but does NOT sanitize attribute keys. Line 153 writes `attr.key` via `{s}` format string without calling `sanitize.sanitizeKey()`. The native journald path at line 118 correctly uses `sanitize.sanitizeKey()`.

**Impact:** Limited. Attribute keys containing control characters or newlines could corrupt stderr log structure. In practice, attribute keys are rarely user-controlled and the stderr fallback is a secondary output path.

**Likelihood:** Low. Requires attacker-controlled attribute keys reaching the journald handler's stderr fallback. Scored at 2.

**Evidence:**

- `src/handlers/journald.zig:153` -- `stderr_writer.print(" {s}=", .{attr.key})` (NO sanitizeKey)
- `src/handlers/journald.zig:118` -- native path correctly uses `sanitize.sanitizeKey(&key_buf, attr.key)`

```zig
// journald.zig:152-153 -- stderr fallback, key NOT sanitized
for (rec.attrs) |attr| {
    stderr_writer.print(" {s}=", .{attr.key}) catch {};  // NO sanitizeKey()
```

**Fix Guidance:** Apply `sanitize.sanitizeKey()` to attribute keys in the stderr fallback, consistent with the native journald path.

**Acceptance Criteria:**

- [ ] `journald.zig` stderr fallback applies `sanitize.sanitizeKey()` to attribute keys
- [ ] Consistent with native journald path (line 118)

**SLA:** 180 days (2026-09-21)

---

### SEC-0022: Windows Event Log unsanitized attribute keys

- **Severity:** Low
- **Risk Score:** 12 (Impact: 2 x Likelihood: 2 x 3)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (Windows Event Log / stderr output)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection

**Summary:** The Windows Event Log handler writes attribute keys without sanitization. Line 111 uses `writer.print(" {s}=", .{attr.key})` without calling `sanitize.sanitizeKey()`. The handler does check `isSensitiveKey()` and uses `sanitize.sanitizeOutput()` for messages, but attribute keys are passed through raw.

**Impact:** Limited. Attribute keys containing control characters could corrupt log structure in Windows Event Log entries or stderr fallback output.

**Likelihood:** Low. Requires attacker-controlled attribute keys. Scored at 2.

**Evidence:**

- `src/handlers/windows_eventlog.zig:111` -- `writer.print(" {s}=", .{attr.key})` (NO sanitizeKey)

```zig
// windows_eventlog.zig:110-111 -- key NOT sanitized
for (rec.attrs) |attr| {
    writer.print(" {s}=", .{attr.key}) catch return error.WriteFailed;  // NO sanitizeKey()
```

**Fix Guidance:** Apply `sanitize.sanitizeKey()` to attribute keys, consistent with text_handler.zig (line 103) and syslog_rfc5424.zig (line 220).

**Acceptance Criteria:**

- [ ] `windows_eventlog.zig` applies `sanitize.sanitizeKey()` to attribute keys

**SLA:** 180 days (2026-09-21)

---

### SEC-0023: Syslog writeSDString no control character escaping

- **Severity:** Low
- **Risk Score:** 8 (Impact: 2 x Likelihood: 1 x 4)
- **Confidence:** `confidence::suspected`
- **Exploit Surface:** Internal network (syslog receivers)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection

**Summary:** The syslog handler's `writeSDString()` function (lines 268-277) correctly escapes `\`, `"`, and `]` per RFC 5424 structured-data rules. However, it does NOT escape control characters (bytes 0x00-0x1F). While RFC 5424 SD-PARAM-VALUE allows UTF-8, downstream syslog parsers may be vulnerable to control character injection, particularly newlines which could break message framing.

**Impact:** Low. RFC 5424 technically permits these characters in SD-PARAM-VALUE. The risk is to downstream parsers that do not handle control characters correctly.

**Likelihood:** Very low. Requires attacker-controlled data in a syslog structured-data parameter value, AND a vulnerable downstream parser. Scored at 1.

**Evidence:**

- `src/handlers/syslog_rfc5424.zig:268-277`

```zig
// syslog_rfc5424.zig:268-277 -- only escapes \, ", ] -- no control chars
fn writeSDString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            ']' => try writer.writeAll("\\]"),
            else => try writer.writeByte(c),  // control chars pass through
        }
    }
}
```

**Fix Guidance:** Add control character escaping (replace bytes < 0x20 except 0x09 with hex escapes or underscore) for defense-in-depth against vulnerable downstream parsers.

**What would confirm:** Testing with a syslog receiver that fails to parse messages containing control characters in SD-PARAM-VALUE.

**Acceptance Criteria:**

- [ ] `writeSDString()` escapes or replaces control characters (0x00-0x1F except TAB)

**SLA:** 180 days (2026-09-21)

---

### SEC-0024: Gitleaks allowlist incomplete for example/test files

- **Severity:** Info
- **Risk Score:** 4 (Impact: 1 x Likelihood: 1 x 4)
- **Confidence:** `confidence::suspected`
- **Exploit Surface:** Repository (CI secret scanning)
- **CWE:** CWE-798 (Use of Hard-coded Credentials)
- **OWASP:** A07:2021 Identification and Authentication Failures

**Summary:** The `.gitleaks.toml` allowlist was narrowed (SEC-0014 fix) to only cover `examples/secret_redaction.zig`. However, `examples/json_logging.zig` and `tests/accept.zig` may contain intentional demo credentials or patterns that trigger false positives, and are not included in the allowlist. This could cause CI failures or require ad-hoc suppressions.

**Impact:** Minimal. If these files trigger gitleaks findings, they will be false positives requiring manual triage. No actual secret exposure risk.

**Likelihood:** Very low. Only relevant if these specific files are modified to include patterns matching gitleaks rules. Scored at 1.

**Evidence:**

- `.gitleaks.toml:8-11` -- allowlist only covers `secret_redaction.zig`

```toml
[allowlist]
paths = [
    '''examples/secret_redaction\.zig''',
]
```

**Fix Guidance:** If `examples/json_logging.zig` or `tests/accept.zig` trigger false positives, add specific path entries to the allowlist. Otherwise, no action needed.

**Acceptance Criteria:**

- [ ] Gitleaks CI passes without false positives on all example and test files
- [ ] Any new allowlist entries are file-specific (not directory-wide)

**SLA:** Backlog

---

### SEC-0025: Network sinks skip sanitizeKey on JSON attribute keys

- **Severity:** Medium
- **Risk Score:** 24 (Impact: 3 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Network-facing (if attribute keys contain user input)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection
- **Status:** **Closed / Implemented** (pass 4)

**Summary:** The TCP, UDP, and HTTP network sinks serialize record attributes into JSON output but did not apply `sanitize.sanitizeKey()` to attribute keys before writing them as JSON object keys. All text-mode handlers (text, journald, windows_eventlog, syslog, rotating_file) already applied key sanitization, but the three network sinks were missed.

**Impact:** Attribute keys containing control characters or injection sequences could be written unsanitized into JSON output sent over the network, potentially confusing downstream log parsers or SIEM systems.

**Likelihood:** Low-medium. Requires attribute keys to contain control characters, which is uncommon but possible when keys are derived from external input. Scored at 2.

**Evidence:**

- `src/sinks/tcp_sink.zig:212` -- `const sanitized_key = sanitize.sanitizeKey(&key_buf, attr.key);`
- `src/sinks/udp_sink.zig:131` -- `const sanitized_key = sanitize.sanitizeKey(&key_buf, attr.key);`
- `src/sinks/http_sink.zig:238` -- `const sanitized_key = sanitize.sanitizeKey(&key_buf, attr.key);`

**Fix:** Added `sanitize` import and `sanitize.sanitizeKey()` call in all three network sinks' attribute iteration loops, consistent with all other handlers.

**Acceptance Criteria:**

- [x] TCP sink applies sanitizeKey to attribute keys before JSON serialization
- [x] UDP sink applies sanitizeKey to attribute keys before JSON serialization
- [x] HTTP sink applies sanitizeKey to attribute keys before JSON serialization

**SLA:** 2026-03-24 (completed)

---

### SEC-0026: All network sinks transmit in cleartext -- no TLS support

- **Severity:** High
- **Risk Score:** 64 (Impact: 4 x Likelihood: 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internet-facing / internal network
- **CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)
- **OWASP:** A02:2021 Cryptographic Failures
- **Status:** **Won't Do** (pass 5: TLS implementation exceeds library scope; Zig stdlib TLS still maturing. SEC-0004 same scope already Won't Do.)

**Summary:** All three network sinks (TCP, UDP, HTTP) transmit log data exclusively in cleartext. The SEC-0001 fix added explicit rejection of `https://` URLs in the HTTP sink, which prevents silent downgrade but also means there is now **no encrypted transport path available** for any network sink. TCP and UDP sinks have never offered TLS/DTLS. This is the umbrella finding covering the complete absence of encrypted transport across all network outputs.

**Impact:** Log data -- potentially containing PII, session tokens, internal hostnames, and application state -- is transmitted in cleartext over the network regardless of which network sink is chosen. In environments with compliance requirements (PCI-DSS, HIPAA, SOC2), plaintext log transport violates data-in-transit encryption requirements. Unlike SEC-0001 (which was about false HTTPS claims), this finding addresses the fundamental absence of any encrypted transport.

**Likelihood:** Trivially exploitable by any network observer. No authentication or special access required. The HTTP sink now makes the limitation explicit (rejects https://), but TCP and UDP offer no encryption option at all. Scored at 4 because exploitation requires network position, which is common in cloud/shared environments.

**Evidence:**

- `src/sinks/http_sink.zig:66-69` -- HTTPS URLs explicitly rejected after SEC-0001 fix

```zig
// http_sink.zig:66-69 -- TLS not implemented, https rejected
if (std.mem.startsWith(u8, url, "https://")) {
    // TLS is not implemented; reject https:// URLs to prevent
    // silently sending data in plaintext
    return error.HttpsNotSupported;
```

- `src/sinks/tcp_sink.zig:75-80` -- Raw TCP connection only

```zig
// tcp_sink.zig:79-80 -- plain TCP, no TLS option
if (std.net.Address.parseIp4(self.options.host, self.options.port)) |address| {
    self.stream = std.net.tcpConnectToAddress(address) catch return error.ConnectionFailed;
```

- `src/sinks/udp_sink.zig:50-55` -- Raw UDP socket, no DTLS

```zig
// udp_sink.zig:51-55 -- plain UDP, no DTLS
const sock = std.posix.socket(
    dest_addr.any.family,
    std.posix.SOCK.DGRAM,
    0,
) catch return error.SocketError;
```

- `src/sinks/tcp_sink.zig:27-34` -- `TcpOptions` has no TLS configuration fields

**Attack Scenario:** An application sends log data to a remote aggregator via the TCP or HTTP sink. An attacker on the same network segment (or any intermediate network hop) captures all log data in plaintext using passive packet capture. In cloud environments with shared networking, this is particularly concerning.

**Fix Guidance:**

1. For TCP sink: add optional TLS wrapper using `std.crypto.tls.Client` or an imported TLS library. Add `tls: bool = false` and `tls_ca_bundle: ?[]const u8 = null` fields to `TcpOptions`.
2. For HTTP sink: implement TLS to allow `https://` URLs. This is the most impactful fix since HTTP is the most common log shipping protocol.
3. For UDP sink: document that UDP is inherently unsuitable for encrypted transport. Recommend TCP+TLS or HTTP+TLS instead.
4. At minimum, add prominent documentation warnings about plaintext transmission to all three sink modules.

**Acceptance Criteria:**

- [ ] At least one network sink supports TLS (TCP or HTTP recommended)
- [ ] Documentation clearly states plaintext risk for all three sinks
- [ ] UDP sink documentation recommends TCP+TLS or HTTP+TLS for sensitive data

**How to Verify:** Capture traffic with `tcpdump -i any -w /tmp/slog.pcap -s0 port <target_port>` while sending log records. Verify pcap contains readable plaintext log data.

**SLA:** 30 days (2026-04-23)

---

### SEC-0027: Secrets embedded in message body bypass all redaction

- **Severity:** Medium
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** All handlers (all output paths)
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures

**Summary:** The `isSensitiveKey()` auto-redaction and `Attr.secret()` mechanisms only protect attribute values. The `rec.message` field is never scanned for sensitive content. If a developer logs a message like `log.info("Login failed for user with password=hunter2", .{})`, the password is written in plaintext through every handler. The `sanitizeOutput()` function only escapes control characters, not sensitive patterns.

**Impact:** Developers commonly include request details, error messages, and debug information in log message strings. Sensitive data embedded in these strings bypasses the entire redaction infrastructure. The false sense of security from `isSensitiveKey()` may cause developers to assume all sensitive data is automatically protected.

**Likelihood:** Moderate. Developers are more likely to put sensitive data in structured attributes (which are redacted) than in message strings, but it does happen, especially in error paths and debug logging. Scored at 3.

**Evidence:**

- `src/handlers/text_handler.zig:73` -- message written with sanitizeOutput (control chars only, no secret scanning)

```zig
// text_handler.zig:73 -- sanitizeOutput escapes \n, \r, etc. but NOT secrets
sanitize.sanitizeOutput(writer, rec.message) catch return error.WriteFailed;
```

- `src/util/redact.zig:45-68` -- `isSensitiveKey()` only called with attribute keys, never with message content
- All handlers follow the same pattern: message is sanitized for control characters but never scanned for secrets

**Attack Scenario:** A developer writes `log.err("Auth failed: token={s}", .{user_token})` using format strings. The token value is interpolated into the message string before the logger sees it. The logger writes it as a plain message. The `isSensitiveKey` mechanism never examines message content, so the token is logged in plaintext to all outputs.

**Fix Guidance:**

1. **Option A (recommended):** Document this as a known limitation prominently in the API docs and SECURITY.md. Add a "Security Best Practices" section recommending `Attr.secret()` or `Attr.string()` with sensitive keys for all secret values.
2. **Option B (defense-in-depth):** Add an optional message scanning feature that searches for common secret patterns (e.g., regex for `password=...`, `token=...`, Bearer tokens, API key formats) in message strings. This would be opt-in due to performance overhead.
3. Add a linter rule or compile-time check that warns when format strings contain known sensitive parameter names.

**Acceptance Criteria:**

- [ ] Documentation clearly states that message body content is NOT scanned for secrets
- [ ] API docs recommend using `Attr.secret()` for all sensitive values
- [ ] SECURITY.md updated to note this limitation

**How to Verify:** Log `log.info("password=hunter2", .{})` and verify the output contains the plaintext password.

**SLA:** 90 days (2026-06-22)

---

### SEC-0028: HTTP sink does not validate server identity

- **Severity:** Medium
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internet-facing / internal network
- **CWE:** CWE-295 (Improper Certificate Validation)
- **OWASP:** A02:2021 Cryptographic Failures

**Summary:** The HTTP sink connects to the configured endpoint via plain TCP with no server identity validation. Combined with the absence of TLS (SEC-0026), there is no mechanism to verify that the application is communicating with the intended log aggregator. Even if TLS were added in the future, the current architecture has no certificate validation infrastructure. DNS poisoning or ARP spoofing could redirect log traffic to an attacker-controlled endpoint without detection.

**Impact:** A man-in-the-middle attacker could impersonate the log aggregator, receiving all log data (potentially containing PII and secrets). The attacker could also inject fake responses to manipulate the sink's retry/circuit-breaker behavior.

**Likelihood:** Requires network-level attack (DNS poisoning, ARP spoofing, BGP hijacking). More practical in cloud environments or shared networks. Scored at 3.

**Evidence:**

- `src/sinks/http_sink.zig:66-69` -- HTTPS rejected, only plain HTTP supported

```zig
// http_sink.zig:66-69 -- no TLS, no server authentication
if (std.mem.startsWith(u8, url, "https://")) {
    return error.HttpsNotSupported;
}
```

- `src/sinks/http_sink.zig:75-80` -- connects to parsed host/port via raw TCP
- No certificate store, no hostname verification, no pinning

**Fix Guidance:**

1. This finding is blocked by SEC-0026 (TLS implementation). Once TLS is available:
2. Validate server certificates against system CA store.
3. Verify the server hostname matches the certificate's Subject Alternative Name.
4. Consider optional certificate pinning for high-security deployments.

**Acceptance Criteria:**

- [ ] When TLS is implemented, server certificates are validated against CA store
- [ ] Hostname verification is performed
- [ ] Connection fails on certificate mismatch

**How to Verify:** After TLS implementation, attempt to connect to a server with a mismatched certificate and verify the connection is rejected.

**SLA:** 90 days (2026-06-22) -- blocked by SEC-0026

---

### SEC-0029: TCP sink has no authentication mechanism

- **Severity:** Medium
- **Risk Score:** 24 (Impact: 2 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal network
- **CWE:** CWE-306 (Missing Authentication for Critical Function)
- **OWASP:** A07:2021 Identification and Authentication Failures

**Summary:** The TCP sink's `TcpOptions` struct contains only connection parameters (host, port, timeout, retries, backoff) with no fields for authentication credentials, tokens, or client certificates. Any endpoint listening on the configured port will receive log data. The log aggregator also has no way to verify the identity of the log source. This is the TCP-specific aspect of the broader SEC-0016 finding (which was marked Won't Do for TCP+UDP combined), but is called out separately because TCP is the most likely candidate for adding mTLS when TLS support is implemented (SEC-0026).

**Impact:** In a compromised network, an attacker could redirect TCP log traffic to a rogue endpoint by DNS poisoning or ARP spoofing, capturing all log data. The log aggregator cannot distinguish legitimate log sources from malicious ones.

**Likelihood:** Requires network-level attack or misconfiguration. Common risk in multi-tenant environments. Scored at 3.

**Evidence:**

- `src/sinks/tcp_sink.zig:27-34` -- no authentication fields in TcpOptions

```zig
// tcp_sink.zig:27-34 -- no auth fields
pub const TcpOptions = struct {
    host: []const u8,
    port: u16,
    connect_timeout_ms: u32 = 5000,
    max_retries: u8 = 3,
    initial_backoff_ms: u32 = 100,
    max_backoff_ms: u32 = 5000,
};
```

**Related:** SEC-0016 (Won't Do) -- covers both TCP and UDP. This finding specifically tracks the TCP authentication gap for when TLS is implemented.

**Fix Guidance:**

1. When TLS is added (SEC-0026), include mTLS support with client certificate authentication.
2. Add optional `auth_token: ?[]const u8 = null` field to TcpOptions for token-based authentication.
3. Document that unauthenticated TCP transport should only be used on trusted networks.

**Acceptance Criteria:**

- [ ] TCP sink supports optional authentication (mTLS or token-based)
- [ ] Documentation states the authentication limitation

**SLA:** 90 days (2026-06-22) -- blocked by SEC-0026

---

### SEC-0030: Sensitive key list incomplete -- missing common patterns

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** All handlers (log output)
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures

**Summary:** The `sensitive_keys` list in `redact.zig` contains 15 patterns (password, passwd, secret, api_key, etc.) but is missing several common sensitive key patterns including: `ssn`, `social_security`, `credit_card`, `card_number`, `cvv`, `cvc`, `session`, `session_id`, `cookie`, `bearer`, `jwt`, `connection_string`, `conn_str`, `database_url`, `db_password`, `pin`, `otp`, `mfa`. Applications logging attributes with these key names will not trigger auto-redaction.

**Impact:** Limited. The existing list covers the most common patterns. Missing patterns are less frequently used as attribute key names in structured logging. Defense-in-depth improvement.

**Likelihood:** Low. Requires an application to log attributes with specific missing key names (e.g., `Attr.string("ssn", value)`). Scored at 2.

**Evidence:**

- `src/util/redact.zig:15-31` -- current sensitive_keys list

```zig
// redact.zig:15-31 -- current list, missing several common patterns
pub const sensitive_keys = [_][]const u8{
    "password", "passwd", "secret", "api_key", "apikey",
    "token", "auth", "authorization", "credential",
    "private_key", "privatekey", "access_key", "accesskey",
    "secret_key", "secretkey",
};
// Missing: ssn, credit_card, cvv, session, cookie, bearer, jwt,
// connection_string, pin, otp, etc.
```

**Fix Guidance:**

1. Add the following patterns to `sensitive_keys`: `ssn`, `social_security`, `credit_card`, `card_number`, `cvv`, `cvc`, `session_id`, `cookie`, `bearer`, `jwt`, `connection_string`, `conn_str`, `database_url`, `db_password`, `pin`, `otp`.
2. Consider making the sensitive key list configurable (user-extensible) rather than hardcoded.
3. The comptime-unrolled pattern matching in `isSensitiveKey()` handles additional patterns efficiently, so performance impact is minimal.

**Acceptance Criteria:**

- [ ] `isSensitiveKey("ssn")` returns true
- [ ] `isSensitiveKey("credit_card")` returns true
- [ ] `isSensitiveKey("session_id")` returns true
- [ ] `isSensitiveKey("bearer")` returns true
- [ ] `isSensitiveKey("jwt")` returns true
- [ ] `isSensitiveKey("connection_string")` returns true

**SLA:** 180 days (2026-09-21)

---

### SEC-0031: Logger name and source_file not sanitized in text handler

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (requires attacker-controlled logger name)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection

**Summary:** The text handler writes `rec.logger` directly to output at line 68 without applying `sanitizeOutput()`. While `rec.message` is correctly sanitized (line 73) and attribute keys use `sanitizeKey()` (line 103), the logger name field is written raw. If a logger name contains newline characters (`\n`), it could inject fake log lines. The `rec.source_file` field in the Record struct is also not sanitized in any handler, though it is currently always set to `""` in test records.

**Impact:** Low. Logger names are typically compile-time constants (e.g., `"http.server"`) and are not user-controlled in most applications. However, if a logger name is derived from dynamic input (e.g., module names from plugin systems), log injection is possible.

**Likelihood:** Low. Requires attacker control over the logger name string, which is uncommon. Scored at 2.

**Evidence:**

- `src/handlers/text_handler.zig:67-69` -- logger name written without sanitization

```zig
// text_handler.zig:67-69 -- logger name NOT sanitized
if (rec.logger.len > 0) {
    writer.writeAll(rec.logger) catch return error.WriteFailed;  // NO sanitizeOutput
    writer.writeByte(' ') catch return error.WriteFailed;
}
```

- Compare with `src/handlers/text_handler.zig:73` -- message IS sanitized:

```zig
// text_handler.zig:73 -- message correctly sanitized
sanitize.sanitizeOutput(writer, rec.message) catch return error.WriteFailed;
```

- `src/record.zig:29` -- `source_file: []const u8` field exists but is not sanitized in any handler

**Fix Guidance:**

1. Replace `writer.writeAll(rec.logger)` with `sanitize.sanitizeOutput(writer, rec.logger)` in text_handler.zig.
2. Apply the same fix to any other handlers that write `rec.logger` directly.
3. If `rec.source_file` is ever written to output, apply `sanitizeOutput()` to it as well.

**Acceptance Criteria:**

- [ ] `rec.logger` is sanitized via `sanitizeOutput()` in text handler
- [ ] Logger name containing `\n` produces escaped output, not a new log line
- [ ] Same fix applied to any other handlers that write `rec.logger` directly

**SLA:** 180 days (2026-09-21)

---

### SEC-0032: Syslog handler hostname written raw, bypassing writeSyslogName sanitization

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal network (syslog receivers)
- **CWE:** CWE-117 (Improper Output Neutralization for Logs)
- **OWASP:** A03:2021 Injection

**Summary:** The syslog RFC5424 handler uses `writeSyslogName()` to sanitize `rec.logger` (APP-NAME at line 141) and `rec.msg_id` (MSGID at line 159), but writes `ctx.options.hostname` (HOSTNAME at line 136) directly via `writer.writeAll()` without any sanitization. The `writeSyslogName()` function restricts output to printable ASCII (33-126) and enforces a 48-character maximum, providing proper RFC5424 conformance. The hostname field bypasses these protections.

**Impact:** Low. The hostname is typically set from configuration, not user input. However, if the hostname contains control characters or is excessively long, it could malform syslog messages or confuse downstream parsers.

**Likelihood:** Low. Requires attacker control of the hostname configuration value. Scored at 2.

**Evidence:**

- `src/handlers/syslog_rfc5424.zig:136` -- hostname written raw

```zig
// syslog_rfc5424.zig:136 -- hostname NOT sanitized
writer.writeAll(ctx.options.hostname) catch return error.WriteFailed;
```

- `src/handlers/syslog_rfc5424.zig:141` -- APP-NAME correctly uses writeSyslogName

```zig
// syslog_rfc5424.zig:141 -- APP-NAME sanitized via writeSyslogName
writeSyslogName(writer, rec.logger) catch return error.WriteFailed;
```

- `src/handlers/syslog_rfc5424.zig:198-207` -- writeSyslogName restricts to printable ASCII

```zig
// syslog_rfc5424.zig:198-207 -- proper sanitization
fn writeSyslogName(writer: anytype, name: []const u8) !void {
    const max_len: usize = 48;
    var written: usize = 0;
    for (name) |c| {
        if (written >= max_len) break;
        if (c >= 33 and c <= 126) {
            try writer.writeByte(c);
            written += 1;
```

**Fix Guidance:**

1. Apply `writeSyslogName()` to the hostname field at line 136, or
2. Validate the hostname at `Context.init()` time (reject hostnames with control characters or exceeding RFC5424 limits).

**Acceptance Criteria:**

- [ ] Hostname is either sanitized via `writeSyslogName()` or validated at init time
- [ ] Hostname containing control characters does not corrupt syslog message framing

**SLA:** 180 days (2026-09-21)

---

### SEC-0033: Data race on Level field in setLevel across handlers

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Admin-only (requires concurrent level change + logging)
- **CWE:** CWE-362 (Concurrent Execution Using Shared Resource with Improper Synchronization)
- **OWASP:** A04:2021 Insecure Design

**Summary:** Every handler's `setLevel()` function performs a non-atomic write to `ctx.level` while `handle()` reads `ctx.level` under a mutex. However, `setLevel()` does not acquire the mutex. If one thread calls `setLevel()` while another thread is between entering `handle()` and reaching the `ctx.level` read, the read may observe a torn value. This is a data race in Zig's memory model. Note: SEC-0011 (fatal_hook race) was fixed with atomic operations, but the same pattern was not applied to handler level fields.

**Impact:** Low in practice. Zig's `Level` is a small enum (fits in a single byte), so torn reads are unlikely on most architectures. The worst case is a log record being emitted at the wrong level, not a crash or memory corruption.

**Likelihood:** Requires concurrent `setLevel()` and `handle()` calls. Dynamic level changes are typically infrequent. Scored at 2.

**Evidence:**

- `src/handlers/text_handler.zig:149-151` -- setLevel writes ctx.level without mutex

```zig
// text_handler.zig:149-151 -- non-atomic write, no mutex
fn setLevel(ctx_ptr: *anyopaque, level: Level) void {
    const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
    ctx.level = level;  // data race with handle() reading ctx.level at line 47
}
```

- `src/handlers/rotating_file.zig:335-337` -- same pattern
- `src/handlers/json_handler.zig:166-168` -- same pattern
- `src/handlers/syslog_rfc5424.zig:300-302` -- same pattern
- `src/handlers/journald.zig:196-198` -- same pattern
- `src/handlers/windows_eventlog.zig:168-170` -- same pattern
- All handlers read `ctx.level` in `handle()` under mutex, but `setLevel()` writes without mutex

**Fix Guidance:**

1. Use `@atomicStore` / `@atomicLoad` for `ctx.level` in all handlers, consistent with the SEC-0011 fix for `fatal_hook`.
2. Alternatively, acquire the handler's existing mutex in `setLevel()` before writing.

**Acceptance Criteria:**

- [ ] `setLevel()` uses atomic write or acquires mutex in all handlers
- [ ] Concurrent `setLevel()` + `handle()` does not constitute a data race

**SLA:** 180 days (2026-09-21)

---

### SEC-0034: Rotating log files created world-readable -- REGRESSION (0o600 mode lost in Zig 0.16 migration)

- **Severity:** Medium (escalated from Low; the fix that mitigated it was reverted)
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (filesystem; shared/multi-tenant hosts)
- **CWE:** CWE-276 (Incorrect Default Permissions), CWE-732
- **OWASP:** A02:2025 Security Misconfiguration (also A01)
- **Status:** **Open / REGRESSION** (was Closed in pass 5; mode dropped during Zig 0.16 migration `fa0de64`)
- **Issue:** [#43](https://gitlab.com/devnw/zig/slog/-/issues/43)
- **Maps to:** APPSEC-01 (`docs/APPSEC_REVIEW_2026-06-12.md`)

**Summary:** The pass-5 fix that passed explicit `0o600` permissions to `createFile` was **lost during the Zig 0.16 `std.fs` -> `std.Io.Dir` migration** (commit `fa0de64`). The rotating file handler now calls `createFile` with no `permissions` field. Zig 0.16 `std.Io.Dir.CreateFileOptions` defaults `permissions = .default_file` = `0o666` on POSIX, so after the process umask (commonly `022`) the on-disk mode is typically `0o644` -- **world-readable**. The tracking docs (this file and GAP_ANALYSIS_RESOLVED.md) still claimed SEC-0034 was Closed; that claim is reconciled by this rev.

**Impact:** Local disclosure of potentially sensitive log content (PII, session identifiers, internal hostnames) to any unprivileged user or co-tenant on a shared host. Rotated backups (`app.log.1`, `.2`, ...) created via `rename` inherit the same permissive mode. This undoes the redaction control at the file-permission layer. No remote vector.

**Likelihood:** The world-readable mode is the default outcome on a default-umask POSIX host, not an edge case. Any local user can `cat` the log. Scored at 3 (raised from the original 2, which assumed a permissive umask was required; in fact the default umask already yields world-readable).

**Evidence:**

- `src/handlers/rotating_file.zig:112` -- createFile with no `permissions` field

```zig
// rotating_file.zig:112 -- no explicit permissions
self.file = std.Io.Dir.cwd().createFile(io, path, .{
    .truncate = false,
}) catch |err| { ... };
```

- Zig 0.16 `std.Io.Dir.CreateFileOptions.permissions` defaults to `.default_file` = `0o666` on POSIX.
- `git log -S` shows the mode-bearing code last appeared around `fa0de64` ("complete zig 0.16.0 migration") and is absent at HEAD `bd50a7f`.

**Fix Guidance:**

1. Pass an explicit owner-only mode to `createFile`: `.permissions = @enumFromInt(0o600)` (widen deliberately, e.g. `0o640` for a log-reader group, only if required).
2. Consider exposing the mode as a `RotationOptions` field.
3. Note `createFile` does not change the mode of an already-existing file; document that operators should also restrict the directory or `chmod` on first open.
4. Reconcile every other `**Closed**` SEC-* item against HEAD -- this regression proves at least one fix was lost in the migration.

**Acceptance Criteria:**

- [ ] `createFile` is passed an explicit `permissions`/mode of `0o600` (or operator-configured value)
- [ ] On POSIX, a created log file satisfies `stat().mode & 0o077 == 0` (no group/other bits)
- [ ] Regression test asserts the permission bits; manual `umask 022; <run>; ls -l app.log` -> `-rw-------`

**How to Verify:** `umask 022; <run handler writing to app.log>; ls -l app.log` should show `-rw-------`, not `-rw-r--r--`.

**SLA:** 90 days (2026-09-10)

---

### SEC-0035: UDP truncation produces malformed JSON

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Internal network (log aggregators)
- **CWE:** CWE-404 (Improper Resource Shutdown or Release)
- **OWASP:** A09:2021 Security Logging and Monitoring Failures

**Summary:** The UDP sink truncates the serialized JSON payload to `max_packet_size` (default 65507 bytes) at `udp_sink.zig:80` using `@min(data.len, self.options.max_packet_size)`. If the JSON payload exceeds this limit, the truncated output is syntactically invalid JSON (missing closing braces, truncated strings). Downstream log aggregators that parse JSON will reject or misparse these records, potentially losing audit-critical log entries.

**Impact:** Low. The default max packet size (65507 bytes) is the maximum UDP payload. Log records exceeding this size are extremely rare. However, in configurations with smaller `max_packet_size` values, truncation is more likely.

**Likelihood:** Low. Requires a log record that serializes to more than `max_packet_size` bytes. Scored at 2.

**Evidence:**

- `src/sinks/udp_sink.zig:80` -- truncation at arbitrary byte boundary

```zig
// udp_sink.zig:80 -- truncation produces malformed JSON
const send_len = @min(data.len, self.options.max_packet_size);
```

**Fix Guidance:**

1. Before sending, check if `data.len > max_packet_size`. If so, either:
   a. Drop the record and increment an error counter (preferred for audit integrity), or
   b. Truncate the message field to fit within the limit while preserving valid JSON structure, or
   c. Send a minimal error record indicating truncation occurred.
2. Log a warning via stderr or metrics when truncation occurs.

**Acceptance Criteria:**

- [ ] UDP sink never sends malformed JSON
- [ ] Oversized records are either dropped with a metric or truncated with valid JSON structure
- [ ] Truncation events are observable via metrics

**SLA:** 180 days (2026-09-21)

---

### SEC-0036: JSON key collision via duplicate keys or keys that sanitize to the same string

- **Severity:** Low
- **Risk Score:** 8 (Impact: 1 x Likelihood: 2 x 4)
- **Confidence:** `confidence::suspected`
- **Exploit Surface:** All JSON output paths
- **CWE:** CWE-20 (Improper Input Validation)
- **OWASP:** A03:2021 Injection

**Summary:** The `sanitizeKey()` function replaces all invalid characters with `_`. Two different attribute keys that differ only in non-alphanumeric characters (e.g., `user/id` and `user@id` both sanitize to `user_id`) will produce duplicate JSON object keys. Additionally, if a user provides two attributes with the same key name, the JSON output will contain duplicate keys. While RFC 8259 does not forbid duplicate keys, most JSON parsers handle them inconsistently (some take the first value, some the last, some error). This could cause data loss or confusion in log analysis.

**Impact:** Minimal. Requires specific attribute naming patterns that collide after sanitization. Data is not lost (both values are present in the JSON) but parsers may only expose one value.

**Likelihood:** Low. Requires either (a) two attributes with names that sanitize to the same string, or (b) two attributes with identical keys. Scored at 2.

**Evidence:**

- `src/util/sanitize.zig:17-27` -- sanitizeKey replaces all non-alphanumeric chars with `_`

```zig
// sanitize.zig:19-24 -- different keys can sanitize to same output
for (key[0..len], 0..) |c, i| {
    if (isValidKeyChar(c)) {
        buf[i] = c;
    } else {
        buf[i] = '_';  // "user/id" and "user@id" both become "user_id"
    }
}
```

- `src/handlers/json_handler.zig:123-148` -- no duplicate key detection

**What would confirm:** Create two attributes `Attr.string("user/id", "a")` and `Attr.string("user@id", "b")`, serialize to JSON, and verify the output contains duplicate `"user_id"` keys.

**Fix Guidance:**

1. **Option A:** Track emitted keys in a small set during serialization. If a collision is detected, append a numeric suffix (e.g., `user_id_2`).
2. **Option B:** Use a different sanitization strategy that preserves more of the original key structure (e.g., hex-encode invalid characters instead of replacing with `_`).
3. **Option C:** Document the collision possibility as a known limitation.

**Acceptance Criteria:**

- [ ] Either: duplicate JSON keys are prevented, or the limitation is documented
- [ ] If deduplication is implemented, all colliding keys are distinguishable in output

**SLA:** 180 days (2026-09-21)

---

## AppSec Review Findings (2026-06-12)

The following findings were discovered during the AppSec code review of HEAD `bd50a7f` (`docs/APPSEC_REVIEW_2026-06-12.md`). SEC-0034 above was reopened as a regression in the same pass.

### SEC-0037: Log path symlink-following and unconstrained absolute writes

- **Severity:** Medium
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Local (requires log-path configuration influence)
- **CWE:** CWE-22 (Path Traversal), CWE-59 (Link Following), CWE-61
- **OWASP:** A01:2025 Broken Access Control
- **Status:** **Open** (SEC-0007's symlink acceptance criterion never met)
- **Issue:** [#46](https://gitlab.com/devnw/zig/slog/-/issues/46)
- **Maps to:** APPSEC-02 (`docs/APPSEC_REVIEW_2026-06-12.md`); relates to SEC-0007

**Summary:** `validatePath` blocks only empty paths and the `..` substring. It does not prevent the log path from being a symlink to a sensitive location, and it accepts absolute paths. SEC-0007 was marked Closed, but its acceptance criterion "symlinks in the path do not allow escaping the intended directory" was never satisfied.

**Impact:** If an attacker can influence the configured log path (env var, config file, deployment template -- the threat model SEC-0007 itself assumes), they can write/append partially attacker-influenced log content to an arbitrary location, or follow a pre-positioned symlink into a sensitive file. Append plus rotation `rename` can also clobber/relocate the target. Medium, not Critical, because it requires control of the path configuration, which is operator-trusted in many deployments.

**Likelihood:** Requires configuration influence over the path; given that influence the write is unconstrained. Scored at 3.

**Evidence:**

- `src/handlers/rotating_file.zig:89-99` -- `validatePath` checks only non-empty and `..`

```zig
fn validatePath(path: []const u8) !void {
    if (path.len == 0) return error.WriteFailed;
    if (std.mem.indexOf(u8, path, "..") != null) return error.WriteFailed;
}
```

- `src/handlers/rotating_file.zig:106-119` -- `createDirPath` + `createFile` via `std.Io.Dir.cwd()` with default options (`resolve_beneath = false`, symlink-following left at OS default).

**Attack Scenario:**

1. Supply an absolute path (`/etc/cron.d/x`, a fifo, a device node) -- `..` filtering does not stop absolute writes; or
2. Pre-create a symlink at the intended log location pointing at a target file; `createFile` with default options follows it and the handler appends attacker-influenced log lines to the symlink target.

**Fix Guidance:**

1. Reject absolute paths unless explicitly opted in; reject paths whose canonical (realpath) form escapes a configured base directory.
2. Open the base log directory once as a `Dir` and create files relative to it with `resolve_beneath = true` (returns `error.AccessDenied` on escape).
3. At minimum, set no-follow/exclusive semantics on first create or `lstat` the final component and refuse if it is a symlink.

**Acceptance Criteria:**

- [ ] Pre-creating a symlink at the target causes init/open to error (or write to the real intended inode, never the link target)
- [ ] Absolute paths outside the configured base are rejected
- [ ] SEC-0007's outstanding symlink criterion is closed
- [ ] Regression tests for symlink and absolute-path rejection

**SLA:** 90 days (2026-09-10)

---

### SEC-0038: Auto-redaction blind spot for keys longer than 64 bytes

- **Severity:** Low
- **Risk Score:** 12 (Impact: 3 x Likelihood: 1 x 4)
- **Confidence:** `confidence::suspected`
- **Exploit Surface:** All handlers (log output); requires an unusually long key
- **CWE:** CWE-532 (Insertion of Sensitive Information into Log File)
- **OWASP:** A09:2025 Logging/Alerting Failures
- **Status:** **Open**
- **Issue:** [#47](https://gitlab.com/devnw/zig/slog/-/issues/47)
- **Maps to:** APPSEC-03 (`docs/APPSEC_REVIEW_2026-06-12.md`)

**Summary:** `isSensitiveKey` lowercases and scans only `key[0..@min(key.len, 64)]` (`lower_buf: [64]u8`). A sensitive pattern (e.g. `api_key`, `password`) whose first character sits at offset >= 64 is never matched, so the value is not redacted. `record.zig` caps the whole record at 64 KB but imposes no per-key length limit, so a 64-byte-prefixed sensitive key is well within budget.

**Impact:** A secret/PII value is logged in cleartext despite a key the user reasonably expects to be auto-redacted. Defense-in-depth blind spot.

**Likelihood:** Keys are normally developer constants; the realistic trigger is a long namespaced key (e.g. a 60-char module prefix + `_api_key`). If key names are ever derived from untrusted input, an attacker could deliberately position the token past byte 64. Scored at 1.

**Evidence:**

- `src/util/redact.zig:81-100` -- fixed 64-byte scan window (`lower_buf: [64]u8`); formatters call `isSensitiveKey(attr.key)` on the raw key (`fmt/text_record.zig:76`, `fmt/json_record.zig:106`, `syslog_rfc5424.zig:226`).

**Fix Guidance:** Scan the entire key (the function already operates on a slice); compare case-insensitively without a fixed buffer, removing the 64-byte cap and the lowercase scratch buffer.

**What would confirm:** A unit test `isSensitiveKey("a" ** 64 ++ "password")` currently returns `false`; after the fix it returns `true`.

**Acceptance Criteria:**

- [ ] `isSensitiveKey("a" ** 64 ++ "password")` returns true
- [ ] A JSON/text formatter test asserts the value renders `[REDACTED]` for such a key
- [ ] No fixed-size truncation of the scanned key remains

**SLA:** 180 days (2026-12-09)

---

### SEC-0039: Silent whole-record drop when rendered size exceeds 8KB buffer

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::suspected`
- **Exploit Surface:** All text/rotating handlers (audit integrity)
- **CWE:** CWE-778 (Insufficient Logging), CWE-755
- **OWASP:** A09 / A10:2025
- **Status:** **Open**
- **Issue:** [#48](https://gitlab.com/devnw/zig/slog/-/issues/48)
- **Maps to:** APPSEC-04 (`docs/APPSEC_REVIEW_2026-06-12.md`)

**Summary:** `logger.log` admits records up to `MAX_RECORD_SIZE = 64 * 1024` (`record.zig:14,51-52`), but the text and rotating-file handlers render into an 8 KB fixed buffer (`text_handler.zig:50`, `rotating_file.zig:271`: `var buf: [8192]u8`). When the rendered line exceeds 8 KB, `writeTextRecord` to the `.fixed` writer fails with `error.NoSpaceLeft` and the handler executes `... catch return error.WriteFailed` (`rotating_file.zig:271-276`), discarding the entire record.

**Impact:** Loss of audit/log records (availability + audit integrity). An attacker who can make a security-relevant event carry a large attribute (within the 64 KB record budget) can suppress that specific audit record. Bounds-safe -- Zig's `.fixed` writer is checked, so there is no buffer overflow or memory unsafety; the issue is silent data loss.

**Likelihood:** Requires an attacker-influenced large value within the 64 KB budget reaching a text/rotating handler. Scored at 2.

**Evidence:**

- `src/handlers/text_handler.zig:50` -- `var buf: [8192]u8`
- `src/handlers/rotating_file.zig:271-276` -- 8 KB buffer; `catch return error.WriteFailed` on `NoSpaceLeft`
- `src/record.zig:14,51-52` -- `MAX_RECORD_SIZE = 64 * 1024`
- (UDP already drops over-MTU records by design at `udp_sink.zig:74-77`; TCP/HTTP/JSON use 16 KB buffers, still below the 64 KB budget.)

**Fix Guidance:** Align the format-buffer size with `MAX_RECORD_SIZE` (size buffers to 64 KB, or grow/stream into the write buffer), or on `NoSpaceLeft` emit a truncated record plus an explicit `truncated=true` marker rather than dropping. Increment a dedicated `dropped`/`truncated` metric (the rotating handler currently only bumps `incErrors()`).

**Acceptance Criteria:**

- [ ] A record whose rendered size is ~16 KB produces a (possibly truncated) line plus a truncation indicator, not nothing
- [ ] A dedicated dropped/truncated metric is incremented and observable
- [ ] Text and rotating-file handlers no longer silently discard sub-64 KB records

**SLA:** 180 days (2026-12-09)

---

### SEC-0040: CI catalog components pinned to mutable version tags, not commit SHAs

- **Severity:** Low
- **Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Build/CI pipeline (supply chain)
- **CWE:** CWE-1357 (Reliance on Insufficiently Trustworthy Component), CWE-494
- **OWASP:** A06 / A08:2025
- **Status:** **Won't Do** (accepted risk -- recorded for visibility)
- **Maps to:** (extends the supply-chain theme of SEC-0008)

**Summary:** `.gitlab-ci.yml` includes reusable CI catalog components by mutable version tag (`@v1.7.1`, `@v1.2.1`) rather than immutable commit SHAs. A force-push or re-tag of a catalog component would change pipeline behavior without a corresponding change in this repo. This mirrors the SEC-0008 concern (floating reference) at the CI layer.

**Impact:** A compromised or re-tagged catalog component could alter SAST/secret-scan/SBOM/release behavior. The build dependency graph (`json`, `thread_pool`) is now SHA-pinned, but the CI catalog includes are not.

**Likelihood:** Requires compromise or accidental re-tag of a first-party catalog component (`gitlab.com/devnw/ci-catalog`). Scored at 2.

**Evidence:**

- `.gitlab-ci.yml:11-24` -- catalog includes pinned to version tags, e.g. `gitlab.com/devnw/ci-catalog/security-sast@v1.7.1`, `.../zig-format@v1.2.1`.

**Disposition / Reason (Won't Do):** The catalog is a first-party, same-org project (`devnw/ci-catalog`); version-tag pinning is the GitLab-recommended and ergonomic convention for catalog components, and SHA-pinning catalog includes is not natively supported in the same way as package deps. Recorded as accepted residual risk. Re-evaluate if third-party catalog components are ever added.

**Acceptance Criteria (if revisited):**

- [ ] CI catalog includes reference immutable revisions, or
- [ ] A documented decision accepts version-tag pinning for first-party catalog components

**SLA:** -- (Won't Do)

---

### SEC-0041: Vendored thread_pool scripts committed mode 0777

- **Severity:** Info (residual Low)
- **Risk Score:** 4 (Impact: 1 x Likelihood: 1 x 4)
- **Confidence:** `confidence::confirmed`
- **Exploit Surface:** Repository (vendored snapshot)
- **CWE:** CWE-732 (Incorrect Permission Assignment for Critical Resource)
- **OWASP:** A05:2025 Security Misconfiguration
- **Status:** **Open** (informational)
- **Cross-reference:** QUALITY tracker NEW-7 (stale `zig-pkg/` snapshots) -- do not duplicate

**Summary:** Vendored `thread_pool` scripts under `zig-pkg/` are committed with permissive `0777` mode bits in the git index. While the on-disk effect is umask-bounded at checkout, committing world-writable/executable modes for vendored scripts is a hygiene/misconfiguration smell.

**Impact:** Minimal -- vendored third-party scripts are not invoked by the slog build's hot path; the concern is repository hygiene and the principle of least privilege for committed file modes. No execution path from attacker-controlled log content reaches these files.

**Likelihood:** Informational; no direct exploitation path. Scored at 1.

**Evidence:**

- Vendored `thread_pool` snapshot under `zig-pkg/` with committed mode `0777` on script files. The broader concern of stale/duplicated `zig-pkg/` snapshots is tracked by the QUALITY tracker (NEW-7); this entry records only the file-mode aspect to avoid duplication.

**Fix Guidance:** Tighten committed file modes (e.g. `git update-index --chmod=-x` / re-add with `0644`/`0755` as appropriate) when the `zig-pkg/` snapshot is regenerated. Coordinate with QUALITY NEW-7's snapshot cleanup rather than fixing in isolation.

**Acceptance Criteria:**

- [ ] Committed vendored script modes are tightened (no `0777`) when `zig-pkg/` is regenerated

**SLA:** Backlog

---

## Phase 3 Audit -- Non-Security Gaps

The following gaps were discovered during the Phase 3 post-closure verification audit. They are documentation and tracking consistency issues, not security vulnerabilities.

### GAP-0026: API.md documents stale convenience function signatures

- **Severity:** Medium
- **Category:** Docs
- **Confidence:** `confidence::confirmed`
- **Status:** **Closed / Implemented** (pass 5)

**Summary:** docs/API.md lines 325-335 show old `stderrHandler`/`stderrJsonHandler` signatures that return `struct{ctx, handler}`. The SEC-0002 fix changed the API to accept a `*Context` out-parameter, but API.md was not updated to reflect the new signatures.

**Resolution:** API.md convenience function signatures updated to match current `*Context` out-parameter API. All code examples corrected to compile with current slogz.zig.

**Evidence:**

- `docs/API.md` -- updated signatures for `stderrHandler(ctx: *text.Context, level: Level) Handler`
- Old `struct { ctx, handler }` return pattern removed from all examples

**Acceptance Criteria:**

- [x] docs/API.md examples compile with current slogz.zig
- [x] `stderrHandler` and `stderrJsonHandler` signatures in API.md match `src/slogz.zig`
- [x] No references to the old `struct { ctx, handler }` return pattern remain in API.md

---

### GAP-0027: ARCHITECTURE.md module tree missing 4 source files

- **Severity:** Low
- **Category:** Docs
- **Confidence:** `confidence::confirmed`
- **Status:** **Closed / Implemented** (pass 5)

**Summary:** ARCHITECTURE.md module tree lists 23 files but the actual source directory contains 27 .zig files. The 4 missing files are: `multi_handler.zig`, `parallel.zig`, `json_value.zig`, `text_value.zig`.

**Resolution:** ARCHITECTURE.md module tree updated to list all source files including multi_handler.zig, parallel.zig, json_value.zig, text_value.zig, json_record.zig, and text_record.zig.

**Evidence:**

- `docs/ARCHITECTURE.md` -- module tree now lists all .zig files in the codebase

**Acceptance Criteria:**

- [x] ARCHITECTURE.md module tree lists all .zig files
- [x] `multi_handler.zig`, `parallel.zig`, `json_value.zig`, `text_value.zig` are all present in the tree

---

### GAP-0028: GitLab issue #40 open but PERF-025 marked Won't Do

- **Severity:** Low
- **Category:** Tracking
- **Confidence:** `confidence::confirmed`
- **Status:** **Won't Do** (pass 5)

**Summary:** PERF_GAP_ANALYSIS.md marks PERF-025 (stack allocations 8-25KB per log call) as "Won't Do", but GitLab issue #40 remains open. The tracker and docs are inconsistent.

**Reason:** Requires manual GitLab issue close; cannot automate without issue access. Marked Won't Do for this gap closure pass. The GitLab issue should be closed manually by the maintainer.

**Acceptance Criteria:**

- [ ] GitLab #40 status matches PERF_GAP_ANALYSIS.md disposition (both closed/won't-do, or both open)

---

## Findings by Area

### Authentication and Authorization

- SEC-0016: No authentication for TCP/UDP sinks (Medium) -- Won't Do
- SEC-0029: TCP sink has no authentication mechanism (Medium) -- **Won't Do** (pass 5)

### Web / API / Network

- SEC-0001: HTTPS plaintext transmission (Critical) -- Closed
- SEC-0003: HTTP header injection (High) -- Closed
- SEC-0004: TCP/UDP plaintext transmission (High) -- Won't Do
- SEC-0018: HTTP status check too permissive (Low) -- Closed
- SEC-0025: Network sinks skip sanitizeKey on JSON attr keys (Medium) -- Closed (pass 4)
- SEC-0026: All network sinks transmit cleartext -- no TLS support (High) -- **Won't Do** (pass 5)
- SEC-0028: HTTP sink does not validate server identity (Medium) -- **Won't Do** (pass 5)
- SEC-0035: UDP truncation produces malformed JSON (Low) -- **Closed** (pass 5)

### Input Validation / Injection

- SEC-0006: Log injection via unsanitized messages (High) -- Closed (pass 3)
- SEC-0007: Path traversal in rotating file (High) -- Closed (`..` only; symlink/absolute criterion tracked as SEC-0037)
- SEC-0037: Log path symlink-following / unconstrained absolute writes (Medium) -- **Open** (#46; APPSEC-02)
- SEC-0010: Text handler unescaped string values (Medium) -- Closed
- SEC-0019: Journald fallback unsanitized stderr (Low) -- Closed
- SEC-0020: Windows Event Log stderr fallback missing sanitizeOutput() (Medium) -- Closed (pass 3)
- SEC-0021: Journald stderr fallback unsanitized attribute keys (Low) -- Closed (pass 3)
- SEC-0022: Windows Event Log unsanitized attribute keys (Low) -- Closed (pass 3)
- SEC-0023: Syslog writeSDString no control char escaping (Low) -- Closed (pass 3)
- SEC-0031: Logger name and source_file not sanitized in text handler (Low) -- **Closed** (pass 5)
- SEC-0032: Syslog hostname bypasses writeSyslogName sanitization (Low) -- **Closed** (pass 5)
- SEC-0036: JSON key collision via duplicate or sanitize-colliding keys (Low) -- **Closed** (pass 5)

### Sensitive Data Handling

- SEC-0005: isSensitiveKey() dead code (High) -- Closed
- SEC-0009: Rotating file missing isSensitiveKey() auto-redaction (High) -- Closed (pass 3)
- SEC-0012: Secret values plaintext in memory (Medium) -- Closed
- SEC-0013: Async handler drops secret attributes (Medium) -- Closed
- SEC-0014: Gitleaks blanket exclusion (Medium) -- Closed
- SEC-0024: Gitleaks allowlist incomplete (Info) -- Closed (pass 3)
- SEC-0027: Secrets in message body bypass all redaction (Medium) -- **Closed** (pass 5)
- SEC-0030: Sensitive key list incomplete (Low) -- **Closed** (pass 5)
- SEC-0038: Auto-redaction blind spot for keys longer than 64 bytes (Low) -- **Open** (#47; APPSEC-03)

### Memory Safety / Concurrency

- SEC-0002: Dangling pointer in stderrHandler (Critical) -- Closed
- SEC-0011: Global fatal_hook race condition (Medium) -- Closed
- SEC-0033: Data race on Level field in setLevel across handlers (Low) -- **Closed** (pass 5)

### File System

- SEC-0034: Rotating log files created world-readable (Medium) -- **Open / REGRESSION** (0o600 lost in `fa0de64`; #43; APPSEC-01)
- SEC-0039: Silent whole-record drop when rendered size exceeds 8KB buffer (Low) -- **Open** (#48; APPSEC-04; also audit-integrity)

### Supply Chain

- SEC-0008: spice on floating main branch (High) -- **Closed** (resolved by removal, 97c5c59; #29 closed)
- SEC-0040: CI catalog components pinned to mutable version tags, not commit SHAs (Low) -- **Won't Do** (accepted risk; first-party catalog)
- SEC-0041: Vendored thread_pool scripts committed mode 0777 (Info) -- **Open** (informational; cross-ref QUALITY NEW-7)

### Operations / CI-CD

- SEC-0015: SECURITY.md false claims (Medium) -- Closed
- SEC-0017: No CI build/test pipeline (Medium) -- Closed

### Documentation / Tracking (Phase 3 Audit)

- GAP-0026: API.md documents stale convenience function signatures (Medium) -- **Closed** (pass 5)
- GAP-0027: ARCHITECTURE.md module tree missing 4 source files (Low) -- **Closed** (pass 5)
- GAP-0028: GitLab issue #40 open but PERF-025 marked Won't Do (Low) -- **Won't Do** (pass 5)

---

## Remediation Roadmap

### Quick Wins (less than 1 day each)

| ID | Finding | Effort | Impact |
|----|---------|--------|--------|
| SEC-0034 | **(OPEN/REGRESSION)** Re-add `.permissions = 0o600` to createFile in rotating_file | 30 min | Restores owner-only log files (#43) |
| SEC-0038 | **(OPEN)** Remove 64-byte scan cap in isSensitiveKey | 20 min | Closes long-key redaction bypass (#47) |
| SEC-0002 | Fix stderrHandler dangling pointer | 1 hour | Eliminates Critical UB |
| SEC-0008 | Pin spice to tagged release -- **Closed (removed entirely, 97c5c59)** | -- | Supply chain risk eliminated |
| SEC-0014 | Narrow gitleaks exclusion | 15 min | Improves secret scanning |
| SEC-0015 | Fix SECURITY.md false claims | 30 min | Accurate documentation |
| SEC-0018 | Fix HTTP status parsing | 30 min | Correct error detection |
| SEC-0009 | Add isSensitiveKey() to rotating_file -- **Closed** (pass 3) | 30 min | Consistent auto-redaction |
| SEC-0024 | Add gitleaks allowlist entries for json_logging/accept.zig | 15 min | Prevents false positive CI failures |
| SEC-0030 | Extend sensitive_keys list with missing patterns | 30 min | Broader auto-redaction coverage |
| SEC-0031 | Sanitize rec.logger in text handler | 15 min | Prevents logger name injection |
| SEC-0032 | Apply writeSyslogName to hostname in syslog handler | 15 min | Consistent syslog field sanitization |
| SEC-0033 | Atomic or mutex-guarded setLevel in all handlers | 1 hour | Eliminates level field data race |
| GAP-0026 | Update API.md stderrHandler/stderrJsonHandler signatures | 30 min | Compilable documentation examples |
| GAP-0027 | Add 4 missing files to ARCHITECTURE.md module tree | 15 min | Accurate architecture docs |
| GAP-0028 | Close GitLab #40 or reopen PERF-025 to resolve status mismatch | 5 min | Tracker/docs consistency |

### Medium Effort (1-5 days each)

| ID | Finding | Effort | Impact |
|----|---------|--------|--------|
| SEC-0003 | Validate HTTP headers | 2 hours | Prevents header injection |
| SEC-0005 | Wire isSensitiveKey into handlers | 4 hours | Enables auto-redaction |
| SEC-0006 | Sanitize messages/keys/values in rotating_file -- **Closed** (pass 3) | 2 hours | Prevents log injection in rotating files |
| SEC-0010 | Escape string values in text handler | 2 hours | Prevents value injection |
| SEC-0007 | Validate rotating file path | 2 hours | Prevents path traversal (`..` only; symlink/absolute criterion now tracked as SEC-0037) |
| SEC-0037 | **(OPEN)** Constrain log path: reject absolute/escaping/symlinked paths; open relative to base Dir with resolve_beneath | 2-3 hours | Closes SEC-0007 symlink criterion (#46) |
| SEC-0039 | **(OPEN)** Size handler format buffers to MAX_RECORD_SIZE or truncate-with-marker; add dropped/truncated metric | 1 hour | Prevents silent audit-record loss (#48) |
| SEC-0011 | Atomic fatal_hook access | 1 hour | Eliminates race condition |
| SEC-0017 | Add CI build/test stage | 2 hours | Automated regression detection |
| SEC-0019 | Sanitize journald stderr fallback | 1 hour | Consistent sanitization |
| SEC-0020 | Sanitize windows_eventlog stderr fallback | 30 min | Consistent sanitization |
| SEC-0021 | Sanitize journald stderr fallback attr keys | 15 min | Consistent key sanitization |
| SEC-0022 | Sanitize windows_eventlog attr keys | 15 min | Consistent key sanitization |
| SEC-0023 | Add control char escaping to syslog writeSDString | 30 min | Defense-in-depth for downstream parsers |
| SEC-0027 | Document message body redaction limitation + best practices | 2 hours | Prevents false sense of security |
| SEC-0035 | Handle UDP truncation gracefully (drop or valid-JSON truncation) | 2 hours | Prevents malformed JSON in audit logs |
| SEC-0036 | Deduplicate or document JSON key collision | 1 hour | Prevents ambiguous log entries |

### Strategic (more than 5 days each)

| ID | Finding | Effort | Impact |
|----|---------|--------|--------|
| SEC-0026 | Implement TLS for at least one network sink (TCP or HTTP) | 5-10 days | Encrypted log transport |
| SEC-0001 | Implement TLS for HTTP sink (or reject https://) | 3-5 days | Encrypted log transport |
| SEC-0004 | Add optional TLS for TCP sink | 3-5 days | Encrypted TCP transport |
| SEC-0013 | Fix async handler attribute serialization | 2-3 days | Complete async logging |
| SEC-0016 | Add mTLS/auth for network sinks | 5+ days | Authenticated log transport |
| SEC-0028 | Implement server certificate validation (requires TLS) | 2-3 days | Prevents MITM attacks |
| SEC-0029 | Add authentication to TCP sink (requires TLS for mTLS) | 3-5 days | Authenticated TCP transport |
| SEC-0012 | Implement secret memory scrubbing | 2-3 days | Defense-in-depth |

---

## Blockers and Unknowns

1. **TLS implementation** (SEC-0026, SEC-0028, SEC-0029): Zig's `std.crypto.tls` client support maturity for 0.15 is unverified. May require a C TLS library import. SEC-0028 (server identity validation) and SEC-0029 (TCP authentication) are both blocked by TLS availability. **What would confirm:** Successful TLS handshake using `std.crypto.tls.Client` in a test against a local TLS server.

2. **Async handler attribute redesign** (SEC-0013): The `QueuedRecord` fixed-buffer approach fundamentally limits attribute fidelity. A proper fix may require architectural changes to the queue. **What would confirm:** A design document for attribute serialization/deserialization that preserves type tags.

3. **CI Zig availability** (SEC-0017): Confirmed that Zig 0.15 is available, but the specific CI runner image/tag with Zig 0.15 needs to be identified. **What would confirm:** A working CI job using a Zig 0.15 container image.

4. **Message body redaction scope** (SEC-0027): Scanning message strings for sensitive patterns is inherently imprecise (regex false positives/negatives, performance overhead). The design decision of whether to implement message scanning vs. documenting the limitation needs team input. **What would confirm:** Team consensus on approach (document-only vs. opt-in scanning).

5. **JSON key collision resolution** (SEC-0036): The sanitizeKey `_` replacement strategy is simple and fast but can produce collisions. Changing to hex-encoding would alter the output format for all existing deployments. **What would confirm:** Assessment of whether any downstream consumers depend on the current sanitized key format.

6. **Long-key redaction bypass** (SEC-0038, `confidence::suspected`): exploitability depends on whether attribute keys are ever derived from untrusted input (normally they are developer constants). **What would confirm:** a unit test `isSensitiveKey("a" ** 64 ++ "password")` returning `false` at HEAD (currently expected), and a formatter test showing the value rendered in cleartext for such a key.

7. **Silent over-buffer record drop** (SEC-0039, `confidence::suspected`): inferred from buffer sizing (8 KB handler buffer vs 64 KB record budget) and the `catch return error.WriteFailed` pattern, not observed at runtime. **What would confirm:** logging a record whose rendered size is ~16 KB through the text/rotating handler and observing no line written and only a generic `WriteFailed`/`incErrors()` signal.

8. **Migration-regression reconciliation** (process, prompted by SEC-0034): the 0o600 fix was lost in the Zig 0.16 migration while the docs still claimed closure. **What would confirm/clear:** a one-time pass diffing every `**Closed**` SEC-* remediation against HEAD `bd50a7f` to detect any other reverted fixes.

---

## Cross-Reference to Prior Gap Analysis

| SEC ID | Prior GAP ID | Notes |
|--------|-------------|-------|
| SEC-0001 | GAP-0006 | Same finding, now security-scored |
| SEC-0002 | GAP-0001 | Same finding, now security-scored |
| SEC-0003 | (new) | HTTP header injection -- new finding |
| SEC-0004 | (new) | TCP/UDP plaintext -- new finding |
| SEC-0005 | (new) | Dead auto-redaction code -- new finding |
| SEC-0006 | (new) | Log injection -- new finding |
| SEC-0007 | (new) | Path traversal -- new finding |
| SEC-0008 | (new) | Supply chain -- new finding |
| SEC-0009 | (new) | Rotating file secret redaction -- new finding |
| SEC-0010 | (new) | Text handler value escaping -- new finding |
| SEC-0011 | (new) | Fatal hook race -- new finding |
| SEC-0012 | (new) | Secret memory exposure -- new finding |
| SEC-0013 | GAP-0016 | Security dimension of async attr drop |
| SEC-0014 | (new) | Gitleaks blanket exclusion -- new finding |
| SEC-0015 | GAP-0013, GAP-0014 | Security dimension of false SECURITY.md claims |
| SEC-0016 | (new) | No authentication for sinks -- new finding |
| SEC-0017 | GAP-0018 | Security dimension of missing CI |
| SEC-0018 | (new) | HTTP status parsing -- new finding |
| SEC-0019 | (new) | Journald stderr unsanitized -- new finding |
| SEC-0020 | GAP-0036 | Windows Event Log stderr fallback missing sanitizeOutput() -- new finding |
| SEC-0021 | (new) | Journald stderr fallback unsanitized attribute keys -- new finding |
| SEC-0022 | (new) | Windows Event Log unsanitized attribute keys -- new finding |
| SEC-0023 | (new) | Syslog writeSDString no control char escaping -- new finding |
| SEC-0024 | (new) | Gitleaks allowlist incomplete -- new finding |
| SEC-0025 | (new) | Network sinks skip sanitizeKey on JSON attr keys -- new finding (pass 4) |
| SEC-0026 | SEC-0001, SEC-0004 | Umbrella finding: all network sinks cleartext. Subsumes SEC-0001 scope (HTTP) and SEC-0004 scope (TCP/UDP). |
| SEC-0027 | (new) | Message body bypasses redaction -- phase 3 verification audit |
| SEC-0028 | (new) | HTTP sink no server identity validation -- phase 3 verification audit |
| SEC-0029 | SEC-0016 | TCP-specific auth gap. SEC-0016 (Won't Do) covers TCP+UDP broadly; this tracks TCP for when TLS is added. |
| SEC-0030 | (new) | Incomplete sensitive key list -- phase 3 verification audit |
| SEC-0031 | (new) | Logger name/source_file not sanitized -- phase 3 verification audit |
| SEC-0032 | (new) | Syslog hostname bypasses writeSyslogName -- phase 3 verification audit |
| SEC-0033 | SEC-0011 | Level field race, same pattern as SEC-0011 (fatal_hook) but in handler contexts |
| SEC-0034 | (new) | Log file default permissions -- phase 3 verification audit |
| SEC-0035 | (new) | UDP truncation malformed JSON -- phase 3 verification audit |
| SEC-0036 | (new) | JSON key collision -- phase 3 verification audit |
| SEC-0037 | SEC-0007 | Log path symlink/absolute write -- AppSec review (APPSEC-02); SEC-0007 symlink criterion unmet |
| SEC-0038 | (new) | Auto-redaction blind spot for keys >64 bytes -- AppSec review (APPSEC-03) |
| SEC-0039 | (new) | Silent whole-record drop > 8KB buffer -- AppSec review (APPSEC-04) |
| SEC-0040 | SEC-0008 | CI catalog mutable version-tag pins -- AppSec review (supply-chain theme) |
| SEC-0041 | (new) | Vendored thread_pool scripts mode 0777 -- AppSec review; cross-ref QUALITY NEW-7 |
| GAP-0026 | (new) | API.md stale convenience function signatures -- phase 3 audit |
| GAP-0027 | (new) | ARCHITECTURE.md module tree missing 4 files -- phase 3 audit |
| GAP-0028 | (new) | GitLab #40 / PERF-025 status mismatch -- phase 3 audit |

---

## Parallelism & Spice Integration Gap Analysis

**Added:** 2026-03-30
**Last updated:** 2026-03-30 (gap closure pass)
**Analyst:** Claude Opus 4.6 (manual review + automated closure)

### Executive Summary

The `spice` dependency is correctly declared in `build.zig.zon` and was wired into `build.zig` as a separate `parallel` module. However, the parallel module was effectively dead code -- none of its functions were called by any handler, sink, or logger.

**Gap closure pass (2026-03-30):** Restructured `parallel.zig` into the `slogz` module (eliminating the separate module that caused Zig 0.15 cross-module file ownership conflicts). Added Handler-native `dispatchHandlers()` and `flushHandlers()` functions. Wired `multi_handler` to use parallel dispatch for both `handle()` and `flush()`. Added `slogz.deinit()` for pool lifecycle, `initPool()` for configurable allocator, and re-exported `parallel` from `slogz.zig`. All tests pass.

### Parallelism Findings

| Rank | ID | Severity | Finding | Component | Evidence | Fix | Status |
|------|---------|----------|---------|-----------|----------|-----|--------|
| 1 | PAR-0001 | High | `parallel.zig` functions are dead code -- never called outside own tests | parallel.zig, all handlers | `grep` for `parallelRecordFormat` etc. found zero call sites | Added `dispatchHandlers()` and `flushHandlers()` Handler-native functions; wired into multi_handler | **Closed** |
| 2 | PAR-0002 | High | `multi_handler.zig` dispatches to N handlers sequentially in a `for` loop | multi_handler.zig | Sequential `for` loop in `handle()` | Replaced with `parallel.dispatchHandlers()` call with stack-allocated results | **Closed** |
| 3 | PAR-0003 | High | `multi_handler.zig` flushes N handlers sequentially | multi_handler.zig | Sequential `for` loop in `flush()` | Replaced with `parallel.flushHandlers()` call with stack-allocated results | **Closed** |
| 4 | PAR-0004 | Medium | `async_handler.zig` spawns raw `std.Thread` instead of spice worker | async_handler.zig:59,80 | `std.Thread.spawn(.{}, workerThread, .{self})` | Dedicated worker thread is the correct pattern for a persistent queue consumer | **Won't Do** |
| 5 | PAR-0005 | Medium | Unit test target missing `parallel` module import | build.zig | Unit tests had no `spice` import | Restructured: parallel.zig is now part of slogz module; added `spice` import to unit test target | **Closed** |
| 6 | PAR-0006 | Medium | Global spice pool never cleaned up -- no `deinitPool()` call path | parallel.zig | `deinitPool()` defined but never called | Added `slogz.deinit()` which calls `parallel.deinitPool()` | **Closed** |
| 7 | PAR-0007 | Low | `parallel.zig` `HandlerTarget` uses `*anyopaque` -- not wired to actual `Handler` type | parallel.zig | `HandlerTarget` incompatible with `handler.zig:Handler` | Added new `dispatchHandlers()` / `flushHandlers()` that work directly with `Handler` type | **Closed** |
| 8 | PAR-0008 | Low | TCP/HTTP sink retry backoff uses blocking `std.Thread.sleep` | tcp_sink.zig, http_sink.zig | `std.Thread.sleep(...)` in retry loops | Blocking sleep is appropriate for network retry backoff -- not a spice concern | **Won't Do** |
| 9 | PAR-0009 | Low | `parallel.zig` not re-exported from `slogz.zig` | slogz.zig | No `pub const parallel` line | Added `pub const parallel = @import("parallel.zig")` to slogz.zig | **Closed** |
| 10 | PAR-0010 | Info | `parallel.zig` tests skip entirely when spice disabled | parallel.zig | `if (!build_options.enable_spice) return error.SkipZigTest;` | Added Handler-native tests that run regardless of spice (test sequential path) | **Closed** |
| 11 | PAR-0011 | Medium | `getPool()` uses page_allocator for spice ThreadPool -- no lifecycle control | parallel.zig | Hardcoded `page_allocator` | Added `initPool(allocator, config)` for explicit initialization with custom allocator | **Closed** |
| 12 | PAR-0012 | Low | `multi_handler.zig` close() is sequential -- could parallelize handler close | multi_handler.zig:89-92 | Sequential `for` loop in `close()` | One-time shutdown cost; not worth the complexity | **Won't Do** |

### Closure Summary

| Status | Count |
|--------|-------|
| Closed | 9 |
| Won't Do | 3 |
| Open | 0 |
| **Total** | **12** |

### Key Implementation Decisions

1. **Module restructuring:** `parallel.zig` was moved from a separate Zig module into the `slogz` module (via relative import). This was required because Zig 0.15 enforces that a file can only belong to one module, and `parallel.zig` needed to import `handler.zig` and `record.zig` (which belong to slogz).

2. **Handler-native parallel API:** Rather than adapting the existing `HandlerTarget`/`parallelHandlerDispatch` (which operates on pre-formatted `[]const u8`), new `dispatchHandlers()` and `flushHandlers()` functions were added that work directly with `Handler` + `*const Record`. The original byte-oriented functions remain for future sink-level parallelism.

3. **async_handler Won't Do:** The dedicated worker thread pattern in `async_handler` is architecturally correct for a persistent queue consumer. Spice's fork/join model is designed for CPU-bound work decomposition, not long-running I/O loops.

4. **Blocking retry Won't Do:** `std.Thread.sleep` in TCP/HTTP retry backoff is the standard pattern. These retries happen on the caller's thread within a mutex-protected section -- moving to spice would add complexity without benefit.
