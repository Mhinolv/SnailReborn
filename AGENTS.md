# AGENTS.md

Guidance for AI coding agents working in this repo. Read [README.md](README.md) for what the project is and [PLAN.md](PLAN.md) for status.

## Hard constraints

1. **No Network Extensions.** The target Mac is Jamf-managed and blocks system extensions and NE providers. Do not add `NEFilterDataProvider`, `NEAppProxyProvider`, `NEPacketTunnelProvider`, content filters, or VPN configurations. Use kernel pf/dummynet only.
2. **Only touch what Snail owns:** anchor `com.apple/snailreborn`, dnctl pipe `47101`, and `/var/run/snailreborn.{json,token}`. Never `dnctl -f flush`, `pfctl -F` on the main ruleset, or `pfctl -d`. Turn pf on with `pfctl -E` and release it with `pfctl -X <token>`. The anchor must stay under `com.apple/`, because `/etc/pf.conf` only evaluates `com.apple/*`.
3. **Nothing user-typed reaches a shell.** Root scripts are built only in `ThrottleScript` from a `ThrottleConfig` that passed `validated()`: integer kbps in range, enum raw values, and an interface name matching `^[a-z]{1,8}[0-9]{1,3}$`. To add a field, validate it and add a test.
4. **Scope to Wi‑Fi** via `WiFi.interfaceName()` (CoreWLAN). Never hard-code `en0`.
5. **Units are SI.** 1 Kbps = 1000 bit/s, matching dnctl's `Kbit/s`. Format with `Rate.format`. The default is 1500 Kbps per stream.
6. **Don't run privileged or network-altering commands** (`sudo`, `pfctl` without `-n`, `dnctl` config, `networksetup -set*`) on the user's machine unless the user explicitly asks. `swift build`, `swift test`, `snailctl rules|script|status|apps`, and `pfctl -n` are fine.
7. **No Murus/Snail proprietary material:** no `it.murus.*` identifiers and no copied plists or protocols. The bundle ID is `com.markhinojosa.SnailReborn`.

## Build and verify

```bash
swift build
```

```bash
swift test
```

```bash
./scripts/build-app.sh
```

```bash
SNAIL_SNAPSHOT_DIR=/tmp/shots swift run SnailApp
```

- `swift build` must produce zero warnings.
- `./scripts/build-app.sh` produces `build/SnailReborn.app` and `build/snailctl`.
- The `SNAIL_SNAPSHOT_DIR` run (DEBUG only) renders the popover and Settings to PNGs. Look at them after any UI change.

## Code map

- `Sources/SnailCore/`: all logic, no UI.
  - `ThrottleConfig.swift`: config, validation, `Preset`s, `SnailError`, and `Rate` formatting.
  - `ThrottleScript.swift`: **pure** builders for pf rules, dnctl args, and the on/off root scripts.
  - `ThrottleController.swift`: `PrivilegedRunner` (`AdminPromptRunner` for the app, `RootShellRunner` for sudo), apply/remove, and reading the active state.
  - `NetworkInterfaces.swift`: Wi‑Fi interface lookup, 64-bit byte counters (`NET_RT_IFLIST2`), and `RoutePath` (detects a VPN or other interface bypassing Wi‑Fi).
  - `AppTraffic.swift`: per-app rates from `/usr/bin/nettop` (unprivileged, fixed arguments). Display only; pf can't match by process.
- `Sources/SnailCLI/main.swift`: `snailctl`.
- `Sources/SnailApp/`: SwiftUI menu bar app.
  - `SnailModel` (all state and intents) and `MenuContentView` (popover).
  - `SettingsView`, `ThroughputSparkline`, and `DebugSnapshots` (DEBUG only).
- `Tests/SnailCoreTests/`: XCTest.

## Conventions

- Swift 5.9 language mode, macOS 13+, no third-party dependencies without approval.
- 4-space indent, minimal comments explaining *why*.
- Views hold no logic. Put intents on `SnailModel` and side effects in SnailCore.
- `AdminPromptRunner` uses `NSAppleScript` and must run on the main thread. `SnailModel.perform` defers one runloop tick so the busy state renders first.
- UI follows the macOS HIG:
  - System fonts, semantic colors, and the accent color.
  - Light and dark mode.
  - Accessibility labels on icon-only controls.
  - Status shown with icon plus text, never color alone.
- If pf is ever blocked and a user-space proxy is needed again, build it on `Network.framework`. The removed BSD-socket proxy is in git history (commit `81170fd`) as a reference for what *not* to do.

## Product overview

SnailReborn is a menu bar app for one Jamf-managed Mac. It caps download and upload speed per stream on the Wi-Fi interface. It uses pf and dummynet through an admin password prompt. It has no Network Extension. `snailctl` gives the same functions on the command line.

- Users: one person who wants to slow large transfers so calls and browsing stay usable.
- Limits: pf cannot match by process, so per-app numbers are display only.
- Agents must not run privileged commands (rule 6). Tests use the pure builders in `ThrottleScript`.
- Visual QA: `scripts/snapshot.sh <out-dir>` renders the popover and Settings in light and dark mode.

## Team Roadmap Workflow (multi-agent, GitHub)

A multi-agent team works the release milestone in GitHub (`Mhinolv/SnailReborn`). GitHub Issues are the single source of truth; every change ships as a pull request into `main`. Everyone writes in ASD-STE100 Simplified Technical English with hard length budgets (see the product-team skill, `~/.claude/writing_standard.md`). Roles:

| Role | Responsibility | Output |
|---|---|---|
| Orchestrator | Supervises, prioritizes, creates issue branches, commits/pushes for the engineer, opens PRs, final approver | Merges PRs, closes issues |
| Product Research | Competitor analysis and gap finding | `research.md` |
| Product Manager | Turns gaps/requests into issues (Problem, Scope & Boundaries, Acceptance criteria) | Issues + `**PM review**` comments |
| UI/UX | `## Design notes` section of each issue | Body section + `**UX notes**` comment |
| Engineer | Implements one issue on its linked branch; regression test first for bugs | Changes + `PR BODY` / `COMMIT FILES` blocks |
| QA | Reviews the PR against the issue's acceptance criteria, design notes and owner decisions | Inline review comments + `QA RESULT: PASS/FAIL` PR comment |

Issue flow labels (exactly one at a time): `needs-pm` → `needs-ux` → `ready` → `in-progress` → `in-review` → (`needs-owner-check`) → closed. Also: `bug`/`feature`, `P0`–`P3`, `owner-request`, `redesign`, `blocked`; PR labels `qa-pass`/`qa-fail`.

Rules:
- Issue bodies use the sections `## Problem / Request`, `## Scope & Boundaries`, `## Acceptance criteria`, `## Design notes`, `## Owner decisions`. Edit one section at a time; never drop the others.
- Product-owner decisions are posted as `**Owner decision:** …` comments and mirrored in `## Owner decisions`; they override earlier wording.
- One issue = one branch (`<n>-<slug>`, created with `gh issue develop`) = one PR into `main`. Commits: `#<n>: <summary>`. Stage only the files changed for that issue. Never `git add -A`. Never commit to main.
- PRs must satisfy the PR template (Issue / What changed / How it was tested / Screenshots). `Refs #n` instead of `Closes #n` while the owner still has to check it.
- CI (build + tests) and the PR-template check must be green before merge.
- The Engineer does not commit, push, open PRs or close issues. QA does not modify source. Only the Orchestrator merges PRs and closes issues.
- For this milestone, **QA PASS + green CI + Orchestrator approval replaces the manual user-test gate** (delegated by the product owner), except issues labelled `needs-owner-check`.
- No agent may use browser/Chrome/computer-use/GUI automation tools.
