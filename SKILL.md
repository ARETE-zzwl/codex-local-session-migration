---
name: codex-local-session-migration
description: Export, verify, and restore local Codex desktop or CLI session history between Windows computers without copying login credentials. Use when a user asks to back up, transfer, import, recover, or move local Codex chats and their local metadata.
---

# Codex Local Session Migration

Migrate local Codex history with the bundled PowerShell helpers. Treat a migration archive as sensitive because chat transcripts and attachments can contain private data even though authentication files are excluded.

## Choose the scope

- Use the default history scope when the destination only needs to read and continue local chats.
- Add `-IncludeManagedProjects` only when the user wants Codex-managed project files under `.chatgpt-projects`. Warn that project files can contain `.env` files or other secrets.
- Add `-IncludeCustomization` only when the user also wants skills, memories, plugins, automations, and local preferences. Warn that custom configuration may contain tokens or private endpoints.
- Source repositories and working folders outside `CODEX_HOME` are never included. Copy them separately if old chats must reopen their original workspaces.

Read [references/migration-model.md](references/migration-model.md) when explaining scope, diagnosing a failed restore, or handling an occupied destination.

## Export

1. Ask the user to close Codex desktop and any Codex CLI sessions that could still be writing history.
2. Run `scripts/Export-CodexLocalSessions.ps1` with a destination directory.
3. Report the ZIP path, size, session-file count, SHA-256 value, and excluded categories.
4. Do not upload or publish the resulting archive. Hand it only to the user through their chosen private transfer method.

Example:

```powershell
pwsh -File scripts/Export-CodexLocalSessions.ps1 -Destination D:\Transfer
```

## Restore

1. On the destination computer, install Codex and sign in once, then close it completely.
2. Put the archive and its `.sha256` sidecar in a local folder.
3. Run the restore script without `-Apply` first. Review the detected bundle, exclusions, and destination state.
4. Run again with `-Apply` only after the user has explicitly requested the restore.
5. Preserve the destination computer's `auth.json`, `installation_id`, and secret stores. The script must never import those from a bundle.
6. If destination history already exists, stop unless the user explicitly accepts replacement with `-ReplaceExistingHistory`. The script creates a rollback archive first.
7. Start Codex and verify several old chats, an attachment, and one continued chat. A successful file copy alone does not prove the UI can read the history.

Example:

```powershell
pwsh -File scripts/Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-20260927-120000.zip
pwsh -File scripts/Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-20260927-120000.zip -Apply
```

## Safety invariants

- Never include `auth.json`, `installation_id`, `.sandbox-secrets`, browser state, caches, temporary files, writer locks, or runtime logs.
- Never infer that account sign-in synchronizes local sessions.
- Never delete the source after export. Keep the old computer or original backup until the destination UI is verified.
- Never merge two populated history databases automatically. Export both sides separately and preserve rollback copies.
- Do not claim that absolute project paths were repaired. If usernames or folder layouts differ, transcripts may remain readable while old working-directory links do not.
