[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.migration-test-' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'source\.codex'
$outputRoot = Join-Path $testRoot 'out'
$fullOutputRoot = Join-Path $testRoot 'out-full'
$destinationRoot = Join-Path $testRoot 'destination\.codex'

try {
    $directories = @(
        (Join-Path $sourceRoot 'sessions\2026\09\27'),
        (Join-Path $sourceRoot 'attachments'),
        (Join-Path $sourceRoot '.sandbox-secrets'),
        (Join-Path $sourceRoot '.chatgpt-projects\demo'),
        (Join-Path $sourceRoot 'skills\demo'),
        $outputRoot,
        $fullOutputRoot,
        $destinationRoot
    )
    New-Item -ItemType Directory -Force -Path $directories | Out-Null

    '{"type":"session_meta","payload":{"id":"test-session","cwd":"C:\\work"}}' | Set-Content -LiteralPath (Join-Path $sourceRoot 'sessions\2026\09\27\rollout-test.jsonl') -Encoding utf8
    'attachment' | Set-Content -LiteralPath (Join-Path $sourceRoot 'attachments\note.txt') -Encoding utf8
    '{"id":"test-session","thread_name":"Demo"}' | Set-Content -LiteralPath (Join-Path $sourceRoot 'session_index.jsonl') -Encoding utf8
    '{}' | Set-Content -LiteralPath (Join-Path $sourceRoot '.codex-global-state.json') -Encoding utf8
    'db' | Set-Content -LiteralPath (Join-Path $sourceRoot 'thread_history_1.sqlite') -Encoding utf8
    'source-token' | Set-Content -LiteralPath (Join-Path $sourceRoot 'auth.json') -Encoding utf8
    'source-id' | Set-Content -LiteralPath (Join-Path $sourceRoot 'installation_id') -Encoding utf8
    'secret' | Set-Content -LiteralPath (Join-Path $sourceRoot '.sandbox-secrets\secret.txt') -Encoding utf8
    'PRIVATE=1' | Set-Content -LiteralPath (Join-Path $sourceRoot '.chatgpt-projects\demo\.env') -Encoding utf8
    'custom' | Set-Content -LiteralPath (Join-Path $sourceRoot 'skills\demo\SKILL.md') -Encoding utf8
    'model = "example"' | Set-Content -LiteralPath (Join-Path $sourceRoot 'config.toml') -Encoding utf8

    'target-token' | Set-Content -LiteralPath (Join-Path $destinationRoot 'auth.json') -Encoding utf8
    'target-id' | Set-Content -LiteralPath (Join-Path $destinationRoot 'installation_id') -Encoding utf8

    $exportScript = Join-Path $repoRoot 'scripts\Export-CodexLocalSessions.ps1'
    $restoreScript = Join-Path $repoRoot 'scripts\Restore-CodexLocalSessions.ps1'
    $exportResult = & $exportScript -Destination $outputRoot -CodexHome $sourceRoot -AllowRunning
    $archive = $exportResult.Archive
    $entries = @(& tar.exe -tf $archive)
    if ($entries -match 'auth\.json|installation_id|sandbox-secrets|chatgpt-projects|skills/demo') {
        throw 'Default export included excluded or optional data.'
    }

    $fullExportResult = & $exportScript -Destination $fullOutputRoot -CodexHome $sourceRoot -IncludeManagedProjects -IncludeCustomization -AllowRunning
    $fullEntries = @(& tar.exe -tf $fullExportResult.Archive)
    if (-not ($fullEntries -match 'chatgpt-projects/demo/\.env')) { throw 'Managed project data was not included when requested.' }
    if (-not ($fullEntries -match 'skills/demo/SKILL\.md')) { throw 'Customization data was not included when requested.' }
    if ([int]$fullExportResult.SuspiciousFileNames -lt 1) { throw 'Suspicious file-name reporting did not flag the managed-project .env file.' }

    & $restoreScript -Bundle $archive -CodexHome $destinationRoot | Out-Null
    & $restoreScript -Bundle $archive -CodexHome $destinationRoot -Apply -AllowRunning | Out-Null

    if ((Get-Content -LiteralPath (Join-Path $destinationRoot 'auth.json') -Raw).Trim() -ne 'target-token') {
        throw 'Destination auth.json was not preserved.'
    }
    if ((Get-Content -LiteralPath (Join-Path $destinationRoot 'installation_id') -Raw).Trim() -ne 'target-id') {
        throw 'Destination installation_id was not preserved.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destinationRoot 'sessions\2026\09\27\rollout-test.jsonl'))) {
        throw 'Session transcript was not restored.'
    }

    $occupiedDestinationRefused = $false
    try {
        & $restoreScript -Bundle $archive -CodexHome $destinationRoot -Apply -AllowRunning | Out-Null
    } catch {
        $occupiedDestinationRefused = $_.Exception.Message -match 'already contains local session'
    }
    if (-not $occupiedDestinationRefused) { throw 'Occupied destination was not refused.' }

    $replaceResult = @(& $restoreScript -Bundle $archive -CodexHome $destinationRoot -Apply -ReplaceExistingHistory -AllowRunning)
    $appliedResult = $replaceResult[-1]
    if (-not $appliedResult.Restored) { throw 'Explicit history replacement did not complete.' }
    if (-not (Test-Path -LiteralPath $appliedResult.RollbackArchive -PathType Leaf)) { throw 'History replacement did not create a rollback archive.' }
    if ((Get-Content -LiteralPath (Join-Path $destinationRoot 'auth.json') -Raw).Trim() -ne 'target-token') {
        throw 'Destination auth.json changed during explicit replacement.'
    }

    [pscustomobject]@{
        Test = 'round-trip'
        Result = 'PASS'
        ArchiveEntries = $entries.Count
        AuthPreserved = $true
        OccupiedDestinationRefused = $true
        OptionalScopeVerified = $true
        ReplacementRollbackCreated = $true
    }
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedRepoRoot = [IO.Path]::GetFullPath($repoRoot)
    if (-not $resolvedTestRoot.StartsWith($resolvedRepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean a test path outside the repository: $resolvedTestRoot"
    }
    if ((Split-Path -Leaf $resolvedTestRoot) -notlike '.migration-test-*') {
        throw "Refusing to clean an unexpected test path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
