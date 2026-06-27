local wezterm = require("wezterm")

local M = {}

M.is_windows = os.getenv("OS") and os.getenv("OS"):lower():find("windows")
M.is_macos = wezterm.target_triple:lower():find("darwin") ~= nil

return M
