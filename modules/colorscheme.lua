local wezterm = require("wezterm")
local act = wezterm.action
local theme_favorites = require("modules.theme_favorites")

local M = {}

local DEFAULTS = { dark = "rose-pine-moon", light = "rose-pine-dawn", mode = "dark", auto = false }
local scheme_path = wezterm.home_dir .. "/.config/wezterm/colorscheme.json"
local master_list_path = wezterm.home_dir .. "/.config/wezterm/.theme_master_list.txt"
local theme_picker_script = wezterm.config_dir .. "/scripts/theme_picker.sh"

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

local function build_scheme_choices()
  local names, scheme_data = sorted_scheme_names()
  local choices = {}
  for _, name in ipairs(names) do
    local s = scheme_data[name]
    local label
    if s and s.ansi then
      local parts = {}
      for i = 2, 7 do
        if s.ansi[i] then
          table.insert(parts, { Foreground = { Color = s.ansi[i] } })
          table.insert(parts, { Text = "█" })
        end
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

local function has_fzf()
  local ok, result = pcall(wezterm.run_child_process, { "which", "fzf" })
  return ok and result
end

-- Fallback picker (native act.InputSelector): used when `fzf` isn't on
-- PATH. Does not support restoring scroll/filter state or an in-list `f`
-- favorite key, since InputSelector exposes neither to Lua.
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

-- Writes the current builtin scheme names out for scripts/theme_picker.sh
-- to read (only Lua can call wezterm.get_builtin_color_schemes()).
local function export_master_list()
  local names = sorted_scheme_names()
  local f = io.open(master_list_path, "w")
  if not f then return end
  for _, name in ipairs(names) do
    f:write(name .. "\n")
  end
  f:close()
end

-- Shows the existing live-preview "Keep this theme" / "Back to list" step,
-- kept as a native InputSelector: it's a static binary choice with no
-- filter/scroll state to preserve and no need for a favorite keybind, so
-- there's no benefit to routing it through fzf too.
local function show_keep_or_back(win, pane, id, query, mode, previous_scheme)
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
          theme_favorites.import_scratch()
        else
          w:set_config_overrides({ color_scheme = previous_scheme })
          theme_favorites.import_scratch()
          open_scheme_picker_fzf(w, pp, mode, previous_scheme, query, id)
        end
      end),
    }),
    pane
  )
end

open_scheme_picker_fzf = function(window, pane, mode, previous_scheme, initial_query, initial_prev)
  export_master_list()
  theme_favorites.export_scratch()

  -- A single in-flight picker session at a time is all this flow supports;
  -- opening a new one simply replaces (and thus invalidates) any pending
  -- session, so stray events from an already-closed pane are ignored once
  -- `wezterm.GLOBAL.theme_picker_pending` has been cleared or overwritten.
  wezterm.GLOBAL.theme_picker_pending = {
    mode = mode,
    previous_scheme = previous_scheme,
    query = nil,
  }

  window:perform_action(
    act.SpawnCommandInNewTab({
      args = {
        "/bin/sh",
        theme_picker_script,
        "run",
        master_list_path,
        theme_favorites.scratch_path(),
        initial_query or "",
        initial_prev or previous_scheme or "",
      },
    }),
    pane
  )
end

-- Registered once at module load: SpawnCommandInNewTab spawns a fresh pane
-- each time the picker (re)opens, so this handler must not be re-registered
-- per invocation (wezterm.on has no matching "off") or callbacks would
-- stack. State for the in-flight picker session lives in wezterm.GLOBAL.
wezterm.on("user-var-changed", function(window, pane, name, value)
  if name ~= "wezterm_theme_result" and name ~= "wezterm_theme_query" then return end
  local pending = wezterm.GLOBAL.theme_picker_pending
  if not pending then return end

  if name == "wezterm_theme_result" then
    if value == "CANCEL" then
      wezterm.GLOBAL.theme_picker_pending = nil
      return
    end
    pending.result = value
  elseif name == "wezterm_theme_query" then
    pending.query = value
  end

  if pending.result and pending.query ~= nil then
    wezterm.GLOBAL.theme_picker_pending = nil
    show_keep_or_back(window, pane, pending.result, pending.query, pending.mode, pending.previous_scheme)
  end
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
        if has_fzf() then
          open_scheme_picker_fzf(win, pane, s.mode, previous_scheme, "", previous_scheme)
        else
          wezterm.log_warn("theme picker: fzf not found on PATH, falling back to built-in picker")
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
