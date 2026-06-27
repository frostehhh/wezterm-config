local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.warn_about_missing_glyphs = false

require("modules.appearance").apply(config)
require("modules.keybindings").apply(config)
require("modules.favorites").apply()
require("modules.events").apply()

return config
