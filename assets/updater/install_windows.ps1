param([Parameter(Mandatory=$true)][string]$PlanPath, [switch]$ElevatedWorker)
$ErrorActionPreference = 'Stop'
$transaction = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($PlanPath))
$plan = $null
$movedOld = $false
$movedNew = $false
$child = $null
try { Start-Transcript -Path (Join-Path $transaction $(if ($ElevatedWorker) { 'worker.log' } else { 'helper.log' })) -Force | Out-Null } catch { }

function Normalize-Directory([string]$item) {
    $full = [IO.Path]::GetFullPath($item)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd('\') -eq $root.TrimEnd('\')) { return $root }
    return $full.TrimEnd('\')
}
function Assert-Sibling([string]$item, [string]$prefix) {
    $full = Normalize-Directory $item
    if ((Normalize-Directory ([IO.Path]::GetDirectoryName($full))) -ne $parent -or
        ($prefix -and -not [IO.Path]::GetFileName($full).StartsWith($prefix)) -or
        $full -eq [IO.Path]::GetPathRoot($full)) { throw 'Unsafe update path' }
    if ((Test-Path -LiteralPath $full) -and
        ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Linked update root is forbidden'
    }
    return $full
}
function Status([string]$status, [string]$message, [string]$code = '') {
    if ($plan) {
        @{ status=$status; message=$message; code=$code } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath (Join-Path $transaction 'result.pending') -Encoding UTF8
        Move-Item -LiteralPath (Join-Path $transaction 'result.pending') -Destination (Join-Path $transaction 'result.json') -Force
    }
}
function Move-Retry([string]$from, [string]$to) {
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try { Move-Item -LiteralPath $from -Destination $to; return }
        catch {
            if ($_.CategoryInfo.Category -eq 'PermissionDenied' -or $attempt -eq 19) { throw }
            Start-Sleep -Milliseconds 300
        }
    }
}
function Remove-BackupTree([string]$directory, [string]$root) {
    $full = Normalize-Directory $directory
    if ($full -ne $root -and -not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path' }
    foreach ($entry in Get-ChildItem -LiteralPath $full -Force) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
            else { [IO.File]::Delete($entry.FullName) }
        } elseif ($entry.PSIsContainer) { Remove-BackupTree $entry.FullName $root }
        else { [IO.File]::Delete($entry.FullName) }
    }
    [IO.Directory]::Delete($full, $false)
}
function Start-UpdatedApp {
    if ($ElevatedWorker) {
        # The original user's unelevated supervisor launches the player.
        [IO.File]::WriteAllText((Join-Path $transaction 'launch-new'), $plan.token)
        for ($attempt=0; $attempt -lt 100; $attempt++) {
            $childFile = Join-Path $transaction 'child.json'
            if (Test-Path -LiteralPath $childFile) {
                $started = Get-Content -LiteralPath $childFile -Raw | ConvertFrom-Json
                if ($started.token -eq $plan.token) {
                    return Get-Process -Id $started.processId -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Milliseconds 100
        }
        throw 'Unable to restart the player in the original user session'
    }
    $env:THMR_UPDATE_ACK = $plan.ack
    $env:THMR_UPDATE_TOKEN = $plan.token
    $arguments = @('--thmr-update-ack', ('"' + $plan.ack + '"'), '--thmr-update-token', $plan.token)
    return Start-Process -FilePath (Join-Path $target 'thmr_app.exe') -ArgumentList $arguments -WorkingDirectory $target -WindowStyle Normal -PassThru
}

try {
    $plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($plan.token -notmatch '^[a-f0-9]{64}$' -or $plan.timeout -lt 2 -or $plan.timeout -gt 120) { throw 'Invalid transaction' }
    foreach ($entry in @(@('ready',$plan.ready), @('ack',$plan.ack), @('result.json',$plan.result))) {
        if ([IO.Path]::GetFullPath($entry[1]) -ne (Join-Path $transaction $entry[0])) { throw 'Invalid transaction file' }
    }
    $parent = Normalize-Directory $plan.parent
    $target = Assert-Sibling $plan.target ''
    $stage = Assert-Sibling $plan.stage '.thmr-update-'
    $backup = Assert-Sibling $plan.backup '.thmr-backup-'
    if ($target -eq $stage -or $target -eq $backup -or $stage -eq $backup) { throw 'Overlapping update paths' }

    if ($plan.requiresElevation -and -not $ElevatedWorker) {
        [IO.File]::WriteAllText((Join-Path $transaction 'authorizing'), $plan.token)
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -PlanPath "' + $PlanPath + '" -ElevatedWorker'
        try {
            $worker = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        } catch {
            Status 'failed' 'Administrator authorization was cancelled or unavailable' 'authorization_cancelled'
            exit 1
        }
        $launchedNew = $false
        $launchedOld = $false
        while ($true) {
            if (-not $launchedNew -and (Test-Path -LiteralPath (Join-Path $transaction 'launch-new')) -and
                [IO.File]::ReadAllText((Join-Path $transaction 'launch-new')) -eq $plan.token) {
                $child = Start-UpdatedApp
                @{token=$plan.token; processId=$child.Id} | ConvertTo-Json -Compress |
                    Set-Content -LiteralPath (Join-Path $transaction 'child.pending') -Encoding UTF8
                Move-Item -LiteralPath (Join-Path $transaction 'child.pending') -Destination (Join-Path $transaction 'child.json') -Force
                $launchedNew = $true
            }
            if (-not $launchedOld -and (Test-Path -LiteralPath (Join-Path $transaction 'launch-old')) -and
                [IO.File]::ReadAllText((Join-Path $transaction 'launch-old')) -eq $plan.token) {
                Start-Process -FilePath (Join-Path $target 'thmr_app.exe') -WorkingDirectory $target -WindowStyle Normal
                $launchedOld = $true
            }
            if ($worker.HasExited) { exit $worker.ExitCode }
            Start-Sleep -Milliseconds 100
        }
    }

    if (Test-Path -LiteralPath (Join-Path $transaction 'cancel')) { throw 'Update transaction cancelled' }
    if ($plan.source) {
        $source = [IO.Path]::GetFullPath($plan.source)
        if ($source -ne (Join-Path $transaction 'payload') -or
            ((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid update source' }
        if (Get-ChildItem -LiteralPath $source -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Linked update source is forbidden' }
        if (Test-Path -LiteralPath $stage) { Remove-BackupTree $stage $stage }
        New-Item -ItemType Directory -Path $stage | Out-Null
        Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $stage -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'thmr_app.exe')) -or
        -not (Test-Path -LiteralPath (Join-Path $stage 'data/flutter_assets')) -or
        (Test-Path -LiteralPath $backup)) { throw 'Invalid application bundle' }
    if ((Get-Item -LiteralPath (Join-Path $stage 'thmr_app.exe') -Force).VersionInfo.ProductVersion -ne $plan.identity) { throw 'Package version does not match signed release' }
    [IO.File]::WriteAllText((Join-Path $transaction 'ready.pending'), $plan.token)
    Move-Item -LiteralPath (Join-Path $transaction 'ready.pending') -Destination $plan.ready -Force
    $oldProcess = Get-Process -Id $plan.processId -ErrorAction SilentlyContinue
    if ($oldProcess -and -not $oldProcess.WaitForExit(120000)) { throw 'Old application did not exit' }
    if (Test-Path -LiteralPath (Join-Path $transaction 'cancel')) { throw 'Update transaction cancelled' }
    Move-Retry $target $backup
    $movedOld = $true
    Move-Retry $stage $target
    $movedNew = $true
    $child = Start-UpdatedApp
    $deadline = (Get-Date).AddSeconds($plan.timeout)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $plan.ack) -and
            (Get-Content -LiteralPath $plan.ack -Raw).Trim() -eq $plan.token) {
            Status 'success' 'Update installed and application started'
            $checkedBackup = Assert-Sibling $backup '.thmr-backup-'
            try { Remove-BackupTree $checkedBackup $checkedBackup } catch { }
            if ($plan.source) { try { Remove-BackupTree $source $source } catch { } }
            exit 0
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'Updated application failed its startup check'
} catch {
    $failure = $_
    try { $failure | Out-String | Add-Content -LiteralPath (Join-Path $transaction 'helper-error.log') -Encoding UTF8 } catch { }
    if ($child -and -not $child.HasExited) { $child.Kill(); $child.WaitForExit(10000) | Out-Null }
    if ($movedNew -and (Test-Path -LiteralPath $target)) { Move-Retry $target $stage }
    if ($movedOld -and (Test-Path -LiteralPath $backup)) {
        Move-Retry $backup $target
        Status 'rollback' $failure.Exception.Message 'startup_failed'
        if ($ElevatedWorker) { [IO.File]::WriteAllText((Join-Path $transaction 'launch-old'), $plan.token) }
        else { Start-Process -FilePath (Join-Path $target 'thmr_app.exe') -WorkingDirectory $target -WindowStyle Normal }
    } else {
        $code = if ($failure.CategoryInfo.Category -eq 'PermissionDenied') { 'permission_required' } else { 'prepare_failed' }
        Status 'failed' $failure.Exception.Message $code
    }
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch { }
    try { [IO.File]::WriteAllText((Join-Path $transaction $(if ($ElevatedWorker) { 'worker.done' } else { 'helper.done' })), 'done') } catch { }
}
