local wezterm = require("wezterm")
local act = wezterm.action
local utils = require("modules.utils")
local theme_favorites = require("modules.theme_favorites")

local M = {}

local DEFAULTS = { dark = "rose-pine-moon", light = "rose-pine-dawn", mode = "dark", auto = false }
local scheme_path = wezterm.home_dir .. "/.config/wezterm/colorscheme.json"
local master_list_path = wezterm.home_dir .. "/.config/wezterm/.theme_master_list.txt"
local theme_picker_script = wezterm.config_dir
  .. (utils.is_windows and "/scripts/theme_picker.ps1" or "/scripts/theme_picker.sh")

local function load_schemes()
  local f = io.open(scheme_path, "r")
  if not f then return DEFAULTS end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(wezterm.json_parse, content)
  if not (ok and type(data) == "table") then return DEFAULTS end
  return {
    dark  = type(data.dark)  == "string"  and data.dark  or DEFAULTS.dark,
    light = type(data.light) == "string"  and data.light or DEFAULTS.light,
    mode  = type(data.mode)  == "string"  and data.mode  or DEFAULTS.mode,
    auto  = type(data.auto)  == "boolean" and data.auto  or DEFAULTS.auto,
  }
end

local function save_schemes(schemes)
  local f = io.open(scheme_path, "w")
  if f then
    f:write(wezterm.json_encode(schemes))
    f:close()
  end
end

local function system_is_dark()
  if not wezterm.gui then return true end
  return wezterm.gui.get_appearance():find("Dark") ~= nil
end

function M.get_current()
  local s = load_schemes()
  if s.auto then
    return system_is_dark() and s.dark or s.light
  end
  return s[s.mode] or s.dark
end

local function sorted_scheme_names()
  local scheme_data = wezterm.get_builtin_color_schemes()
  local names = {}
  for name in pairs(scheme_data) do table.insert(names, name) end
  table.sort(names)
  return names, scheme_data
end

-- The ansi[2..7] foreground colors used for the small per-theme swatch,
-- shared between the fallback InputSelector list (via wezterm.format) and
-- the fzf list (via raw ANSI escapes, see ansi_preview() below).
local function swatch_colors(s)
  local colors = {}
  if s and s.ansi then
    for i = 2, 7 do
      if s.ansi[i] then table.insert(colors, s.ansi[i]) end
    end
  end
  return colors
end

local function build_scheme_choices()
  local names, scheme_data = sorted_scheme_names()
  local choices = {}
  for _, name in ipairs(names) do
    local s = scheme_data[name]
    local colors = swatch_colors(s)
    local label
    if #colors > 0 then
      local parts = {}
      for _, c in ipairs(colors) do
        table.insert(parts, { Foreground = { Color = c } })
        table.insert(parts, { Text = "█" })
      end
      table.insert(parts, { Foreground = { Color = s.foreground } })
      table.insert(parts, { Background = { Color = s.background } })
      local star = theme_favorites.is_favorite(name) and "★ " or "  "
      table.insert(parts, { Text = star .. name })
      label = wezterm.format(parts)
    else
      label = name
    end
    table.insert(choices, { id = name, label = label })
  end
  return choices
end

local function hex_to_rgb(hex)
  if type(hex) ~= "string" then return nil end
  hex = hex:gsub("#", "")
  if #hex < 6 then return nil end
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  return r, g, b
end

-- Same swatch as build_scheme_choices, but as raw ANSI truecolor escapes,
-- plus the theme's name rendered as a little chip in the theme's own
-- fg/bg (matching build_scheme_choices' color-picker text-visibility
-- fix): this goes into the plain-text master list
-- scripts/theme_picker.{sh,ps1} read and fzf renders (with --ansi) itself,
-- since wezterm.format isn't available outside Lua.
local function ansi_preview(name, s)
  local colors = swatch_colors(s)
  local parts = {}
  for _, c in ipairs(colors) do
    local r, g, b = hex_to_rgb(c)
    if r then table.insert(parts, string.format("\27[38;2;%d;%d;%dm█", r, g, b)) end
  end
  if #parts > 0 then table.insert(parts, "\27[0m") end

  local fr, fg, fb = s and s.foreground and hex_to_rgb(s.foreground)
  local br, bg, bb = s and s.background and hex_to_rgb(s.background)
  if fr and br then
    table.insert(
      parts,
      string.format(" \27[38;2;%d;%d;%dm\27[48;2;%d;%d;%dm %s \27[0m", fr, fg, fb, br, bg, bb, name)
    )
  else
    table.insert(parts, " " .. name)
  end
  return table.concat(parts)
end

-- GUI-launched apps (Dock/Spotlight/double-click) do NOT get the PATH a
-- login shell builds from /etc/paths(.d) or a shell rc file's tool-version-
-- manager hook (mise, etc) — only apps launched from an already-configured
-- terminal do. So `fzf` can be missing from wezterm-gui's own inherited
-- PATH even when it's perfectly installed and used every day from a
-- terminal. To not depend on how WezTerm itself was launched, fall back to
-- checking a handful of common install locations directly by absolute
-- path before giving up.
local function candidate_fzf_dirs()
  if utils.is_windows then
    return {
      wezterm.home_dir .. "\\.local\\share\\mise\\shims",
      wezterm.home_dir .. "\\scoop\\shims",
      "C:\\ProgramData\\chocolatey\\bin",
    }
  end
  return {
    "/opt/homebrew/bin",
    "/usr/local/bin",
    wezterm.home_dir .. "/.local/share/mise/shims",
    wezterm.home_dir .. "/.local/share/mise/installs/fzf/latest",
  }
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Returns (found, dir): dir is nil when `fzf` already resolves via
-- wezterm-gui's own inherited PATH (no override needed to spawn it), or the
-- absolute directory it was found in via the candidate-path fallback.
local function resolve_fzf()
  local pok, success = pcall(wezterm.run_child_process, { "fzf", "--version" })
  if pok and success then return true, nil end

  local bin_name = utils.is_windows and "fzf.exe" or "fzf"
  local sep = utils.is_windows and "\\" or "/"
  for _, dir in ipairs(candidate_fzf_dirs()) do
    if file_exists(dir .. sep .. bin_name) then
      local pok2, success2 = pcall(wezterm.run_child_process, { dir .. sep .. bin_name, "--version" })
      if pok2 and success2 then return true, dir end
    end
  end
  return false, nil
end

-- Builds a PATH for the spawned picker script that's guaranteed to include
-- both `fzf` (via fzf_dir, if it wasn't already on the inherited PATH) and
-- the standard system utilities the script itself shells out to (grep,
-- sort, mktemp, base64, ...), regardless of what wezterm-gui's own PATH
-- happened to be at launch.
local function build_picker_path(fzf_dir)
  local sep = utils.is_windows and ";" or ":"
  local dirs = {}
  if fzf_dir then table.insert(dirs, fzf_dir) end
  if not utils.is_windows then
    for _, d in ipairs({ "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin" }) do
      table.insert(dirs, d)
    end
  end
  local base = os.getenv("PATH")
  if base and base ~= "" then table.insert(dirs, base) end
  return table.concat(dirs, sep)
end

-- Fallback picker (native act.InputSelector): used when `fzf` isn't on
-- PATH. Does not support restoring scroll/filter state or an in-list
-- Shift+F favorite key, since InputSelector exposes neither to Lua.
local open_scheme_picker_fallback
local open_scheme_picker_fzf

open_scheme_picker_fallback = function(window, pane, mode, previous_scheme)
  window:perform_action(
    act.InputSelector({
      title = "Color Theme  [Enter = preview]  (Current: " .. (previous_scheme or "unknown") .. ")",
      choices = build_scheme_choices(),
      fuzzy = true,
      action = wezterm.action_callback(function(win, p, id, _)
        if not id then return end
        win:set_config_overrides({ color_scheme = id })
        win:perform_action(
          act.InputSelector({
            title = 'Previewing "' .. id .. '"',
            choices = {
              { id = "keep", label = "Keep this theme" },
              { id = "back", label = "Back to list" },
            },
            action = wezterm.action_callback(function(w, pp, choice, _)
              if choice == "keep" then
                local saved = load_schemes()
                saved[mode] = id
                saved.mode = mode
                save_schemes(saved)
              else
                w:set_config_overrides({ color_scheme = previous_scheme })
                open_scheme_picker_fallback(w, pp, mode, previous_scheme)
              end
            end),
          }),
          p
        )
      end),
    }),
    pane
  )
end

-- Writes the current builtin scheme names + their ANSI preview out for
-- scripts/theme_picker.{sh,ps1} to read (only Lua can call
-- wezterm.get_builtin_color_schemes()), one "<name>\t<preview>" per line.
local function export_master_list()
  local names, scheme_data = sorted_scheme_names()
  local f = io.open(master_list_path, "w")
  if not f then return end
  for _, name in ipairs(names) do
    f:write(name .. "\t" .. ansi_preview(name, scheme_data[name]) .. "\n")
  end
  f:close()
end

open_scheme_picker_fzf = function(window, pane, mode, previous_scheme, fzf_dir)
  export_master_list()
  theme_favorites.export_scratch()

  -- A single in-flight picker session at a time is all this flow supports;
  -- opening a new one simply replaces (and thus invalidates) any pending
  -- session. Everything — the list, the live preview, the keep/back
  -- prompt, and "Back to list" looping with the filter/scroll state still
  -- intact — happens inside ONE run of the spawned script/pane (see the
  -- big comment atop scripts/theme_picker.sh for why: an earlier version
  -- round-tripped "Back to list" through a fresh pane + Lua, which raced
  -- that pane's auto-close against showing the next prompt and made
  -- selecting a theme silently do nothing).
  wezterm.GLOBAL.theme_picker_pending = {
    mode = mode,
    previous_scheme = previous_scheme,
  }

  local args
  if utils.is_windows then
    args = { "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", theme_picker_script }
  else
    args = { "/bin/sh", theme_picker_script }
  end
  table.insert(args, "run")
  table.insert(args, master_list_path)
  table.insert(args, theme_favorites.scratch_path())
  table.insert(args, "")
  table.insert(args, previous_scheme or "")

  -- Explicitly set PATH for the spawned picker (rather than trusting
  -- whatever wezterm-gui itself inherited at launch) so `fzf` and the
  -- script's own coreutils calls (grep/sort/mktemp/base64/...) resolve
  -- regardless of how WezTerm was started. See resolve_fzf()/build_picker_path().
  window:perform_action(
    act.SpawnCommandInNewTab({
      args = args,
      set_environment_variables = { PATH = build_picker_path(fzf_dir) },
    }),
    pane
  )
end

-- Registered once at module load: SpawnCommandInNewTab spawns a fresh pane
-- each time the picker (re)opens, so this handler must not be re-registered
-- per invocation (wezterm.on has no matching "off") or callbacks would
-- stack. State for the in-flight picker session lives in wezterm.GLOBAL.
--
-- `set_config_overrides` is a per-WINDOW override, not per-pane, so the
-- live preview doesn't need to target any particular pane — it applies
-- regardless of which pane inside the window the event fired against.
wezterm.on("user-var-changed", function(window, _pane, name, value)
  if name == "wezterm_theme_preview" then
    window:set_config_overrides({ color_scheme = value })
    return
  end
  if name ~= "wezterm_theme_result" then return end

  local pending = wezterm.GLOBAL.theme_picker_pending
  if not pending then return end
  wezterm.GLOBAL.theme_picker_pending = nil

  if value == "CANCEL" then
    window:set_config_overrides({ color_scheme = pending.previous_scheme })
  else
    local saved = load_schemes()
    saved[pending.mode] = value
    saved.mode = pending.mode
    save_schemes(saved)
  end
  theme_favorites.import_scratch()
end)

function M.get_palette_commands(window)
  local s = load_schemes()
  local current_scheme = M.get_current()
  local effective_mode = s.auto and (system_is_dark() and "dark" or "light") or s.mode
  local current_mode_label = s.auto
    and ("auto/" .. (effective_mode == "light" and "Light" or "Dark"))
    or (s.mode == "light" and "Light" or "Dark")
  local auto_brief = "Appearance | Toggle automatically adjusting to system's dark/light mode ("
    .. (s.auto and "Enabled" or "Disabled") .. ")"

  return {
    {
      brief = "Appearance | Set color theme (Current: " .. current_scheme .. ")",
      action = wezterm.action_callback(function(win, pane)
        local previous_scheme = win:effective_config().color_scheme
        local found, fzf_dir = resolve_fzf()
        if found then
          open_scheme_picker_fzf(win, pane, s.mode, previous_scheme, fzf_dir)
        else
          wezterm.log_warn("theme picker: fzf not found (checked PATH and common install locations), falling back to built-in picker")
          open_scheme_picker_fallback(win, pane, s.mode, previous_scheme)
        end
      end),
    },
    {
      brief = "Appearance | Toggle dark/light theme (Current: " .. current_mode_label .. ")",
      action = wezterm.action_callback(function(win, _)
        local saved = load_schemes()
        local current_mode = saved.auto and (system_is_dark() and "dark" or "light") or saved.mode
        local next_mode = current_mode == "dark" and "light" or "dark"
        saved.auto = false
        saved.mode = next_mode
        save_schemes(saved)
        win:set_config_overrides({ color_scheme = saved[next_mode] })
      end),
    },
    {
      brief = auto_brief,
      action = wezterm.action_callback(function(win, _)
        local saved = load_schemes()
        saved.auto = not saved.auto
        save_schemes(saved)
        if saved.auto then
          local scheme = system_is_dark() and saved.dark or saved.light
          win:set_config_overrides({ color_scheme = scheme })
        end
      end),
    },
  }
end

function M.apply()
  wezterm.on("update-right-status", function(window, _)
    local s = load_schemes()
    if not s.auto then return end
    local is_dark = system_is_dark()
    if wezterm.GLOBAL.colorscheme_last_dark == is_dark then return end
    wezterm.GLOBAL.colorscheme_last_dark = is_dark
    local scheme = is_dark and s.dark or s.light
    local overrides = window:get_config_overrides() or {}
    overrides.color_scheme = scheme
    window:set_config_overrides(overrides)
  end)
end

return M
