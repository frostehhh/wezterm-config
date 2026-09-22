# wezterm-config
Common config for WezTerm

## Color theme picker

Command palette (`Ctrl+Shift+P`) → **"Set color theme"** opens a live
preview picker for every builtin WezTerm color scheme. Picking one applies
it immediately as a preview, then asks you to **Keep this theme** or **Back
to list**.

There are two implementations behind that one command, chosen automatically:

| | Built-in (always available) | fzf-backed (used when `fzf` is found) |
|---|---|---|
| Fuzzy filter | ✅ | ✅ |
| Restores scroll position + typed filter text on "Back to list" | ❌ (always reopens at the top, filter cleared) | ✅ |
| Press `Shift+F` on a highlighted theme to favorite it (⭐, sorts to top) | ❌ | ✅ |

### What `fzf` is

[`fzf`](https://github.com/junegunn/fzf) is a general-purpose command-line
fuzzy finder. It's the only reason the richer picker is possible at all:
WezTerm's own native picker widget (`InputSelector`) never exposes the
scroll position or typed filter text back to the config, and has no way to
bind an extra key like Shift+F — so those two features are implemented by
shelling out to `fzf` in a spawned pane (`scripts/theme_picker.sh`, or
`scripts/theme_picker.ps1` on Windows) instead. It's entirely optional:
nothing else in this config depends on it.

### Installing it

Any of these put `fzf` somewhere this config's picker will find it:

```sh
brew install fzf                 # Homebrew
mise use -g fzf                  # mise (see note below)
sudo apt install fzf              # Debian/Ubuntu
sudo pacman -S fzf                # Arch
```

**Note for version managers (mise, asdf, etc.):** these only add `fzf` to
`PATH` inside shells that source their activation hook. A GUI-launched
WezTerm (Dock, Spotlight, double-click) doesn't run through your shell rc
files, so it won't see a version-manager shim even if your terminal does.
The picker also checks a few common install locations directly
(`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/share/mise/shims`,
`~/.local/share/mise/installs/fzf/latest`) as a fallback — see
`resolve_fzf()` in `modules/colorscheme.lua` — but the simplest fix if
`fzf` still isn't found is a plain Homebrew/apt/pacman install, or
symlinking your version manager's `fzf` binary into `/opt/homebrew/bin`
(no sudo needed, already on `PATH` everywhere):

```sh
ln -sf ~/.local/share/mise/installs/fzf/latest/fzf /opt/homebrew/bin/fzf
```

### Checking whether it's actually being used

- Open the picker (`Ctrl+Shift+P` → "Set color theme"). If it looks like
  the mockup below (its own pane, a `Theme>` prompt, a `[Shift+F] favorite`
  hint in the header), fzf is active. If instead you get WezTerm's plain
  built-in list with no such header, it fell back.
- From a shell: `which fzf` (or, inside WezTerm, just run `fzf` and see if
  it launches).
- Check the log for the fallback warning:
  ```sh
  tail -5 ~/.local/share/wezterm/wezterm-gui-log-*.txt
  # look for: "theme picker: fzf not found (checked PATH and common
  # install locations), falling back to built-in picker"
  ```
  (or open WezTerm's debug overlay, default `Ctrl+Shift+L`).

### What it looks like

The fzf-backed picker opens in its own pane, themes sorted with favorites
(⭐) first, then alphabetically, each row showing a small swatch of that
theme's actual palette next to its name (rendered in real color, not just
text):

```
Theme> rose‸
  [Enter] preview  [Shift+F] favorite  [Esc] cancel
  4/247
★ ██████ rose-pine
★ ██████ rose-pine-moon
  ██████ rose-pine-dawn
> ██████ rosebox
```

Pressing `Enter` on a highlighted theme applies it live and drops you into
the Keep/Back prompt; choosing "Back to list" reopens fzf with `rose`
still typed and the cursor back on `rosebox` — exactly where you left off.
Pressing `Shift+F` on any row toggles its ⭐ immediately, without leaving
the list — plain `f` still just filters, so it doesn't conflict with typing
theme names that contain an "f" (e.g. searching "nightfox").

### Windows

The picker spawns `scripts/theme_picker.ps1` (via `powershell.exe`)
instead of the POSIX `scripts/theme_picker.sh` used on macOS/Linux — no
separate setup beyond having `fzf.exe` on `PATH`. This path is implemented
against fzf's documented Windows behavior (`--with-shell` pins fzf's
bind/reload commands to PowerShell instead of its `cmd.exe` default) but
hasn't been exercised on an actual Windows machine — if the `Shift+F`
favorite key or "Back to list" restore misbehaves there, it's the first
place to look.
