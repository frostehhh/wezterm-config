# wezterm-config

Personal [WezTerm](https://wezterm.org/) configuration. This repo mirrors
`~/.config/wezterm` — changes made here are synced into that path.

## Features

- Color theme picker with live preview, fuzzy search, and favorites
- Automatic dark/light mode that follows the OS appearance
- Favorite working directories, jumpable from the command palette
- Pane, tab, and workspace renaming
- Custom tab titles and a status bar showing pane title + workspace
- Cross-platform tweaks for macOS and Windows (opacity/blur, fonts, default shell)

## Requirements

- [WezTerm](https://wezterm.org/)
- A [Nerd Font](https://www.nerdfonts.com/) — this config uses Hack Nerd Font,
  falling back to JetBrains Mono
- [`fzf`](https://github.com/junegunn/fzf) — optional, enables the enhanced
  theme picker (favorites, scroll/filter restore); everything else works
  without it

## Setup

Point WezTerm's config directory at this repo, either by cloning it directly
into `~/.config/wezterm`, or by symlinking:

```sh
ln -sfn "$(pwd)/wezterm-config" ~/.config/wezterm
```

There's no build step — WezTerm reloads these files automatically on save,
or you can trigger a reload manually from the command palette.

## Commands & keybindings

| Command name | Shortcut | Description |
|---|---|---|
| Command palette | `Ctrl+Shift+P` | Opens WezTerm's command palette — entry point for every palette-only command below |
| Rename current pane | `Ctrl+Shift+E` (also in palette) | Prompts for a new pane title, pre-filled with the current one |
| Rename current tab | `Ctrl+Shift+R` (also in palette) | Prompts for a new tab title, pre-filled with the current one |
| Rename the current workspace | Command palette only | Prompts for a new name and renames the active workspace |
| Add current directory to favorites | Command palette only | Saves the active pane's working directory to your favorites |
| Go to favorite directory | Command palette only | Picks a saved favorite and `cd`s the active pane into it |
| Remove a favorite directory | Command palette only | Picks a saved favorite and removes it from your list |
| Set color theme | Command palette only | Opens the theme picker (fzf-backed if available, otherwise WezTerm's built-in picker) |
| Toggle color picker (fzf / Default) | Command palette only | Switches the theme picker backend, saved for next time |
| Toggle dark/light theme | Command palette only | Flips between your saved dark and light scheme, disabling auto mode |
| Toggle automatic dark/light mode | Command palette only | Keeps the color scheme in sync with the OS appearance as it changes |

While the theme picker itself is open, a few extra keys apply:

| Key | Action |
|---|---|
| `Enter` | Preview the highlighted theme, then confirm to keep it |
| `Shift+F` | Toggle the highlighted theme as a favorite (⭐, fzf picker only) |
| `Esc` | Cancel and restore the previous theme |

## Color theme picker

By default, the fzf-backed picker is used whenever `fzf` is found on the
system (checked at launch time, cached for the session); otherwise it falls
back to WezTerm's built-in picker automatically.

| | Built-in (always available) | fzf-backed (used when `fzf` is found) |
|---|---|---|
| Fuzzy filter | ✅ | ✅ |
| Restores scroll position + typed filter on "Back to list" | ❌ | ✅ |
| Favorite a theme with `Shift+F` | ❌ | ✅ |

WezTerm looks for `fzf` using the GUI process's own `PATH`, then a short list
of common install locations (Homebrew, mise shims, etc.) as a fallback — so
version-manager shims that only live in your shell's `PATH` may not be
picked up automatically. Installing it normally is usually enough:

```sh
brew install fzf     # or: mise use -g fzf
```

If it still isn't detected, symlinking the binary into `/opt/homebrew/bin`
(or another common location) resolves it.

## Platform notes

- **macOS** — 80% window opacity with background blur, larger default font
  sizes.
- **Windows** — uses `pwsh.exe` as the default shell, 90% window opacity, and
  spawns `scripts/theme_picker.ps1` (via `powershell.exe`) instead of the
  POSIX `theme_picker.sh` for the fzf picker. This path is implemented
  against fzf's documented Windows behavior but hasn't been verified on an
  actual Windows machine — if `Shift+F` or the "Back to list" restore
  misbehave there, start there.
