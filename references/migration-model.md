# Migration Model

## What the default archive contains

The export helper discovers the active Codex home from `CODEX_HOME`, falling back to `$HOME\.codex`. It copies the local history surfaces that may be needed by different Codex app versions:

- `sessions/` and `session_index.jsonl`
- `attachments/`, `generated_images/`, and `visualizations/`
- `.codex-global-state.json*`
- `thread_history_*.sqlite*`, `state_*.sqlite*`, and the `sqlite/` directory

The app's storage schema is not a stable public interchange format. Keeping both transcripts and local indexes/databases gives the destination app the best chance of discovering historical chats across versions.

## Optional archive content

`-IncludeManagedProjects` adds `.chatgpt-projects/`. These are project files, not just chat metadata, and may contain credentials or large generated artifacts.

`-IncludeCustomization` adds local preferences and extensions such as `config.toml`, `AGENTS.md`, `skills/`, `memories/`, `plugins/`, and `automations/`. Custom configuration can contain private server addresses or tokens, so this option is never implied by a request to move chats alone.

## Always excluded

- `auth.json` and `installation_id`
- `.sandbox-secrets/`
- Browser and computer-use state
- Caches, temporary data, queues, logs, and active writer locks
- Source projects located outside the Codex home

Excluding authentication is necessary but does not make the archive non-sensitive. Conversations, attachments, generated images, project metadata, and memories can still contain private information.

## Destination behavior

Use a freshly installed destination when possible. The restore helper preserves the destination login and device identity. It refuses a populated destination by default because SQLite history databases cannot be safely concatenated by copying files.

`-ReplaceExistingHistory` means replacement, not database merge. A rollback ZIP is created before any imported history is written. If both computers contain valuable independent chats, export both computers and keep both archives; do not combine their databases automatically.

## Verification

Verification has three layers:

1. Archive integrity: compare the ZIP SHA-256 with the `.sha256` sidecar.
2. File restoration: compare the manifest's file count and representative hashes.
3. Product behavior: open several migrated chats, inspect an attachment, and continue one chat in Codex.

Only the third layer confirms that the installed Codex version can read the migrated local state.

## Path changes

Session transcripts can retain absolute paths from the source computer. Copy external repositories separately and place them at the same path when practical. Otherwise, reopen the project at its new location; do not rewrite session JSON or SQLite paths without a version-specific, tested migration.
