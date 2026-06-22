local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

local is_windows = os.getenv("OS") and os.getenv("OS"):lower():find("windows")
local is_macos = wezterm.target_triple:lower():find("darwin") ~= nil

config.color_scheme = "rose-pine-moon"
config.max_fps = 120
-- Source: https://www.nerdfonts.com/font-downloads
config.font = wezterm.font("Hack Nerd Font", { weight = "DemiBold" })
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_frame = {
  font = wezterm.font("Hack Nerd Font", { weight = "Bold" }),
}
config.inactive_pane_hsb = {
  saturation = 0.0,
  brightness = 0.5,
}

if is_windows then
  config.window_background_opacity = 0.7
  config.window_frame.font_size = 10.0
end

if is_macos then
  config.window_background_opacity = 0.8
  config.macos_window_background_blur = 50
  config.font_size = 15.0
  config.window_frame.font_size = 13.0
end

wezterm.on("update-right-status", function(window, pane)
  window:set_right_status(window:active_workspace() .. "  ")
end)

wezterm.on("augment-command-palette", function()
  return {
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
    {
      brief = "Window | Workspace: Delete current workspace",
      action = wezterm.action_callback(function(window, pane)
        local current = wezterm.mux.get_active_workspace()
        local all = wezterm.mux.all_workspaces()

        if #all <= 1 then
          return
        end

        local target
        for _, ws in ipairs(all) do
          if ws ~= current then
            target = ws
            break
          end
        end

        for _, gui_win in ipairs(wezterm.gui.gui_windows()) do
          if gui_win:active_workspace() == current then
            gui_win:perform_action(
              act.SwitchToWorkspace({ name = target }),
              gui_win:active_pane()
            )
          end
        end

        for _, mux_win in ipairs(wezterm.mux.all_windows()) do
          if mux_win:get_workspace() == current then
            for _, tab in ipairs(mux_win:tabs()) do
              for _, p in ipairs(tab:panes()) do
                p:send_text("exit\r\n")
              end
            end
          end
        end
      end),
    },
  }
end)

return config

