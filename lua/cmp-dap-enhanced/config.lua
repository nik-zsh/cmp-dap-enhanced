-- Configuration module for enhanced cmp-dap
local M = {}

-- Default configuration
M.defaults = {
  log_level = vim.log.levels.INFO,
  enable_logging = true,
  completion_timeout = 5000,
  fallback_enabled = true,
  enable_snippet_completion = true,
  enable_variable_completion = true,
  
  -- Additional buffer types to support
  supported_buffer_types = {
    "dap-repl",
    "dapui_watches",
    "dapui_hover", 
    "dapui_console",
    "dapui_scopes",
    "dapui_stacks",
    "dapui_breakpoints"
  },
  
  -- Debug command completions
  debug_commands = {
    "continue", "step", "next", "finish", "quit", "restart",
    "print", "p", "pp", "info", "help", "backtrace", "bt",
    "up", "down", "frame", "locals", "args", "break", "delete",
    "disable", "enable", "watch", "unwatch"
  },
  
  -- Completion item kinds mapping
  kind_mapping = {
    variable = "Variable",
    ["function"] = "Function", 
    method = "Method",
    field = "Field",
    property = "Property",
    class = "Class",
    interface = "Interface",
    module = "Module",
    unit = "Unit",
    value = "Value",
    enum = "Enum",
    keyword = "Keyword",
    snippet = "Snippet",
    text = "Text",
    file = "File",
    reference = "Reference"
  }
}

function M.setup(user_config)
  return vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

return M
