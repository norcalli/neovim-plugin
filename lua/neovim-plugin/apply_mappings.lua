-- local extend = require 'neovim-plugin/extend'
local byte = string.byte
local mergein = require 'neovim-plugin/mergein'
local validate = require 'neovim-plugin/validate'
local format = string.format

local buffer_local_key = 'neovim-plugin-keys'
local vim_key_store_key = '_plugin_keys'

local valid_modes = {
	n = 'n'; v = 'v'; x = 'x'; i = 'i';
	o = 'o'; t = 't'; c = 'c'; s = 's';
	-- :map! and :map
	['!'] = '!'; [' '] = '';
}

local valid_built_in_options = {
  expr = 'b';
  noremap = 'b';
  nowait = 'b';
  script = 'b';
  silent = 'b';
  unique = 'b';
}

local valid_options = {
  -- Built-in options
  expr = 'b';
  noremap = 'b';
  nowait = 'b';
  script = 'b';
  silent = 'b';
  unique = 'b';

  -- Extensions
  buffer = { 'n', 'b' };
  dot_repeat = 'b';

  -- text_operator = 'b';
  -- text_object = 'b';
}

local function escape_keymap(key)
	-- Prepend with a letter so it can be used as a dictionary key
	return 'k'..key:gsub('.', byte)
end

local function validate_option_keywords(options, validation_prefix)
  local validated = {}
  for option_name, expected_type in pairs(valid_options) do
    local value = options[option_name]
    if value then
      validate {
        [validation_prefix.."."..option_name] = { value, expected_type };
      }
      validated[option_name] = value
    end
  end
  return validated
end

return function(vim)
  assert(vim)
  local api = assert(vim.api)
  local nvim_get_current_buf = assert(api.nvim_get_current_buf)
  local nvim_buf_set_keymap = assert(api.nvim_buf_set_keymap)
  local nvim_set_keymap = assert(api.nvim_set_keymap)
  local nvim_replace_termcodes = assert(api.nvim_replace_termcodes)

  -- TODO(ashkan): Fill this in.
  local function has_tpope_dot_repeat()
    return true
  end

  local buffer_store = assert(vim.buffer_store)
  -- local buffer_store = require 'neovim-plugin/buffer_store'(vim)

  -- TODO(ashkan): pass vim in.
  -- TODO(ashkan): only required for repeat#set
  local nvim = require 'neovim-plugin/nvim'

  -- This is where we'll store our keys. It's a workaround for
  -- lack of builtin support for using lua keys. The name is meant
  -- to be unique enough not to conflict with anyone else.
  vim[vim_key_store_key] = vim[vim_key_store_key] or {}
  local key_store = vim[vim_key_store_key]
  -- ASHKAN_NEOVIM_PLUGIN_KEYS = ASHKAN_NEOVIM_PLUGIN_KEYS or {}
  -- local key_store = ASHKAN_NEOVIM_PLUGIN_KEYS

  -- TODO(ashkan): @feature Disable noremap if the rhs starts with <Plug>
  -- TODO(ashkan): Add "text_operator = true" and "text_object = true"
  local function nvim_apply_mappings(mappings, user_default_options)
    validate {
      mappings = { mappings, 't' };
      user_default_options = { user_default_options, 't', true };
    }
    local default_options = {}
    if user_default_options then
      default_options = validate_option_keywords(user_default_options, "default_options")
    end
    -- TODO:
    --  check for dupes.
    --    - ashkan, Fri 28 Aug 2020 12:52:45 AM JST
    mergein(default_options, validate_option_keywords(mappings, 'mappings'))

    -- May or may not be used.
    local current_bufnr = nvim_get_current_buf()
    for key, options in pairs(mappings) do
      -- Skip any inline default keywords.
      repeat
        if valid_options[key] then
          break
        end
        local rhs
        if type(options) == 'function' then
          rhs = options
          options = {}
        elseif type(options) == 'string' then
          rhs = options
          options = {}
        elseif type(options) == 'table' then
          rhs = options[1]
        else
          error(format("Invalid type for option rhs: %q = %s", type(options), vim.inspect(options)))
        end
        -- Clean up the options.
        options = mergein({}, default_options, validate_option_keywords(options, "options"))
        local built_in_options = {}
        for k in pairs(valid_built_in_options) do
          built_in_options[k] = options[k]
        end
        local bufnr = current_bufnr
        -- Protect against specifying 0, since it denotes current buffer in api by convention
        if type(options.buffer) == 'number' and options.buffer ~= 0 then
          bufnr = options.buffer
        end
        local mode, mapping = key:match("^(.)(.+)$")
        if not mode then
          assert(false, "nvim_apply_mappings: invalid mode specified for keymapping "..key)
        end
        if not valid_modes[mode] then
          assert(false, "nvim_apply_mappings: invalid mode specified for keymapping. mode="..mode)
        end
        mode = valid_modes[mode]
        if type(rhs) == 'function' then
          -- Use a value that won't be misinterpreted below since special keys
          -- like <CR> can be in key, and escaping those isn't easy.
          local escaped = escape_keymap(key)
          local key_mapping
          if options.dot_repeat then
            assert(has_tpope_dot_repeat(), "Install tpope/vim-repeat!")
            local key_function = rhs
            rhs = function()
              key_function()
              -- TODO(ashkan): implement my own dot repeat if tpope's isn't available.
              -- I could do it if I figure out how to distinguish between whether the
              -- last mapping executed was one of mine or a built-in one.
              -- if not ASHKAN_NEOVIM_PLUGIN_REPEAT_FUNCTION then
              --   nvim_apply_mappings {
              --     ['n.'] = function()
              --     end;
              --   }
              -- end
              -- ASHKAN_NEOVIM_PLUGIN_REPEAT_FUNCTION = key_function
              nvim.fn["repeat#set"](nvim_replace_termcodes(key_mapping, true, true, true), nvim.v.count)
            end
          end
          if options.buffer then
            buffer_store(bufnr, buffer_local_key)[escaped] = rhs
            -- TODO(ashkan): if v:lua is availble, use that? Or if native callbacks are merged.
            key_mapping = ("vim.buffer_store(0, %q).%s()"):format(buffer_local_key, escaped)
          else
            key_store[escaped] = rhs
            key_mapping = ("vim[%q].%s()"):format(vim_key_store_key, escaped)
            -- key_mapping = ("%slua ASHKAN_NEOVIM_PLUGIN_KEYS.%s()<CR>"):format(key_prefix, escaped)
          end
          local key_prefix, key_suffix
          if built_in_options.expr then
            -- TODO(ashkan, 2020-08-15 19:51:36+0900) use v:lua if available?
            -- Use enough ='s to not care about the internals.
            key_prefix = "luaeval [=====["
            key_suffix = "]=====]"
          else
            key_suffix = "<CR>"
            -- <Cmd> doesn't work in visual modes.
    				if mode == "x" or mode == "v" then
    					key_prefix = ":<C-u>lua "
            else
              key_prefix = "<Cmd>lua "
            end
          end
          key_mapping = key_prefix..key_mapping..key_suffix
          rhs = key_mapping
          built_in_options.noremap = true
          built_in_options.silent = true
        end
        if options.buffer then
          pcall(nvim_buf_set_keymap, bufnr, mode, mapping, rhs, built_in_options)
        else
          pcall(nvim_set_keymap, mode, mapping, rhs, built_in_options)
        end
      until true
    end
  end
  return nvim_apply_mappings
end
