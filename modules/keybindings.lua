local wezterm = require("wezterm")
local act = wezterm.action
local favorites = require("modules.favorites")

local M = {}

function M.apply(config)
  config.keys = {
    {
      key = "E",
      mods = "CTRL|SHIFT",
      action = act.PromptInputLine({
        description = "Rename pane:",
        action = wezterm.action_callback(function(_, pane, line)
          if line and line ~= "" then
            favorites.pane_titles[pane:pane_id()] = line
          end
        end),
      }),
    },
    {
      key = "R",
      mods = "CTRL|SHIFT",
      action = act.PromptInputLine({
        description = "Rename tab:",
        action = wezterm.action_callback(function(window, _, line)
          if line and line ~= "" then
            window:active_tab():set_title(line)
          end
        end),
      }),
    },
  }
end

return M
