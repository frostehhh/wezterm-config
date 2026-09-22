#!/bin/sh
# theme_picker.sh — fzf-backed color theme picker for wezterm-config.
#
# Subcommands:
#   list   <master_list_path> <favorites_path>
#       Prints tab-delimited "<marker>\t<name>\t<sortkey>" lines for every
#       theme in master_list_path, favorites (from favorites_path, one name
#       per line) marked with a star and sorted first.
#
#   toggle <favorites_path> <theme_name>
#       Adds theme_name to favorites_path if absent, removes it if present.
#
#   run    <master_list_path> <favorites_path> <query> <prev_theme>
#       Runs fzf over `list`'s output, seeded with the given query text and
#       cursor position (derived from prev_theme), with Shift+F (bind key
#       "F") bound to `toggle` + a live `reload` — plain `f` stays free for
#       filtering. Reports the result back to wezterm via OSC 1337
#       SetUserVar escapes:
#         wezterm_theme_result = "CANCEL" | <base64 theme name>
#         wezterm_theme_query  = <base64 typed query text>
#
# Called by modules/colorscheme.lua via act.SpawnCommandInNewTab, on macOS
# and Linux (utils.is_windows == false). Must stay executable (chmod +x)
# and dependency-free besides fzf/grep/sort/base64, which are standard on
# macOS/Linux. Windows uses the PowerShell counterpart, theme_picker.ps1,
# with the same three-subcommand contract.

set -eu

self="$0"

cmd_list() {
  master="$1"
  favorites="$2"
  [ -f "$favorites" ] || : >"$favorites"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if grep -qxF "$name" "$favorites" 2>/dev/null; then
      printf '\xe2\x98\x85\t%s\t1\n' "$name"
    else
      printf ' \t%s\t0\n' "$name"
    fi
  done <"$master" | sort -t "$(printf '\t')" -k3,3r -k2,2
}

cmd_toggle() {
  favorites="$1"
  name="$2"
  [ -f "$favorites" ] || : >"$favorites"
  if grep -qxF "$name" "$favorites" 2>/dev/null; then
    grep -vxF "$name" "$favorites" >"$favorites.tmp" || true
    mv "$favorites.tmp" "$favorites"
  else
    printf '%s\n' "$name" >>"$favorites"
  fi
}

cmd_run() {
  master="$1"
  favorites="$2"
  query="$3"
  prev="$4"

  pos=1
  if [ -n "$prev" ]; then
    tab="$(printf '\t')"
    found="$(cmd_list "$master" "$favorites" | grep -nF -- "${tab}${prev}${tab}" | head -n1 | cut -d: -f1 || true)"
    [ -n "$found" ] && pos="$found"
  fi

  tmp_out="$(mktemp)"
  trap 'rm -f "$tmp_out"' EXIT

  if cmd_list "$master" "$favorites" | fzf \
    --delimiter="$(printf '\t')" --with-nth=1,2 --nth=2 \
    --print-query \
    --prompt='Theme> ' \
    --header='[Enter] preview  [Shift+F] favorite  [Esc] cancel' \
    --query="$query" \
    --bind "load:pos($pos)" \
    --bind "F:execute-silent($self toggle \"$favorites\" {2})+reload($self list \"$master\" \"$favorites\")" \
    >"$tmp_out"; then
    typed_query="$(sed -n '1p' "$tmp_out")"
    selected="$(sed -n '2p' "$tmp_out" | cut -f2)"
    if [ -z "$selected" ]; then
      printf '\033]1337;SetUserVar=wezterm_theme_result=%s\007' "$(printf '%s' "CANCEL" | base64 | tr -d '\n')"
    else
      printf '\033]1337;SetUserVar=wezterm_theme_result=%s\007' "$(printf '%s' "$selected" | base64 | tr -d '\n')"
      printf '\033]1337;SetUserVar=wezterm_theme_query=%s\007' "$(printf '%s' "$typed_query" | base64 | tr -d '\n')"
    fi
  else
    printf '\033]1337;SetUserVar=wezterm_theme_result=%s\007' "$(printf '%s' "CANCEL" | base64 | tr -d '\n')"
  fi
}

action="${1:-}"
[ $# -ge 1 ] && shift || true

case "$action" in
  list) cmd_list "$@" ;;
  toggle) cmd_toggle "$@" ;;
  run) cmd_run "$@" ;;
  *)
    echo "usage: theme_picker.sh {list|toggle|run} ..." >&2
    exit 1
    ;;
esac
