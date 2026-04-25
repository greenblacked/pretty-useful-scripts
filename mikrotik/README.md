# MikroTik RouterOS scripts

A small collection of RouterOS 7.x scripts (verified against **RouterOS 7.22**)
for backups, WiFi rotation, monitoring and Telegram notifications. All scripts
live in `/system script` on the router and are run either manually or from
`/system scheduler`.

> The `.lua` extension is just for editor syntax highlighting — these are
> RouterOS scripts, not Lua. Paste the file contents into the *Source* field
> of a `/system script` entry on the router.

## Files at a glance

| File                       | Purpose                                                                 |
| -------------------------- | ----------------------------------------------------------------------- |
| `tg_send.lua`              | Generic Telegram text-message helper used by every other script.        |
| `backup.lua`               | Daily binary + export backup with Telegram confirmation.                |
| `change_WIFI_pw.lua`       | Rotates 2.4 GHz / 5 GHz WPA2 PSK and announces it via Telegram.          |
| `health_check.lua`         | CPU / RAM / disk / temperature watchdog with threshold alerts.          |
| `update_check.lua`         | Notifies once when a newer RouterOS version appears on your channel.    |
| `wan_failover_notify.lua`  | One-shot Telegram alert on built-in WAN-detect state transitions.       |
| `detect_internet.lua`      | Re-runs RouterOS WAN/LAN auto-detection (manual reset).                 |
| `reboot-and-flush.lua`     | Flushes DNS + connection tracking, then reboots. No pre-reboot ping.    |

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
| `notify-boot` (inline)| `start-time=startup` — see [Reboot notifications](#reboot-notifications) |

`detect_internet` and `reboot-and-flush` are intentionally manual / on-demand —
don't schedule them.

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
