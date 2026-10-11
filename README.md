# Samsung LC32G7xT power LED control (Windows)

`samsung-led.ps1` talks to the monitor over DDC/CI using only built-in Windows APIs (no downloads).

**Result on a real LC32G7xT (Windows 11):** the power LED setting is exposed as VCP code `0xFE`, but it is
**read-only**. `Get -Code 0xFE` returns the current menu setting (2 = *Working*, 1 = *Stand-by*), while
`Set -Code 0xFE` reports success and the value never changes (checked after a 2 s delay, and brightness
`0x10` writes worked on the same connection, so DDC/CI writes are fine). The LED can therefore only be
changed from the on-screen menu (System > Power LED On), and it cannot be turned off in standby from software.
Practical options: set the menu to **Stand-by** (LED dark while the monitor is on), and use a switched
power strip or cover the LED for standby.

The script is still useful for reading codes (`Snapshot`, `Diff`, `Get`). It has only been run on that one
setup; the `Off`/`On` actions are untested because there is no writable LED code to point them at.

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

## Hardware option: disconnecting the LED (not verified for this model)
**No verified teardown exists for the LC32G7xT, and this section has not been tested.** It voids the warranty
and risks damaging the monitor, so treat it as an outline only, not step-by-step instructions.

- Samsung's service manual for the related LC27G7*T* series (also listed for the LC32G7*T*) has a
  disassembly section: <https://www.manualslib.com/manual/2922630/Samsung-Odyssey-G7-Lc27g7-T-Series.html?page=27>.
  Follow it for the real steps and part names.
- Its general warnings: unplug the monitor first, never pry the cabinet with metal tools, and handle the
  boards with static precautions.
- Owners of similar Odyssey G7 units report that the back cover is held by hidden plastic clips (use plastic
  pry tools, work slowly) and that the control board sits near the power switch with ribbon connectors.
- Identify the LED on the board before changing anything, photograph every connector, and prefer unplugging a
  dedicated LED/switch connector over cutting or desoldering. Note that the LED may share a board or
  connector with the power switch and joystick, in which case removing it could disable them.
- Tape over the LED or a switched power strip achieves the same result without opening the monitor.
