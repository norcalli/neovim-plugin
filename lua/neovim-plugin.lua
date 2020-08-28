local plugin_key = {}
local buffer_store = require 'neovim-plugin/buffer_store'
local format = string.format
local concat = table.concat
local insert = table.insert

local function initialize(vim)
  buffer_store(vim)
  local api = vim.api
  local nvim_buf_attach = api.nvim_buf_attach
  if not NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW then
    NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW_ATTACHERS = {}
    function NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW(bufnr)
      local bufnr = bufnr or tonumber(vim.fn.expand("<abuf>"))
      if bufnr == api.nvim_get_current_buf() then
        local callbacks = NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW_ATTACHERS
        for k, v in pairs(callbacks) do
          if not vim.buffer_store(bufnr, 'neovim-plugin-callback-checks')[k] then
            vim.buffer_store(bufnr, 'neovim-plugin-callback-checks')[k] = true
            -- TODO:
            --  handle err
            --    - ashkan, Thu 27 Aug 2020 11:58:59 PM JST
            local ok, err = pcall(v, bufnr)
          end
        end
        return true
      else
        -- TODO:
        --  hack to work around executing inside of a buffer.
        --    - ashkan, Fri 28 Aug 2020 01:11:15 AM JST
        vim.cmd(format('autocmd BufEnter <buffer=%d> ++once lua NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW()', bufnr))
      end
    end
    vim.cmd 'augroup K_NEOVIM_PLUGIN'
    vim.cmd 'autocmd!'
    -- vim.cmd 'autocmd BufEnter * lua NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW()'
    vim.cmd 'autocmd BufNew * lua NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW()'
    vim.cmd 'augroup K_NEOVIM_PLUGIN'
  end
end

local function validate_exported_functions(lookup_name, lookup, functions)
  local R = {}
  for lhs, rhs in pairs(lookup) do
    local fn_name
    if type(rhs) == 'table' then
      fn_name = rhs[1]
    elseif type(rhs) == 'string' then
      fn_name = rhs
    else
      error(format("Invalid type for %s value: %q", lookup_name, rhs))
    end
    assert(fn_name)
    -- TODO:
    --  callable
    --    - ashkan, Thu 27 Aug 2020 11:50:03 PM JST
    assert(type(functions[fn_name]) == 'function')
    if type(rhs) == 'table' then
      local O = {}
      for k, v in pairs(rhs) do
        O[k] = v
      end
      O[1] = functions[fn_name]
      R[lhs] = O
    elseif type(rhs) == 'string' then
      R[lhs] = functions[fn_name]
    end
  end
  return R
end


return function(vim)
  assert(vim)
  initialize(vim)
  local apply_mappings = require 'neovim-plugin/apply_mappings'(vim)
  local apply_commands = require 'neovim-plugin/apply_commands'(vim)
  local validate = require 'neovim-plugin/validate'
  local api = vim.api

  local M

  local function export(config)
    validate {
      config = { config, 't' };
    }
    validate {
      functions = { config.functions, 't', true };
      mappings = { config.mappings, 't', true };
      commands = { config.commands, 't', true };
      events = { config.events, 't', true };
      attach = { config.attach, 'f', true };
      -- attach = { config.attach, 'c', true };
      setup = { config.setup, 'f', true };
    }
    local mappings = config.mappings
    local commands = config.commands
    local events = config.events
    local setup = config.setup
    local attach = config.attach
    local functions = config.functions

    if mappings then
      assert(functions, "If you are defining mappings, then you need to export the functions on the 'functions' table first")
      mappings = validate_exported_functions('mappings', mappings, functions)
    end
    if commands then
      assert(functions, "If you are defining commands, then you need to export the functions on the 'functions' table first")
      commands = validate_exported_functions('commands', commands, functions)
    end

    -- TODO(ashkan, 2020-08-15 19:13:14+0900) setup signature as setup(vim, config)?

    local function use_defaults(...)
      if setup then setup(...) end
      if mappings then apply_mappings(mappings, mappings) end
      if commands then apply_commands(commands) end
      if events then error("events aren't implemented yet.") end
    end

    if attach then
      local function attacher(bufnr)
        local ok, exported = pcall(attach, bufnr, config)
        if ok and type(exported) == 'table' then
          local buf_functions = exported.functions or {}
          local buf_function_lookup = setmetatable({}, {
            __index = function(_, k)
              return buf_functions[k] or functions[k]
            end
          })
          local commands
          if exported.commands then
            commands = validate_exported_functions(format('buf[%d].commands', bufnr), exported.commands, buf_function_lookup)
            -- Pass the target buffer.
            for k, v in pairs(commands) do
            	if type(v) ~= 'table' then
                v = { v }
              end
              -- TODO:
              --  targetting buffers...
              --    - ashkan, Fri 28 Aug 2020 01:06:22 AM JST
              -- v.buffer = bufnr
              v.buffer = true
              commands[k] = v
            end
          end
          local mappings
          if exported.mappings then
            mappings = validate_exported_functions(format('buf[%d].mappings', bufnr), exported.mappings, buf_function_lookup)
          end
          if mappings then
            -- Pass the default as the target buffer.
            mappings.buffer = bufnr
            local ok, err = pcall(apply_mappings, mappings, mappings)
            if not ok then
              print(err)
            end
          end
          if commands then
            apply_commands(commands)
          end
          -- TODO:
          --  events
          --    - ashkan, Fri 28 Aug 2020 12:11:52 AM JST
        end
      end
      NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW_ATTACHERS[plugin_key] = attacher
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        -- TODO:
        --  hmmm??
        --    - ashkan, Fri 28 Aug 2020 01:25:18 AM JST
        if api.nvim_buf_is_loaded(bufnr) then
          NEOVIM_PLUGIN_COPYRIGHT_2020_BUFNEW(bufnr)
        end
      end
    end

    return {
      mappings = mappings;
      commands = commands;
      events = events;
      setup = setup;
      use_defaults = use_defaults;
      vim = M;
    }
  end

  M = {
    apply_mappings = apply_mappings;
    apply_commands = apply_commands;
    -- TODO(ashkan, 2020-08-15 19:24:25+0900) deleting key support
    -- TODO(ashkan, 2020-08-15 19:24:25+0900) deleting command support
    export = export;
  }

  return M
end

