local wezterm = require 'wezterm'

local M = {}

local function json_decode(value)
  if wezterm.json_parse then
    local ok, result = pcall(wezterm.json_parse, value)
    if ok and type(result) == 'table' then
      return result
    end
  end

  if wezterm.serde and wezterm.serde.json_decode then
    local ok, result = pcall(wezterm.serde.json_decode, value)
    if ok and type(result) == 'table' then
      return result
    end
  end

  return nil
end

local function non_empty(value)
  return type(value) == 'string' and value ~= ''
end

local function visualhud_status(state)
  local progress = tonumber(state.progress_percent or 0) or 0
  local label = state.name or 'VisualHUD'
  if non_empty(state.context_title) then
    return ' ' .. state.context_title .. ' '
  end
  if state.state_kind == 'progress' or state.state_kind == 'journey' then
    return string.format(' %s %d%% ', label, progress)
  end
  return ' ' .. label .. ' '
end

local function visualhud_background(state)
  local tint = state.tint_color
  if not non_empty(tint) then
    tint = '#101010'
  end

  local layers = {
    {
      source = { Color = tint },
      width = '100%',
      height = '100%',
      opacity = 1.0,
    },
  }

  if non_empty(state.sprite_path) then
    table.insert(layers, {
      source = { File = state.sprite_path },
      width = '100%',
      height = 'Contain',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
      horizontal_align = 'Right',
      vertical_align = 'Middle',
      opacity = 0.58,
      hsb = {
        brightness = 0.62,
        saturation = 0.95,
      },
    })
  end

  return layers
end

local function apply_state(window, state)
  local overrides = window:get_config_overrides() or {}
  local color = state.color
  if not non_empty(color) then
    color = '#7aa2ff'
  end

  overrides.colors = overrides.colors or {}
  overrides.colors.background = state.tint_color or '#101010'
  overrides.colors.cursor_bg = color
  overrides.colors.cursor_border = color
  overrides.colors.selection_bg = color
  overrides.background = visualhud_background(state)
  overrides.window_background_opacity = 1.0
  overrides.text_background_opacity = 1.0

  window:set_config_overrides(overrides)
  window:set_right_status(visualhud_status(state))
end

function M.apply_to_config(config)
  config.enable_tab_bar = true
  config.use_fancy_tab_bar = true

  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name ~= 'visualhudState' then
      return
    end

    local state = json_decode(value)
    if not state then
      wezterm.log_warn('VisualHUD ignored malformed state payload')
      return
    end

    apply_state(window, state)
  end)

  return config
end

return M
