# Security Gap Analysis -- slogz (Zig Structured Logging Library)

**Repository:** gitlab.com/devnw/zig/slog
**Branch:** main (commit 677630f)
**Last updated:** 2026-03-24 (rev 3 -- pass 3: SEC-0006/SEC-0009 fixed, SEC-0020-0024 closed, SEC-0008 blocked)
**Analyst:** Phase 3 Adversarial Review + Claude Opus 4.6 (automated scoring)
**Methodology:** Risk Score = Impact(1-5) x Likelihood(1-5) x 4

---

## Summary

| Severity | Count | Closed | Blocked | Won't Do | Open |
|----------|-------|--------|---------|----------|------|
| Critical | 2 | 2 | 0 | 0 | 0 |
| High | 7 | 5 | 1 | 1 | 0 |
| Medium | 9 | 8 | 0 | 1 | 0 |
| Low | 5 | 5 | 0 | 0 | 0 |
| Info | 1 | 1 | 0 | 0 | 0 |
| **Total** | **24** | **21** | **1** | **2** | **0** |

### Top Risks (Open Only)

1. **SEC-0008** (High, Score 48) -- Supply chain: spice on floating main branch. **Blocked** -- requires upstream spice repo to publish tagged release.

### Immediate Actions Required

- **No secrets are currently leaked** -- no rotation required.
- **SEC-0006 and SEC-0009 FIXED (pass 3):** rotating_file.zig now has sanitizeOutput on messages, sanitizeKey on attr keys, and isSensitiveKey auto-redaction. See [confidential issue #36](https://gitlab.com/devnw/zig/slog/-/issues/36) (closed).
- SEC-0008 (spice on floating main branch) blocked on upstream tagged release.

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
| 8 | SEC-0008 | High | 48 | Supply chain: spice on floating main branch | build.zig.zon | CWE-1357 / A06:2021 | build.zig.zon:19-22 | Pin to tagged release | TBD | 2026-04-22 | **Blocked** (upstream spice repo needs tagged release) |
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

**Summary:** The `spice` dependency in `build.zig.zon` tracks the `main` branch of `gitlab.com/devnw/zig/spice` instead of a pinned tagged release. The hash provides some integrity protection, but any update to main changes the archive content. The `json` dependency correctly uses a tagged release (`v0.1.0`).

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

## Findings by Area

### Authentication and Authorization
- SEC-0016: No authentication for TCP/UDP sinks (Medium)

### Web / API / Network
- SEC-0001: HTTPS plaintext transmission (Critical)
- SEC-0003: HTTP header injection (High)
- SEC-0004: TCP/UDP plaintext transmission (High)
- SEC-0018: HTTP status check too permissive (Low)

### Input Validation / Injection
- SEC-0006: Log injection via unsanitized messages -- Closed (pass 3) (High)
- SEC-0007: Path traversal in rotating file (High) -- Closed
- SEC-0010: Text handler unescaped string values (Medium) -- Closed
- SEC-0019: Journald fallback unsanitized stderr (Low) -- Closed
- SEC-0020: Windows Event Log stderr fallback missing sanitizeOutput() (Medium) -- Closed (pass 3)
- SEC-0021: Journald stderr fallback unsanitized attribute keys (Low) -- Closed (pass 3)
- SEC-0022: Windows Event Log unsanitized attribute keys (Low) -- Closed (pass 3)
- SEC-0023: Syslog writeSDString no control char escaping (Low) -- Closed (pass 3)

### Sensitive Data Handling
- SEC-0005: isSensitiveKey() dead code (High) -- Closed
- SEC-0009: Rotating file missing isSensitiveKey() auto-redaction -- Closed (pass 3) (High)
- SEC-0012: Secret values plaintext in memory (Medium) -- Closed
- SEC-0013: Async handler drops secret attributes (Medium) -- Closed
- SEC-0014: Gitleaks blanket exclusion (Medium) -- Closed
- SEC-0024: Gitleaks allowlist incomplete (Info) -- Closed (pass 3)

### Memory Safety
- SEC-0002: Dangling pointer in stderrHandler (Critical)
- SEC-0011: Global fatal_hook race condition (Medium)

### Supply Chain
- SEC-0008: spice on floating main branch (High)

### Operations / CI-CD
- SEC-0015: SECURITY.md false claims (Medium)
- SEC-0017: No CI build/test pipeline (Medium)

---

## Remediation Roadmap

### Quick Wins (less than 1 day each)

| ID | Finding | Effort | Impact |
|----|---------|--------|--------|
| SEC-0002 | Fix stderrHandler dangling pointer | 1 hour | Eliminates Critical UB |
| SEC-0008 | Pin spice to tagged release | 15 min | Fixes supply chain risk |
| SEC-0014 | Narrow gitleaks exclusion | 15 min | Improves secret scanning |
| SEC-0015 | Fix SECURITY.md false claims | 30 min | Accurate documentation |
| SEC-0018 | Fix HTTP status parsing | 30 min | Correct error detection |
| SEC-0009 | Add isSensitiveKey() to rotating_file -- **Closed** (pass 3) | 30 min | Consistent auto-redaction |
| SEC-0024 | Add gitleaks allowlist entries for json_logging/accept.zig | 15 min | Prevents false positive CI failures |

### Medium Effort (1-5 days each)

| ID | Finding | Effort | Impact |
|----|---------|--------|--------|
| SEC-0003 | Validate HTTP headers | 2 hours | Prevents header injection |
| SEC-0005 | Wire isSensitiveKey into handlers | 4 hours | Enables auto-redaction |
| SEC-0006 | Sanitize messages/keys/values in rotating_file -- **Closed** (pass 3) | 2 hours | Prevents log injection in rotating files |
| SEC-0010 | Escape string values in text handler | 2 hours | Prevents value injection |
| SEC-0007 | Validate rotating file path | 2 hours | Prevents path traversal |
| SEC-0011 | Atomic fatal_hook access | 1 hour | Eliminates race condition |
| SEC-0017 | Add CI build/test stage | 2 hours | Automated regression detection |
| SEC-0019 | Sanitize journald stderr fallback | 1 hour | Consistent sanitization |
| SEC-0020 | Sanitize windows_eventlog stderr fallback | 30 min | Consistent sanitization |
| SEC-0021 | Sanitize journald stderr fallback attr keys | 15 min | Consistent key sanitization |
| SEC-0022 | Sanitize windows_eventlog attr keys | 15 min | Consistent key sanitization |
| SEC-0023 | Add control char escaping to syslog writeSDString | 30 min | Defense-in-depth for downstream parsers |

### Strategic (more than 5 days each)

| ID | Finding | Effort | Impact |
|----|---------|--------|--------|
| SEC-0001 | Implement TLS for HTTP sink (or reject https://) | 3-5 days | Encrypted log transport |
| SEC-0004 | Add optional TLS for TCP sink | 3-5 days | Encrypted TCP transport |
| SEC-0013 | Fix async handler attribute serialization | 2-3 days | Complete async logging |
| SEC-0016 | Add mTLS/auth for network sinks | 5+ days | Authenticated log transport |
| SEC-0012 | Implement secret memory scrubbing | 2-3 days | Defense-in-depth |

---

## Blockers and Unknowns

1. **TLS implementation** (SEC-0001, SEC-0004): Zig's `std.crypto.tls` client support maturity for 0.15 is unverified. May require a C TLS library import. **What would confirm:** Successful TLS handshake using `std.crypto.tls.Client` in a test against a local TLS server.

2. **Async handler attribute redesign** (SEC-0013): The `QueuedRecord` fixed-buffer approach fundamentally limits attribute fidelity. A proper fix may require architectural changes to the queue. **What would confirm:** A design document for attribute serialization/deserialization that preserves type tags.

3. **CI Zig availability** (SEC-0017): Confirmed that Zig 0.15 is available, but the specific CI runner image/tag with Zig 0.15 needs to be identified. **What would confirm:** A working CI job using a Zig 0.15 container image.

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
