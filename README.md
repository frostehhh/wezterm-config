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

### How WezTerm finds `fzf`

Every time you open the picker, `resolve_fzf()` in `modules/colorscheme.lua`
looks for `fzf` in this order and stops at the first hit:

1. **Run `fzf --version` directly**, using whatever `PATH` the **WezTerm
   GUI process itself** was started with — not your shell's `PATH`. This is
   the detail that trips people up: when WezTerm is launched from Dock,
   Spotlight, or a double-click, it does *not* go through your shell's
   startup files (`.zshrc`, `.bash_profile`, …), so anything that only
   modifies `PATH` there — including version-manager shims (mise, asdf) —
   is invisible to it, even though `fzf` works perfectly from a terminal.
   Only WezTerm launched *from* an already-configured terminal inherits
   that `PATH`.
2. **If that fails, check a fixed list of common install directories
   directly by absolute path** (bypassing `PATH` entirely): on
   macOS/Linux, `/opt/homebrew/bin`, `/usr/local/bin`,
   `~/.local/share/mise/shims`, then
   `~/.local/share/mise/installs/fzf/latest`, in that order (see
   `candidate_fzf_dirs()`); on Windows, mise's shims, Scoop's shims, then
   Chocolatey's bin dir. Each candidate has to both exist *and* actually
   run (`<dir>/fzf --version` succeeds) to count.
3. **If a candidate matches**, that one directory is prepended to the
   `PATH` used *only* for the spawned picker pane (`build_picker_path()`,
   via `set_environment_variables` on the spawn action) — this never
   touches WezTerm's own process `PATH`, just the one script invocation.
4. **If nothing matches**, it logs a warning and falls back to the
   built-in picker (see "Checking whether it's actually being used" below).

This check isn't cached — it re-runs every time you open the picker — so
installing `fzf` (or fixing its location) takes effect immediately, no
WezTerm restart needed.

### Installing it

Any of these put `fzf` somewhere step 1 or step 2 above will find it:

```sh
brew install fzf                 # Homebrew -> /opt/homebrew/bin, already covered
mise use -g fzf                  # mise -> only found via step 2's shims/installs fallback
sudo apt install fzf              # Debian/Ubuntu -> /usr/bin, found via step 1's PATH check
sudo pacman -S fzf                # Arch -> /usr/bin, found via step 1's PATH check
```

If you use a version manager and the picker still isn't finding it (e.g.
you're on a distro/path layout `candidate_fzf_dirs()` doesn't know about),
the simplest fix is a plain Homebrew/apt/pacman install instead, or
symlinking your version manager's `fzf` binary into `/opt/homebrew/bin`
(no sudo needed on macOS, and it's one of step 2's known candidates):

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
(⭐) first, then alphabetically. Each row shows a swatch of that theme's
actual palette plus its own name rendered as a little chip in the theme's
own foreground/background (both in real color, not just text):

```
Theme> rose‸
  [Enter] preview  [Shift+F] favorite  [Esc] cancel
  4/247
★ ██████  rose-pine
★ ██████  rose-pine-moon
  ██████  rose-pine-dawn
> ██████  rosebox
```

Pressing `Enter` on a highlighted theme applies it live, right there, and
drops you into a small "Keep this theme" / "Back to list" prompt — still
inside the same pane (list, preview and confirm are one continuous fzf
session, not separate popups, so there's no flicker or tab-switching
between steps). Choosing "Back to list" returns to the list with `rose`
still typed and the cursor back on `rosebox` — exactly where you left off,
since it's the same running process, not reconstructed from scratch.
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
