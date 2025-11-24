-- File: ~/.config/nvim/lua/user/tenant_feature.lua
--
-- Generic plugin to manage feature flags in multi-tenant Rails systems
--
-- REQUIRED CONFIGURATION:
--
-- require("user.tenant_feature").setup({
--   tenant_model = "Tenant",                    -- REQUIRED
--   tenant_switch_template = "...",             -- REQUIRED
--   enable_command = "...",                     -- REQUIRED
--   disable_command = "...",                    -- REQUIRED
--   check_command = "...",                      -- REQUIRED
--   
--   -- Optional (with defaults):
--   rails_cmd = "bin/rails",                    -- default: "bin/rails"
--   rails_env = "RAILS_ENV=development",        -- default: "RAILS_ENV=development"
--   shell = "/bin/bash",                        -- default: "/bin/bash"
-- })
--
-- Configuration examples:
--
-- For Apartment + MyCompany::Feature:
--   tenant_model = "Tenant"
--   tenant_switch_template = "Apartment::Tenant.switch('%s') do; %s; end"
--   enable_command = "MyCompany::Feature.enable(:%s)"
--   disable_command = "MyCompany::Feature.disable(:%s)"
--   check_command = "puts MyCompany::Feature.enabled?(:%s)"
--
-- For Flipper (without multi-tenant):
--   tenant_model = "User"
--   tenant_switch_template = "%s"
--   enable_command = "Flipper.enable(:%s)"
--   disable_command = "Flipper.disable(:%s)"
--   check_command = "puts Flipper.enabled?(:%s)"
--
-- For ActsAsTenant + Flipper:
--   tenant_model = "Account"
--   tenant_switch_template = "ActsAsTenant.with_tenant(Account.find_by(name: '%s')) do; %s; end"
--   enable_command = "Flipper.enable(:%s)"
--   disable_command = "Flipper.disable(:%s)"
--   check_command = "puts Flipper.enabled?(:%s)"
--
-- Usage:
--   1. Visually select a feature name (viw)
--   2. Press:
--      <leader>fe - Enable feature
--      <leader>fd - Disable feature
--      <leader>fc - Check status
--   3. Select the tenant from the menu
--
local M = {}

-- Configuration (no defaults, requires setup)
local config = nil

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Tenant Feature" })
end

local function check_config()
  if not config then
    notify("Error: tenant_feature is not configured. Call setup() first.", vim.log.levels.ERROR)
    return false
  end

  local required = {
    "tenant_model",
    "tenant_switch_template",
    "enable_command",
    "disable_command",
    "check_command",
  }

  for _, key in ipairs(required) do
    if not config[key] or config[key] == "" then
      notify(
        string.format("Error: configuration '%s' is required but not defined.", key),
        vim.log.levels.ERROR
      )
      return false
    end
  end

  return true
end

local function escape_single_quotes(s)
  return (s or ""):gsub("'", "\\'")
end

local function to_ruby_symbol(feature_text)
  local s = feature_text or ""
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("[%s%p]+", "_"):lower():gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  if s == "" then
    return nil, "Selected text is empty after normalization"
  end
  return s
end

local function get_visual_selection()
  -- Get the positions of the visual selection
  local _, srow, scol = unpack(vim.fn.getpos("'<"))
  local _, erow, ecol = unpack(vim.fn.getpos("'>"))

  -- Validate that we have a selection
  if srow == 0 or erow == 0 then
    return nil, "No visual selection"
  end

  local lines = vim.fn.getline(srow, erow)
  if #lines == 0 then
    return nil, "Empty selection"
  end

  -- Adjust the first and last line according to columns
  if #lines == 1 then
    lines[1] = string.sub(lines[1], scol, ecol)
  else
    lines[#lines] = string.sub(lines[#lines], 1, ecol)
    lines[1] = string.sub(lines[1], scol)
  end

  return table.concat(lines, "\n")
end

local function run_cmd(cmd, on_exit)
  local stdout, stderr = {}, {}
  -- Use bash with login shell to load rbenv and execute from current directory
  local cwd = vim.fn.getcwd()
  local full_cmd = string.format("cd '%s' && %s", cwd, cmd)
  vim.system({ config.shell, "-lc", full_cmd }, {
    text = true,
    stdout = function(_, d)
      if d then
        table.insert(stdout, d)
      end
    end,
    stderr = function(_, d)
      if d then
        table.insert(stderr, d)
      end
    end,
  }, function(res)
    local out = table.concat(stdout, "")
    local err = table.concat(stderr, "")
    if on_exit then
      on_exit(res.code, out, err)
    end
  end)
end

local function fetch_tenants(cb)
  local rails_env_prefix = config.rails_env ~= "" and config.rails_env .. " " or ""
  local runner = rails_env_prefix
    .. config.rails_cmd
    .. ' runner "puts '
    .. config.tenant_model
    .. '.pluck(:name).to_json"'
  run_cmd(runner, function(code, out, err)
    if code ~= 0 then
      return cb(nil, "rails runner failed: " .. (err ~= "" and err or out))
    end
    -- Search for the line containing JSON (array)
    local json_line = nil
    for line in out:gmatch("[^\r\n]+") do
      local trimmed = line:match("^%s*(.-)%s*$")
      -- Look for a line starting with [ (JSON array)
      if trimmed:match("^%[.*%]$") then
        json_line = trimmed
        break
      end
    end

    if not json_line then
      return cb(nil, "JSON not found in output: " .. out)
    end

    -- Parse the JSON
    local ok, tenants = pcall(vim.json.decode, json_line)
    if not ok or type(tenants) ~= "table" then
      return cb(nil, "Could not parse JSON: " .. json_line)
    end

    if #tenants == 0 then
      return cb(nil, "No tenants in array")
    end

    cb(tenants)
  end)
end

local function enable_feature_for_tenant(tenant_name, feature_symbol)
  local tq = escape_single_quotes(tenant_name)
  local fq = escape_single_quotes(feature_symbol)

  -- Build the feature command
  local feature_cmd = string.format(config.enable_command, fq)
  -- Wrap in tenant switch
  local ruby = string.format(config.tenant_switch_template, tq, feature_cmd)

  local rails_env_prefix = config.rails_env ~= "" and config.rails_env .. " " or ""
  local runner = rails_env_prefix .. config.rails_cmd .. ' runner "' .. ruby .. '"'

  notify("Enabling :" .. feature_symbol .. " in '" .. tenant_name .. "'…", vim.log.levels.INFO)

  run_cmd(runner, function(code, out, err)
    vim.schedule(function()
      if code == 0 then
        notify("✓ Feature :" .. feature_symbol .. " enabled in '" .. tenant_name .. "'", vim.log.levels.INFO)
      else
        notify("Error enabling feature: " .. (err ~= "" and err or out), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function disable_feature_for_tenant(tenant_name, feature_symbol)
  local tq = escape_single_quotes(tenant_name)
  local fq = escape_single_quotes(feature_symbol)

  -- Build the feature command
  local feature_cmd = string.format(config.disable_command, fq)
  -- Wrap in tenant switch
  local ruby = string.format(config.tenant_switch_template, tq, feature_cmd)

  local rails_env_prefix = config.rails_env ~= "" and config.rails_env .. " " or ""
  local runner = rails_env_prefix .. config.rails_cmd .. ' runner "' .. ruby .. '"'

  notify("Disabling :" .. feature_symbol .. " in '" .. tenant_name .. "'…", vim.log.levels.INFO)

  run_cmd(runner, function(code, out, err)
    vim.schedule(function()
      if code == 0 then
        notify("✓ Feature :" .. feature_symbol .. " disabled in '" .. tenant_name .. "'", vim.log.levels.INFO)
      else
        notify("Error disabling feature: " .. (err ~= "" and err or out), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function check_feature_status_for_tenant(tenant_name, feature_symbol)
  local tq = escape_single_quotes(tenant_name)
  local fq = escape_single_quotes(feature_symbol)

  -- Build the feature command
  local feature_cmd = string.format(config.check_command, fq)
  -- Wrap in tenant switch
  local ruby = string.format(config.tenant_switch_template, tq, feature_cmd)

  local rails_env_prefix = config.rails_env ~= "" and config.rails_env .. " " or ""
  local runner = rails_env_prefix .. config.rails_cmd .. ' runner "' .. ruby .. '"'

  notify("Checking :" .. feature_symbol .. " in '" .. tenant_name .. "'…", vim.log.levels.INFO)

  run_cmd(runner, function(code, out, err)
    vim.schedule(function()
      if code == 0 then
        -- Look for "true" or "false" in output
        local status = out:match("true") and "enabled" or "disabled"
        local icon = out:match("true") and "✓" or "✗"
        notify(
          icon .. " Feature :" .. feature_symbol .. " is " .. status .. " in '" .. tenant_name .. "'",
          vim.log.levels.INFO
        )
      else
        notify("Error checking feature: " .. (err ~= "" and err or out), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.enable_feature_command()
  if not check_config() then
    return
  end

  local sel, e = get_visual_selection()
  if not sel then
    return notify(e or "No selection", vim.log.levels.ERROR)
  end
  local feature, ferr = to_ruby_symbol(sel)
  if not feature then
    return notify(ferr or "Invalid text", vim.log.levels.ERROR)
  end

  notify("Loading tenants…")
  fetch_tenants(function(tenants, terr)
    vim.schedule(function()
      if not tenants then
        return notify(terr or "Could not fetch tenants", vim.log.levels.ERROR)
      end
      if #tenants == 0 then
        return notify("No tenants", vim.log.levels.WARN)
      end
      vim.ui.select(tenants, { prompt = "Select Tenant to enable :" .. feature }, function(choice)
        if not choice then
          return notify("Cancelled")
        end
        enable_feature_for_tenant(choice, feature)
      end)
    end)
  end)
end

function M.disable_feature_command()
  if not check_config() then
    return
  end

  local sel, e = get_visual_selection()
  if not sel then
    return notify(e or "No selection", vim.log.levels.ERROR)
  end
  local feature, ferr = to_ruby_symbol(sel)
  if not feature then
    return notify(ferr or "Invalid text", vim.log.levels.ERROR)
  end

  notify("Loading tenants…")
  fetch_tenants(function(tenants, terr)
    vim.schedule(function()
      if not tenants then
        return notify(terr or "Could not fetch tenants", vim.log.levels.ERROR)
      end
      if #tenants == 0 then
        return notify("No tenants", vim.log.levels.WARN)
      end
      vim.ui.select(tenants, { prompt = "Select Tenant to disable :" .. feature }, function(choice)
        if not choice then
          return notify("Cancelled")
        end
        disable_feature_for_tenant(choice, feature)
      end)
    end)
  end)
end

function M.check_feature_command()
  if not check_config() then
    return
  end

  local sel, e = get_visual_selection()
  if not sel then
    return notify(e or "No selection", vim.log.levels.ERROR)
  end
  local feature, ferr = to_ruby_symbol(sel)
  if not feature then
    return notify(ferr or "Invalid text", vim.log.levels.ERROR)
  end

  notify("Loading tenants…")
  fetch_tenants(function(tenants, terr)
    vim.schedule(function()
      if not tenants then
        return notify(terr or "Could not fetch tenants", vim.log.levels.ERROR)
      end
      if #tenants == 0 then
        return notify("No tenants", vim.log.levels.WARN)
      end
      vim.ui.select(tenants, { prompt = "Select Tenant to check :" .. feature }, function(choice)
        if not choice then
          return notify("Cancelled")
        end
        check_feature_status_for_tenant(choice, feature)
      end)
    end)
  end)
end

function M.setup(opts)
  opts = opts or {}

  -- Set defaults for Rails
  local defaults = {
    rails_cmd = "bin/rails",
    rails_env = "RAILS_ENV=development",
    shell = "/bin/bash",
  }

  -- Merge defaults with user options
  config = vim.tbl_deep_extend("force", defaults, opts)

  -- Validate configuration immediately
  if not check_config() then
    notify("Could not create commands due to configuration errors.", vim.log.levels.ERROR)
    return
  end

  -- User commands
  vim.api.nvim_create_user_command("EnableFeatureForTenant", function()
    M.enable_feature_command()
  end, {})

  vim.api.nvim_create_user_command("DisableFeatureForTenant", function()
    M.disable_feature_command()
  end, {})

  vim.api.nvim_create_user_command("CheckFeatureForTenant", function()
    M.check_feature_command()
  end, {})

  -- Keymaps
  vim.keymap.set("v", "<leader>fe", function()
    -- Exit visual mode first to update the '< and '> marks
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "x", false)
    vim.schedule(function()
      M.enable_feature_command()
    end)
  end, { silent = true, desc = "Enable feature for tenant" })

  vim.keymap.set("v", "<leader>fd", function()
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "x", false)
    vim.schedule(function()
      M.disable_feature_command()
    end)
  end, { silent = true, desc = "Disable feature for tenant" })

  vim.keymap.set("v", "<leader>fc", function()
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "x", false)
    vim.schedule(function()
      M.check_feature_command()
    end)
  end, { silent = true, desc = "Check feature status for tenant" })
end

return M
