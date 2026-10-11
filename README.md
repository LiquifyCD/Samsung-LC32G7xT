# Samsung LC32G7xT power LED control (Windows)

`samsung-led.ps1` talks to the monitor over DDC/CI using only built-in Windows APIs (no downloads).

**Status: untested.** Samsung does not document a DDC/CI code for the power LED on this monitor, so the
script can find one if it exists, but it may not. If nothing changes between snapshots, the LED is not
exposed over DDC/CI and no script can control it.

## Requirements
- Windows 11, PowerShell 5.1 or 7
- In the monitor menu: **System > DDC/CI (or "Auto source/DDC") enabled**
- Monitor connected via DisplayPort or HDMI to the Windows PC

## Find the LED code
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\samsung-led.ps1 List
# 1. Menu: System > Power LED On = Working (LED lit while on)
.\samsung-led.ps1 Snapshot -Out led-lit.json
# 2. Menu: change the setting so the LED goes dark / differs
.\samsung-led.ps1 Snapshot -Out led-dark.json
.\samsung-led.ps1 Diff -A led-lit.json -B led-dark.json
```
Ignore codes that obviously aren't it (e.g. 0x02, 0xDF). A candidate in the 0xE0-0xFF range is likely.
Snapshots are read-only. Also compare a "standby" state if the LED behaves differently there.

## Use it
```powershell
Copy-Item led-config.example.json led-config.json   # then edit code / on / off
.\samsung-led.ps1 Off
.\samsung-led.ps1 On
```
Writes to `0x04 0x05 0x06 0x08 0xB0 0xD6` (factory reset / power) are refused unless you pass `-Force`.

Run `Off` at logon with Task Scheduler if the setting doesn't persist across power cycles.
