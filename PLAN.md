# Plan and Status

**Goal:** on Wi‑Fi only, cap video streams at about 1.5 Mbps per flow, like AT&T Video Management, so adaptive players fall back to SD. It must not use a Network Extension (MDM blocks them).

## Decisions (defaults chosen 2026‑10‑01; easy to revisit)

| Question | Decision | Why |
|---|---|---|
| Per-flow or total cap | **Per stream by default**; "total" is available in Settings | Matches AT&T: video is capped while browsing stays quick |
| What to throttle | **Inbound TCP and UDP from port 443** by default; "all traffic" is optional | Covers HTTPS video and QUIC (YouTube) without keeping CDN lists |
| Privilege model | **One admin prompt per change** (AppleScript `with administrator privileges`) | Works today with no helper install; macOS caches the credential for a few minutes |
| Keep the proxy | **Removed** | pf covers every app, including QUIC; the proxy was broken (see below) |

## Status of the original findings

| # | Problem in the JR prototype | Status |
|---|---|---|
| C1 | `applyLimits` built pf rules and threw them away; pf never enabled | ✅ Rewritten: `ThrottleScript.onScript` loads the anchor and runs `pfctl -E` (token kept) |
| C2 | Anchor `it.murus.snail` is never evaluated | ✅ `com.apple/snailreborn` |
| C3 | "Create Pipe 1" had no pf rule | ✅ Pipe and rule are always applied together |
| C4/C5 | Shell injection (including as root) from text fields | ✅ Validated config only; tests cover injection attempts |
| C6 | Quit and Reset wiped every proxy and every pipe and prompted on each quit | ✅ Off removes only Snail's anchor, pipe, and token; quitting prompts only if a limit is on and the setting is enabled |
| C7 | Unprivileged `networksetup` claimed success | ✅ Removed; errors are shown in the UI |
| C8/C9 | Proxy broke HTTP and deadlocked under load | ✅ Proxy removed |
| H1 | No per-video targeting | ✅ Per-flow mask and port-443 scope |
| H2/H3/H4/H5 | Proxy aggregate, QUIC, env-var, and DNS issues | ✅ Removed along with the proxy |
| H6 | 32-bit counters, hard-coded en0, 1024 units | ✅ `NET_RT_IFLIST2` 64-bit counters, CoreWLAN interface, SI units |
| H7 | Fake "root authorized" flag | ✅ Removed |
| M1/M2 | Dead NE code, copied Snail protocols and plists | ✅ Deleted |
| M3 | README didn't match the app | ✅ Rewritten |
| M4 | `snailctl delete` missing; global flush | ✅ New CLI: `on/off/status/rules/script` |
| M5 | Logic in views, no tests, no build script, no git | ✅ Logic is in SnailCore, 12 tests, `scripts/build-app.sh`, git baseline `81170fd` |
| M6 | "2056" default | ✅ Presets 1500/3000/5000 |

## UI/UX rewrite

The 4-tab, 880×640 dashboard (proxy logs, raw monitor, app launcher, raw pipes) became a **menu bar utility**:

- **Popover:** status icon, a one-line status ("Each stream capped at 1.5 Mbps"), and one switch.
  - SD/HD/Full HD segmented control, with the resulting video quality spelled out.
  - Live Wi‑Fi down/up and a 60 s graph. A dashed limit line appears only in total mode, where it means something.
  - Inline error and "Settings changed · Apply" banners, plus Settings (⌘,) and Quit (⌘Q).
- **Settings:** a grouped form for custom speed, per-stream vs. total, scope, Wi‑Fi status, quit behavior, the exact rules, and Remove Rules.
  - Edits are staged while on, so you don't get a password prompt per keystroke.
- No Dock icon (`LSUIElement`). Light and dark mode, system accent color, and accessibility labels throughout.

## Remaining work

1. **Field test on this Mac (needs you; admin password):**
   - Turn Stream Saver on at SD.
   - Watch YouTube with quality on Auto and run a speed test.
   - Confirm about 1.5 Mbps per connection and that Jamf doesn't reset pf. Commands are in README → "Verify it works".
   - Things to watch for:
     - Whether `mask dst-port` gives true per-flow pipes for both IPv4 and IPv6. The pf grammar is verified by tests; the kernel behavior isn't yet.
     - Whether `pfctl -E` succeeds under the Jamf profile.
2. **Prompt-free toggling (optional):** an `SMAppService` LaunchDaemon helper with XPC. Check first whether Jamf allows background items.
3. **Launch at login (optional):** `SMAppService.mainApp`, as a Settings toggle.
4. **Inbound-only shaping caveat:** packets are delayed after they cross the Wi‑Fi link, so TCP backs off and real usage converges to the cap, the same idea as AT&T's pacing. A brief burst at the start of each flow still arrives at full speed. If measured savings fall short, consider a smaller pipe queue (`queue 20`) to tighten the feedback loop.
5. **Hotspot/SSID awareness (optional):** turn on automatically only on specific networks, such as a phone hotspot. Reading the SSID needs Location permission on macOS 14+.
