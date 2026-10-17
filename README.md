# Snail (SnailReborn)

A macOS menu bar utility that saves bandwidth on Wi‑Fi by capping video streams, the way AT&T's **Video Management / Stream Saver** works on cellular. Each connection is paced to about **1.5 Mbps**. Adaptive players (YouTube, Netflix, HLS/DASH apps) see the lower throughput and drop to SD by themselves, while page loads and small downloads stay fast.

It is inspired by Murus **Snail.app**, which needs a Network Extension. Our MDM (Jamf) blocks Network Extensions, so **this app uses no Network Extension**. It uses the kernel's built-in **pf firewall + dummynet** (`pfctl` / `dnctl`) instead.

## How it works

```
Menu bar app / snailctl ──▶ root shell script (one admin prompt) ──▶ dnctl pipe 47101 (1500 Kbit/s, per-flow mask)
                                                                  └▶ pf anchor com.apple/snailreborn:
                                                                       dummynet in on <Wi‑Fi> proto {tcp udp} from any port 443 → pipe 47101
```

- **Per stream (default):** `mask dst-port 0xffff` gives every connection its own 1.5 Mbps pipe, as AT&T does.
- **Total:** all matching Wi‑Fi traffic shares one pipe.
- **Applies to:** web & video (inbound TCP and QUIC from port 443, the default), all traffic, or custom TCP/UDP ports.
- Only the Wi‑Fi interface is shaped. Its name is detected with CoreWLAN, not hard-coded to `en0`.
- Snail only touches its own anchor and pipe. It takes a pf enable reference with `pfctl -E` and gives it back with `pfctl -X`; it never runs `pfctl -d` or a global `dnctl flush`.
- State lives in `/var/run/snailreborn.{json,token}`. The JSON is world-readable, so the app and CLI always agree. Everything clears at reboot, as pf rules do.

## Requirements

- macOS 13 or later and an **administrator account**. Each on, off, or change asks for your password once; macOS caches it for a few minutes.
- Xcode or the Command Line Tools (Swift 5.9+) to build.

## Build and run

```bash
./scripts/build-app.sh
```

```bash
open build/SnailReborn.app
```

A Snail window opens, and a snail-shell icon appears in the menu bar (filled when Stream Saver is on). Closing the window keeps Snail running in the menu bar. Opening the app again from Finder or Launchpad brings the window back. For development, `swift run SnailApp` works too.

On a MacBook with a notch, new menu bar icons usually go on the far left, which can be behind the notch. Snail defaults to a spot near the clock instead. ⌘-drag the icon to move it.

### The app

- **Popover** (click the snail):
  - The Stream Saver switch.
  - The speed limit: SD 1.5, HD 3, or Full HD 5 Mbps. Changing it while on applies right away.
  - Live Wi‑Fi throughput with a 60‑second graph.
  - **Apps now:** the five busiest apps by download rate (from `nettop`, no root needed). Helpers are grouped under their app.
  - A warning when a **VPN** (or another interface) is carrying your traffic. The limit can't apply then; see below.
  - Settings… (⌘,) and Quit (⌘Q).
- **Settings:**
  - Custom speed, per-stream vs. total, and web & video vs. all traffic. While on, changes are staged and pushed with **Apply Now**.
  - Whether quitting turns the limit off (default: yes).
  - A view of the exact rules.
  - **Remove Rules** to clean up.

In Settings, select **Export CSV…** beside **Clear History…** to save daily Wi-Fi totals.
The button is disabled when the history has no rows. Export needs no administrator password.
The CSV uses UTF-8 and these columns: `date,timezone,bytes_in,bytes_out,observed_seconds`.
Rows list stored days from oldest to newest. Days without samples have no row.
Bytes use plain ASCII integers. Observed seconds round down to whole seconds.
The timezone is the current system timezone at export. The history does not store a timezone for each day.

In Settings, enable **Data Budget** and enter an amount in MB or GB.
The budget counts observed Wi-Fi downloads and uploads while enabled.
The units are SI: 1 MB is 1,000,000 bytes. 1 GB is 1,000 MB.
The popover shows the amount left and an alert at 100%.
The alert dismissal persists until **Reset Budget**. Reset Budget clears the total and permits the next alert.
The budget does not change the speed limit. It excludes traffic while Snail is closed or the budget is disabled.
The budget total and preferences persist across app restarts. **Clear History** does not change the budget.

### The CLI

```bash
sudo build/snailctl on
```

```bash
sudo build/snailctl on --hd --total
```

```bash
build/snailctl status
```

```bash
build/snailctl apps
```

```bash
sudo build/snailctl off
```

`snailctl rules` and `snailctl script on|off` print exactly what would run, without root.

Use `snailctl status --json` for local scripts. The command prints JSON with sorted keys and a final newline.
The `schemaVersion` is `1`. The `recordedConfig` field contains the saved config. It does not confirm live kernel state.
The `active` field is `true` for a valid saved config and `false` for an absent state file, with `recordedConfig` set to `null`.
The report includes `stateFile`, `wifiInterface`, and `bypass`. If Wi-Fi is absent, `wifiInterface` is `null`.
If no bypass exists, `bypass` is `null`. Otherwise, it contains `interface` and `kind` (`vpn` or `otherInterface`).

| State file | Exit code | Output |
|---|---|---|
| Valid | 0 | JSON on stdout |
| Absent | 0 | JSON on stdout with `"active": false` and `"recordedConfig": null` |
| Not valid | 4 | Error on stderr only |
| Cannot be read | 5 | Error on stderr only |

These exit codes apply only to `status --json`. Plain `status` output stays the same.
An unknown option for `status` returns exit code `64` and an error on stderr.

## Verify it works (first run on a new Mac)

1. Turn Stream Saver on, at SD, per stream.
2. Run a speed test that uses one connection, or watch a YouTube video with quality on Auto. Throughput should settle near 1.5 Mbps, and the video at about 480p.
3. Check the kernel state:

```bash
sudo pfctl -a com.apple/snailreborn -s dummynet
```

```bash
sudo dnctl list
```

If Jamf blocks pf, the app shows the `pfctl` error in a yellow banner.

### VPNs bypass the limit

A VPN such as Cloudflare WARP wraps all traffic in one encrypted tunnel (WARP uses WireGuard on UDP 2408). The rule on Wi‑Fi sees a single flow on the wrong port, so nothing is capped, and per-stream shaping can't tell videos apart. Snail detects this by asking the kernel which interface it would route public traffic through, and shows a warning. Disconnect the VPN for the limit to work.

Some apps use ports other than 443. For IPTV apps such as UHF, select **Custom ports (TCP and UDP)**. Enter the remote ports, such as `25461, 8080`. Snail accepts one to eight ports from 1 to 65535. Use commas or spaces as separators. Snail removes duplicates and keeps the port order.

To print custom rules without root, run:

```bash
build/snailctl rules --ports "25461, 8080"
```

## Recovery

If anything looks wrong, run:

```bash
sudo build/snailctl off
```

Or by hand:

```bash
sudo pfctl -a com.apple/snailreborn -F all; sudo dnctl pipe delete 47101
```

A reboot also clears everything.

## Development

```bash
swift test
```

Tests cover config validation, rule and script generation (including a real `pfctl -n` parse), AppleScript escaping, and 64-bit interface counters. UI snapshots in light and dark mode, including the On, pending, and error states:

```bash
SNAIL_SNAPSHOT_DIR=/tmp/shots swift run SnailApp
```

See [AGENTS.md](AGENTS.md) for contributor rules and [PLAN.md](PLAN.md) for status and next steps.
