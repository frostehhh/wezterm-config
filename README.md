# wezterm-config
Common config for WezTerm

## Prerequisites

The color theme picker (command palette → "Set color theme") prefers
[`fzf`](https://github.com/junegunn/fzf) for a richer picker: your typed
filter text and scroll position are restored when you back out of the
theme-preview step, and you can press `f` on a highlighted theme to
favorite/unfavorite it without leaving the list. `fzf` must be resolvable on
`PATH` for the process that runs WezTerm (a GUI app launch may not see PATH
changes made only in shell rc files — a plain `mise activate`/shell alias
isn't enough on its own; the `fzf` shim/binary directory needs to be on the
GUI process's PATH, e.g. via `/etc/paths.d`, `launchctl setenv`, or
installing `fzf` somewhere already on that PATH such as Homebrew).

If `fzf` isn't found, the picker automatically falls back to WezTerm's
built-in list (no scroll/filter restore, no `f` favorite key).

`brew install fzf`, or install via [mise](https://mise.jdx.dev/): `mise use -g fzf`.

**Windows**: the picker spawns `scripts/theme_picker.ps1` (via
`powershell.exe`) instead of the POSIX `scripts/theme_picker.sh` used on
macOS/Linux — no separate setup beyond having `fzf.exe` on `PATH`. This path
is implemented against fzf's documented Windows behavior (`--with-shell`
pins fzf's bind/reload commands to PowerShell instead of its `cmd.exe`
default) but hasn't been exercised on an actual Windows machine — if the
`f` favorite key or "Back to list" restore misbehaves there, it's the first
place to look.
