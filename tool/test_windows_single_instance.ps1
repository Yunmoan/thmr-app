# Build first: flutter build windows --debug
# Run: pwsh -NoProfile -File tool/test_windows_single_instance.ps1
param([string]$Executable = "$PSScriptRoot/../build/windows/x64/runner/Debug/thmr_app.exe")

$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path -LiteralPath $Executable).Path
if (Get-Process thmr_app -ErrorAction SilentlyContinue) {
    throw 'Close the running THMR app before running this smoke test.'
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ThmrInstanceProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string title);
    public static IntPtr FindThmrWindow() { return FindWindow("THMR_RUNNER_WIN32_WINDOW", null); }
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr window);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
}
'@

$launched = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
function Start-Thmr {
    # This is a visible-window test. SW_HIDE in STARTUPINFO would override the
    # app's first ShowWindow call and invalidate the normal-launch scenario.
    $process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) -PassThru -WindowStyle Normal
    $launched.Add($process)
    return $process
}
function Wait-Until([scriptblock]$Condition, [string]$Description, [int]$Seconds = 30) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    foreach ($process in $launched) {
        Write-Output "Process $($process.Id): exited=$($process.HasExited) exitCode=$($process.ExitCode)"
    }
    $failureWindow = [ThmrInstanceProbe]::FindThmrWindow()
    [uint32]$failureOwner = 0
    $null = [ThmrInstanceProbe]::GetWindowThreadProcessId($failureWindow, [ref]$failureOwner)
    Write-Output "Window=$failureWindow owner=$failureOwner visible=$([ThmrInstanceProbe]::IsWindowVisible($failureWindow))"
    throw "Timed out: $Description"
}
function Assert-Duplicate([IntPtr]$Window) {
    $duplicate = Start-Thmr
    if (-not $duplicate.WaitForExit(10000)) { throw 'Second process stayed alive.' }
    if ($duplicate.ExitCode -ne 0) { throw "Second process exit code: $($duplicate.ExitCode)" }
    Wait-Until {
        [ThmrInstanceProbe]::IsWindowVisible($Window) -and
        -not [ThmrInstanceProbe]::IsIconic($Window)
    } 'existing window restored'
    Wait-Until { [ThmrInstanceProbe]::GetForegroundWindow() -eq $Window } 'existing window foreground'
    if (@($launched | Where-Object { -not $_.HasExited }).Count -ne 1) {
        throw 'Expected exactly one live THMR process.'
    }
}

try {
    # Race the first launch against several others before Flutter is ready.
    1..6 | ForEach-Object { $null = Start-Thmr }
    Wait-Until {
        @($launched | Where-Object { -not $_.HasExited }).Count -eq 1 -and
        [ThmrInstanceProbe]::FindThmrWindow() -ne [IntPtr]::Zero
    } 'concurrent launches reduced to one process'
    $window = [ThmrInstanceProbe]::FindThmrWindow()
    Wait-Until { [ThmrInstanceProbe]::IsWindowVisible($window) } 'first frame visible'
    Assert-Duplicate $window
    Write-Output 'PASS: startup race and visible-window activation'

    $null = [ThmrInstanceProbe]::ShowWindowAsync($window, 0) # SW_HIDE, like tray hiding.
    Wait-Until { -not [ThmrInstanceProbe]::IsWindowVisible($window) } 'window hidden'
    Assert-Duplicate $window
    Write-Output 'PASS: hidden window restored and foreground'

    $null = [ThmrInstanceProbe]::ShowWindowAsync($window, 6) # SW_MINIMIZE
    Wait-Until { [ThmrInstanceProbe]::IsIconic($window) } 'window minimized'
    Assert-Duplicate $window
    Write-Output 'PASS: minimized window restored and foreground'

    $null = [ThmrInstanceProbe]::ShowWindowAsync($window, 3) # SW_MAXIMIZE
    Wait-Until { [ThmrInstanceProbe]::IsZoomed($window) } 'window maximized'
    Assert-Duplicate $window
    if (-not [ThmrInstanceProbe]::IsZoomed($window)) { throw 'Maximized state was lost.' }
    $null = [ThmrInstanceProbe]::ShowWindowAsync($window, 6)
    Wait-Until { [ThmrInstanceProbe]::IsIconic($window) } 'maximized window minimized'
    Assert-Duplicate $window
    if (-not [ThmrInstanceProbe]::IsZoomed($window)) { throw 'Restore lost the maximized state.' }
    Write-Output 'PASS: maximized state preserved'

    $primary = @($launched | Where-Object { -not $_.HasExited })[0]
    Stop-Process -Id $primary.Id -Force
    $primary.WaitForExit()
    $restart = Start-Thmr
    Wait-Until {
        $handle = [ThmrInstanceProbe]::FindThmrWindow()
        if ($handle -eq [IntPtr]::Zero) { return $false }
        [uint32]$ownerId = 0
        $null = [ThmrInstanceProbe]::GetWindowThreadProcessId($handle, [ref]$ownerId)
        return $ownerId -eq $restart.Id -and [ThmrInstanceProbe]::IsWindowVisible($handle)
    } 'restart after forced termination'
    Assert-Duplicate ([ThmrInstanceProbe]::FindThmrWindow())
    Write-Output 'PASS: crash cleanup and restart'
} finally {
    # Stop only the processes this test started.
    foreach ($process in $launched) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit(5000) | Out-Null
        }
        $process.Dispose()
    }
}
