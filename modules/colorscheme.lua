local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local DEFAULTS = { dark = "rose-pine-moon", light = "rose-pine-dawn", mode = "dark", auto = false }
local scheme_path = wezterm.home_dir .. "/.config/wezterm/colorscheme.json"

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

local function build_scheme_choices()
  local scheme_data = wezterm.get_builtin_color_schemes()
  local names = {}
  for name in pairs(scheme_data) do table.insert(names, name) end
  table.sort(names)
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
      table.insert(parts, { Foreground = { Color = "Default" } })
      table.insert(parts, { Text = "  " .. name })
      label = wezterm.format(parts)
    else
      label = name
    end
    table.insert(choices, { id = name, label = label })
  end
  return choices
end

local open_scheme_picker

open_scheme_picker = function(window, pane, mode, previous_scheme)
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
                open_scheme_picker(w, pp, mode, previous_scheme)
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

function M.apply()
  wezterm.on("augment-command-palette", function(window, _)
    local s = load_schemes()
    local current_scheme = M.get_current()
    local current_mode_label = (current_scheme == s.light) and "Light" or "Dark"
    local auto_brief = "Appearance | Toggle automatically adjusting to system's dark/light mode ("
      .. (s.auto and "Enabled" or "Disabled") .. ")"

    return {
      {
        brief = "Appearance | Set color theme (Current: " .. current_scheme .. ")",
        action = wezterm.action_callback(function(window, pane)
          local previous_scheme = window:effective_config().color_scheme
          open_scheme_picker(window, pane, s.mode, previous_scheme)
        end),
      },
      {
        brief = "Appearance | Toggle dark/light theme (Current: " .. current_mode_label .. ")",
        action = wezterm.action_callback(function(window, _)
          local saved = load_schemes()
          local next_mode = (saved.mode == "dark") and "light" or "dark"
          saved.mode = next_mode
          save_schemes(saved)
          window:set_config_overrides({ color_scheme = saved[next_mode] })
        end),
      },
      {
        brief = auto_brief,
        action = wezterm.action_callback(function(window, _)
          local saved = load_schemes()
          saved.auto = not saved.auto
          save_schemes(saved)
          if saved.auto then
            local scheme = system_is_dark() and saved.dark or saved.light
            window:set_config_overrides({ color_scheme = scheme })
          end
        end),
      },
    }
  end)
end

return M
