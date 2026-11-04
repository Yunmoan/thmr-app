param([Parameter(Mandatory=$true)][string]$PlanPath)
$ErrorActionPreference = 'Stop'
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
$parent = [IO.Path]::GetFullPath($plan.parent).TrimEnd('\')
function Assert-Sibling([string]$item, [string]$prefix) {
    $full = [IO.Path]::GetFullPath($item).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $parent -or
        ($prefix -and -not [IO.Path]::GetFileName($full).StartsWith($prefix)) -or
        $full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) { throw 'Unsafe update path' }
    if (Test-Path -LiteralPath $full) {
        if ((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked update root is forbidden' }
    }
    return $full
}
$target = Assert-Sibling $plan.target ''
$stage = Assert-Sibling $plan.stage '.thmr-update-'
$backup = Assert-Sibling $plan.backup '.thmr-backup-'
if ($target -eq $stage -or $target -eq $backup -or $stage -eq $backup) { throw 'Overlapping update paths' }
function Status([string]$status, [string]$message) {
    @{ status=$status; message=$message } | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $plan.result -Encoding UTF8
}
function Move-Retry([string]$from, [string]$to) {
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try { Move-Item -LiteralPath $from -Destination $to; return }
        catch { if ($attempt -eq 19) { throw }; Start-Sleep -Milliseconds 300 }
    }
}
function Remove-BackupTree([string]$directory, [string]$root) {
    $full = [IO.Path]::GetFullPath($directory).TrimEnd('\')
    if ($full -ne $root -and -not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
    foreach ($entry in Get-ChildItem -LiteralPath $full -Force) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            # Delete only the link itself; never recurse through junctions.
            if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
            else { [IO.File]::Delete($entry.FullName) }
        } elseif ($entry.PSIsContainer) {
            Remove-BackupTree $entry.FullName $root
        } else { [IO.File]::Delete($entry.FullName) }
    }
    [IO.Directory]::Delete($full, $false)
}
$movedOld = $false
$movedNew = $false
$child = $null
try {
    if ($plan.token -notmatch '^[a-f0-9]{64}$' -or $plan.timeout -lt 2 -or $plan.timeout -gt 120) { throw 'Invalid transaction' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'thmr_app.exe')) -or
        -not (Test-Path -LiteralPath (Join-Path $stage 'data/flutter_assets')) -or
        (Test-Path -LiteralPath $backup)) { throw 'Invalid application bundle' }
    $newExe = Join-Path $stage 'thmr_app.exe'
    if ((Get-Item -LiteralPath $newExe).VersionInfo.ProductVersion -ne $plan.identity) { throw 'Package version does not match signed release' }
    Set-Content -LiteralPath $plan.ready -Value $plan.token -NoNewline
    $oldProcess = Get-Process -Id $plan.processId -ErrorAction SilentlyContinue
    if ($oldProcess -and -not $oldProcess.WaitForExit(120000)) { throw 'Old application did not exit' }
    if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $plan.ready) 'cancel')) { throw 'Update transaction cancelled' }
    Move-Retry $target $backup
    $movedOld = $true
    Move-Retry $stage $target
    $movedNew = $true
    $arguments = @('--thmr-update-ack', ('"' + $plan.ack + '"'), '--thmr-update-token', $plan.token)
    $env:THMR_UPDATE_ACK = $plan.ack
    $env:THMR_UPDATE_TOKEN = $plan.token
    $child = Start-Process -FilePath (Join-Path $target 'thmr_app.exe') -ArgumentList $arguments -WorkingDirectory $target -WindowStyle Normal -PassThru
    $deadline = (Get-Date).AddSeconds($plan.timeout)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $plan.ack) -and
            (Get-Content -LiteralPath $plan.ack -Raw).Trim() -eq $plan.token) {
            Status 'success' 'Update installed and application started'
            $checkedBackup = Assert-Sibling $backup '.thmr-backup-'
            try { Remove-BackupTree $checkedBackup $checkedBackup } catch { }
            exit 0
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'Updated application failed its startup check'
} catch {
    $failure = $_.Exception.Message
    if ($child -and -not $child.HasExited) { $child.Kill(); $child.WaitForExit(10000) | Out-Null }
    if ($movedNew -and (Test-Path -LiteralPath $target)) { Move-Retry $target $stage }
    if ($movedOld -and (Test-Path -LiteralPath $backup)) {
        Move-Retry $backup $target
        Status 'rollback' $failure
        Start-Process -FilePath (Join-Path $target 'thmr_app.exe') -WorkingDirectory $target -WindowStyle Normal
    } else { Status 'failed' $failure }
    exit 1
}
