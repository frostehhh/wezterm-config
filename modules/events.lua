local wezterm = require("wezterm")
local act = wezterm.action
local favorites = require("modules.favorites")
local colorscheme = require("modules.colorscheme")

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

  wezterm.on("augment-command-palette", function(window, _)
    local entries = {}
    for _, e in ipairs(colorscheme.get_palette_commands(window)) do
      table.insert(entries, e)
    end
    for _, e in ipairs(favorites.get_palette_commands()) do
      table.insert(entries, e)
    end
    table.insert(entries, {
      brief = "Tab: Rename current tab",
      action = wezterm.action_callback(function(win, pane)
        local current_title = win:active_tab():get_title()
        if not current_title or current_title == "" then
          current_title = pane:get_title()
        end
        win:perform_action(
          act.PromptInputLine({
            description = "Rename tab (current: " .. current_title .. "):",
            action = wezterm.action_callback(function(w, _, line)
              if line and line ~= "" then
                w:active_tab():set_title(line)
              end
            end),
          }),
          pane
        )
      end),
    })
    table.insert(entries, {
      brief = "Pane: Rename current pane",
      action = wezterm.action_callback(function(win, pane)
        local current_title = favorites.pane_titles[pane:pane_id()] or pane:get_title()
        win:perform_action(
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
    })
    table.insert(entries, {
      brief = "Window | Workspace: Rename the current workspace",
      action = act.PromptInputLine({
        description = "Rename workspace:",
        action = wezterm.action_callback(function(_, _, line)
          if line and line ~= "" then
            wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
          end
        end),
      }),
    })
    return entries
  end)
end

return M
