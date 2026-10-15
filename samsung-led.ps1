<#
.SYNOPSIS
  Probe and control Samsung monitor settings over DDC/CI on Windows (no extra tools needed).

.DESCRIPTION
  Uses the Windows dxva2.dll monitor API. Written for the Samsung Odyssey LC32G7xT power LED,
  but the LED's VCP code is not documented, so you first find it with Snapshot + Diff.

  Actions
    List                       Show detected monitors.
    Snapshot -Out file.json    Read every VCP code (0x00-0xFF) and save the values. Read-only.
    Diff -A a.json -B b.json   Show codes whose value differs between two snapshots.
    Get -Code 0xNN             Read one code.
    Set -Code 0xNN -Value N    Write one code.
    Off / On                   Write the values stored in led-config.json.
    MonitorOff                 Power the monitor off (VCP 0xD6 = 4). Wake it with the JOG/power button.

  Finding the LED code
    1. Set "Power LED On" in the monitor menu so the LED is lit, then:  .\samsung-led.ps1 Snapshot -Out led-lit.json
    2. Change the menu setting so the LED is dark, then:                .\samsung-led.ps1 Snapshot -Out led-dark.json
    3. .\samsung-led.ps1 Diff -A led-lit.json -B led-dark.json
    4. Put the code and values in led-config.json (copy led-config.example.json).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('List', 'Snapshot', 'Diff', 'Get', 'Set', 'Off', 'On', 'MonitorOff')]
    [string]$Action,
    [int]$Monitor = 0,
    [string]$Code,
    [string]$Value,
    [string]$Out,
    [string]$A,
    [string]$B,
    [string]$Config = (Join-Path $PSScriptRoot 'led-config.json'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Ddc {
    delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr lprc, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szPhysicalMonitorDescription;
    }

    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc cb, IntPtr data);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out uint type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint value);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitor(IntPtr h);

    public static IntPtr[] Handles = new IntPtr[0];
    public static string[] Names = new string[0];

    public static void Refresh() {
        Release();
        var hs = new List<IntPtr>(); var ns = new List<string>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hm, IntPtr hdc, IntPtr r, IntPtr d) => {
            uint n; 
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(hm, out n) && n > 0) {
                var arr = new PHYSICAL_MONITOR[n];
                if (GetPhysicalMonitorsFromHMONITOR(hm, n, arr))
                    foreach (var p in arr) { hs.Add(p.hPhysicalMonitor); ns.Add(p.szPhysicalMonitorDescription); }
            }
            return true;
        }, IntPtr.Zero);
        Handles = hs.ToArray(); Names = ns.ToArray();
    }

    public static void Release() {
        foreach (var h in Handles) DestroyPhysicalMonitor(h);
        Handles = new IntPtr[0]; Names = new string[0];
    }

    // Returns false if the monitor does not support the code.
    public static bool Get(int idx, byte code, out uint cur, out uint max) {
        uint type;
        return GetVCPFeatureAndVCPFeatureReply(Handles[idx], code, out type, out cur, out max);
    }

    public static bool Set(int idx, byte code, uint value) {
        return SetVCPFeature(Handles[idx], code, value);
    }
}
'@

function ConvertTo-Byte([string]$s) {
    $n = [Convert]::ToInt32($s, $(if ($s -match '^0x') { 16 } else { 10 }))
    if ($n -lt 0 -or $n -gt 255) { throw "VCP code must be 0-255 (got $s)" }
    [byte]$n
}

# Writing these can reset settings or power the monitor off/into a bad state.
$dangerous = 0x04, 0x05, 0x06, 0x08, 0xB0, 0xD6

function Write-Vcp([byte]$code, [uint32]$value) {
    if ($dangerous -contains $code -and -not $Force) {
        throw ("VCP 0x{0:X2} can reset the monitor or change its power state. Re-run with -Force if you really mean it." -f $code)
    }
    if (-not [Ddc]::Set($Monitor, $code, $value)) { throw ("Writing 0x{0:X2} = {1} failed (monitor may not support it)." -f $code, $value) }
    Write-Host ("Set 0x{0:X2} = {1}" -f $code, $value)
}

try {
    if ($Action -eq 'Diff') {
        if (-not $A -or -not $B) { throw 'Diff needs -A and -B snapshot files.' }
        $sa = Get-Content $A -Raw | ConvertFrom-Json
        $sb = Get-Content $B -Raw | ConvertFrom-Json
        $keys = @($sa.PSObject.Properties.Name) + @($sb.PSObject.Properties.Name) | Sort-Object -Unique { [Convert]::ToInt32($_, 16) }
        $found = $false
        foreach ($k in $keys) {
            $va = $sa.$k.current; $vb = $sb.$k.current
            if ($va -ne $vb) { $found = $true; "0x{0}: {1} -> {2} (max {3})" -f $k, $va, $vb, $sb.$k.max }
        }
        if (-not $found) { Write-Host 'No differences.' }
        return
    }

    [Ddc]::Refresh()
    if ([Ddc]::Handles.Length -eq 0) { throw 'No DDC/CI-capable monitors found.' }
    if ($Monitor -ge [Ddc]::Handles.Length) { throw "Monitor index $Monitor out of range (found $([Ddc]::Handles.Length))." }

    switch ($Action) {
        'List' {
            for ($i = 0; $i -lt [Ddc]::Names.Length; $i++) { "{0}: {1}" -f $i, [Ddc]::Names[$i] }
        }
        'Snapshot' {
            if (-not $Out) { throw 'Snapshot needs -Out file.json' }
            $snap = [ordered]@{}
            for ($c = 0; $c -le 255; $c++) {
                [uint32]$cur = 0; [uint32]$max = 0
                if ([Ddc]::Get($Monitor, [byte]$c, [ref]$cur, [ref]$max)) {
                    $snap[('{0:X2}' -f $c)] = [ordered]@{ current = $cur; max = $max }
                }
            }
            $snap | ConvertTo-Json -Depth 3 | Set-Content $Out
            Write-Host ("Saved {0} readable codes from '{1}' to {2}" -f $snap.Count, [Ddc]::Names[$Monitor], $Out)
        }
        'Get' {
            $c = ConvertTo-Byte $Code; [uint32]$cur = 0; [uint32]$max = 0
            if ([Ddc]::Get($Monitor, $c, [ref]$cur, [ref]$max)) { "0x{0:X2}: current={1} max={2}" -f $c, $cur, $max }
            else { throw ("Monitor did not answer for 0x{0:X2}." -f $c) }
        }
        'Set' {
            if (-not $Code -or -not $Value) { throw 'Set needs -Code and -Value.' }
            Write-Vcp (ConvertTo-Byte $Code) ([uint32]$Value)
        }
        'MonitorOff' {
            # Verified on a real LC32G7xT: 0xD6 = 4 powers the monitor off. 0xD6 reads back as 255, so don't rely on Get.
            if (-not [Ddc]::Set($Monitor, 0xD6, 4)) { throw 'Writing 0xD6 = 4 failed.' }
            Write-Host 'Sent power-off (0xD6 = 4). Press the JOG/power button to wake the monitor.'
        }
        { $_ -in 'Off', 'On' } {
            if (-not (Test-Path $Config)) { throw "Config not found: $Config (copy led-config.example.json to led-config.json and fill it in)." }
            $cfg = Get-Content $Config -Raw | ConvertFrom-Json
            $v = if ($Action -eq 'Off') { $cfg.off } else { $cfg.on }
            Write-Vcp (ConvertTo-Byte ([string]$cfg.code)) ([uint32]$v)
        }
    }
}
finally {
    [Ddc]::Release()
}
