local wezterm = require("wezterm")
local act = wezterm.action
local favorites = require("modules.favorites")

local M = {}

function M.apply(config)
  config.keys = {
    {
      key = "E",
      mods = "CTRL|SHIFT",
      action = wezterm.action_callback(function(window, pane)
        local current_title = favorites.pane_titles[pane:pane_id()] or pane:get_title()
        window:perform_action(
          act.PromptInputLine({
            description = "Rename pane (current: " .. current_title .. "):",
            action = wezterm.action_callback(function(_, p, line)
              if line and line ~= "" then
                favorites.pane_titles[p:pane_id()] = line
              end
            end),
          }),
          pane
        )
      end),
    },
    {
      key = "R",
      mods = "CTRL|SHIFT",
      action = wezterm.action_callback(function(window, pane)
        local current_title = window:active_tab():get_title()
        if not current_title or current_title == "" then
          current_title = pane:get_title()
        end
        window:perform_action(
          act.PromptInputLine({
            description = "Rename tab (current: " .. current_title .. "):",
            action = wezterm.action_callback(function(win, _, line)
              if line and line ~= "" then
                win:active_tab():set_title(line)
              end
            end),
          }),
          pane
        )
      end),
    },
  }
end

return M
