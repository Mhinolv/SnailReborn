# Product research

Research date: 2026-10-17.

## Executive Summary

- Build custom port targets first. The README identifies IPTV traffic outside port 443 as a current problem.
- Add saved profiles and better usage visibility next. These features support the Wi-Fi data saver purpose.
- Keep delay and packet loss controls as lower-priority developer features.
- Preserve the single pipe, Wi-Fi scope, validated scripts, and current administrator prompt model.
- Exclude per-app limits, extensions, VPN profiles, content filters, and independent directional caps.

The supplied GitHub issue list is empty. No supplied open issue duplicates these recommendations. No issue number is available for exclusion.
Live GitHub issue completeness remains unverified. The report does not treat an empty supplied list as proof of an empty repository backlog.

I read `AGENTS.md`, `README.md`, and `PLAN.md`. The repository has no separate release or review document under those names.
`PLAN.md` still requires field tests for Jamf compatibility and the per-flow mask. Product claims must retain that qualification.

## Competitors

Prices reflect the cited pages on the research date. Dollar prices are USD unless stated otherwise. Tax and regional prices can differ.
Weaknesses below describe fit for Snail's purpose. They are not performance test results.

| Product and position | Platform and price | Target user | Standout features | Weakness relative to Snail |
|---|---|---|---|---|
| [Murus Snail][snail], direct | macOS 11.3+, $10 personal license | People with data caps | Per-app caps, live app rates, automatic hotspot activation | Our README identifies its Network Extension dependency. Independent verification of that dependency remains incomplete. |
| [Apple Network Link Conditioner][apple], adjacent | macOS and iOS developer tools. Current package price is unverified. | App developers | Custom presets for bandwidth, latency, and loss | Developer setup adds friction. A simple video saver workflow is unverified. |
| [Charles][charles], adjacent | macOS, Windows, Linux. [$50 per user][charles-price] | Web developers | Adjustable bandwidth and latency, HTTP inspection | Proxy coverage depends on client configuration. It does not replace our native TCP/QUIC rule. |
| [Proxyman][proxyman], adjacent | macOS, Windows, Linux. [$89 Standard perpetual license][proxyman-price], one year of updates | App and API developers | Network profiles, delay, loss, domain scope | Its cited v1 document says users cannot customize profiles. Current v2 availability is unverified. |
| [TripMode][tripmode], direct for data savings | macOS. Store lists $14.99 and $17.99 annual options, plus $49.99 lifetime | Hotspot users | App access controls, profiles, schedules, data limits, usage reports | Its documented controls stop traffic. A continuous speed cap is unverified. |
| [NetLimiter][netlimiter], adjacent | Windows. [One-year or two-year terms][netlimiter-price]. Exact current price is unverified. | Users who need detailed traffic control | App and connection caps, priorities, quotas, long-term statistics | No macOS version on the cited product page. |
| [Little Snitch][little], display reference | macOS. [$59 single license][little-price] | Privacy-conscious Mac users | Connection search, traffic history, network profiles, [CSV access][little-csv] | Its firewall model exceeds our scope. A bandwidth cap is unverified. |
| [Throttly][throttly], adjacent | Android. Retrieved store page shows KRW 3,800. US price is unverified. | Mobile app developers | Custom network profiles, latency, DNS records | Uses Android VpnService. It is not a Mac alternative. |
| [Throttlr][throttlr], direct | macOS. $39.99 lifetime offer through 2026-12-31 | Mac users with heavy app traffic | App upload/download caps, quotas, daily history | Jamf compatibility and its extension requirements are unverified. |
| [Murus Pro][murus], pf front end | macOS 14.6+ for version 3. $25 Pro, $10 Basic, free noncommercial Lite | Administrators and advanced users | Custom pf rules, bandwidth controls, presets, accounting | Broad firewall control exceeds Snail's narrow ownership boundary. |
| [sitespeed.io throttle][throttle], pf front end | macOS and Linux. Free, MIT license | Web performance developers | CLI, config documents, separate rates, RTT, packet loss | Requires Node.js and administrator rights. Its macOS instructions include edits to `/etc/pf.conf`. |

Throttly and Throttlr are separate products. Their names must not be used interchangeably.
No competitor above received a local installation or a runtime test.

## Feature Matrix

**Y:** documented. **N:** absent in inspected Snail source. **U:** unverified for a competitor.
**Partial:** a narrower feature exists. “History” means saved usage totals, not HTTP request archives.
Each competitor row uses the sources in its product link and the table above.

| Product | Speed cap | Target selection | Profiles | Live app rates | History / budget | Delay / loss | Automation |
|---|---|---|---|---|---|---|---|
| SnailReborn | Per-stream or total download | Port 443 or all inbound | Three fixed speeds | Y, five apps | Session only / N | N / N | CLI |
| [Murus Snail][snail] | Per-app | App | U | Y | U / U | U / U | Hotspot activation |
| [Apple conditioner][apple] | Y | U | Custom | U | U / U | Y / Y | U |
| [Charles][charles] | Proxy traffic | Proxy scope | U | U | U / U | Y / U | [CLI][charles-cli] |
| [Proxyman][proxyman] | Download/upload profiles | System or domain | Fixed in v1 | U | U / U | Y / Y | U |
| [TripMode][tripmode] | U | App access | Custom | Y | Y / Y | U / U | Schedule, AppleScript |
| [NetLimiter][netlimiter] | App, connection, machine | App or filter | U | Y | Y / Y | U / U | [Rule schedule][netlimiter-schedule] |
| [Little Snitch][little] | U | App, host, port access | Custom | Y | Y / U | U / U | Network profiles, CSV CLI |
| [Throttly][throttly] | Y | U | Custom | U | U / U | Y / U | U |
| [Throttlr][throttlr] | App and system, both directions | App | U | Y | Y / Y | U / U | U |
| [Murus Pro][murus] | Y | Custom pf rules | Custom | U | Accounting / U | U / U | U |
| [sitespeed.io throttle][throttle] | Separate download/upload | Interface, localhost option | Fixed and config document | U | U / U | Y / Y | CLI, Node API |

## Gap Analysis

I searched `Sources` and `Tests` with `rg` for profile, budget, quota, delay, loss, port, host, history, session, JSON, CSV, and schedule.
I then read the relevant declarations and consumers. The table distinguishes missing features from partial features.

| Gap | Code evidence | Verified conclusion |
|---|---|---|
| G1: Custom ports | `Sources/SnailCore/ThrottleScript.swift:24`, `Sources/SnailCore/ThrottleConfig.swift:12` | Only port 443 and all inbound traffic are available. |
| G2: Named profiles | `Sources/SnailCore/ThrottleConfig.swift:51`, `Sources/SnailApp/SnailModel.swift:40` | Three speed presets and one preference set exist. No named collection exists. |
| G3: Visible app upload rates | `Sources/SnailApp/MenuContentView.swift:284`, `Sources/SnailCore/AppTraffic.swift:99` | Rows show download only. VoiceOver already includes upload. The list sorts by download first. |
| G4: Saved daily totals | `Sources/SnailApp/SnailModel.swift:20`, `Sources/SnailApp/SnailModel.swift:181` | Session totals and a 60-second graph exist. Neither persists as usage history. |
| G5: Budget alert | `Sources/SnailApp/SnailModel.swift:40`, `Sources/SnailApp/SnailModel.swift:181` | Counters exist. A threshold, reset action, and budget alert do not exist. |
| G6: Remote IP target | `Sources/SnailCore/ThrottleScript.swift:24` | Rules match any remote address. No address target exists. |
| G7: Usage export | `Sources/SnailCLI/main.swift:13`, `Sources/SnailApp/SettingsView.swift:1` | No usage export exists. The CSV parser reads nettop input only. |
| G8: Structured CLI status | `Sources/SnailCLI/main.swift:23`, `Sources/SnailCore/ThrottleController.swift:72` | Status is text. Internal JSON state already exists. |
| G9: Delay control | `Sources/SnailCore/ThrottleScript.swift:30`, `Sources/SnailCore/ThrottleConfig.swift:22` | Pipe arguments contain bandwidth and an optional mask, without delay. |
| G10: Loss control | `Sources/SnailCore/ThrottleScript.swift:30`, `Sources/SnailCore/ThrottleConfig.swift:22` | No loss field or `plr` argument exists. |

The existing source also provides custom speed, total mode, rules preview, cleanup, app grouping, and VPN warnings.
These features are not gaps. Session bytes measure all observed Wi-Fi traffic, not saved bytes or only capped traffic.

### Constraints and deferred gaps

- Independent upload/download caps need separate directional pipes in the documented dummynet model.
  `AGENTS.md` permits only pipe `47101`. Do not propose a second pipe under this contract.
- The local manual confirms `delay` and `plr` support in `/usr/share/man/man8/dnctl.8:121` and `:204`.
  Lines 413–416 describe the separate-pipe model. No privileged command was run.
- Per-app caps and access controls cannot use our pf design. App rates remain display data.
- Schedules and automatic hotspot activation require an explicit answer for administrator prompts and unattended failures.
  `PLAN.md` already lists hotspot awareness and a possible helper. Neither is a small independent feature under the current prompt model.
- Launch at login already appears in `PLAN.md`. Keep it separate from automatic rule activation.
- Delay and loss support in the manual does not prove behavior on this managed Mac. Authorized field tests remain necessary.

## Recommended Features

P1 addresses the main data saver workflow. P2 adds control and visibility. P3 supports developer use.
S means a small change. M means one focused change across layers. No recommendation requires an account, backend, or third-party dependency.
Each numbered item is one proposed PR. Only item 7 depends on another item.

For every new config field, add validation tests and backward-compatible decoding of existing state.
Keep root commands in `ThrottleScript`. Convert typed input to validated values before script construction.
Store user preferences outside `/var/run`. Keep profile names out of root scripts.

### 1. Custom service ports — P1, M

- **Problem:** IPTV outside port 443 requires the broad all-traffic option today.
- **Precedent:** [Murus Pro][murus] supports ports and custom rules. README names port 25461 as a local example.
- **Behavior:** Add a custom scope with up to eight remote TCP/UDP ports. Apply one selected rate to those ports.
- **Boundary:** Accept integers from 1 through 65535. Remove duplicates. Exclude ranges, protocol selection, and per-port rates.
- **Files:** `Sources/SnailCore/ThrottleConfig.swift`, `Sources/SnailCore/ThrottleScript.swift`, `Sources/SnailCLI/main.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, `Tests/SnailCoreTests/ThrottleScriptTests.swift`.
- **Check:** Test invalid input and IPv4/IPv6 rule syntax with `pfctl -n`. Gap: G1.

### 2. Named local profiles — P1, M

- **Problem:** Users must re-enter a custom speed, mode, and scope for each repeated task.
- **Precedent:** [TripMode][tripmode], [Murus Pro][murus], and [Apple conditioner][apple] provide profiles or custom presets.
- **Behavior:** Save, select, rename, and delete up to ten local profiles. Profile selection stages changes until Apply.
- **Boundary:** Store configuration values, not interface names. Resolve Wi-Fi at apply time. Exclude import, sync, and automatic activation.
- **Files:** New `Sources/SnailCore/SavedProfile.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, new `Tests/SnailCoreTests/SavedProfileTests.swift`.
- **Check:** Test persistence, invalid values, and profile selection without an immediate administrator prompt. Gap: G2.

### 3. App upload view — P1, S

- **Problem:** The visible app list hides upload-heavy apps behind download-heavy apps.
- **Precedent:** [Throttlr][throttlr] displays app upload and download rates.
- **Behavior:** Show both rates. Add Download and Upload sort choices for the five displayed apps.
- **Boundary:** Use current nettop samples. Exclude per-app controls and saved app history.
- **Files:** `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/MenuContentView.swift`, `Sources/SnailApp/DebugSnapshots.swift`.
- **Check:** Inspect light and dark snapshots with a high-upload app. Preserve the existing VoiceOver rate labels. Gap: G3.

### 4. Daily Wi-Fi usage totals — P2, M

- **Problem:** Users lose their usage totals when the app quits.
- **Precedent:** [TripMode][tripmode] and [Throttlr][throttlr] provide usage history.
- **Behavior:** Retain daily download and upload totals for 30 days. Show a compact table and a Clear History action.
- **Boundary:** Measure Wi-Fi only while the app is open. Label gaps. Exclude per-app totals and estimates of saved data.
- **Files:** New `Sources/SnailCore/UsageHistory.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, new `Tests/SnailCoreTests/UsageHistoryTests.swift`.
- **Check:** Test restart, midnight, counter reset, and interface changes. Gap: G4.

### 5. Session budget alert — P2, S

- **Problem:** A speed cap does not tell users when they approach a data allowance.
- **Precedent:** [TripMode][tripmode] and [NetLimiter][netlimiter] provide quotas. This proposal uses an alert, not their automatic cutoff.
- **Behavior:** Let users set a combined upload/download allowance. Show remaining bytes and one inline alert at the threshold.
- **Boundary:** Provide Reset Budget. Use observed Wi-Fi bytes since reset. Exclude carrier totals, automatic cutoff, and notification permission.
- **Files:** New `Sources/SnailCore/UsageBudget.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/MenuContentView.swift`, `Sources/SnailApp/SettingsView.swift`, new budget tests.
- **Check:** Test exact threshold, large counters, reset, and the visible measurement boundary. Gap: G5.

### 6. One remote IP target — P2, M

- **Problem:** Users cannot restrict a cap to one known server.
- **Precedent:** [Murus Pro][murus] supports custom pf rules. [Proxyman][proxyman] offers the related domain-scope feature.
- **Behavior:** Add an optional numeric IPv4 or IPv6 address to the selected scope. Match inbound packets from that address.
- **Boundary:** Parse and regenerate a canonical address before script construction. Exclude DNS names, CIDR ranges, lists, and service discovery.
- **Files:** `Sources/SnailCore/ThrottleConfig.swift`, `Sources/SnailCore/ThrottleScript.swift`, `Sources/SnailCLI/main.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, core tests.
- **Check:** Test malformed input and address-family rules. Explain that shared or changing server addresses limit usefulness. Gap: G6.

### 7. Usage CSV export — P2, S

- **Problem:** Users cannot retain a usage record outside the app.
- **Precedent:** [Little Snitch][little-csv] exports traffic statistics as CSV.
- **Behavior:** Export the daily totals from feature 4 through a save dialog.
- **Boundary:** Include date, timezone, bytes in, bytes out, and observed duration. Exclude app names and network identities.
- **Files:** `Sources/SnailCore/UsageHistory.swift`, new `Sources/SnailCore/UsageCSV.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, CSV tests.
- **Check:** Test empty history, stable columns, and decimal values without locale separators. Gap: G7. Dependency: feature 4.

### 8. Structured CLI status — P2, S

- **Problem:** Local scripts must parse human-readable status text.
- **Precedent:** [Little Snitch][little-csv] provides structured CLI data. Its documented format is CSV, not JSON.
- **Behavior:** Add `snailctl status --json` with a schema version, recorded config, Wi-Fi interface, and bypass status.
- **Boundary:** Keep the existing text default. Distinguish absent, invalid, and unreadable state. Do not claim kernel verification from saved JSON.
- **Files:** `Sources/SnailCLI/main.swift`, `Sources/SnailCore/ThrottleController.swift`, new `Sources/SnailCore/StatusReport.swift`, status tests.
- **Check:** Test valid, absent, corrupt, and unreadable state. Keep errors separate from JSON output. Gap: G8.

### 9. Optional inbound delay — P3, M

- **Problem:** Developers cannot reproduce a slow response path with a bandwidth cap alone.
- **Precedent:** [Apple conditioner][apple], [Charles][charles], and [sitespeed.io throttle][throttle] provide delay controls.
- **Behavior:** Add an advanced delay field from 0 to 2000 milliseconds. Apply it to the existing inbound pipe.
- **Boundary:** Default to zero. Label it added inbound delay, not total RTT. Exclude jitter and separate directional delay.
- **Files:** `Sources/SnailCore/ThrottleConfig.swift`, `Sources/SnailCore/ThrottleScript.swift`, `Sources/SnailCLI/main.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, core tests.
- **Check:** Test range limits, default decoding, and generated arguments. Require an authorized field test before performance claims. Gap: G9.

### 10. Optional inbound packet loss — P3, M

- **Problem:** Developers cannot reproduce an unreliable connection.
- **Precedent:** [Apple conditioner][apple], [Proxyman][proxyman], and [sitespeed.io throttle][throttle] provide loss simulation.
- **Behavior:** Add an advanced integer percentage from 0 through 100. Convert it to a locale-independent `plr` value.
- **Boundary:** Default to zero. Show an explicit warning at 100 percent. Apply loss only to traffic that matches Snail's rules.
- **Files:** `Sources/SnailCore/ThrottleConfig.swift`, `Sources/SnailCore/ThrottleScript.swift`, `Sources/SnailCLI/main.swift`, `Sources/SnailApp/SnailModel.swift`, `Sources/SnailApp/SettingsView.swift`, core tests.
- **Check:** Test endpoints, invalid input, state compatibility, and numeric serialization. Gap: G10.

## Sources

Vendor documents support competitor claims. Recommendations and relative-fit judgments are product inferences.
Unverified entries indicate missing evidence, not proof that a competitor lacks a feature.

- [Murus Snail: features and price][snail]
- [Apple: profiles, latency, and loss][apple]
- [Apple: macOS tool availability][apple-mac]
- [Charles: bandwidth and latency][charles]
- [Charles: prices and platforms][charles-price]
- [Charles: CLI options][charles-cli]
- [Charles: proxy coverage][charles-proxy]
- [Proxyman: network conditions][proxyman]
- [Proxyman: licenses and prices][proxyman-price]
- [TripMode: developer description and regional purchase options][tripmode]
- [NetLimiter: features and platform][netlimiter]
- [NetLimiter: license terms][netlimiter-price]
- [NetLimiter: schedules][netlimiter-schedule]
- [Little Snitch: display features][little]
- [Little Snitch: price][little-price]
- [Little Snitch: CSV command][little-csv]
- [Throttly: Android product and retrieved regional price][throttly]
- [Throttlr: Mac product and offer][throttlr]
- [Murus: pf features and prices][murus]
- [sitespeed.io throttle: capabilities and setup][throttle]

Local sources: `AGENTS.md`, `README.md`, `PLAN.md`, the code references above, and `/usr/share/man/man8/dnctl.8`.

[snail]: https://murusfirewall.com/snail/
[apple]: https://developer.apple.com/videos/play/wwdc2019/422/
[apple-mac]: https://developer.apple.com/videos/play/wwdc2021/10239/
[charles]: https://www.charlesproxy.com/documentation/proxying/throttling/
[charles-price]: https://www.charlesproxy.com/buy/
[charles-cli]: https://www.charlesproxy.com/documentation/using-charles/command-line-options/
[charles-proxy]: https://www.charlesproxy.com/
[proxyman]: https://docs.proxyman.com/advanced-features/network-throttling
[proxyman-price]: https://proxyman.com/pricing
[tripmode]: https://apps.apple.com/us/app/tripmode/id1513400665?mt=12
[netlimiter]: https://netlimiter.com/
[netlimiter-price]: https://netlimiter.com/buy
[netlimiter-schedule]: https://www.netlimiter.com/docs/basic-concepts/rules/scheduler
[little]: https://www.obdev.at/products/littlesnitch/index-en.html
[little-price]: https://www.obdev.at/products/littlesnitch/order.html
[little-csv]: https://help.obdev.at/littlesnitch6/cmd-log-traffic
[throttly]: https://play.google.com/store/apps/details?id=me.twocities.throttly.paid
[throttlr]: https://www.throttlr.app/
[murus]: https://www.murusfirewall.com/murus/
[throttle]: https://github.com/sitespeedio/throttle
