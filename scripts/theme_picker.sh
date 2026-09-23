#!/bin/sh
# theme_picker.sh — fzf-backed color theme picker for wezterm-config.
#
# Subcommands:
#   list   <master_list_path> <favorites_path>
#       Reads "<name>\t<ansi preview>" lines from master_list_path (written
#       by modules/colorscheme.lua, since only Lua can read WezTerm's
#       builtin color scheme data — <ansi preview> is a swatch of the
#       theme's palette plus its name rendered in the theme's own fg/bg)
#       and prints tab-delimited "<marker>\t<name>\t<preview>\t<sortkey>"
#       lines, favorites (from favorites_path, one name per line) marked
#       with a star and sorted first.
#
#   toggle <favorites_path> <theme_name>
#       Adds theme_name to favorites_path if absent, removes it if present.
#
#   run    <master_list_path> <favorites_path> <query> <prev_theme>
#       Drives the whole list -> preview -> keep/back interaction as ONE
#       loop in this single process/pane (deliberately NOT split across
#       multiple wezterm-spawned panes — an earlier version re-opened a new
#       pane for "Back to list" and round-tripped state through WezTerm;
#       that pane's exit_behavior = CloseOnCleanExit closed it right after
#       emitting its result, racing the "show the keep/back prompt" step
#       against the pane already being gone, which is what made selecting
#       a theme silently do nothing). Keeping it all in one script means
#       "Back to list" is just `continue`ing this loop with the query/prev
#       variables already in hand — no serialization, no race.
#
#       Reports back to wezterm via OSC 1337 SetUserVar escapes:
#         wezterm_theme_preview = <base64 theme name>   -- sent on every
#           Enter in the list, before the keep/back prompt, so WezTerm can
#           apply it live; safe to send repeatedly, this pane stays open.
#         wezterm_theme_result  = "CANCEL" | <base64 theme name>  -- sent
#           once, right before exiting, once the user has actually
#           confirmed (Keep) or given up (Esc from the list, or Esc from
#           every keep/back prompt in a row with no Keep).
#
# Called by modules/colorscheme.lua via act.SpawnCommandInNewTab, on macOS
# and Linux (utils.is_windows == false). Must stay executable (chmod +x)
# and dependency-free besides fzf/grep/sort/base64, which are standard on
# macOS/Linux. Windows uses the PowerShell counterpart, theme_picker.ps1,
# with the same three-subcommand contract.

set -eu

self="$0"

emit_uservar() {
  printf '\033]1337;SetUserVar=%s=%s\007' "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')"
}

cmd_list() {
  # A `while read` loop forking `grep` once per theme (1000+ builtin
  # schemes) took ~4s per call here, and cmd_run calls this twice per
  # loop iteration (pos lookup + the actual list) - single-pass awk does
  # the same favorite lookup via an in-memory associative array instead,
  # cutting that to milliseconds.
  #
  # NOTE: favfile is compared by FILENAME, not the classic `FNR==NR`
  # idiom - FNR==NR is only reliable when file 1 (favorites) is
  # non-empty; when it's empty (the common case, e.g. no favorites yet:
  # freshly created via `: >"$favorites"` below), FNR and NR never
  # diverge, so FNR==NR stays true for every line of the SECOND file too
  # and silently swallows the entire theme list into the favorites
  # branch, producing no output at all.
  master="$1"
  favorites="$2"
  [ -f "$favorites" ] || : >"$favorites"
  awk -F'\t' -v favfile="$favorites" -v tab="$(printf '\t')" -v star="$(printf '\xe2\x98\x85')" '
    FILENAME == favfile { fav[$0] = 1; next }
    $1 == "" { next }
    {
      if ($1 in fav) { m = star; sk = 1 } else { m = " "; sk = 0 }
      printf "%s%s%s%s%s%s%d\n", m, tab, $1, tab, $2, tab, sk
    }
  ' "$favorites" "$master" | sort -t "$(printf '\t')" -k4,4r -k2,2
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

  while :; do
    pos=1
    if [ -n "$prev" ]; then
      tab="$(printf '\t')"
      found="$(cmd_list "$master" "$favorites" | grep -nF -- "${tab}${prev}${tab}" | head -n1 | cut -d: -f1 || true)"
      [ -n "$found" ] && pos="$found"
    fi

    tmp_out="$(mktemp)"
    if cmd_list "$master" "$favorites" | fzf \
      --ansi \
      --delimiter="$(printf '\t')" --with-nth=1,3 --nth=2 \
      --print-query \
      --prompt='Theme> ' \
      --header='[Enter] preview  [Shift+F] favorite  [Esc] cancel' \
      --query="$query" \
      --bind "load:pos($pos)" \
      --bind "F:execute-silent($self toggle \"$favorites\" {2})+reload($self list \"$master\" \"$favorites\")" \
      >"$tmp_out"; then
      query="$(sed -n '1p' "$tmp_out")"
      selected="$(sed -n '2p' "$tmp_out" | cut -f2)"
      rm -f "$tmp_out"
    else
      rm -f "$tmp_out"
      emit_uservar wezterm_theme_result "CANCEL"
      return
    fi

    if [ -z "$selected" ]; then
      emit_uservar wezterm_theme_result "CANCEL"
      return
    fi

    # Live-preview immediately. This pane stays open for the keep/back
    # prompt below (and possibly more loop iterations after "Back to
    # list"), so there's no race with it closing.
    emit_uservar wezterm_theme_preview "$selected"

    confirm="$(printf 'Keep this theme\nBack to list\n' | fzf \
      --prompt="\"$selected\" > " \
      --header='[Enter] confirm  [Esc] back to list' \
      --info=hidden)" || confirm=""

    if [ -z "$confirm" ] || [ "$confirm" = "Back to list" ]; then
      prev="$selected"
      continue
    fi

    emit_uservar wezterm_theme_result "$selected"
    return
  done
}

action="${1:-}"
[ $# -ge 1 ] && shift || true

case "$action" in
  list) cmd_list "$@" ;;
  toggle) cmd_toggle "$@" ;;
  run)
    cmd_run "$@"
    # WezTerm closes the pane as soon as this exits, and a user var set by
    # a pane that's already gone never reaches the Lua handler (the pick
    # was silently not saved). Wait instead: the handler in
    # modules/colorscheme.lua closes this pane once it has processed
    # wezterm_theme_result. The timeout is only a fallback.
    sleep 5
    ;;
  *)
    echo "usage: theme_picker.sh {list|toggle|run} ..." >&2
    exit 1
    ;;
esac
