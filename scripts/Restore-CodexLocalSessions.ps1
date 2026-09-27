[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),

    [switch]$Apply,
    [switch]$ReplaceExistingHistory,
    [switch]$AllowRunning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CodexRunning {
    $names = @('Codex', 'codex')
    return [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $names } | Select-Object -First 1)
}

function Copy-Tree {
    param([string]$Source, [string]$Target)
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    & robocopy.exe $Source $Target /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ /NFL /NDL /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy failed for '$Source' with exit code $LASTEXITCODE." }
}

function Assert-SafeArchiveEntries {
    param([string[]]$Entries)
    foreach ($entry in $Entries) {
        $normalized = $entry.Replace('\', '/').Trim()
        if (-not $normalized) { continue }
        if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:' -or $normalized.Split('/') -contains '..') {
            throw "Unsafe archive entry: $entry"
        }
    }
}

$bundlePath = [IO.Path]::GetFullPath($Bundle)
if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) { throw "Bundle not found: $bundlePath" }
if ([IO.Path]::GetExtension($bundlePath) -ne '.zip') { throw 'Bundle must be a .zip file created by Export-CodexLocalSessions.ps1.' }

$codexRoot = [IO.Path]::GetFullPath($CodexHome)
if ($codexRoot -eq [IO.Path]::GetPathRoot($codexRoot)) { throw 'Refusing to use a filesystem root as CodexHome.' }

$sidecarPath = "$bundlePath.sha256"
$actualArchiveHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
if (Test-Path -LiteralPath $sidecarPath) {
    $expectedArchiveHash = ((Get-Content -LiteralPath $sidecarPath -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    if ($actualArchiveHash -ne $expectedArchiveHash) {
        throw "Archive SHA-256 mismatch. Expected $expectedArchiveHash but found $actualArchiveHash."
    }
} else {
    Write-Warning 'No .sha256 sidecar was found. The archive cannot be compared with the export receipt.'
}

$entries = @(& tar.exe -tf $bundlePath)
if ($LASTEXITCODE -ne 0) { throw "Unable to list archive contents; tar exited with $LASTEXITCODE." }
Assert-SafeArchiveEntries -Entries $entries

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("codex-session-restore-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    & tar.exe -xf $bundlePath -C $tempRoot
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract archive; tar exited with $LASTEXITCODE." }

    $manifestFile = @(Get-ChildItem -LiteralPath $tempRoot -Recurse -File -Filter 'manifest.json')
    if ($manifestFile.Count -ne 1) { throw "Expected exactly one manifest.json, found $($manifestFile.Count)." }
    $bundleRoot = $manifestFile[0].Directory.FullName
    $payloadRoot = Join-Path $bundleRoot 'payload\.codex'
    if (-not (Test-Path -LiteralPath $payloadRoot -PathType Container)) { throw 'Bundle payload/.codex directory is missing.' }

    $manifest = Get-Content -LiteralPath $manifestFile[0].FullName -Raw | ConvertFrom-Json
    if ($manifest.schema_version -ne 1) { throw "Unsupported manifest schema version: $($manifest.schema_version)" }

    $forbiddenNames = @('auth.json', 'installation_id')
    $forbidden = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -Force | Where-Object {
        $_.Name -in $forbiddenNames -or $_.FullName -match '[\\/]\.sandbox-secrets([\\/]|$)'
    })
    if ($forbidden.Count -gt 0) { throw 'Bundle contains forbidden authentication or secret-store entries.' }

    $payloadFiles = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -Force)
    if ($payloadFiles.Count -ne [int]$manifest.payload_file_count) {
        throw "Payload file count mismatch. Manifest: $($manifest.payload_file_count); extracted: $($payloadFiles.Count)."
    }

    $hashByPath = @{}
    foreach ($file in $payloadFiles) {
        $relative = [IO.Path]::GetRelativePath($payloadRoot, $file.FullName).Replace('\', '/')
        $hashByPath[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    foreach ($record in $manifest.files) {
        if (-not $hashByPath.ContainsKey([string]$record.path)) { throw "Manifest file is missing: $($record.path)" }
        if ($hashByPath[[string]$record.path] -ne ([string]$record.sha256).ToLowerInvariant()) {
            throw "Payload hash mismatch: $($record.path)"
        }
    }

    $existingSessionRoot = Join-Path $codexRoot 'sessions'
    $existingSessionFiles = if (Test-Path -LiteralPath $existingSessionRoot) { @(Get-ChildItem -LiteralPath $existingSessionRoot -Recurse -File -Force).Count } else { 0 }

    $preview = [pscustomobject]@{
        Mode = if ($Apply) { 'Apply' } else { 'PreviewOnly' }
        Bundle = $bundlePath
        BundleSHA256 = $actualArchiveHash
        Destination = $codexRoot
        ImportedSessionFiles = [int]$manifest.session_file_count
        ImportedPayloadFiles = [int]$manifest.payload_file_count
        ExistingSessionFiles = $existingSessionFiles
        ManagedProjectsIncluded = [bool]$manifest.scope.managed_projects
        CustomizationIncluded = [bool]$manifest.scope.customization
        ExistingHistoryReplacementRequested = [bool]$ReplaceExistingHistory
    }
    $preview

    if (-not $Apply) { return }
    if ((Test-CodexRunning) -and -not $AllowRunning) {
        throw 'Codex appears to be running. Close Codex before restore, or use -AllowRunning only if you accept an inconsistent restore risk.'
    }
    if ($existingSessionFiles -gt 0 -and -not $ReplaceExistingHistory) {
        throw 'Destination already contains local session files. Export that computer first, then rerun with -ReplaceExistingHistory if replacement is intended.'
    }

    New-Item -ItemType Directory -Force -Path $codexRoot | Out-Null
    $rollbackArchive = $null
    if ((Get-ChildItem -LiteralPath $codexRoot -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        $rollbackParent = Split-Path -Parent $codexRoot
        $rollbackStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $rollbackName = "codex-before-session-restore-$rollbackStamp.zip"
        $rollbackArchive = Join-Path $rollbackParent $rollbackName
        & tar.exe -a -c -f $rollbackArchive --exclude='auth.json' --exclude='installation_id' --exclude='.sandbox-secrets' -C $codexRoot .
        if ($LASTEXITCODE -ne 0) { throw "Failed to create rollback archive; tar exited with $LASTEXITCODE." }
    }

    if ($existingSessionFiles -gt 0 -and $ReplaceExistingHistory) {
        $coreNames = @('sessions', 'attachments', 'generated_images', 'visualizations', 'sqlite', 'session_index.jsonl')
        foreach ($name in $coreNames) {
            $path = Join-Path $codexRoot $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        }
        $corePatterns = @('.codex-global-state.json*', 'thread_history_*.sqlite*', 'state_*.sqlite*')
        foreach ($pattern in $corePatterns) {
            Get-ChildItem -LiteralPath $codexRoot -File -Force -Filter $pattern -ErrorAction SilentlyContinue | Remove-Item -Force
        }
    }

    Get-ChildItem -LiteralPath $payloadRoot -Force | ForEach-Object {
        $target = Join-Path $codexRoot $_.Name
        if ($_.PSIsContainer) {
            Copy-Tree -Source $_.FullName -Target $target
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }

    $restoredSessions = if (Test-Path -LiteralPath (Join-Path $codexRoot 'sessions')) {
        @(Get-ChildItem -LiteralPath (Join-Path $codexRoot 'sessions') -Recurse -File -Force).Count
    } else { 0 }
    if ($restoredSessions -lt [int]$manifest.session_file_count) {
        throw "Restore verification failed. Expected at least $($manifest.session_file_count) session files, found $restoredSessions."
    }

    $receipt = [ordered]@{
        restored_utc = (Get-Date).ToUniversalTime().ToString('o')
        bundle = $bundlePath
        bundle_sha256 = $actualArchiveHash
        destination = $codexRoot
        restored_session_files = $restoredSessions
        rollback_archive = $rollbackArchive
        destination_auth_preserved = $true
        next_step = 'Start Codex and verify several chats, an attachment, and one continued chat.'
    }
    $receiptPath = Join-Path (Split-Path -Parent $bundlePath) (([IO.Path]::GetFileNameWithoutExtension($bundlePath)) + '.restore-receipt.json')
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    [pscustomobject]@{ Restored = $true; Destination = $codexRoot; SessionFiles = $restoredSessions; RollbackArchive = $rollbackArchive; Receipt = $receiptPath }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
