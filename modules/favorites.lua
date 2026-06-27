local wezterm = require("wezterm")
local act = wezterm.action
local utils = require("modules.utils")

local M = {}

local function normalize_path(path)
  if utils.is_windows and path:sub(1, 1) == "/" then
    return path:sub(2)
  end
  return path
end

M.pane_titles = {}

local favorites_path = wezterm.home_dir .. "/.config/wezterm/favorite_dirs.json"

local function load_favorites()
  local f = io.open(favorites_path, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(wezterm.json_parse, content)
  return (ok and type(data) == "table") and data or {}
end

local function save_favorites(favorites)
  local f = io.open(favorites_path, "w")
  if f then
    f:write(wezterm.json_encode(favorites))
    f:close()
  end
end

function M.apply()
  wezterm.on("augment-command-palette", function()
    return {
      {
        brief = "Directory | Add current directory to favorites",
        action = wezterm.action_callback(function(_, pane)
          local cwd_url = pane:get_current_working_dir()
          if not cwd_url then return end
          local cwd = normalize_path(cwd_url.file_path)
          local favs = load_favorites()
          for _, v in ipairs(favs) do
            if v == cwd then return end
          end
          table.insert(favs, cwd)
          save_favorites(favs)
        end),
      },
      {
        brief = "Directory | Remove a favorite directory",
        action = wezterm.action_callback(function(window, pane)
          local favs = load_favorites()
          if #favs == 0 then return end
          local choices = {}
          for i, v in ipairs(favs) do
            table.insert(choices, { id = tostring(i), label = v })
          end
          window:perform_action(
            act.InputSelector({
              title = "Remove favorite directory",
              choices = choices,
              action = wezterm.action_callback(function(_, _, id, _)
                if not id then return end
                local idx = tonumber(id)
                local updated = load_favorites()
                table.remove(updated, idx)
                save_favorites(updated)
              end),
            }),
            pane
          )
        end),
      },
      {
        brief = "Directory | Go to favorite directory",
        action = wezterm.action_callback(function(window, pane)
          local favs = load_favorites()
          if #favs == 0 then return end
          local choices = {}
          for _, v in ipairs(favs) do
            table.insert(choices, { id = v, label = v })
          end
          window:perform_action(
            act.InputSelector({
              title = "Go to favorite directory",
              choices = choices,
              action = wezterm.action_callback(function(_, p, id, _)
                if id then
                  p:send_text('cd "' .. id .. '"\r\n')
                end
              end),
            }),
            pane
          )
        end),
      },
    }
  end)
end

return M
