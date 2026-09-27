# Codex Local Session Migration

A reusable Codex Skill for safely moving local Codex desktop and CLI chats between Windows computers.

It exports local transcripts, indexes, attachments, and history databases while excluding login credentials, device identity, secret stores, caches, and active lock files. Restore runs as a preview by default and creates a rollback archive before replacing existing history.

## Install as a Codex Skill

Clone this repository into your personal skills directory:

```powershell
git clone https://github.com/ARETE-zzwl/codex-local-session-migration.git "$HOME\.codex\skills\codex-local-session-migration"
```

Restart Codex, then ask:

```text
Use $codex-local-session-migration to export my local Codex chats to D:\Transfer.
```

You can also run the helpers directly.

## Export

Close Codex first, then run:

```powershell
pwsh -File .\scripts\Export-CodexLocalSessions.ps1 -Destination D:\Transfer
```

Optional switches:

- `-IncludeManagedProjects` includes `.chatgpt-projects`.
- `-IncludeCustomization` includes skills, memories, plugins, automations, and preferences.
- `-AllowRunning` permits a best-effort snapshot while Codex is running; avoid it when a consistent backup is required.

The command creates a ZIP, a `.sha256` sidecar, and a JSON receipt.

## Restore

Install Codex on the destination computer, sign in once, and close it. Preview first:

```powershell
pwsh -File .\scripts\Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-YYYYMMDD-HHMMSS.zip
```

Then apply:

```powershell
pwsh -File .\scripts\Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-YYYYMMDD-HHMMSS.zip -Apply
```

If the destination already has local chats, export them first. Replacement requires the explicit `-ReplaceExistingHistory` switch and automatically creates a rollback ZIP.

## Important limitations

- This is a local-state migration, not an official cloud synchronization feature.
- Working repositories outside `.codex` are not included.
- Old chats can contain absolute source-computer paths.
- Chat archives remain sensitive even without account credentials.
- Always verify migrated chats in the Codex UI before retiring the source computer.

## License

MIT
