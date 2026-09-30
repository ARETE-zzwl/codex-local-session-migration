# Codex Local Session Migration

[中文](#中文) · [English](#english)

## 中文

在 Windows 电脑之间备份和迁移 Codex 本地聊天记录的 PowerShell 脚本，也可以作为 Codex skill 使用。

默认导出聊天文件、索引、附件和历史数据库，不复制登录凭据、设备标识、缓存和运行锁。恢复前会先预览；覆盖目标电脑已有历史时，会创建回滚备份。

### 安装

需要 Windows 和 PowerShell 7（`pwsh`）。脚本还会调用 Windows 自带的 `robocopy.exe` 和 `tar.exe`。

```powershell
git clone https://github.com/ARETE-zzwl/codex-local-session-migration.git "$HOME\.codex\skills\codex-local-session-migration"
```

若使用自定义 `CODEX_HOME`，把 skill 放到该目录的 `skills` 下。重新启动 Codex 后可调用：

```text
使用 $codex-local-session-migration，把本机聊天记录导出到 D:\Transfer。
```

以下命令也可以直接使用。在仓库根目录执行。

### 导出

先关闭 Codex 桌面应用和仍在运行的 CLI 会话，再执行：

```powershell
pwsh -File .\scripts\Export-CodexLocalSessions.ps1 -Destination D:\Transfer
```

输出包含 ZIP、SHA-256 校验文件和 JSON 回执。额外范围由参数选择：

| 参数 | 包含内容 |
| --- | --- |
| `-IncludeManagedProjects` | `.chatgpt-projects` 下的托管项目 |
| `-IncludeCustomization` | skills、memories、plugins、automations 和本地偏好 |
| `-AllowRunning` | 允许运行中导出，但不能保证得到一致快照 |

托管项目和自定义配置可能包含密钥；聊天和附件本身也可能有私人信息。请通过私人渠道传输备份。

### 恢复

在目标电脑安装 Codex、登录一次，然后完全关闭。把 ZIP 和对应的 `.sha256` 文件放在同一目录，先预览：

```powershell
pwsh -File .\scripts\Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-YYYYMMDD-HHMMSS.zip
```

将示例文件名替换为实际文件名。确认预览后再执行：

```powershell
pwsh -File .\scripts\Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-YYYYMMDD-HHMMSS.zip -Apply
```

如果目标电脑已有本地聊天，先备份目标电脑。覆盖还需要 `-ReplaceExistingHistory`；脚本不会自动合并两份历史数据库，并会在替换前创建回滚 ZIP。

### 迁移范围

这是本地文件迁移，不是官方云同步功能。`CODEX_HOME` 以外的工作仓库需要另行复制，旧聊天中的绝对路径也不会自动修复。

恢复后在 Codex 中检查几条聊天、一个附件和一次续聊。确认可用前，保留源电脑的记录和备份。详细范围见 [migration-model.md](references/migration-model.md)。

## English

PowerShell scripts for backing up and moving local Codex chats between Windows computers. The repository can also be installed as a Codex skill.

The default export includes transcripts, indexes, attachments and history databases. It excludes login credentials, device identity, caches and active locks. Restore previews changes by default and creates a rollback archive before replacing existing history.

### Install

Use Windows with PowerShell 7 (`pwsh`), `robocopy.exe` and `tar.exe`.

```powershell
git clone https://github.com/ARETE-zzwl/codex-local-session-migration.git "$HOME\.codex\skills\codex-local-session-migration"
```

For a custom `CODEX_HOME`, install under its `skills` directory. Restart Codex, then ask:

```text
Use $codex-local-session-migration to export my local Codex chats to D:\Transfer.
```

You can also run the scripts directly from the repository root.

### Export and restore

Close Codex and any CLI sessions before exporting:

```powershell
pwsh -File .\scripts\Export-CodexLocalSessions.ps1 -Destination D:\Transfer
```

This creates a ZIP, a SHA-256 sidecar and a JSON receipt. `-IncludeManagedProjects` adds `.chatgpt-projects`; `-IncludeCustomization` adds skills, memories, plugins, automations and preferences. Both can include private configuration. `-AllowRunning` permits a best-effort snapshot, without guaranteeing consistency.

On the destination, install Codex, sign in once and close it. Keep the ZIP and its `.sha256` sidecar together. Substitute the actual archive name below:

```powershell
pwsh -File .\scripts\Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-YYYYMMDD-HHMMSS.zip
pwsh -File .\scripts\Restore-CodexLocalSessions.ps1 -Bundle D:\Transfer\codex-local-sessions-YYYYMMDD-HHMMSS.zip -Apply
```

The first command previews the restore. Back up any existing destination chats before applying it. Replacing them also requires `-ReplaceExistingHistory` and creates a rollback ZIP; the script does not merge populated history databases.

### Scope and checks

This migrates local state, not official cloud sync. Working repositories outside `CODEX_HOME` must be copied separately, and absolute paths in old chats are not repaired.

Archives can contain private chats and attachments even when credentials are excluded. Transfer them privately. Check several chats, an attachment and a continued chat in Codex before retiring the source copy. See [migration-model.md](references/migration-model.md) for details.

## License

[MIT](LICENSE).
