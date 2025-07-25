local M = {}

---Get sorted environment variables based on config.sort_var_fn
---@return table[] List of sorted environment variables
function M.get_sorted_vars()
  local ecolog = require("ecolog")
  local env_vars = ecolog.get_env_vars()
  local config = ecolog.get_config()

  local var_entries = {}
  for name, info in pairs(env_vars) do
    table.insert(var_entries, vim.tbl_extend("force", { name = name }, info))
  end

  if config.sort_var_fn and type(config.sort_var_fn) == "function" then
    table.sort(var_entries, function(a, b)
      return config.sort_var_fn(a, b)
    end)
  end

  return var_entries
end

---Format environment variables for display with masked values
---@param module_name string Name of the calling module (for shelter context)
---@param mask_on_copy boolean Whether to mask values when copying
---@return table[] Formatted environment variables
function M.format_env_vars_for_picker(module_name)
  local shelter = require("ecolog.shelter")
  local utils = require("ecolog.utils")
  local ecolog = require("ecolog")
  local config = ecolog.get_config()
  
  local var_entries = M.get_sorted_vars()

  local result = {}
  for idx, entry in ipairs(var_entries) do
    local masked_value = shelter.mask_value(entry.value, module_name, entry.name, entry.source)
    
    -- Generate display name with workspace context for the source
    local source_display = utils.get_env_file_display_name(entry.source, config)
    
    -- Format: "VAR_NAME (source.env) = value"
    local display = string.format("%-30s (%s) = %s", entry.name, vim.fn.fnamemodify(source_display, ":t"), masked_value)

    table.insert(result, {
      name = entry.name,
      value = entry.value,
      masked_value = masked_value,
      source = entry.source,
      source_display = source_display,
      type = entry.type,
      display = display,
      idx = idx,
    })
  end

  return result
end

return M

