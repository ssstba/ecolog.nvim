local M = {}

local api = vim.api
local fn = vim.fn

---@class PresetWindow
---@field bufnr number
---@field winnr number
---@field preset_name string?
---@field mode "list"|"edit"|"create"
---@field current_col number
---@field current_row number

local current_window = nil

-- Form state for editing
local form_state = {
  original_preset = nil,
  columns = {
    { name = "REQ", width = 1 },
    { name = "VARIABLE", width = 35 },
    { name = "TYPE", width = 20 }
  }
}

local function create_window(width, height, title)
  -- Create buffer
  local bufnr = api.nvim_create_buf(false, true)
  
  -- Set buffer options
  api.nvim_buf_set_option(bufnr, "modifiable", true)
  api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  api.nvim_buf_set_option(bufnr, "swapfile", false)
  api.nvim_buf_set_option(bufnr, "filetype", "ecolog-preset")
  
  -- Calculate window size and position
  local screen_w = api.nvim_get_option("columns")
  local screen_h = api.nvim_get_option("lines")
  
  local win_w = math.min(width, screen_w - 4)
  local win_h = math.min(height, screen_h - 4)
  
  local row = math.floor((screen_h - win_h) / 2)
  local col = math.floor((screen_w - win_w) / 2)
  
  -- Create window
  local opts = {
    relative = "editor",
    width = win_w,
    height = win_h,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title or " Ecolog ",
    title_pos = "center",
  }
  
  local winnr = api.nvim_open_win(bufnr, true, opts)
  
  -- Set window options
  api.nvim_win_set_option(winnr, "wrap", false)
  api.nvim_win_set_option(winnr, "cursorline", true)
  api.nvim_win_set_option(winnr, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
  api.nvim_win_set_option(winnr, "signcolumn", "no")
  
  -- Enable mouse
  api.nvim_win_set_option(winnr, "mouse", "a")
  
  return bufnr, winnr
end

function M.handle_click()
  if not current_window then return end
  
  local cursor = api.nvim_win_get_cursor(current_window.winnr)
  local line = cursor[1]
  
  if current_window.mode == "list" then
    -- Handle list view clicks
    if line > 2 then -- Skip header lines
      M.edit_preset()
    end
  else
    -- Handle edit view clicks
    if current_window.var_line_numbers and vim.tbl_contains(current_window.var_line_numbers, line) then
      M.toggle_required()
    end
  end
end

local function setup_keymaps(bufnr, mode)
  -- Clear existing keymaps first
  for _, mode in ipairs({'n'}) do
    local keymaps = vim.api.nvim_buf_get_keymap(bufnr, mode)
    for _, keymap in ipairs(keymaps) do
      pcall(vim.keymap.del, mode, keymap.lhs, { buffer = bufnr })
    end
  end
  
  -- Set up keymaps with buffer-local options
  local opts = { 
    noremap = true, 
    silent = true,
    nowait = true  -- Ensure immediate keymap response
  }
  
  if mode == "list" then
    -- List view keymaps
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':lua require("ecolog.ui.presets").close()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', ':lua require("ecolog.ui.presets").close()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', ':lua require("ecolog.ui.presets").edit_preset()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', ':lua require("ecolog.ui.presets").delete_preset()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'c', ':lua require("ecolog.ui.presets").create_preset()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'v', ':lua require("ecolog.ui.presets").validate_current_env()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'u', ':lua require("ecolog.ui.presets").update_preset()<CR>', opts)
  else
    -- Edit view keymaps
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'h', ':lua require("ecolog.ui.presets").form_move_left()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'l', ':lua require("ecolog.ui.presets").form_move_right()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', ':lua require("ecolog.ui.presets").form_move_down()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', ':lua require("ecolog.ui.presets").form_move_up()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', ':lua require("ecolog.ui.presets").form_edit()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>', ':lua require("ecolog.ui.presets").form_edit()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'w', ':lua require("ecolog.ui.presets").form_save()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':lua require("ecolog.ui.presets").close()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', ':lua require("ecolog.ui.presets").close()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'a', ':lua require("ecolog.ui.presets").form_add_var()<CR>', opts)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', ':lua require("ecolog.ui.presets").form_delete_var()<CR>', opts)
  end
end

local function draw_list_view()
  if not current_window then return end
  
  -- Set buffer as modifiable
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
  
  local presets = require("ecolog.presets").list_presets()
  local lines = {}
  
  if not next(presets) then
    table.insert(lines, "No presets found. Press 'c' to create one.")
  else
    for name, preset in pairs(presets) do
      local var_count = vim.tbl_count(preset.variables)
      table.insert(lines, string.format("📋 %s (%d variables)", name, var_count))
    end
  end
  
  -- Clear buffer and set new lines
  api.nvim_buf_set_lines(current_window.bufnr, 0, -1, false, lines)
  
  -- Set buffer as non-modifiable
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", false)
end

local function get_column_ranges()
  local ranges = {}
  local current_pos = 1 -- Start after single space indent
  
  for i, col in ipairs(form_state.columns) do
    local start_pos = current_pos
    local end_pos = start_pos + col.width
    
    -- For the REQ column, only include the single character position
    if col.name == "REQ" then
      end_pos = start_pos + 1 -- Only include one character
    else
      -- For other columns, exclude trailing spaces
      local content_width = col.width
      if i < #form_state.columns then
        content_width = content_width - 1 -- Remove one trailing space
      end
      end_pos = start_pos + content_width
    end
    
    table.insert(ranges, { start_pos, end_pos })
    current_pos = current_pos + col.width + 1 -- +1 for single space between columns
  end
  
  return ranges
end

local function highlight_current_cell()
  if not current_window or not current_window.current_row or not current_window.current_col then return end
  
  local ns_id = api.nvim_create_namespace('ecolog_form')
  api.nvim_buf_clear_namespace(current_window.bufnr, ns_id, 0, -1)
  
  -- Highlight help text
  local line_count = #api.nvim_buf_get_lines(current_window.bufnr, 0, -1, false)
  api.nvim_buf_add_highlight(current_window.bufnr, ns_id, 'Comment', line_count - 1, 0, -1)
  
  -- Highlight current cell
  local ranges = get_column_ranges()
  local row = current_window.current_row - 1 -- No header offset needed
  local col_range = ranges[current_window.current_col]
  
  if col_range then
    -- Get the current line content
    local line = api.nvim_buf_get_lines(current_window.bufnr, row, row + 1, false)[1]
    
    if form_state.columns[current_window.current_col].name == "REQ" then
      -- For REQ column, highlight just the character
      api.nvim_buf_add_highlight(current_window.bufnr, ns_id, 'Visual', row, col_range[1], col_range[1] + 1)
    else
      -- For other columns, find the actual content bounds
      local content = line:sub(col_range[1] + 1, col_range[2])
      local content_start = content:find("[^%s]") or 1
      local content_end = content:find("%s*$") - 1
      
      if content_end > 0 then
        api.nvim_buf_add_highlight(current_window.bufnr, ns_id, 'Visual', row, 
          col_range[1] + content_start - 1,
          col_range[1] + content_end)
      end
    end
  end
end

local function draw_edit_form(preset_name)
  if not current_window then return end
  
  -- Set buffer options for editing
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
  api.nvim_buf_set_option(current_window.bufnr, "readonly", false)
  
  local presets = require("ecolog.presets").list_presets()
  local preset = presets[preset_name]
  if not preset then return end
  
  -- Store original preset for comparison
  form_state.original_preset = vim.deepcopy(preset)
  
  -- Update window title with env file info
  local env_filename = vim.fn.fnamemodify(current_window.env_file, ':t')
  api.nvim_win_set_config(current_window.winnr, {
    title = string.format(" 🌲 %s (%s) ", preset_name, env_filename),
    title_pos = "center",
  })
  
  -- Sort variables alphabetically
  local sorted_vars = {}
  for var_name, var_info in pairs(preset.variables) do
    table.insert(sorted_vars, { name = var_name, info = var_info })
  end
  table.sort(sorted_vars, function(a, b) return a.name < b.name end)
  
  -- Create content lines
  local lines = {}
  local row_data = {}
  
  for _, var in ipairs(sorted_vars) do
    local line = " " -- Single space indent
    
    -- Required status
    line = line .. (var.info.required and "+" or "-")
    
    -- Variable name with truncation if needed
    local var_name = var.name
    if #var_name > form_state.columns[2].width - 2 then
      var_name = var_name:sub(1, form_state.columns[2].width - 3) .. "…"
    end
    line = line .. " " .. string.format("%-" .. form_state.columns[2].width .. "s", var_name)
    
    -- Type with truncation
    local type_name = var.info.type
    if #type_name > form_state.columns[3].width - 2 then
      type_name = type_name:sub(1, form_state.columns[3].width - 3) .. "…"
    end
    line = line .. " " .. string.format("%-" .. form_state.columns[3].width .. "s", type_name)
    
    table.insert(lines, line)
    table.insert(row_data, {
      var_name = var.name,
      type = var.info.type,
      required = var.info.required
    })
  end
  
  -- Add empty line and help text at the bottom
  table.insert(lines, "")
  table.insert(lines, " ⌨  h/j/k/l navigate • <Enter> edit • <Space> toggle • w save • a add • d delete • q quit")
  
  -- Set lines in buffer
  api.nvim_buf_set_lines(current_window.bufnr, 0, -1, false, lines)
  
  -- Store window state
  current_window.row_data = row_data
  current_window.current_row = 1
  current_window.current_col = 1
  
  -- Set up highlights
  local ns_id = api.nvim_create_namespace('ecolog_form')
  api.nvim_buf_clear_namespace(current_window.bufnr, ns_id, 0, -1)
  
  -- Highlight help text
  api.nvim_buf_add_highlight(current_window.bufnr, ns_id, 'Comment', #lines - 1, 0, -1)
  
  -- Highlight current cell
  highlight_current_cell()
  
  -- Set initial cursor position
  api.nvim_win_set_cursor(current_window.winnr, {1, 1}) -- First row, minimal indent
end

local function move_cursor(direction)
  if not current_window or not current_window.row_data then return end
  
  if direction == "left" then
    current_window.current_col = math.max(1, current_window.current_col - 1)
  elseif direction == "right" then
    current_window.current_col = math.min(#form_state.columns, current_window.current_col + 1)
  elseif direction == "up" then
    current_window.current_row = math.max(1, current_window.current_row - 1)
  elseif direction == "down" then
    current_window.current_row = math.min(#current_window.row_data, current_window.current_row + 1)
  end
  
  highlight_current_cell()
  
  -- Update cursor position
  local row = current_window.current_row - 1 -- No header offset needed
  local ranges = get_column_ranges()
  local col_range = ranges[current_window.current_col]
  if col_range then
    -- For REQ column, place cursor directly on the character
    if form_state.columns[current_window.current_col].name == "REQ" then
      api.nvim_win_set_cursor(current_window.winnr, {row + 1, col_range[1]})
    else
      -- For other columns, get the actual content to find where to place cursor
      local line = api.nvim_buf_get_lines(current_window.bufnr, row, row + 1, false)[1]
      local content = line:sub(col_range[1] + 1, col_range[2])
      local first_non_space = content:find("[^%s]") or 1
      api.nvim_win_set_cursor(current_window.winnr, {row + 1, col_range[1] + first_non_space - 1})
    end
  end
end

local function safe_input(prompt, default)
  local ok, result = pcall(fn.input, prompt, default or "")
  if not ok then
    -- Input was interrupted
    return nil
  end
  return result
end

local function edit_current_cell()
  if not current_window or not current_window.row_data then return end
  
  local row_data = current_window.row_data[current_window.current_row]
  if not row_data then return end
  
  local col_name = form_state.columns[current_window.current_col].name
  local current_value = row_data[string.lower(col_name)]
  
  -- Get the current line and preserve its indentation
  local line = api.nvim_buf_get_lines(current_window.bufnr, current_window.current_row - 1, current_window.current_row, false)[1]
  
  if col_name == "REQ" then
    -- Toggle required status
    row_data.required = not row_data.required
    
    -- Update the display
    local ranges = get_column_ranges()
    local col_range = ranges[current_window.current_col]
    
    -- Create new line with toggled status
    local new_line = line:sub(1, col_range[1] - 1) .. 
                    (row_data.required and "+" or "-") .. 
                    line:sub(col_range[2])
    
    api.nvim_buf_set_lines(current_window.bufnr, current_window.current_row - 1, current_window.current_row, false, {new_line})
  else
    -- Edit other fields with input
    local prompt = string.format("Enter %s: ", col_name:lower())
    local new_value = safe_input(prompt, current_value or "")
    if new_value and new_value ~= "" then
      -- Update the data
      row_data[string.lower(col_name)] = new_value
      
      -- Update the display
      local ranges = get_column_ranges()
      local col_range = ranges[current_window.current_col]
      local col_width = form_state.columns[current_window.current_col].width
      
      -- Reconstruct the line while preserving structure
      local parts = {
        line:sub(1, col_range[1]), -- Everything before the cell
        string.format("%-" .. col_width .. "s", new_value), -- The new value
        line:sub(col_range[2] + 3) -- Everything after the cell
      }
      local new_line = table.concat(parts)
      
      api.nvim_buf_set_lines(current_window.bufnr, current_window.current_row - 1, current_window.current_row, false, {new_line})
    end
  end
  
  highlight_current_cell()
end

local function setup_form_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  
  -- Navigation
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'h', ':lua require("ecolog.ui.presets").form_move_left()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'l', ':lua require("ecolog.ui.presets").form_move_right()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', ':lua require("ecolog.ui.presets").form_move_down()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', ':lua require("ecolog.ui.presets").form_move_up()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', ':lua require("ecolog.ui.presets").form_edit()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Space>', ':lua require("ecolog.ui.presets").form_edit()<CR>', opts)
  
  -- Actions
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'w', ':lua require("ecolog.ui.presets").form_save()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':lua require("ecolog.ui.presets").close()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', ':lua require("ecolog.ui.presets").close()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'a', ':lua require("ecolog.ui.presets").form_add_var()<CR>', opts)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', ':lua require("ecolog.ui.presets").form_delete_var()<CR>', opts)
end

-- Form navigation functions
function M.form_move_left() move_cursor("left") end
function M.form_move_right() move_cursor("right") end
function M.form_move_up() move_cursor("up") end
function M.form_move_down() move_cursor("down") end
function M.form_edit() edit_current_cell() end

function M.form_save()
  if not current_window or not current_window.preset_name or not current_window.row_data then return end
  
  -- Convert row_data back to preset format
  local preset = { variables = {} }
  
  for _, row in ipairs(current_window.row_data) do
    preset.variables[row.var_name] = {
      type = row.type,
      required = row.required
    }
  end
  
  -- Delete the existing preset and create a new one with updated variables
  local presets = require("ecolog.presets")
  if presets.delete_preset(current_window.preset_name) and 
     presets.create_preset_from_variables(current_window.preset_name, preset.variables) then
    vim.notify("Preset saved successfully", vim.log.levels.INFO)
    
    -- Return to list view
    current_window.mode = "list"
    setup_keymaps(current_window.bufnr, "list")
    draw_list_view()
  else
    vim.notify("Failed to save preset", vim.log.levels.ERROR)
  end
end

function M.form_add_var()
  if not current_window or not current_window.preset_name then return end
  
  local var_name = safe_input("Variable name: ")
  if not var_name or #var_name == 0 then return end
  
  local type_name = safe_input("Variable type: ")
  if not type_name or #type_name == 0 then return end
  
  local required = fn.confirm("Is this variable required?", "&Yes\n&No", 1) == 1
  
  -- Add to row_data
  table.insert(current_window.row_data, {
    var_name = var_name,
    type = type_name,
    required = required
  })
  
  -- Redraw the form
  draw_edit_form(current_window.preset_name)
end

function M.form_delete_var()
  if not current_window or not current_window.row_data then return end
  
  local row_data = current_window.row_data[current_window.current_row]
  if not row_data then return end
  
  local choice = fn.confirm(string.format("Delete variable '%s'?", row_data.var_name), "&Yes\n&No", 2)
  if choice == 1 then
    -- Remove from row_data
    table.remove(current_window.row_data, current_window.current_row)
    
    -- Adjust current row if needed
    if current_window.current_row > #current_window.row_data then
      current_window.current_row = math.max(1, #current_window.row_data)
    end
    
    -- Update the UI
    local lines = {}
    for _, row in ipairs(current_window.row_data) do
      local line = " " -- Single space indent
      
      -- Required status
      line = line .. (row.required and "+" or "-")
      
      -- Variable name with truncation if needed
      local var_name = row.var_name
      if #var_name > form_state.columns[2].width - 2 then
        var_name = var_name:sub(1, form_state.columns[2].width - 3) .. "…"
      end
      line = line .. " " .. string.format("%-" .. form_state.columns[2].width .. "s", var_name)
      
      -- Type with truncation
      local type_name = row.type
      if #type_name > form_state.columns[3].width - 2 then
        type_name = type_name:sub(1, form_state.columns[3].width - 3) .. "…"
      end
      line = line .. " " .. string.format("%-" .. form_state.columns[3].width .. "s", type_name)
      
      table.insert(lines, line)
    end
    
    -- Add empty line and help text at the bottom
    table.insert(lines, "")
    table.insert(lines, " ⌨  h/j/k/l navigate • <Enter> edit • <Space> toggle • w save • a add • d delete • q quit")
    
    -- Update buffer
    api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
    api.nvim_buf_set_lines(current_window.bufnr, 0, -1, false, lines)
    api.nvim_buf_set_option(current_window.bufnr, "modifiable", false)
    
    -- Update highlights
    highlight_current_cell()
    
    vim.notify(string.format("Variable '%s' deleted. Press 'w' to save changes.", row_data.var_name), vim.log.levels.INFO)
  end
end

function M.parse_buffer_changes()
  if not current_window or not current_window.preset_name then return end
  
  local lines = api.nvim_buf_get_lines(current_window.bufnr, 0, -1, false)
  local changes = {}
  
  for _, line in ipairs(lines) do
    -- Skip non-variable lines
    if line:match("^%s*[⚡○]%s*%[") then
      local type_name, var_name, desc = line:match("%[([^%]]+)%]%s+([^%s%-]+)%s*%-%s*(.*)")
      if type_name and var_name then
        changes[var_name] = {
          type = type_name,
          required = line:match("^%s*⚡") ~= nil,
          description = desc ~= "" and desc or nil
        }
      end
    end
  end
  
  current_window.changes = changes
end

function M.save_changes()
  if not current_window or not current_window.preset_name or not current_window.changes then return end
  
  local success = true
  for var_name, info in pairs(current_window.changes) do
    if not require("ecolog").update_preset_variable(current_window.preset_name, var_name, info) then
      success = false
      break
    end
  end
  
  if success then
    vim.notify("Preset saved successfully", vim.log.levels.INFO)
    api.nvim_buf_set_option(current_window.bufnr, "modified", false)
  else
    vim.notify("Failed to save preset", vim.log.levels.ERROR)
  end
end

function M.toggle_required()
  if not current_window or not current_window.preset_name then return end
  
  local cursor = api.nvim_win_get_cursor(current_window.winnr)
  local line = api.nvim_buf_get_lines(current_window.bufnr, cursor[1] - 1, cursor[1], false)[1]
  
  -- Skip if not on a variable line
  if not line:match("^%s*[⚡○]%s*%[") then return end
  
  -- Make buffer modifiable
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
  
  -- Toggle the status icon
  if line:match("^%s*⚡") then
    line = line:gsub("^(%s*)⚡", "%1○")
  else
    line = line:gsub("^(%s*)○", "%1⚡")
  end
  
  api.nvim_buf_set_lines(current_window.bufnr, cursor[1] - 1, cursor[1], false, {line})
  
  -- Make buffer non-modifiable again
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", false)
  
  -- Parse changes
  M.parse_buffer_changes()
end

function M.edit_description()
  if not current_window or not current_window.preset_name then return end
  
  local cursor = api.nvim_win_get_cursor(current_window.winnr)
  local line = api.nvim_buf_get_lines(current_window.bufnr, cursor[1] - 1, cursor[1], false)[1]
  
  -- Skip if not on a variable line
  if not line:match("^%s*[⚡○]%s*%[") then return end
  
  local type_name, var_name, desc = line:match("%[([^%]]+)%]%s+([^%s%-]+)%s*%-%s*(.*)")
  if not (type_name and var_name) then return end
  
  local new_desc = fn.input("Enter description: ", desc)
  if new_desc ~= nil then
    -- Make buffer modifiable
    api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
    
    -- Update the line
    local status_icon = line:match("^%s*⚡") and "⚡" or "○"
    local new_line = string.format("  %s [%s] %s - %s", status_icon, type_name, var_name, new_desc)
    api.nvim_buf_set_lines(current_window.bufnr, cursor[1] - 1, cursor[1], false, {new_line})
    
    -- Make buffer non-modifiable again
    api.nvim_buf_set_option(current_window.bufnr, "modifiable", false)
    
    -- Parse changes
    M.parse_buffer_changes()
  end
end

function M.toggle(selected_env_file)
  -- Check if presets module is enabled
  local config = require("ecolog").get_config()
  if not config or not config.presets then
    vim.notify("Presets module is disabled. Enable it in your configuration with `presets = true`.", vim.log.levels.ERROR)
    return
  end

  if current_window then
    M.close()
    return
  end
  
  -- Get current buffer file path
  local current_file = vim.fn.expand('%:p')
  local env_file = nil
  local ecolog = require("ecolog")
  
  -- Check if current file is an env file
  if current_file:match("%.env[^/]*$") then
    env_file = current_file
  else
    -- Use selected env file from ecolog module
    env_file = selected_env_file or ecolog.get_selected_env_file()
  end
  
  if not env_file then
    vim.notify("No environment file selected. Use :EcologSelect to select one.", vim.log.levels.ERROR)
    return
  end
  
  -- Create window with increased size and title including env file info
  local env_filename = vim.fn.fnamemodify(env_file, ':t')
  local bufnr, winnr = create_window(80, 25, string.format(" 🌲 Ecolog Presets (%s) ", env_filename))
  current_window = {
    bufnr = bufnr,
    winnr = winnr,
    mode = "list",
    env_file = env_file
  }
  
  setup_keymaps(bufnr, "list")
  draw_list_view()
end

function M.close()
  if not current_window then return end
  
  api.nvim_win_close(current_window.winnr, true)
  api.nvim_buf_delete(current_window.bufnr, { force = true })
  current_window = nil
end

function M.edit_preset()
  if not current_window or current_window.mode ~= "list" then return end
  
  local line = api.nvim_get_current_line()
  local preset_name = line:match("📋 ([^%(]+)")
  if not preset_name then return end
  
  preset_name = vim.trim(preset_name)
  current_window.preset_name = preset_name
  current_window.mode = "edit"
  
  -- Set buffer options
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
  api.nvim_buf_set_option(current_window.bufnr, "readonly", false)
  api.nvim_buf_set_option(current_window.bufnr, "buftype", "nofile")
  
  -- Set up form keymaps
  setup_keymaps(current_window.bufnr, "edit")
  
  -- Draw form view
  draw_edit_form(preset_name)
end

function M.delete_preset()
  if not current_window or current_window.mode ~= "list" then return end
  
  local line = api.nvim_get_current_line()
  local preset_name = line:match("📋 ([^%(]+)")
  if not preset_name then return end
  
  preset_name = vim.trim(preset_name)
  local choice = fn.confirm(string.format("Delete preset '%s'?", preset_name), "&Yes\n&No", 2)
  if choice == 1 then
    if require("ecolog.presets").delete_preset(preset_name) then
      vim.notify(string.format("Preset '%s' deleted successfully", preset_name), vim.log.levels.INFO)
      draw_list_view()
    else
      vim.notify(string.format("Failed to delete preset '%s'", preset_name), vim.log.levels.ERROR)
    end
  end
end

function M.create_preset()
  if not current_window then return end
  
  local name = fn.input("Enter preset name: ")
  if name and #name > 0 then
    if require("ecolog.presets").create_preset_from_file(name, current_window.env_file) then
      vim.notify("Preset created successfully", vim.log.levels.INFO)
      draw_list_view()
    end
  end
end

function M.validate_current_env()
  if not current_window or current_window.mode ~= "list" then return end
  
  local line = api.nvim_get_current_line()
  local preset_name = line:match("📋 ([^%(]+)")
  if not preset_name then return end
  
  preset_name = vim.trim(preset_name)
  local presets = require("ecolog.presets")
  local errors = presets.validate_env_file(current_window.env_file, preset_name)
  
  if not next(errors) then
    vim.notify("Environment file is valid!", vim.log.levels.INFO)
  else
    local error_lines = {"Validation errors:"}
    for var_name, error_msg in pairs(errors) do
      table.insert(error_lines, string.format("• %s: %s", var_name, error_msg))
    end
    vim.notify(table.concat(error_lines, "\n"), vim.log.levels.ERROR)
  end
end

function M.add_variable()
  if not current_window or not current_window.preset_name then return end
  
  local var_name = fn.input("Variable name: ")
  if not var_name or #var_name == 0 then return end
  
  local type_name = fn.input("Variable type: ")
  if not type_name or #type_name == 0 then return end
  
  local required = fn.confirm("Is this variable required?", "&Yes\n&No", 1) == 1
  local desc = fn.input("Description (optional): ")
  
  -- Make buffer modifiable
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
  
  -- Add new variable line
  local new_line = string.format("%s [%s] %s - %s",
    required and "⚡" or "○",
    type_name,
    var_name,
    desc
  )
  
  -- Find position to insert (before footer)
  local lines = api.nvim_buf_get_lines(current_window.bufnr, 0, -1, false)
  local insert_pos = #lines - 5 -- Before footer
  api.nvim_buf_set_lines(current_window.bufnr, insert_pos, insert_pos, false, {new_line})
  
  -- Make buffer non-modifiable again
  api.nvim_buf_set_option(current_window.bufnr, "modifiable", false)
  
  -- Parse changes
  M.parse_buffer_changes()
end

function M.delete_variable()
  if not current_window or not current_window.preset_name then return end
  
  local cursor = api.nvim_win_get_cursor(current_window.winnr)
  local line = api.nvim_buf_get_lines(current_window.bufnr, cursor[1] - 1, cursor[1], false)[1]
  
  -- Skip if not on a variable line
  if not line:match("^%s*[⚡○]%s*%[") then return end
  
  local type_name, var_name = line:match("%[([^%]]+)%]%s+([^%s%-]+)")
  if not (type_name and var_name) then return end
  
  local choice = fn.confirm(string.format("Delete variable '%s'?", var_name), "&Yes\n&No", 2)
  if choice == 1 then
    -- Make buffer modifiable
    api.nvim_buf_set_option(current_window.bufnr, "modifiable", true)
    
    -- Delete the line
    api.nvim_buf_set_lines(current_window.bufnr, cursor[1] - 1, cursor[1], false, {})
    
    -- Make buffer non-modifiable again
    api.nvim_buf_set_option(current_window.bufnr, "modifiable", false)
    
    -- Parse changes
    M.parse_buffer_changes()
  end
end

function M.update_preset()
  if not current_window or current_window.mode ~= "list" then return end
  
  local line = api.nvim_get_current_line()
  local preset_name = line:match("📋 ([^%(]+)")
  if not preset_name then return end
  
  preset_name = vim.trim(preset_name)
  
  -- Confirm update
  local choice = fn.confirm(string.format("Update preset '%s' from current env file?", preset_name), "&Yes\n&No", 2)
  if choice == 1 then
    -- Delete existing preset and create new one with same name
    require("ecolog.presets").delete_preset(preset_name)
    if require("ecolog.presets").create_preset_from_file(preset_name, current_window.env_file) then
      vim.notify(string.format("Preset '%s' updated successfully", preset_name), vim.log.levels.INFO)
      draw_list_view()
    else
      vim.notify(string.format("Failed to update preset '%s'", preset_name), vim.log.levels.ERROR)
    end
  end
end

return M 