# MikroTik RouterOS scripts

A small collection of RouterOS 7.x scripts (verified against **RouterOS 7.22**)
for backups, WiFi rotation, monitoring and Telegram notifications. All scripts
live in `/system script` on the router and are run either manually or from
`/system scheduler`. Repository overview: [`README.md`](../README.md).

> The `.lua` extension is just for editor syntax highlighting — these are
> RouterOS scripts, not Lua. Paste the file contents into the *Source* field
> of a `/system script` entry on the router.

## Table of contents

- [Files at a glance](#files-at-a-glance)
- [Installation](#installation)
- [Script details](#script-details)
- [Security action surface](#security-action-surface)
- [Docker integration tests (CHR 7.22)](#docker-integration-tests-chr-722)
- [RouterOS 7.22 notes & gotchas](#routeros-722-notes-gotchas)
- [Upgrading RouterOS](#upgrading-routeros)

## Files at a glance

| File                            | Purpose                                                                 |
| ------------------------------- | ----------------------------------------------------------------------- |
| `tg_send.lua`                   | Generic Telegram text-message helper used by every other script.        |
| `backup.lua`                    | Daily binary + export backup with Telegram confirmation.                |
| `change_WIFI_pw.lua`            | Rotates 2.4 GHz / 5 GHz WPA2 PSK and announces it via Telegram.          |
| `health_check.lua`              | CPU / RAM / disk / temperature watchdog with threshold alerts.          |
| `update_check.lua`              | Notifies once when a newer RouterOS version appears on your channel.    |
| `wan_failover_notify.lua`       | One-shot Telegram alert on built-in WAN-detect state transitions.       |
| `wan_link_flap_notify.lua`      | Telegram when the WAN interface link (`running`) goes up or down.        |
| `cert_expiry_watch.lua`         | Telegram if a cert is expired or expires within the configured day window. |
| `backup_file_cleanup.lua`       | Deletes `backup-*` files on `/file` older than `RetentionDays`.        |
| `wireguard_watch.lua`           | Telegram on WireGuard down or stale peer handshakes.                   |
| `netwatch_notify.lua`           | Telegram when `/tool netwatch` host status snapshot changes.           |
| `pull_router_backups.sh`        | **Host:** `scp` backup-*.backup / .rsc from the router (bash).         |
| `detect_internet.lua`           | Re-runs RouterOS WAN/LAN auto-detection (manual reset).                 |
| `reboot-and-flush.lua`          | Flushes DNS + connection tracking, then reboots. No pre-reboot ping.    |
| `dhcp_lease_watch.lua`          | Alerts on new MACs, duplicate hostnames, and lease churn.               |
| `firewall_drift.lua`            | Diffs current firewall rules against a saved baseline; alerts on drift. |
| `firewall_drift_baseline.lua`   | Manual helper that re-arms `firewall_drift` after intentional changes.  |
| `mac_allowlist_dhcp.lua`        | Flags (and optionally blocks) DHCP leases for non-allowlisted MACs.     |
| `rogue_dns_check.lua`           | Detects DNS upstream hijack and clients using non-approved resolvers.   |

## Installation

1. **Set up a Telegram bot** ([@BotFather](https://t.me/BotFather)), grab the
   token, and find your chat ID (e.g. message your bot then visit
   `https://api.telegram.org/bot<TOKEN>/getUpdates`).
2. Open Winbox / WebFig → **System → Scripts → Add (+)**.
3. For each `.lua` file in this folder:
   - Set **Name** to the filename without extension (e.g. `tg_send`, `backup`,
     `change_WIFI_pw`).
   - Tick **Policy:** `read,write,policy,test,sensitive,ftp` — `policy` is
     required to read other script sources via `[:parse [/system script get …
     source]]`, `sensitive` for secrets, `ftp` for `/tool fetch`.
   - Paste the script body into **Source** and save.
4. Edit `tg_send.lua` and replace the `BotToken` / `ChatID` placeholders with
   your real values, **or** create a tiny startup script that sets globals:

   ```routeros
   :global TG_BOT_TOKEN "123456:ABC...";
   :global TG_CHAT_ID   "12345678";
   ```

   then add a Scheduler entry with `start-time=startup` pointing to it. The
   `tg_send` helper picks them up automatically.
5. Run `detect_internet` once if you plan to use `wan_failover_notify`. It
   enables `detect-interface-list=all`, which is the prerequisite for the
   per-interface `detect-internet-state` property to be populated.

### Suggested schedules

Add via **System → Scheduler** (use the same policy set as the scripts):

| Script                | Trigger / interval         |
| --------------------- | -------------------------- |
| `backup`              | `1d` at `04:00:00`         |
| `change_WIFI_pw`      | `30d` (or on demand)       |
| `health_check`        | `5m`                       |
| `update_check`        | `1d`                       |
| `wan_failover_notify` | `1m`                       |
| `wan_link_flap_notify`| `1m`                       |
| `cert_expiry_watch`   | `1d`                       |
| `backup_file_cleanup` | `7d` (after `backup`)      |
| `wireguard_watch`     | `5m`                       |
| `netwatch_notify`     | `5m`                       |
| `dhcp_lease_watch`    | `5m`                       |
| `firewall_drift`      | `15m`                      |
| `mac_allowlist_dhcp`  | `5m`                       |
| `rogue_dns_check`     | `10m`                      |
| `notify-boot` (inline)| `start-time=startup` — see [Reboot notifications](#reboot-notifications) |

`detect_internet`, `reboot-and-flush`, and `firewall_drift_baseline` are
intentionally manual / on-demand — don't schedule them.

Set `WanInterface` in both `wan_failover_notify` and `wan_link_flap_notify` to
your real WAN (e.g. `pppoe-out1` vs `ether1`).

### Off-router backups

[`pull_router_backups.sh`](pull_router_backups.sh) runs on your Mac or Linux
box (not on the router). Use `-h` / `--help` for usage. Enable **SSH + SFTP**
on the router, then:

```bash
chmod +x pull_router_backups.sh
./pull_router_backups.sh admin@192.168.88.1 ~/Archive/mikrotik-backups
```

It uses `scp` wildcards (`backup-*.backup`, `backup-*.rsc`). If nothing
matches, the script exits **0** and prints a notice.

### Reboot notifications

`reboot-and-flush` does **not** Telegram before rebooting (the message would
race the reboot itself; see the script comment). The recommended pattern is a
one-shot startup notifier that fires once the router is back online:

```routeros
/system scheduler add name=notify-boot start-time=startup \
    policy=read,write,policy,test,sensitive,ftp \
    on-event=":delay 20s; :local S [:parse [/system script get tg_send source]]; \$S MessageText=(\"\\F0\\9F\\9F\\A2 <b>\" . [/system identity get name] . \":</b> back online\");"
```

The 20 s delay gives DHCP / WAN / DNS time to come up before `tg_send` tries
to reach Telegram.

## Script details

### `tg_send.lua`
Generic Telegram text-message helper. All other scripts call it via
`[:parse [/system script get tg_send source]]`. Posts to `sendMessage` with
HTML parse mode using `application/x-www-form-urlencoded`, retries up to 3×
on transient failures, and truncates messages above Telegram's 4096-char
limit. Reads `:global TG_BOT_TOKEN` / `:global TG_CHAT_ID` if defined so
secrets can stay out of the script body.

### `backup.lua`
Creates a binary backup (`.backup`) and a config export (`.rsc`) and sends a
Telegram notification with the resulting filename. Optional binary-backup
encryption via `BackupPassword`. Sanitizes the date so non-ISO `date-format`
settings don't accidentally produce filenames with `/` (which would create
sub-folders on disk). Files accumulate in `/file` — clean them up manually
or via a separate scheduler if needed.

### `change_WIFI_pw.lua`
Generates fresh random passwords for the 2.4 GHz and 5 GHz security profiles
and announces the new credentials via Telegram. Uses the SCEP-OTP generator
when the certificate package supports it and falls back to `:rndnum`
otherwise. Set `UseWifiWave2` to `true` for routers using the new
`/interface wifi` (WiFiWave2) stack instead of the legacy
`/interface wireless`.

### `reboot-and-flush.lua`
Flushes DNS cache + connection tracking and reboots after a 1-second grace
period. Use sparingly — flushing connection tracking drops every active
session. Intentionally has no Telegram step; pair it with the `notify-boot`
scheduler entry above for a "back online" alert after each reboot.

### `detect_internet.lua`
Forces RouterOS to re-run its WAN/LAN role auto-detection by toggling
`detect-interface-list`. Helpful after ISP outages where interfaces stay
tagged `unknown`. Also enables detect-internet on **all** interfaces, which
is the prerequisite for `wan_failover_notify`.

### `health_check.lua`
Reads CPU / memory / disk / temperature, compares against thresholds (default
85 % / 85 % / 90 % / 75 °C) and only Telegrams when something is wrong.
Temperature lookup iterates `/system health` entries (`temperature`,
`cpu-temperature`, `board-temperature`) so it works across hardware lines.

### `update_check.lua`
Asks the official update server whether a newer RouterOS version exists on
your channel, and notifies once when one appears. Does **not** auto-install.

### `wan_failover_notify.lua`
Polls the WAN interface's built-in `detect-internet-state` property and sends
a Telegram message **only on transitions** (e.g. `internet → no-link`). State
is held in `:global WAN_LAST_STATE` so consecutive runs stay quiet while the
state is unchanged. The global resets on reboot, which means the first run
after boot sends a single baseline notification.

Requires detect-internet to be enabled on the interface — run
`detect_internet.lua` once, or run:

```routeros
/interface detect-internet set detect-interface-list=all
```

Edit `WanInterface` at the top of the script if your WAN port isn't
`ether1`.

### `wan_link_flap_notify.lua`
Watches the WAN interface's L1 `running` flag (carrier / link up vs down) and
Telegrams on **transitions** only. Complements `wan_failover_notify.lua`
(`detect-internet-state` can stay `internet` while the physical link flaps).
Uses `:global WAN_LINK_LAST` (`up` / `down`); first scheduled run sets baseline
without messaging. Edit `WanInterface` (e.g. `pppoe-out1`).

### `cert_expiry_watch.lua`
Scans non-disabled `/certificate` entries. Telegram lists any **expired** cert
and any cert whose `invalid-after` falls within the script's `+ 30d` window
(edit the interval in source to tune). Schedule at **`1d`** or longer to avoid
duplicate alerts.

### `backup_file_cleanup.lua`
Removes `/file` entries whose name matches `backup-*` and whose
`creation-time` is older than `RetentionDays` (default 30). Pairs with
`backup.lua`; logs to `/log` only (no Telegram). Schedule weekly or right
after backups.

### `wireguard_watch.lua`
Requires a WireGuard interface named in `Iface` (default `wireguard1`). Sets
health state `:global WGHEALTHLAST` to `ok`, `down`, or `stale`. Alerts on
transitions (and on first run if already unhealthy). **Down:** interface not
running. **Stale:** any enabled peer's `last-handshake` is older than `300s`
(edit in source). Handshake math is in `on-error` — verify on your RouterOS
build.

### `netwatch_notify.lua`
Builds a string snapshot of all `/tool netwatch` rows (`host:status|…`) and
Telegrams when it changes. First run stores `:global NETWATCHSNAP` only. Add
hosts under **Tools → Netwatch** in Winbox.

### `dhcp_lease_watch.lua`
Periodically scans `/ip dhcp-server lease` and alerts on three conditions:
new MACs not seen before (relative to `:global DHCP_KNOWN_MACS`), the same
hostname showing up under multiple MACs, and lease-count churn beyond
`ChurnThreshold` (default 10) since the previous run. The first run after
boot silently establishes the baseline. With `Enforce=true` (default), each
new MAC's lease IP is added to address-list `dhcp-watch-new` with a 1-day
timeout so you can pin a forward rule to it. Sticky `:global DHCP_DUPS_FLAG`
and `DHCP_CHURN_FLAG` suppress repeat alerts while the same condition
persists.

### `firewall_drift.lua`
Stores a signature string of every `/ip firewall filter` and `/ip firewall
nat` rule (`chain|action|src-address|dst-port|protocol|comment`) in
`:global FW_BASELINE` on first run, then alerts when later runs see
additions, removals, or a different ordering of rules whose comment contains
`#critical`. On drift the script also logs a marker entry into address-list
`fw-drift-events` (sentinel address `127.0.0.1`, 1-hour timeout) so the
router carries a router-side audit trail. Run `firewall_drift_baseline.lua`
after intentional firewall changes to clear the global; the next
`firewall_drift` run silently re-baselines.

### `firewall_drift_baseline.lua`
Manual helper. Sets `:global FW_BASELINE` to empty string. Does not touch
firewall rules. Run after intentional firewall edits before the next
scheduled `firewall_drift` run, otherwise the change will be reported as
drift.

### `mac_allowlist_dhcp.lua`
Iterates `/ip dhcp-server lease` and flags any lease whose MAC is not on the
allowlist. The allowlist comes from `:global MAC_ALLOWLIST` (delimited
string, e.g. `";aa:bb:..;cc:dd:..;"`) or from a per-lease comment containing
the literal substring `#allow`. With `Enforce=true` (default), unknown lease
IPs are tagged into address-list `dhcp-unknown` with a 1-day timeout. With
`BlockUnknown=true` (off by default), the script idempotently installs a
single `chain=forward action=drop` rule sourced from that list (the rule is
appended at the end of `/ip firewall filter` — review and move it manually
to the right position). Refuses to do anything if `MAC_ALLOWLIST` is empty,
to avoid accidentally locking every device out of an unconfigured router.
Re-alerts only when the set of unknown MACs changes between runs.

### `rogue_dns_check.lua`
Two checks per run. First, it `:resolve`s a control hostname (default
`dns.cloudflare.com`) and warns if the answer is not in `:global
DNS_EXPECTED` — a sign of upstream DNS hijack or a wrong/leaking resolver
config. Second, it walks `/ip firewall connection` for outbound
UDP/TCP `dst-port=53` flows whose destination is neither a router-self IP
nor an entry in `:global DNS_ALLOWED_RESOLVERS`, aggregates offenders by
source IP, and (with `Enforce=true`, default) tags those source IPs into
address-list `rogue-dns-clients` with a 1-hour timeout. Pair with a
documented filter rule to redirect or drop their port-53 traffic (see
[Security action surface](#security-action-surface) below).

## Security action surface

The four security scripts above keep their actions on a small, reversible
surface so a noisy detector cannot brick the router:

| Address-list          | Populated by              | Purpose                                                |
| --------------------- | ------------------------- | ------------------------------------------------------ |
| `dhcp-watch-new`      | `dhcp_lease_watch`        | New DHCP lease IPs (informational; tag for ad-hoc rules). |
| `dhcp-unknown`        | `mac_allowlist_dhcp`      | DHCP lease IPs whose MAC is not on the allowlist.      |
| `fw-drift-events`     | `firewall_drift`          | Sentinel marker `127.0.0.1` per drift event (audit trail). |
| `rogue-dns-clients`   | `rogue_dns_check`         | Source IPs caught using non-approved DNS resolvers.    |

Optional filter rule templates (commented out on purpose — review first,
then apply if you want enforcement). All of them assume the lists above are
populated by the corresponding scheduled scripts:

```routeros
# Drop traffic from devices not on the MAC allowlist (mac_allowlist_dhcp).
/ip firewall filter add chain=forward action=drop \
    src-address-list=dhcp-unknown comment=mac-allowlist-block disabled=yes

# Redirect port-53 traffic from rogue clients to the router itself
# (rogue_dns_check). NAT entries that match are then DNAT'd onto 192.0.2.1.
/ip firewall nat add chain=dstnat action=dst-nat to-addresses=192.0.2.1 \
    protocol=udp dst-port=53 src-address-list=rogue-dns-clients \
    comment=rogue-dns-redirect disabled=yes

# Quarantine new DHCP devices from talking to the LAN until you
# acknowledge them (dhcp_lease_watch with Enforce=true).
/ip firewall filter add chain=forward action=drop \
    src-address-list=dhcp-watch-new comment=dhcp-watch-quarantine disabled=yes
```

To re-baseline the firewall drift detector after an intentional change,
either run `/system script run firewall_drift_baseline` from the terminal or
schedule it manually before applying the change.

## Docker integration tests (CHR 7.22)

To validate all scripts on **real RouterOS 7.22** inside Docker (QEMU + official CHR
image), use [`tests/README.md`](tests/README.md) and from the repo root run
`./mikrotik/tests/run.sh`. This is the closest practical “emulation” of your router:
MikroTik does not ship a standalone script interpreter, so the tests talk to a live
CH instance over the API.

The macOS setup scripts in this repo have a **separate** lightweight Docker
harness (syntax + ShellCheck only, no Homebrew) — see
[`macos-initial-setup/README.md`](../macos-initial-setup/README.md#development-docker-checks).

## RouterOS 7.22 notes & gotchas

- RouterOS scripts use `/` for paths and `:` for built-in commands
  (`:local`, `:if`, `:foreach`). `:interface ...` is **not** valid syntax —
  always `/interface ...`.
- `/tool fetch` requires the `ftp` policy, not just `read`.
- HTTPS fetches verify TLS certificates by default. If `tg_send` reports
  fetch failures, either import a CA bundle:

  ```routeros
  /tool fetch url=https://curl.se/ca/cacert.pem dst-path=cacert.pem
  /certificate import file-name=cacert.pem passphrase=""
  ```

  or, less securely, append `check-certificate=no` to the fetch command in
  `tg_send.lua`.
- Telegram message text uses URL-style escapes: `%0A` for newline,
  `\F0\9F...` for emoji codepoints encoded as UTF-8 byte literals. When
  copy-pasting through editors, double-check those escape sequences survived.
- `:global` variables persist across scheduler runs *within an uptime
  session*. They are cleared on reboot — `wan_failover_notify` relies on
  this and treats the first post-boot run as the baseline state.
- For `change_WIFI_pw` on RouterOS 7.13+: the new `wifi` (WiFiWave2) stack
  uses `/interface wifi security` with the property `passphrase`, not the
  legacy `/interface wireless security-profiles wpa2-pre-shared-key`. Toggle
  `UseWifiWave2` accordingly.

## Upgrading RouterOS

These scripts are exercised on **7.22** (see [`tests/README.md`](tests/README.md)).
When you move to a newer **7.x** patch or minor:

1. Read MikroTik’s release notes for scripting, `wifi` vs `wireless`, and
   certificate / fetch behavior.
2. Re-run `./mikrotik/tests/run.sh` after bumping the CHR image / version the
   harness uses (or spot-check by pasting changed scripts into a lab router).
3. Smoke-test `tg_send` and one scheduled script on the production router
   before relying on alerts.

Update the “verified against **7.22**” lines in this README and the root
[`README.md`](../README.md) when you intentionally re-baseline on a new version.
