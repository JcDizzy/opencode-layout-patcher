# OpenCode Layout Patcher

A small Windows patcher for [OpenCode Desktop](https://github.com/anomalyco/opencode) that rearranges the session workspace into a more conventional IDE layout:

```text
File Tree | Editor / Review | Agent / Chat
```

instead of the stock arrangement where the Agent/Chat panel is on the left and the file tree sits on the right side of the editor.

The patch is implemented as a CSS override injected into OpenCode Desktop's Electron `app.asar`. It does **not** rebuild OpenCode from source.

## What it changes

The patch performs two layout swaps:

```text
Stock
Agent / Chat | Editor / Review | File Tree

Patched
File Tree | Editor / Review | Agent / Chat
```

It also adjusts the relevant resize handles and divider positions so the panels continue to resize naturally after the swap.

## Quick start

### Apply

1. Download or clone this repository.
2. Close OpenCode Desktop, or let the script close it when prompted.
3. Double-click:

```text
patch-layout.cmd
```

### Restore

To return to the stock OpenCode layout, double-click:

```text
restore-layout.cmd
```

The restore script removes only the CSS block injected by this project from the **current** `app.asar`. It does not blindly replace the current OpenCode package with an old backup.

## Requirements

- Windows PowerShell
- Either:
  - Node.js/npm with `npx`, or
  - Bun with `bunx`

The scripts prefer `@electron/asar@3.2.17` for broad Node.js compatibility and fall back to the current `@electron/asar` package.

## Automatic OpenCode detection

The patcher tries several locations automatically, including the standard per-user install directory, uninstall-registry entries, and `OpenCode.exe` on `PATH`.

If detection fails, it asks for one of:

- the OpenCode installation directory;
- `OpenCode.exe`; or
- `resources\app.asar`.

You can also provide the path directly:

```bat
patch-layout.cmd "C:\Users\you\AppData\Local\Programs\@opencode-aidesktop"
restore-layout.cmd "C:\Users\you\AppData\Local\Programs\@opencode-aidesktop"
```

## Backup and update behavior

On the first patch of an installation, the patcher creates:

```text
resources\app.asar.layout-backup.bak
```

This is an emergency backup only.

Normal restore is surgical: it extracts the current `app.asar`, removes the injected style block, repacks it, and leaves the rest of the current OpenCode version intact.

When OpenCode updates, its installer will normally replace `app.asar` and remove the patch. Run `patch-layout.cmd` again after the update.

## Safety checks

The scripts:

- require OpenCode to be stopped before replacing `app.asar`;
- preserve `app.asar.unpacked` entries;
- refuse to replace the package if the repacked ASAR looks unexpectedly small;
- update an existing injected patch instead of stacking duplicate CSS blocks;
- judge native `npx`/`bunx` commands by exit code rather than treating harmless stderr warnings as fatal.

## Troubleshooting

### `NODE_TLS_REJECT_UNAUTHORIZED=0` warning

If Node prints:

```text
Warning: Setting the NODE_TLS_REJECT_UNAUTHORIZED environment variable to '0' ...
```

the patcher will no longer mistake that warning for a failed ASAR command.

However, the environment variable itself disables TLS certificate verification for Node.js. If you did not intentionally configure it, remove it from your environment.

### Patch stops working after an OpenCode release

This project relies on a few OpenCode DOM IDs/classes, such as `#review-panel` and `#file-tree-panel`. If OpenCode changes that structure, the ASAR patch/restore mechanism may still work while the CSS selectors need an update.

Please open an issue with:

- your OpenCode version;
- what the layout looks like;
- whether `patch-layout.cmd` reports success.

Do not include screenshots or logs containing private source code unless you have redacted them.

## 中文说明

这个工具用于把 OpenCode Desktop 的工作区调整成更传统的 IDE 布局：

```text
文件树 | 编辑 / Review | Agent 对话
```

双击 `patch-layout.cmd` 应用，双击 `restore-layout.cmd` 恢复官方布局。

脚本不会编译 OpenCode，而是修改 Electron 的 `app.asar`，向 renderer 注入一小段 CSS。OpenCode 更新后通常会覆盖补丁，再运行一次 Patch 即可。

## Compatibility

Initially tested against OpenCode Desktop **v1.18.14** on Windows.

Because this project patches implementation details of OpenCode's renderer, compatibility with future releases is best-effort.

## Disclaimer

This is an unofficial community utility and is not affiliated with or endorsed by the OpenCode project.

Modifying application package contents may invalidate vendor signatures or integrity assumptions. Use at your own risk and keep backups of important work.

## License

MIT
