-- Enhanced cmp-dap: Improved nvim-cmp source for nvim-dap REPL and buffers
-- Author: Assistant
-- Version: 2.0.0
-- Description: An updated and robust cmp-dap plugin with better error handling and features

local M = {}

-- Plugin configuration defaults
local config = {
  log_level = vim.log.levels.INFO,
  enable_logging = true,
  completion_timeout = 5000,
  fallback_enabled = true,
  enable_snippet_completion = true,
  enable_variable_completion = true,
}

-- Logging utility
local function log(level, msg)
  if config.enable_logging and level >= config.log_level then
    vim.notify(string.format("[cmp-dap] %s", msg), level, { title = "cmp-dap" })
  end
end

-- Check if we are in a DAP buffer
function M.is_dap_buffer()
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = 0 })
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })
  local bufname = vim.api.nvim_buf_get_name(0)
  
  -- Check buffer type and filetype
  if buftype == "prompt" then
    return filetype == "dap-repl" or 
           filetype == "dapui_watches" or 
           filetype == "dapui_hover" or
           filetype == "dapui_console" or
           filetype == "dapui_scopes"
  end
  
  -- Check buffer name patterns
  return bufname:match("DAP") or bufname:match("dap%-repl")
end

-- Enhanced DAP session validation
local function get_dap_session()
  local ok, dap = pcall(require, "dap")
  if not ok then
    log(vim.log.levels.WARN, "nvim-dap not available")
    return nil
  end
  
  local session = dap.session()
  if not session then
    log(vim.log.levels.DEBUG, "No active DAP session")
    return nil
  end
  
  if not session.capabilities then
    log(vim.log.levels.WARN, "DAP session has no capabilities")
    return nil
  end
  
  return session
end

-- Check if completion requests are supported
local function supports_completion_requests()
  local session = get_dap_session()
  if not session then return false end
  
  return session.capabilities.supportsCompletionsRequest == true
end

-- Get current context for completion
local function get_completion_context()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before_cursor = string.sub(line, 1, col)
  
  return {
    line = line,
    column = col,
    before_cursor = before_cursor,
    text = before_cursor
  }
end

-- Enhanced completion source
local source = {}

function source:new()
  local self = setmetatable({}, { __index = source })
  self.id = "dap"
  return self
end

function source:get_debug_name()
  return "DAP completion source"
end

function source:is_available()
  return M.is_dap_buffer()
end

-- Get trigger characters from DAP session
function source:get_trigger_characters()
  local session = get_dap_session()
  if session and session.capabilities and session.capabilities.completionTriggerCharacters then
    return session.capabilities.completionTriggerCharacters
  end
  -- Default trigger characters for common debugging scenarios
  return { ".", "[", "(", " " }
end

-- Main completion function with enhanced error handling
function source:complete(params, callback)
  if not self:is_available() then
    log(vim.log.levels.DEBUG, "Not in DAP buffer, skipping completion")
    callback({ items = {}, isIncomplete = false })
    return
  end
  
  if not supports_completion_requests() then
    log(vim.log.levels.DEBUG, "DAP adapter does not support completion requests")
    
    if config.fallback_enabled then
      -- Provide basic fallback completions
      local fallback_items = self:get_fallback_completions(params)
      callback({ items = fallback_items, isIncomplete = false })
    else
      callback({ items = {}, isIncomplete = false })
    end
    return
  end
  
  local session = get_dap_session()
  local context = get_completion_context()
  
  -- Request completion from DAP
  local completion_request = {
    frameId = session.current_frame and session.current_frame.id or nil,
    text = context.before_cursor,
    column = context.column,
    line = vim.fn.line('.') - 1  -- DAP uses 0-based line numbers
  }
  
  log(vim.log.levels.DEBUG, string.format("Requesting completion: %s", vim.inspect(completion_request)))
  
  -- Set up timeout
  local timer = vim.loop.new_timer()
  local completed = false
  
  timer:start(config.completion_timeout, 0, function()
    if not completed then
      completed = true
      timer:stop()
      timer:close()
      log(vim.log.levels.WARN, "DAP completion request timed out")
      callback({ items = {}, isIncomplete = true })
    end
  end)
  
  -- Make the DAP completion request
  session:request("completions", completion_request, function(err, response)
    if completed then return end
    completed = true
    
    timer:stop()
    timer:close()
    
    if err then
      log(vim.log.levels.ERROR, string.format("DAP completion error: %s", err.message or vim.inspect(err)))
      
      if config.fallback_enabled then
        local fallback_items = self:get_fallback_completions(params)
        callback({ items = fallback_items, isIncomplete = false })
      else
        callback({ items = {}, isIncomplete = false })
      end
      return
    end
    
    if not response or not response.targets then
      log(vim.log.levels.DEBUG, "No completion targets received")
      callback({ items = {}, isIncomplete = false })
      return
    end
    
    -- Convert DAP completion targets to nvim-cmp items
    local items = {}
    for _, target in ipairs(response.targets) do
      table.insert(items, self:convert_dap_item(target))
    end
    
    log(vim.log.levels.DEBUG, string.format("Received %d completion items", #items))
    callback({ 
      items = items, 
      isIncomplete = false 
    })
  end)
end

-- Convert DAP completion item to nvim-cmp format
function source:convert_dap_item(dap_item)
  local item = {
    label = dap_item.label or dap_item.text or "",
    kind = self:get_completion_kind(dap_item.type),
    detail = dap_item.detail,
    documentation = dap_item.documentation,
    sortText = dap_item.sortText,
    filterText = dap_item.filterText or dap_item.label,
    insertText = dap_item.text or dap_item.label,
  }
  
  -- Handle snippet completion if enabled
  if config.enable_snippet_completion and dap_item.text and dap_item.text:find("%$") then
    item.insertTextFormat = 2  -- Snippet format
  end
  
  return item
end

-- Map DAP completion types to nvim-cmp kinds
function source:get_completion_kind(dap_type)
  local cmp = require("cmp")
  local kind_map = {
    method = cmp.lsp.CompletionItemKind.Method,
    ["function"] = cmp.lsp.CompletionItemKind.Function,
    constructor = cmp.lsp.CompletionItemKind.Constructor,
    field = cmp.lsp.CompletionItemKind.Field,
    variable = cmp.lsp.CompletionItemKind.Variable,
    class = cmp.lsp.CompletionItemKind.Class,
    interface = cmp.lsp.CompletionItemKind.Interface,
    module = cmp.lsp.CompletionItemKind.Module,
    property = cmp.lsp.CompletionItemKind.Property,
    unit = cmp.lsp.CompletionItemKind.Unit,
    value = cmp.lsp.CompletionItemKind.Value,
    enum = cmp.lsp.CompletionItemKind.Enum,
    keyword = cmp.lsp.CompletionItemKind.Keyword,
    snippet = cmp.lsp.CompletionItemKind.Snippet,
    text = cmp.lsp.CompletionItemKind.Text,
    file = cmp.lsp.CompletionItemKind.File,
    reference = cmp.lsp.CompletionItemKind.Reference,
  }
  
  return kind_map[dap_type] or cmp.lsp.CompletionItemKind.Variable
end

-- Enhanced fallback completions
function source:get_fallback_completions(params)
  if not config.fallback_enabled then
    return {}
  end
  
  local items = {}
  local context = get_completion_context()
  
  -- Add common debugging keywords
  local debug_keywords = {
    "continue", "step", "next", "finish", "quit", "restart",
    "print", "p", "pp", "info", "help", "backtrace", "bt",
    "up", "down", "frame", "locals", "args"
  }
  
  for _, keyword in ipairs(debug_keywords) do
    if keyword:find("^" .. vim.pesc(context.before_cursor)) then
      table.insert(items, {
        label = keyword,
        kind = require("cmp").lsp.CompletionItemKind.Keyword,
        detail = "Debug command",
        insertText = keyword
      })
    end
  end
  
  -- Add variable completions if enabled
  if config.enable_variable_completion then
    local var_items = self:get_variable_completions()
    vim.list_extend(items, var_items)
  end
  
  return items
end

-- Get variable completions from current scope
function source:get_variable_completions()
  local items = {}
  local session = get_dap_session()
  
  if not session or not session.current_frame then
    return items
  end
  
  -- Try to get variables from scopes
  pcall(function()
    session:request("scopes", { frameId = session.current_frame.id }, function(err, response)
      if err or not response or not response.scopes then
        return
      end
      
      for _, scope in ipairs(response.scopes) do
        session:request("variables", { variablesReference = scope.variablesReference }, function(var_err, var_response)
          if var_err or not var_response or not var_response.variables then
            return
          end
          
          for _, var in ipairs(var_response.variables) do
            table.insert(items, {
              label = var.name,
              kind = require("cmp").lsp.CompletionItemKind.Variable,
              detail = var.type or "variable",
              documentation = var.value,
              insertText = var.name
            })
          end
        end)
      end
    end)
  end)
  
  return items
end

-- Plugin setup function
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  
  -- Register the source with nvim-cmp
  local ok, cmp = pcall(require, "cmp")
  if not ok then
    log(vim.log.levels.ERROR, "nvim-cmp not found, cannot register source")
    return
  end
  
  cmp.register_source("dap", source:new())
  log(vim.log.levels.INFO, "Enhanced cmp-dap source registered successfully")
end

return M
