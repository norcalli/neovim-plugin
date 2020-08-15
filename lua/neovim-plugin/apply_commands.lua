local format = string.format
local concat = table.concat
local insert = table.insert

local buffer_key = 'neovim-plugin-commands'
local vim_command_store_key = '_plugin_commands'

-- TODO(ashkan, Sat 15 Aug 2020 07:05:10 PM JST): full validation.
local function validate_command_name(name)
  if name:find("%s") then
    error(format("Space found in command name, which is invalid: %q", name))
  end
end

return function(vim)
  local buffer_store = require 'neovim-plugin/buffer_store'(vim)
  -- TODO(ashkan): pass vim in.
  -- TODO(ashkan): only required for repeat#set
  local nvim = require 'neovim-plugin/nvim'
  local api = assert(vim.api)
  local nvim_command = assert(api.nvim_command)

  -- This is where we'll store our commands. It's a workaround for
  -- lack of builtin support for using lua commands. The name is meant
  -- to be unique enough not to conflict with anyone else.
  vim[vim_command_store_key] = vim[vim_command_store_key] or {}
  -- ASHKAN_NEOVIM_PLUGIN_COMMANDS = ASHKAN_NEOVIM_PLUGIN_COMMANDS or {}
  -- local command_store = ASHKAN_NEOVIM_PLUGIN_COMMANDS
  local command_store = vim[vim_command_store_key]

  local function nvim_create_commands(commands)
    local curbuf = api.nvim_get_current_buf()
    for cmd_name, cmd_conf in pairs(commands) do
      validate_command_name(cmd_name)
      local parts = {"command!"}

      if type(cmd_conf) == 'string' then
        insert(parts, cmd_name)
        insert(parts, cmd_conf)
      elseif type(cmd_conf) == 'function' then
        command_store[cmd_name] = cmd_conf
        insert(parts, cmd_name)
        insert(parts, format('lua vim[%q][%q](<q-args>)', vim_command_store_key, cmd_name))
        -- insert(parts, format('lua ASHKAN_NEOVIM_PLUGIN_COMMANDS[%q](<q-args>)', cmd_name))
      elseif type(cmd_conf) == 'table' then
        local rhs = cmd_conf[1] or error("No config found at index 1 in command table for "..cmd_name)

        -- TODO(ashkan): validate the key names
        for k, v in pairs(cmd_conf) do
          if type(k) == 'string' then
            if v == true then
              insert(parts, '-'..k)
            elseif type(v) == 'string' then
              insert(parts, '-'..k.."="..v)
            end
          end
        end
        insert(parts, cmd_name)

        if type(rhs) == 'string' then
        elseif type(rhs) == 'function' then
          local args
          args = '(<q-args>, { range = {<line1>,<line2>,<range>}; bang = "<bang>"; count = <count>; register = "<reg>"; })'
          -- if cmd_conf.range then
          --   args = '(<q-args>, { line = <line1>; <line2>)'
          -- else
          --   args = '(<q-args>)'
          -- end
          if cmd_conf.buffer then
            local bufnr = type(cmd_conf.buffer) == 'number' and cmd_conf.buffer or curbuf
            buffer_store(bufnr, buffer_key)[cmd_name] = cmd_conf
            rhs = format('lua vim.buffer_store(0, %q)[%q][1]%s', buffer_key, cmd_name, args)
          else
            command_store[cmd_name] = cmd_conf
            rhs = format('lua vim[%q][%q][1]%s', vim_command_store_key, cmd_name, args)
            -- rhs = format('lua ASHKAN_NEOVIM_PLUGIN_COMMANDS[%q][1]%s', cmd_name, args)
          end
        else
          error(format("Invalid type found for command definition of %q: %s", cmd_name, type(rhs)))
        end
        assert(type(rhs) == 'string')
        insert(parts, rhs)
      end

      nvim_command(concat(parts, ' '))
    end
  end

  return nvim_create_commands
end
