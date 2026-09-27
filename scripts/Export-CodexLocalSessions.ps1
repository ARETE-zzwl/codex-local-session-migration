[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),

    [switch]$IncludeManagedProjects,
    [switch]$IncludeCustomization,
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
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed for '$Source' with exit code $LASTEXITCODE."
    }
}

function Copy-ExactEntry {
    param([string]$Name, [string]$SourceRoot, [string]$TargetRoot)

    $sourcePath = Join-Path $SourceRoot $Name
    if (-not (Test-Path -LiteralPath $sourcePath)) { return }

    $item = Get-Item -LiteralPath $sourcePath -Force
    $targetPath = Join-Path $TargetRoot $Name
    if ($item.PSIsContainer) {
        Copy-Tree -Source $sourcePath -Target $targetPath
    } else {
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }
}

function Copy-MatchingFiles {
    param([string]$Pattern, [string]$SourceRoot, [string]$TargetRoot)

    Get-ChildItem -LiteralPath $SourceRoot -File -Force -Filter $Pattern -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $TargetRoot $_.Name) -Force
    }
}

function Get-RelativePath {
    param([string]$BasePath, [string]$Path)
    return [IO.Path]::GetRelativePath($BasePath, $Path).Replace('\', '/')
}

$codexRoot = [IO.Path]::GetFullPath($CodexHome)
if (-not (Test-Path -LiteralPath $codexRoot -PathType Container)) {
    throw "Codex home does not exist: $codexRoot"
}

if ((Test-CodexRunning) -and -not $AllowRunning) {
    throw 'Codex appears to be running. Close Codex for a consistent snapshot, or rerun with -AllowRunning for a best-effort export.'
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$destinationRoot = [IO.Path]::GetFullPath($Destination)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundleName = "codex-local-sessions-$stamp"
$stageRoot = Join-Path $destinationRoot $bundleName
$payloadRoot = Join-Path $stageRoot 'payload\.codex'
$archivePath = Join-Path $destinationRoot "$bundleName.zip"
$receiptPath = Join-Path $destinationRoot "$bundleName.receipt.json"
$sidecarPath = "$archivePath.sha256"

foreach ($path in @($stageRoot, $archivePath, $receiptPath, $sidecarPath)) {
    if (Test-Path -LiteralPath $path) { throw "Output already exists: $path" }
}

New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null

$historyDirectories = @('sessions', 'attachments', 'generated_images', 'visualizations', 'sqlite')
$historyFiles = @('session_index.jsonl')
$historyPatterns = @('.codex-global-state.json*', 'thread_history_*.sqlite*', 'state_*.sqlite*')

foreach ($name in $historyDirectories) { Copy-ExactEntry -Name $name -SourceRoot $codexRoot -TargetRoot $payloadRoot }
foreach ($name in $historyFiles) { Copy-ExactEntry -Name $name -SourceRoot $codexRoot -TargetRoot $payloadRoot }
foreach ($pattern in $historyPatterns) { Copy-MatchingFiles -Pattern $pattern -SourceRoot $codexRoot -TargetRoot $payloadRoot }

if ($IncludeManagedProjects) {
    Copy-ExactEntry -Name '.chatgpt-projects' -SourceRoot $codexRoot -TargetRoot $payloadRoot
}

if ($IncludeCustomization) {
    $customDirectories = @('skills', 'memories', 'plugins', 'automations', 'ambient-suggestions', 'dictation-history')
    $customFiles = @('config.toml', 'AGENTS.md')
    $customPatterns = @('memories_*.sqlite*', 'goals_*.sqlite*')
    foreach ($name in $customDirectories) { Copy-ExactEntry -Name $name -SourceRoot $codexRoot -TargetRoot $payloadRoot }
    foreach ($name in $customFiles) { Copy-ExactEntry -Name $name -SourceRoot $codexRoot -TargetRoot $payloadRoot }
    foreach ($pattern in $customPatterns) { Copy-MatchingFiles -Pattern $pattern -SourceRoot $codexRoot -TargetRoot $payloadRoot }
}

$forbiddenNames = @('auth.json', 'installation_id')
$forbidden = Get-ChildItem -LiteralPath $payloadRoot -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -in $forbiddenNames -or $_.FullName -match '[\\/]\.sandbox-secrets([\\/]|$)'
}
if ($forbidden) {
    throw "Refusing to create an archive containing forbidden authentication or secret-store entries: $($forbidden.FullName -join ', ')"
}

$payloadFiles = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -Force)
if ($payloadFiles.Count -eq 0) { throw 'No migration data was found.' }

$inventory = @($payloadFiles | ForEach-Object {
    [ordered]@{
        path = Get-RelativePath -BasePath $payloadRoot -Path $_.FullName
        bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})

$suspiciousPattern = '(^|/)(\.env($|\.)|[^/]*(secret|token|credential|private[_-]?key)[^/]*)$|\.(pem|pfx|p12|key)$'
$suspicious = @($inventory | Where-Object { $_['path'] -match $suspiciousPattern } | ForEach-Object { [string]$_['path'] })
$sessionRoot = Join-Path $payloadRoot 'sessions'
$sessionFileCount = if (Test-Path -LiteralPath $sessionRoot) { @(Get-ChildItem -LiteralPath $sessionRoot -Recurse -File -Force).Count } else { 0 }
$payloadBytes = [long](($payloadFiles | Measure-Object Length -Sum).Sum)

$manifest = [ordered]@{
    schema_version = 1
    created_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_codex_home = $codexRoot
    source_user = $env:USERNAME
    powershell_version = $PSVersionTable.PSVersion.ToString()
    scope = [ordered]@{
        history = $true
        managed_projects = [bool]$IncludeManagedProjects
        customization = [bool]$IncludeCustomization
        best_effort_while_running = [bool]$AllowRunning
    }
    session_file_count = $sessionFileCount
    payload_file_count = $payloadFiles.Count
    payload_bytes = $payloadBytes
    always_excluded = @('auth.json', 'installation_id', '.sandbox-secrets', 'browser state', 'computer-use state', 'caches', 'temporary files', 'queues', 'logs', 'writer locks')
    suspicious_file_names = $suspicious
    files = $inventory
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stageRoot 'manifest.json') -Encoding utf8

@'
This archive contains private Codex local history. It intentionally excludes login credentials,
device identity, secret stores, caches, and active locks. Sign in normally on the destination
computer. Verify migrated chats in Codex before retiring the source computer.
'@ | Set-Content -LiteralPath (Join-Path $stageRoot 'RESTORE-NOTES.txt') -Encoding utf8

try {
    & tar.exe -a -c -f $archivePath -C $destinationRoot $bundleName
    if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE." }

    $archive = Get-Item -LiteralPath $archivePath
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$archiveHash  $($archive.Name)" | Set-Content -LiteralPath $sidecarPath -Encoding ascii

    $receipt = [ordered]@{
        archive = $archive.FullName
        archive_bytes = $archive.Length
        archive_sha256 = $archiveHash
        sha256_sidecar = $sidecarPath
        session_file_count = $sessionFileCount
        payload_file_count = $payloadFiles.Count
        payload_bytes = $payloadBytes
        suspicious_file_names = $suspicious
    }
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}

[pscustomobject]@{
    Archive = $archivePath
    ArchiveBytes = (Get-Item -LiteralPath $archivePath).Length
    SHA256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    SessionFiles = $sessionFileCount
    PayloadFiles = $payloadFiles.Count
    Receipt = $receiptPath
    SuspiciousFileNames = $suspicious.Count
}
