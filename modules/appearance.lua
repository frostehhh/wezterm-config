local wezterm = require("wezterm")
local utils = require("modules.utils")

local M = {}

-- Source: https://www.nerdfonts.com/font-downloads
local font = wezterm.font_with_fallback({
  { family = "Hack Nerd Font", weight = "DemiBold" },
  { family = "JetBrains Mono" },
})
local frame_font = wezterm.font_with_fallback({
  { family = "Hack Nerd Font", weight = "Bold" },
  { family = "JetBrains Mono" },
})

function M.apply(config)
  config.color_scheme = "rose-pine-moon"
  config.max_fps = 120
  config.font = font
  config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
  config.window_frame = {
    font = frame_font,
  }
  config.inactive_pane_hsb = {
    saturation = 0.0,
    brightness = 0.5,
  }

  if utils.is_windows then
    config.default_prog = { "pwsh.exe", "-NoLogo" }
    config.window_background_opacity = 0.9
    config.window_frame.font_size = 10.0
  end

  if utils.is_macos then
    config.window_background_opacity = 0.8
    config.macos_window_background_blur = 50
    config.font_size = 15.0
    config.window_frame.font_size = 13.0
  end
end

return M
