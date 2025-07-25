local M = {}

M.providers = setmetatable({}, {
  __index = function(t, k)
    t[k] = {}
    return t[k]
  end,
})

local _provider_cache = {}
local _provider_loading = {}

M.filetype_map = {
  typescript = { "typescript", "typescriptreact" },
  javascript = { "javascript", "javascriptreact" },
  python = { "python" },
  php = { "php" },
  lua = { "lua" },
  go = { "go" },
  rust = { "rust" },
  java = { "java" },
  csharp = { "cs", "csharp" },
  ruby = { "ruby" },
  shell = { "sh", "bash", "zsh" },
  kotlin = { "kotlin", "kt" },
}

local _filetype_provider_map = {}
for provider, filetypes in pairs(M.filetype_map) do
  for _, ft in ipairs(filetypes) do
    _filetype_provider_map[ft] = provider
  end
end

local function load_provider(name)
  -- Validate input
  if not name or type(name) ~= "string" or name == "" then
    vim.notify("Invalid provider name: " .. tostring(name), vim.log.levels.ERROR)
    return nil
  end

  -- Sanitize provider name to prevent path traversal
  local sanitized_name = name:gsub("[^%w_%-]", "")
  if sanitized_name ~= name then
    vim.notify("Provider name contains invalid characters, sanitized: " .. name, vim.log.levels.WARN)
    name = sanitized_name
  end

  if _provider_cache[name] then
    return _provider_cache[name]
  end

  if _provider_loading[name] then
    vim.notify("Circular dependency detected in provider loading: " .. name, vim.log.levels.WARN)
    return nil
  end

  local module_path = "ecolog.providers." .. name
  _provider_loading[name] = true
  local ok, provider = pcall(require, module_path)
  _provider_loading[name] = nil

  if ok then
    -- Validate provider structure
    if not provider or type(provider) ~= "table" then
      vim.notify("Invalid provider structure from: " .. name, vim.log.levels.ERROR)
      return nil
    end

    _provider_cache[name] = provider
    return provider
  else
    vim.notify("Failed to load provider: " .. name .. " - " .. tostring(provider), vim.log.levels.ERROR)
  end
  return nil
end

function M.load_providers_for_filetype(filetype)
  -- Validate input
  if not filetype or type(filetype) ~= "string" or filetype == "" then
    vim.notify("Invalid filetype provided to load_providers_for_filetype: " .. tostring(filetype), vim.log.levels.ERROR)
    return
  end

  local provider_name = _filetype_provider_map[filetype]
  if not provider_name then
    -- This is normal, not all filetypes have providers
    return
  end

  local provider = load_provider(provider_name)
  if not provider then
    vim.notify("Failed to load provider: " .. provider_name, vim.log.levels.WARN)
    return
  end

  -- Use pcall to protect against provider registration errors
  local success, err = pcall(function()
    if type(provider) == "table" then
      if provider.provider then
        -- Single provider wrapped in .provider field
        M.register(provider.provider)
      else
        -- Multiple providers or single provider table
        if #provider > 0 then
          -- Array of providers
          M.register_many(provider)
        else
          -- Single provider table
          M.register(provider)
        end
      end
    else
      vim.notify("Provider has invalid structure: " .. provider_name, vim.log.levels.ERROR)
    end
  end)

  if not success then
    vim.notify("Failed to register provider " .. provider_name .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
end

local _pattern_cache = setmetatable({}, {
  __mode = "k",
})

-- Cache size limit to prevent memory leaks
local MAX_CACHE_SIZE = 100
local _cache_size = 0

-- Add cache cleanup function
function M.cleanup_cache()
  _provider_cache = {}
  _pattern_cache = setmetatable({}, { __mode = "k" })
  _cache_size = 0
end

-- Improved cache cleanup with selective retention
function M.cleanup_cache_selective()
  -- Keep essential providers in cache
  local essential_providers = {
    "lua",
  }

  local new_cache = {}
  for _, provider_name in ipairs(essential_providers) do
    if _provider_cache[provider_name] then
      new_cache[provider_name] = _provider_cache[provider_name]
    end
  end

  _provider_cache = new_cache
  _pattern_cache = setmetatable({}, { __mode = "k" })
  _cache_size = #essential_providers
end

-- Add cache size monitoring
local function check_cache_size()
  _cache_size = _cache_size + 1
  if _cache_size > MAX_CACHE_SIZE then
    vim.notify("Provider cache size limit exceeded, clearing cache", vim.log.levels.WARN)
    M.cleanup_cache_selective()
  end
end

-- Safe wrapper for provider function execution
local function safe_provider_call(provider, func_name, ...)
  if not provider then
    return nil
  end

  local func = provider[func_name]
  if not func or type(func) ~= "function" then
    return nil
  end

  local success, result = pcall(func, ...)
  if not success then
    vim.notify("Provider " .. func_name .. " failed: " .. tostring(result), vim.log.levels.ERROR)
    return nil
  end

  return result
end

-- Wrap provider functions with error boundaries
local function wrap_provider_with_error_boundaries(provider)
  if not provider or type(provider) ~= "table" then
    return provider
  end

  local wrapped = {}

  -- Copy all properties
  for k, v in pairs(provider) do
    wrapped[k] = v
  end

  -- Wrap extract_var function
  if provider.extract_var then
    wrapped.extract_var = function(...)
      return safe_provider_call(provider, "extract_var", ...)
    end
  end

  -- Wrap get_completion_trigger function
  if provider.get_completion_trigger then
    wrapped.get_completion_trigger = function(...)
      return safe_provider_call(provider, "get_completion_trigger", ...)
    end
  end

  return wrapped
end

function M.register(provider)
  -- Comprehensive provider validation
  if not provider or type(provider) ~= "table" then
    vim.notify("Provider must be a table", vim.log.levels.ERROR)
    return false
  end

  local cache_key = provider
  if _pattern_cache[cache_key] ~= nil then
    return _pattern_cache[cache_key]
  end

  -- Validate required fields
  if not provider.pattern or type(provider.pattern) ~= "string" or provider.pattern == "" then
    vim.notify("Provider must have a valid pattern string", vim.log.levels.ERROR)
    _pattern_cache[cache_key] = false
    return false
  end

  if not provider.filetype then
    vim.notify("Provider must have a filetype", vim.log.levels.ERROR)
    _pattern_cache[cache_key] = false
    return false
  end

  if not provider.extract_var or type(provider.extract_var) ~= "function" then
    vim.notify("Provider must have an extract_var function", vim.log.levels.ERROR)
    _pattern_cache[cache_key] = false
    return false
  end

  -- Validate optional fields
  if provider.get_completion_trigger and type(provider.get_completion_trigger) ~= "function" then
    vim.notify("Provider get_completion_trigger must be a function", vim.log.levels.WARN)
  end

  -- Validate pattern complexity to prevent ReDoS
  local pattern_length = #provider.pattern
  if pattern_length > 1000 then
    vim.notify("Provider pattern is too long (>1000 chars), potential ReDoS risk", vim.log.levels.ERROR)
    _pattern_cache[cache_key] = false
    return false
  end

  -- Check for dangerous pattern constructs
  if provider.pattern:find("%(.*%*.*%*.*%)") or provider.pattern:find("%(.*%+.*%+.*%)") then
    vim.notify("Provider pattern contains potentially dangerous constructs", vim.log.levels.WARN)
  end

  -- Validate and normalize filetypes
  local filetypes = type(provider.filetype) == "string" and { provider.filetype } or provider.filetype

  if type(filetypes) ~= "table" then
    vim.notify("Provider filetype must be a string or table", vim.log.levels.ERROR)
    _pattern_cache[cache_key] = false
    return false
  end

  -- Validate each filetype
  for _, ft in ipairs(filetypes) do
    if not ft or type(ft) ~= "string" or ft == "" then
      vim.notify("Invalid filetype in provider: " .. tostring(ft), vim.log.levels.ERROR)
      _pattern_cache[cache_key] = false
      return false
    end

    -- Sanitize filetype
    local sanitized_ft = ft:gsub("[^%w_%-]", "")
    if sanitized_ft ~= ft then
      vim.notify("Filetype contains invalid characters: " .. ft, vim.log.levels.WARN)
      ft = sanitized_ft
    end

    -- Wrap provider with error boundaries before registering
    local wrapped_provider = wrap_provider_with_error_boundaries(provider)

    -- Register provider for this filetype
    M.providers[ft] = M.providers[ft] or {}
    table.insert(M.providers[ft], wrapped_provider)
  end

  _pattern_cache[cache_key] = true
  check_cache_size()
  return true
end

function M.register_many(providers)
  if not providers or type(providers) ~= "table" then
    vim.notify("Providers must be a table", vim.log.levels.ERROR)
    return false
  end

  local success_count = 0
  local total_count = 0

  for _, provider in ipairs(providers) do
    total_count = total_count + 1

    local success, result = pcall(M.register, provider)
    if success and result then
      success_count = success_count + 1
    else
      vim.notify("Failed to register provider " .. total_count .. ": " .. tostring(result), vim.log.levels.ERROR)
    end
  end

  --[[ if success_count > 0 then
    vim.notify("Successfully registered " .. success_count .. "/" .. total_count .. " providers", vim.log.levels.DEBUG)
  end
]]
  return success_count == total_count
end

function M.get_providers(filetype)
  -- Validate input
  if not filetype or type(filetype) ~= "string" or filetype == "" then
    vim.notify("Invalid filetype provided to get_providers: " .. tostring(filetype), vim.log.levels.ERROR)
    return {}
  end

  -- Sanitize filetype
  local sanitized_ft = filetype:gsub("[^%w_%-]", "")
  if sanitized_ft ~= filetype then
    vim.notify("Filetype contains invalid characters: " .. filetype, vim.log.levels.WARN)
    filetype = sanitized_ft
  end

  -- Load providers if not already loaded
  if not M.providers[filetype] or #M.providers[filetype] == 0 then
    local success, err = pcall(M.load_providers_for_filetype, filetype)
    if not success then
      vim.notify("Failed to load providers for filetype " .. filetype .. ": " .. tostring(err), vim.log.levels.ERROR)
      return {}
    end
  end

  -- Return providers or empty table if none found
  return M.providers[filetype] or {}
end

-- Public function to safely execute provider functions
function M.safe_execute_provider(provider, func_name, ...)
  return safe_provider_call(provider, func_name, ...)
end

-- Function to test if a provider is valid and functional
function M.test_provider(provider)
  if not provider or type(provider) ~= "table" then
    return false, "Provider is not a table"
  end

  -- Test required fields
  if not provider.pattern or type(provider.pattern) ~= "string" then
    return false, "Invalid pattern"
  end

  if not provider.filetype then
    return false, "Missing filetype"
  end

  if not provider.extract_var or type(provider.extract_var) ~= "function" then
    return false, "Missing extract_var function"
  end

  -- Test extract_var function with safe inputs
  local success, result = pcall(provider.extract_var, "test_line", 5)
  if not success then
    return false, "extract_var function failed: " .. tostring(result)
  end

  -- Test get_completion_trigger if present
  if provider.get_completion_trigger then
    if type(provider.get_completion_trigger) ~= "function" then
      return false, "get_completion_trigger is not a function"
    end

    local trigger_success, trigger_result = pcall(provider.get_completion_trigger)
    if not trigger_success then
      return false, "get_completion_trigger failed: " .. tostring(trigger_result)
    end
  end

  return true, "Provider is valid"
end

return M
