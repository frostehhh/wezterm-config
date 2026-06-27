local wezterm = require("wezterm")
local config = wezterm.config_builder()

require("modules.appearance").apply(config)
require("modules.keybindings").apply(config)
require("modules.favorites").apply()
require("modules.events").apply()

return config
