local nvp_packages = {}
local loaded_nvp_packages = {}
local function nvp_require(name)
  local loaded = loaded_nvp_packages[name]
  if loaded then
    return loaded
  end
  loaded = nvp_packages[name]()
  loaded_nvp_packages[name] = loaded
  return loaded
end

nvp_packages["buffer_store"] = function()
local rawget = rawget
local rawset = rawset

return function(vim)
  assert(vim)
  local api = assert(vim.api)
  local nvim_command = assert(api.nvim_command)
  local nvim_get_current_buf = assert(api.nvim_get_current_buf)
  local nvim_buf_attach = assert(api.nvim_buf_attach)
  local nvim_buf_is_valid = assert(api.nvim_buf_is_valid)
  local nvim_buf_clear_namespace = assert(api.nvim_buf_clear_namespace)

  local function normalize_bufnr(bufnr)
    if bufnr == nil or bufnr == 0 then
      return nvim_get_current_buf()
    end
    return bufnr
  end

  -- do
  --   local prev = nvim_buf_clear_namespace
  --   nvim_buf_clear_namespace = function(bufnr, ns_id, line_start, line_end)
  --   end
  -- end

  local function buffer_local_map()
    return setmetatable({}, {
      __index = function(t, bufnr)
        bufnr = normalize_bufnr(bufnr)
        if not nvim_buf_is_valid(bufnr) then
          return
        end
        local bt = {}
        rawset(t, bufnr, bt)
        nvim_buf_attach(bufnr, false, {
          on_detach = function(_, bufnr)
            rawset(t, bufnr, nil)
          end
        })
        return bt
      end
    })
  end

  -- This is to avoid having reloads affect the storage of variables.
  -- It could be stored on `vim`, but I would rather not pollute it.
  -- Also storing a local variable in this module is less persistent than a global variable.
  ASHKAN_NEOVIM_PLUGIN_BUFFER_STORE_DB = ASHKAN_NEOVIM_PLUGIN_BUFFER_STORE_DB or buffer_local_map()
  local store = ASHKAN_NEOVIM_PLUGIN_BUFFER_STORE_DB

  local function buffer_store(bufnr, namespace)
    local buffer_table = store[assert(normalize_bufnr(bufnr))]
    if namespace and buffer_table then
      local subtable = buffer_table[namespace]
      if not subtable then
        subtable = {}
        buffer_table[namespace] = subtable
      end
      return subtable
    end
    return buffer_table
  end

  vim.buffer_store = buffer_store

  return buffer_store
end

end
nvp_packages["validate"] = function()
local type_names = {
  t='table', s='string', n='number', b='boolean', f='function', c='callable',
  ['table']='table', ['string']='string', ['number']='number',
  ['boolean']='boolean', ['function']='function', ['callable']='callable',
  ['nil']='nil', ['thread']='thread', ['userdata']='userdata',
}

local function error_out(key, expected_type, input_type)
  if type(expected_type) == 'table' then
    expected_type = table.concat(expected_type, ' or ')
  end
  error(string.format("validation_failed: %q: expected %s, received %s", key, expected_type, input_type))
end

local function validate_one(value, expected_type, optional)
  if optional and value == nil then
    return true
  end
  local input_type = type(value)
  expected_type = type_names[expected_type] or error(("validate: Invalid expected type specified: %q"):format(expected_type))
  return input_type == expected_type
end

local function validate_many(value, expected_type, optional)
  for _, ty in ipairs(expected_type) do
    if validate_one(value, ty, optional) then
      return true
    end
  end
  return false
end

local function validate(conf)
  assert(type(conf) == 'table')
  for key, v in pairs(conf) do
    local optional = v[3]
    local expected_type = v[2]
    local value = v[1]
    local validate_fn = type(expected_type) == 'table' and validate_many or validate_one
    if not validate_fn(value, expected_type, optional) then
      error_out(key, expected_type, type(value))
    end
  end
  return true
end

return validate

end
nvp_packages["apply_commands"] = function()
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
  local buffer_store = nvp_require("buffer_store")(vim)
  -- TODO(ashkan): pass vim in.
  -- TODO(ashkan): only required for repeat#set
  local nvim = nvp_require("nvim")
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

end
nvp_packages["nvim"] = function()
-- Bring vim into local scope.
local vim = vim
local api = vim.api
local inspect = vim.inspect

-- Equivalent to `echo vim.inspect(...)`
local function nvim_print(...)
  if select("#", ...) == 1 then
    api.nvim_out_write(inspect((...)))
  else
    api.nvim_out_write(inspect {...})
  end
  api.nvim_out_write("\n")
end

--- Equivalent to `echo` EX command
local function nvim_echo(...)
  for i = 1, select("#", ...) do
    local part = select(i, ...)
    api.nvim_out_write(tostring(part))
    -- vim.api.nvim_out_write("\n")
    api.nvim_out_write(" ")
  end
  api.nvim_out_write("\n")
end

local window_options = {
            arab = true;       arabic = true;   breakindent = true; breakindentopt = true;
             bri = true;       briopt = true;            cc = true;           cocu = true;
            cole = true;  colorcolumn = true; concealcursor = true;   conceallevel = true;
             crb = true;          cuc = true;           cul = true;     cursorbind = true;
    cursorcolumn = true;   cursorline = true;          diff = true;            fcs = true;
             fdc = true;          fde = true;           fdi = true;            fdl = true;
             fdm = true;          fdn = true;           fdt = true;            fen = true;
       fillchars = true;          fml = true;           fmr = true;     foldcolumn = true;
      foldenable = true;     foldexpr = true;    foldignore = true;      foldlevel = true;
      foldmarker = true;   foldmethod = true;  foldminlines = true;    foldnestmax = true;
        foldtext = true;          lbr = true;           lcs = true;      linebreak = true;
            list = true;    listchars = true;            nu = true;         number = true;
     numberwidth = true;          nuw = true; previewwindow = true;            pvw = true;
  relativenumber = true;    rightleft = true;  rightleftcmd = true;             rl = true;
             rlc = true;          rnu = true;           scb = true;            scl = true;
             scr = true;       scroll = true;    scrollbind = true;     signcolumn = true;
           spell = true;   statusline = true;           stl = true;            wfh = true;
             wfw = true;        winbl = true;      winblend = true;   winfixheight = true;
     winfixwidth = true; winhighlight = true;         winhl = true;           wrap = true;
}

local function validate(conf)
  assert(type(conf) == 'table')
  local type_names = {
    t='table', s='string', n='number', b='boolean', f='function', c='callable',
    ['table']='table', ['string']='string', ['number']='number',
    ['boolean']='boolean', ['function']='function', ['callable']='callable',
    ['nil']='nil', ['thread']='thread', ['userdata']='userdata',
  }
  for k, v in pairs(conf) do
    if not (v[3] and v[1] == nil) and type(v[1]) ~= type_names[v[2]] then
      error(string.format("validation_failed: %q: expected %s, received %s", k, type_names[v[2]], type(v[1])))
    end
  end
  return true
end

local function make_meta_accessor(get, set, del)
  validate {
    get = {get, 'f'};
    set = {set, 'f'};
    del = {del, 'f', true};
  }
  local mt = {}
  if del then
    function mt:__newindex(k, v)
      if v == nil then
        return del(k)
      end
      return set(k, v)
    end
  else
    function mt:__newindex(k, v)
      return set(k, v)
    end
  end
  function mt:__index(k)
    return get(k)
  end
  return setmetatable({}, mt)
end

local function pcall_ret(status, ...)
  if status then return ... end
end

local function nil_wrap(fn)
  return function(...)
    return pcall_ret(pcall(fn, ...))
  end
end

local fn = setmetatable({}, {
  __index = function(t, k)
    local f = function(...) return api.nvim_call_function(k, {...}) end
    rawset(t, k, f)
    return f
  end
})

local function getenv(k)
  local v = fn.getenv(k)
  if v == vim.NIL then
    return nil
  end
  return v
end

local function new_win_accessor(winnr)
  local function get(k)
    if winnr == nil and type(k) == 'number' then
      return new_win_accessor(k)
    end
    return api.nvim_win_get_var(winnr or 0, k)
  end
  local function set(k, v) return api.nvim_win_set_var(winnr or 0, k, v) end
  local function del(k)    return api.nvim_win_del_var(winnr or 0, k) end
  return make_meta_accessor(nil_wrap(get), set, del)
end

local function new_win_opt_accessor(winnr)
  local function get(k)
    if winnr == nil and type(k) == 'number' then
      return new_win_opt_accessor(k)
    end
    return api.nvim_win_get_option(winnr or 0, k)
  end
  local function set(k, v) return api.nvim_win_set_option(winnr or 0, k, v) end
  return make_meta_accessor(nil_wrap(get), set)
end

local function new_buf_accessor(bufnr)
  local function get(k)
    if bufnr == nil and type(k) == 'number' then
      return new_buf_accessor(k)
    end
    return api.nvim_buf_get_var(bufnr or 0, k)
  end
  local function set(k, v) return api.nvim_buf_set_var(bufnr or 0, k, v) end
  local function del(k)    return api.nvim_buf_del_var(bufnr or 0, k) end
  return make_meta_accessor(nil_wrap(get), set, del)
end

local function new_buf_opt_accessor(bufnr)
  local function get(k)
    if window_options[k] then
      return api.nvim_err_writeln(k.." is a window option, not a buffer option")
    end
    if bufnr == nil and type(k) == 'number' then
      return new_buf_opt_accessor(k)
    end
    return api.nvim_buf_get_option(bufnr or 0, k)
  end
  local function set(k, v)
    if window_options[k] then
      return api.nvim_err_writeln(k.." is a window option, not a buffer option")
    end
    return api.nvim_buf_set_option(bufnr or 0, k, v)
  end
  return make_meta_accessor(nil_wrap(get), set)
end

-- `nvim.$method(...)` redirects to `nvim.api.nvim_$method(...)`
-- `nvim.fn.$method(...)` redirects to `vim.api.nvim_call_function($method, {...})`
-- TODO `nvim.ex.$command(...)` is approximately `:$command {...}.join(" ")`
-- `nvim.print(...)` is approximately `echo vim.inspect(...)`
-- `nvim.echo(...)` is approximately `echo table.concat({...}, '\n')`
-- Both methods cache the inital lookup in the metatable, but there is api small overhead regardless.
return setmetatable({
  print = nvim_print;
  echo = nvim_echo;
  fn = rawget(vim, "fn") or fn;
  validate = validate;
  g = rawget(vim, 'g') or make_meta_accessor(nil_wrap(api.nvim_get_var), api.nvim_set_var, api.nvim_del_var);
  v = rawget(vim, 'v') or make_meta_accessor(nil_wrap(api.nvim_get_vvar), api.nvim_set_vvar);
  o = rawget(vim, 'o') or make_meta_accessor(api.nvim_get_option, api.nvim_set_option);
  w = new_win_accessor(nil);
  b = new_buf_accessor(nil);
  env = rawget(vim, "env") or make_meta_accessor(getenv, fn.setenv);
  wo = rawget(vim, "wo") or new_win_opt_accessor(nil);
  bo = rawget(vim, "bo") or new_buf_opt_accessor(nil);
  buf = {
    line = api.nvim_get_current_line;
    nr = api.nvim_get_current_buf;
  };
  ex = setmetatable({}, {
    __index = function(t, k)
      local command = k:gsub("_$", "!")
      local f = function(...)
        return api.nvim_command(table.concat(vim.tbl_flatten {command, ...}, " "))
      end
      rawset(t, k, f)
      return f
    end
  });
}, {
  __index = function(t, k)
    local f = api['nvim_'..k]
    if f then
      rawset(t, k, f)
    end
    return f
  end
})
-- vim:et ts=2 sw=2



end
nvp_packages["mergein"] = function()
return function(res, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do
      rawset(res, k, v)
      -- res[k] = v
    end
  end
  return res
end

end
nvp_packages["defaultdict"] = function()
local function defaultdict(default_fn)
  assert(default_fn)
	return setmetatable({}, {
		__index = function(t, key)
			local value = default_fn(key)
			rawset(t, key, value)
			return value
		end;
	})
end
return defaultdict

end
nvp_packages["extend"] = function()
return function(r, ...)
  for i = 1, select("#", ...) do
    for _, v in ipairs((select(i, ...))) do
      r[#r+1] = v
    end
  end
  return r
end

end
nvp_packages["apply_mappings"] = function()
-- local extend = nvp_require("extend")
local byte = string.byte
local mergein = nvp_require("mergein")
local validate = nvp_require("validate")
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
  -- local buffer_store = nvp_require("buffer_store")(vim)

  -- TODO(ashkan): pass vim in.
  -- TODO(ashkan): only required for repeat#set
  local nvim = nvp_require("nvim")

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

end
local plugin_key = {}
local buffer_store = nvp_require("buffer_store")
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
  local apply_mappings = nvp_require("apply_mappings")(vim)
  local apply_commands = nvp_require("apply_commands")(vim)
  local validate = nvp_require("validate")
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


