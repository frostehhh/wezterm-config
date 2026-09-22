local wezterm = require("wezterm")

local M = {}

-- Canonical, at-rest storage: a JSON array of favorited theme names.
local favorites_path = wezterm.home_dir .. "/.config/wezterm/favorite_themes.json"
-- Transient, shell-writable storage used only while the fzf picker is open:
-- one theme name per line, so scripts/theme_picker.sh can grep/append it
-- without a JSON dependency. Reconciled back into favorites_path once the
-- picker session ends.
local scratch_path = wezterm.home_dir .. "/.config/wezterm/.theme_favorites_scratch.txt"

function M.load()
  local f = io.open(favorites_path, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(wezterm.json_parse, content)
  return (ok and type(data) == "table") and data or {}
end

function M.save(list)
  local f = io.open(favorites_path, "w")
  if f then
    f:write(wezterm.json_encode(list))
    f:close()
  end
end

function M.is_favorite(name)
  for _, v in ipairs(M.load()) do
    if v == name then return true end
  end
  return false
end

-- Path a spawned shell script can pass to `theme_picker.sh list/toggle`.
function M.scratch_path()
  return scratch_path
end

-- Write the canonical favorites list out as the plain-text scratch file.
-- Call before spawning the fzf picker.
function M.export_scratch()
  local f = io.open(scratch_path, "w")
  if not f then return end
  for _, name in ipairs(M.load()) do
    f:write(name .. "\n")
  end
  f:close()
end

-- Read the scratch file (as mutated live by theme_picker.sh's `toggle`
-- subcommand) back into the canonical JSON store. Call once the picker
-- session ends.
function M.import_scratch()
  local f = io.open(scratch_path, "r")
  if not f then return end
  local list = {}
  for line in f:lines() do
    if line ~= "" then table.insert(list, line) end
  end
  f:close()
  M.save(list)
end

return M
