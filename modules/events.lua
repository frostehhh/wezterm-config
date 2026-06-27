local wezterm = require("wezterm")
local act = wezterm.action
local favorites = require("modules.favorites")

local M = {}

function M.apply()
  wezterm.on("update-right-status", function(window, pane)
    local pane_title = favorites.pane_titles[pane:pane_id()] or pane:get_title()
    local workspace = window:active_workspace()
    window:set_right_status("Pane: " .. pane_title .. " | Workspace: " .. workspace .. "  ")
    window:set_left_status("")
  end)

  wezterm.on("format-tab-title", function(tab)
    local title = tab.tab_title
    if not title or #title == 0 then
      title = tab.active_pane.title
    end
    return title
  end)

  wezterm.on("augment-command-palette", function()
    return {
      {
        brief = "Tab: Rename current tab",
        action = act.PromptInputLine({
          description = "Rename tab:",
          action = wezterm.action_callback(function(window, _, line)
            if line and line ~= "" then
              window:active_tab():set_title(line)
            end
          end),
        }),
      },
      {
        brief = "Pane: Rename current pane",
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
        brief = "Window | Workspace: Rename the current workspace",
        action = act.PromptInputLine({
          description = "Rename workspace:",
          action = wezterm.action_callback(function(_, _, line)
            if line and line ~= "" then
              wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
            end
          end),
        }),
      },
    }
  end)
end

return M
