-- Health check module for enhanced cmp-dap
local M = {}

function M.check()
  vim.health.start("cmp-dap")
  
  -- Check if nvim-cmp is available
  local cmp_ok, _ = pcall(require, "cmp")
  if cmp_ok then
    vim.health.ok("nvim-cmp is available")
  else
    vim.health.error("nvim-cmp is not available", { 
      "Install nvim-cmp: https://github.com/hrsh7th/nvim-cmp" 
    })
  end
  
  -- Check if nvim-dap is available
  local dap_ok, dap = pcall(require, "dap")
  if dap_ok then
    vim.health.ok("nvim-dap is available")
    
    -- Check if there's an active session
    local session = dap.session()
    if session then
      vim.health.ok("DAP session is active")
      
      -- Check completion support
      if session.capabilities and session.capabilities.supportsCompletionsRequest then
        vim.health.ok("DAP adapter supports completion requests")
      else
        vim.health.warn("DAP adapter does not support completion requests", {
          "Completion will use fallback mode",
          "Check your DAP adapter configuration"
        })
      end
    else
      vim.health.warn("No active DAP session", {
        "Start a debug session to test completion functionality"
      })
    end
  else
    vim.health.error("nvim-dap is not available", {
      "Install nvim-dap: https://github.com/mfussenegger/nvim-dap"
    })
  end
  
  -- Check buffer type
  local is_dap_buffer = require("cmp_dap").is_dap_buffer()
  if is_dap_buffer then
    vim.health.ok("Current buffer is a DAP buffer")
  else
    vim.health.info("Current buffer is not a DAP buffer", {
      "This is normal if you're not currently debugging"
    })
  end
  
  -- Check Neovim version
  if vim.fn.has("nvim-0.8") == 1 then
    vim.health.ok("Neovim version is supported (>= 0.8)")
  else
    vim.health.error("Neovim version is too old", {
      "Upgrade to Neovim 0.8 or later"
    })
  end
end

return M
