local M = {}

---@class EnvPreset
---@field name string The name of the preset
---@field variables table<string, { type: string, required: boolean, description?: string }> The variables in the preset

local function get_preset_path()
  local config = require("ecolog").get_config()
  return config.presets_file or (vim.fn.stdpath("config") .. "/ecolog_presets.json")
end

-- Load existing presets from file
local function load_presets()
  local preset_path = get_preset_path()
  local f = io.open(preset_path, "r")
  if not f then
    return {}
  end
  local content = f:read("*all")
  f:close()
  local ok, presets = pcall(vim.json.decode, content)
  if not ok then
    vim.notify("Failed to parse presets file", vim.log.levels.ERROR)
    return {}
  end
  return presets
end

-- Save presets to file
local function save_presets(presets)
  local preset_path = get_preset_path()
  local f = io.open(preset_path, "w")
  if not f then
    vim.notify("Failed to open presets file for writing", vim.log.levels.ERROR)
    return false
  end
  local ok, content = pcall(vim.json.encode, presets)
  if not ok then
    vim.notify("Failed to encode presets", vim.log.levels.ERROR)
    return false
  end
  f:write(content)
  f:close()
  return true
end

-- Create a preset from an env file
---@param name string The name of the preset
---@param env_file string The path to the env file
---@return boolean success
function M.create_preset_from_file(name, env_file)
  local types = require("ecolog.types")
  local utils = require("ecolog.utils")
  local f = io.open(env_file, "r")
  if not f then
    vim.notify("Could not open env file", vim.log.levels.ERROR)
    return false
  end

  local variables = {}
  for line in f:lines() do
    if not line:match("^%s*$") and not line:match("^%s*#") then
      local key, value = line:match(utils.PATTERNS.key_value)
      if key then
        key = key:match(utils.PATTERNS.trim)
        value = value:match(utils.PATTERNS.trim)
        value = value:gsub(utils.PATTERNS.quoted, "%1")
        
        local type_name = types.detect_type(value)
        variables[key] = {
          type = type_name,
          required = true, -- By default, all variables are required
          description = nil -- Can be added manually later
        }
      end
    end
  end
  f:close()

  local presets = load_presets()
  presets[name] = {
    name = name,
    variables = variables
  }
  return save_presets(presets)
end

-- Create a preset from a variables table
---@param name string The name of the preset
---@param variables table<string, { type: string, required: boolean }> The variables to add to the preset
---@return boolean success
function M.create_preset_from_variables(name, variables)
  local presets = load_presets()
  presets[name] = {
    name = name,
    variables = variables
  }
  return save_presets(presets)
end

-- Validate an env file against a preset
---@param env_file string The path to the env file
---@param preset_name string The name of the preset to validate against
---@return table<string, string> errors Table of validation errors
function M.validate_env_file(env_file, preset_name)
  local types = require("ecolog.types")
  local utils = require("ecolog.utils")
  local presets = load_presets()
  local preset = presets[preset_name]
  if not preset then
    return { ["error"] = "Preset not found: " .. preset_name }
  end

  local errors = {}
  local found_vars = {}

  -- Read and validate env file
  local f = io.open(env_file, "r")
  if not f then
    return { ["error"] = "Could not open env file" }
  end

  for line in f:lines() do
    if not line:match("^%s*$") and not line:match("^%s*#") then
      local key, value = line:match(utils.PATTERNS.key_value)
      if key then
        key = key:match(utils.PATTERNS.trim)
        value = value:match(utils.PATTERNS.trim)
        value = value:gsub(utils.PATTERNS.quoted, "%1")
        found_vars[key] = true

        local var_def = preset.variables[key]
        if var_def then
          local type_name = types.detect_type(value)
          if type_name ~= var_def.type then
            errors[key] = string.format("Type mismatch: expected %s, got %s", var_def.type, type_name)
          end
        else
          errors[key] = "Unknown variable not defined in preset"
        end
      end
    end
  end
  f:close()

  -- Check for missing required variables
  for key, var_def in pairs(preset.variables) do
    if var_def.required and not found_vars[key] then
      errors[key] = "Required variable is missing"
    end
  end

  return errors
end

-- List all available presets
---@return table<string, EnvPreset>
function M.list_presets()
  return load_presets()
end

-- Delete a preset
---@param name string The name of the preset to delete
---@return boolean success
function M.delete_preset(name)
  local presets = load_presets()
  if not presets[name] then
    return false
  end
  presets[name] = nil
  return save_presets(presets)
end

-- Update preset variable properties
---@param preset_name string The name of the preset
---@param var_name string The name of the variable to update
---@param properties table The properties to update (type, required, description)
---@return boolean success
function M.update_preset_variable(preset_name, var_name, properties)
  local presets = load_presets()
  local preset = presets[preset_name]
  if not preset or not preset.variables[var_name] then
    return false
  end

  for k, v in pairs(properties) do
    preset.variables[var_name][k] = v
  end

  return save_presets(presets)
end

return M 