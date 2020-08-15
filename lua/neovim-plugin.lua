-- return function(vim_obj)
--   local vim = vim_obj or vim
return function(vim)
  assert(vim)
  local apply_mappings = require 'neovim-plugin/apply_mappings'(vim)
  local apply_commands = require 'neovim-plugin/apply_commands'(vim)
  local validate = require 'neovim-plugin/validate'

  local M


  local function export(config)
    validate {
      config = { config, 't' };
    }
    validate {
      mappings = { config.mappings, 't', true };
      commands = { config.commands, 't', true };
      events = { config.events, 't', true };
      setup = { config.setup, 'f', true };
    }
    local mappings = config.mappings
    local commands = config.commands
    local events = config.events
    local setup = config.setup

    -- TODO(ashkan, 2020-08-15 19:13:14+0900) setup signature as setup(vim, config)?

    local function use_defaults(...)
      if setup then setup(...) end
      if mappings then apply_mappings(mappings, mappings) end
      if commands then apply_commands(commands) end
      if events then error("events aren't implemented yet.") end
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

