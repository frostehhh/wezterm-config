local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

local pane_titles = {}

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
  config.default_prog = { 'pwsh.exe', '-NoLogo' }
  config.window_background_opacity = 0.9
  config.window_frame.font_size = 10.0
end

if is_macos then
  config.window_background_opacity = 0.8
  config.macos_window_background_blur = 50
  config.font_size = 15.0
  config.window_frame.font_size = 13.0
end

wezterm.on("update-right-status", function(window, pane)
  local pane_title = pane_titles[pane:pane_id()] or pane:get_title()
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
        action = wezterm.action_callback(function(window, pane, line)
          if line and line ~= "" then
            pane_titles[pane:pane_id()] = line
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
    {
      brief = "Directory | Add current directory to favorites",
      action = wezterm.action_callback(function(_, pane)
        local cwd_url = pane:get_current_working_dir()
        if not cwd_url then return end
        local cwd = cwd_url.file_path
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
                p:send_text('cd \"' .. id .. '\"\r\n')
              end
            end),
          }),
          pane
        )
      end),
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

config.keys = {
  {
    key = "E",
    mods = "CTRL|SHIFT",
    action = act.PromptInputLine({
      description = "Rename pane:",
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= "" then
          pane_titles[pane:pane_id()] = line
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
  }
}

return config

