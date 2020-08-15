--- NVIM SPECIFIC SHORTCUTS
local vim = vim
local api = vim.api

local M = {}

VISUAL_MODE = {
	line = "line"; -- linewise
	block = "block"; -- characterwise
	char = "char"; -- blockwise-visual
}

-- TODO I didn't know that api.nvim_buf_* methods could take 0 to signify the
-- current buffer, so refactor potentially everything to avoid the call to
-- api.nvim_get_current_buf

-- An enhanced version of nvim_buf_get_mark which also accepts:
-- - A number as input: which is taken as a line number.
-- - A pair, which is validated and passed through otherwise.
function M.nvim_mark_or_index(buf, input)
	if type(input) == 'number' then
		-- TODO how to handle column? It would really depend on whether this was the opening mark or ending mark
		-- It also doesn't matter as long as the functions are respecting the mode for transformations
		assert(input ~= 0, "Line number must be >= 1 or <= -1 for last line(s)")
		return {input, 0}
	elseif type(input) == 'table' then
		-- TODO Further validation?
		assert(#input == 2)
		assert(input[1] >= 1)
		return input
	elseif type(input) == 'string' then
		return api.nvim_buf_get_mark(buf, input)
		-- local result = api.nvim_buf_get_mark(buf, input)
		-- if result[2] == 2147483647 then
		-- 	result[2] = -1
		-- end
		-- return result
	end
	error(("nvim_mark_or_index: Invalid input buf=%q, input=%q"):format(buf, input))
end

-- TODO should I be wary of `&selection` in the nvim_buf_get functions?
--[[
" https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript
function! s:get_visual_selection()
		" Why is this not a built-in Vim script function?!
		let [line_start, column_start] = getpos("'<")[1:2]
		let [line_end, column_end] = getpos("'>")[1:2]
		let lines = getline(line_start, line_end)
		if len(lines) == 0
				return ''
		endif
		let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
		let lines[0] = lines[0][column_start - 1:]
		return join(lines, "\n")
endfunction
--]]

local function cmp_pos(a, b)
  local ka = a[1]
  local kb = b[1]
  if (ka ~= kb) then
    return (ka < kb)
  else
    local ka = a[2]
    local kb = b[2]
    if (ka ~= kb) then
      return (ka < kb)
    else
      return false
    end
  end
end

function M.nvim_visual_region()
  local start = api.nvim_win_get_cursor(0)
  local finish = vim.fn.getpos 'v'
  local finish = {finish[2], finish[3]-1}
  if cmp_pos(start, finish) then
    return start, finish
  else
    return finish, start
  end
end

--- Return the lines of the selection, respecting selection modes.
-- RETURNS: table
function M.nvim_buf_get_region_lines(buf, mark_a, mark_b, mode)
	mode = mode or VISUAL_MODE.char
	buf = buf or api.nvim_get_current_buf()

	local start = M.nvim_mark_or_index(buf, mark_a)
  local finish = M.nvim_mark_or_index(buf, mark_b)
  local lines = api.nvim_buf_get_lines(buf, start[1] - 1, finish[1], false)

	if mode == VISUAL_MODE.line then
		return lines
	end

	if mode == VISUAL_MODE.char then
		-- Order is important. Truncate the end first, because these are not commutative
		if finish[2] ~= 2147483647 then
			lines[#lines] = lines[#lines]:sub(1, finish[2] + 1)
		end
		if start[2] ~= 0 then
			lines[1] = lines[1]:sub(start[2] + 1)
		end
		return lines
	end

	local firstcol = start[2] + 1
	local lastcol = finish[2]
	if lastcol == 2147483647 then
		lastcol = -1
	else
		lastcol = lastcol + 1
	end
	for i, line in ipairs(lines) do
		lines[i] = line:sub(firstcol, lastcol)
	end
	return lines
end

function M.nvim_buf_set_region_lines(buf, mark_a, mark_b, mode, lines)
	buf = buf or api.nvim_get_current_buf()

	assert(mode == VISUAL_MODE.line, "Other modes aren't supported yet")

	local start = M.nvim_mark_or_index(buf, mark_a)
	local finish = M.nvim_mark_or_index(buf, mark_b)

  return api.nvim_buf_set_lines(buf, start[1] - 1, finish[1], false, lines)
end

-- This is actually more efficient if what you're doing is modifying a region
-- because it can save api calls.
-- It's also the only way to do transformations that are correct with `char` mode
-- since it has to have access to the initial values of the region lines.
function M.nvim_buf_transform_region_lines(buf, mark_a, mark_b, mode, fn)
	buf = buf or api.nvim_get_current_buf()

	local start = M.nvim_mark_or_index(buf, mark_a)
	local finish = M.nvim_mark_or_index(buf, mark_b)

	assert(start and finish)

	-- TODO contemplate passing in a function instead of lines as is.
	-- local lines
	-- local function lazy_lines()
	-- 	if not lines then
	-- 		lines = api.nvim_buf_get_lines(buf, start[1] - 1, finish[1], false)
	-- 	end
	-- 	return lines
	-- end

	local lines = api.nvim_buf_get_lines(buf, start[1] - 1, finish[1], false)

	local result
	if mode == VISUAL_MODE.char then
		local prefix = ""
		local suffix = ""
		-- Order is important. Truncate the end first, because these are not commutative
		-- TODO file a bug report about this, it's probably supposed to be -1
		if finish[2] ~= 2147483647 then
			suffix = lines[#lines]:sub(finish[2]+2)
			lines[#lines] = lines[#lines]:sub(1, finish[2] + 1)
		end
		if start[2] ~= 0 then
			prefix = lines[1]:sub(1, start[2])
			lines[1] = lines[1]:sub(start[2] + 1)
		end
		result = fn(lines, mode)

		-- If I take the result being nil as leaving it unmodified, then I can use it
		-- to skip the set part and reuse this just to get fed the input.
		if result == nil then
			return
		end

		-- Sane defaults, assume that they want to erase things if it is empty
		if #result == 0 then
			result = {""}
		end

		-- Order is important. Truncate the end first, because these are not commutative
		-- TODO file a bug report about this, it's probably supposed to be -1
		if finish[2] ~= 2147483647 then
			result[#result] = result[#result]..suffix
		end
		if start[2] ~= 0 then
			result[1] = prefix..result[1]
		end
	elseif mode == VISUAL_MODE.line then
		result = fn(lines, mode)
		-- If I take the result being nil as leaving it unmodified, then I can use it
		-- to skip the set part and reuse this just to get fed the input.
		if result == nil then
			return
		end
	elseif mode == VISUAL_MODE.block then
		local firstcol = start[2] + 1
		local lastcol = finish[2]
		if lastcol == 2147483647 then
			lastcol = -1
		else
			lastcol = lastcol + 1
		end
		local block = {}
		for _, line in ipairs(lines) do
			table.insert(block, line:sub(firstcol, lastcol))
		end
		result = fn(block, mode)
		-- If I take the result being nil as leaving it unmodified, then I can use it
		-- to skip the set part and reuse this just to get fed the input.
		if result == nil then
			return
		end

		if #result == 0 then
			result = {''}
		end
		for i, line in ipairs(lines) do
			local result_index = (i-1) % #result + 1
			local replacement = result[result_index]
			lines[i] = table.concat {line:sub(1, firstcol-1), replacement, line:sub(lastcol+1)}
		end
		result = lines
	end

	return api.nvim_buf_set_lines(buf, start[1] - 1, finish[1], false, result)
end

function M.nvim_get_visual_selection_lines(mode)
  local start, finish = M.nvim_visual_region()
  local mode = mode or M.nvim_visual_mode()
  return M.nvim_buf_get_region_lines(0, start, finish, mode), mode, start, finish
end

function M.nvim_transform_visual_selection_lines(mode, fn, start, finish)
  if not start then
    start, finish = M.nvim_visual_region()
  end
  local mode = mode or M.nvim_visual_mode()
  return M.nvim_buf_transform_region_lines(0, start, finish, mode, function(lines)
    return fn(lines, mode, start, finish)
  end)
end

-- Equivalent to `echo vim.inspect(...)`
function M.nvim_print(...)
  if select("#", ...) == 1 then
    api.nvim_out_write(vim.inspect((...)))
  else
    api.nvim_out_write(vim.inspect {...})
  end
  api.nvim_out_write("\n")
end

--- Equivalent to `echo` EX command
function M.nvim_echo(...)
  for i = 1, select("#", ...) do
    local part = select(i, ...)
    api.nvim_out_write(tostring(part))
    -- api.nvim_out_write("\n")
    api.nvim_out_write(" ")
  end
	api.nvim_out_write("\n")
end

---
-- Higher level text manipulation utilities
---

function M.nvim_set_selection_lines(lines)
  local start, finish = M.nvim_visual_region()
	return M.nvim_buf_set_region_lines(0, start, finish, VISUAL_MODE.line, lines)
end

-- Return the selection *IN CHAR MODE* as a string
-- RETURNS: string
function M.nvim_selection()
  local start, finish = M.nvim_visual_region()
	return table.concat(M.nvim_buf_get_region_lines(0, start, finish, VISUAL_MODE.char))
end

-- TODO Use iskeyword
-- WORD_PATTERN = "[%w_]"

-- -- TODO accept buf or win as arguments?
-- function nvim_transform_cword(fn)
-- 	-- lua nvim_print(nvim.win_get_cursor(nvim.get_current_win()))
-- 	local win = api.nvim_get_current_win()
-- 	local row, col = unpack(api.nvim_win_get_cursor(win))
-- 	local buf = api.nvim_get_current_buf()
-- 	-- local row, col = unpack(api.nvim_buf_get_mark(buf, '.'))
-- 	local line = nvim_buf_get_region_lines(buf, row, row, VISUAL_MODE.line)[1]
-- 	local start_idx, end_idx
-- 	_, end_idx = line:find("^[%w_]+", col+1)
-- 	end_idx = end_idx or (col + 1)
-- 	if line:sub(col+1, col+1):match("[%w_]") then
-- 		_, start_idx = line:sub(1, col+1):reverse():find("^[%w_]+")
-- 		start_idx = col + 1 - (start_idx - 1)
-- 	else
-- 		start_idx = col + 1
-- 	end
-- 	local fragment = fn(line:sub(start_idx, end_idx))
-- 	local new_line = line:sub(1, start_idx-1)..fragment..line:sub(end_idx+1)
-- 	nvim_buf_set_region_lines(buf, row, row, VISUAL_MODE.line, {new_line})
-- end

function M.nvim_text_operator(fn)
	LUA_OPFUNC = fn
	vim.o.opfunc = 'v:lua.LUA_OPFUNC'
	api.nvim_feedkeys('g@', 'ni', false)
end

function M.nvim_text_operator_transform_selection(fn, forced_visual_mode)
	return M.nvim_text_operator(function(visualmode)
		M.nvim_buf_transform_region_lines(0, "[", "]", forced_visual_mode or visualmode, function(lines)
			return fn(lines, visualmode)
		end)
	end)
end

function M.nvim_visual_mode()
	local visualmode = vim.fn.mode()
-- 	local visualmode = vim.fn.visualmode()
	if visualmode == 'v' then
		return VISUAL_MODE.char
	elseif visualmode == 'V' then
		return VISUAL_MODE.line
	else
		return VISUAL_MODE.block
	end
end

function M.nvim_transform_cword(fn)
	M.nvim_text_operator_transform_selection(function(lines)
		return {fn(lines[1])}
	end)
	api.nvim_feedkeys('iw', 'n', false)
end

function M.nvim_transform_cWORD(fn)
	M.nvim_text_operator_transform_selection(function(lines)
		return {fn(lines[1])}
	end)
	api.nvim_feedkeys('iW', 'n', false)
end

function M.nvim_source_current_buffer()
	loadstring(table.concat(M.nvim_buf_get_region_lines(nil, 1, -1, VISUAL_MODE.line), '\n'))()
end

local function buffer_local_map()
  return setmetatable({}, {
    __index = function(t, bufnr)
      if bufnr == 0 then
        bufnr = api.nvim_get_current_buf()
      end
      local bt = rawget(t, bufnr)
      if bt then return bt end
      bt = {}
      rawset(t, bufnr, bt)
      api.nvim_buf_attach(bufnr, false, {
        on_detach = function()
          rawset(t, bufnr, nil)
        end
      })
      return bt
    end
  })
end

M._keys = {}
M._bufkeys = buffer_local_map()

local function escape_keymap(key)
	-- Prepend with a letter so it can be used as a dictionary key
	return 'k'..key:gsub('.', string.byte)
end

local valid_modes = {
	n = 'n'; v = 'v'; x = 'x'; i = 'i';
	o = 'o'; t = 't'; c = 'c'; s = 's';
	-- :map! and :map
	['!'] = '!'; [' '] = '';
}

-- TODO(ashkan) @feature Disable noremap if the rhs starts with <Plug>
function M.nvim_apply_mappings(mappings, default_options)
	-- May or may not be used.
	local current_bufnr = api.nvim_get_current_buf()
	for key, options in pairs(mappings) do
		options = vim.tbl_extend("keep", options, default_options or {})
		local bufnr = current_bufnr
		-- TODO allow passing bufnr through options.buffer?
		-- protect against specifying 0, since it denotes current buffer in api by convention
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
		local rhs = options[1]
		-- Remove this because we're going to pass it straight to nvim_set_keymap
		options[1] = nil
		if type(rhs) == 'function' then
			-- Use a value that won't be misinterpreted below since special keys
			-- like <CR> can be in key, and escaping those isn't easy.
			local escaped = escape_keymap(key)
			local key_mapping
			if options.dot_repeat then
				local key_function = rhs
				rhs = function()
					key_function()
          REPEAT_FUNCTION = key_function
					vim.fn["repeat#set"](api.nvim_replace_termcodes(key_mapping, true, true, true), vim.v.count)
				end
				options.dot_repeat = nil
			end
			if options.buffer then
				M._bufkeys[bufnr][escaped] = rhs
        key_mapping = ("<cmd>lua require'nvim_utils'._bufkeys[0].%s()<CR>"):format(escaped)
			else
				M._keys[escaped] = rhs
        key_mapping = ("<cmd>lua require'nvim_utils'._keys.%s()<CR>"):format(escaped)
			end
			rhs = key_mapping
			options.noremap = true
			options.silent = true
		end
		if options.buffer then
			options.buffer = nil
			api.nvim_buf_set_keymap(bufnr, mode, mapping, rhs, options)
		else
			api.nvim_set_keymap(mode, mapping, rhs, options)
		end
	end
end

function M.nvim_create_augroups(definitions)
	for group_name, definition in pairs(definitions) do
		api.nvim_command('augroup '..group_name)
		api.nvim_command('autocmd!')
		for _, def in ipairs(definition) do
			-- if type(def) == 'table' and type(def[#def]) == 'function' then
			-- 	def[#def] = lua_callback(def[#def])
			-- end
			local command = table.concat(vim.tbl_flatten{'autocmd', def}, ' ')
			api.nvim_command(command)
		end
		api.nvim_command('augroup END')
	end
end

--- Highlight a region in a buffer from the attributes specified
function M.nvim_highlight_region(buf, ns, highlight_name,
		 region_line_start, region_byte_start,
		 region_line_end, region_byte_end)
	if region_line_start == region_line_end then
		api.nvim_buf_add_highlight(buf, ns, highlight_name, region_line_start, region_byte_start, region_byte_end)
	else
		api.nvim_buf_add_highlight(buf, ns, highlight_name, region_line_start, region_byte_start, -1)
		for linenum = region_line_start + 1, region_line_end - 1 do
			api.nvim_buf_add_highlight(buf, ns, highlight_name, linenum, 0, -1)
		end
		api.nvim_buf_add_highlight(buf, ns, highlight_name, region_line_end, 0, region_byte_end)
	end
end

M._cbs = {}
function M.lua_callback(fn)
	assert(type(fn) == 'function', 'lua_callback: fn must be a function')
	table.insert(M._cbs, fn)
	local callback_number = #M._cbs
	return ("require'nvim_utils'._cbs[%d]()"):format(callback_number)
end

function M.lua_callback_cmd(fn)
	return "lua "..M.lua_callback(fn)
end

function M.map_cmd(...)
	return { ("<Cmd>%s<CR>"):format(table.concat(vim.tbl_flatten {...}, " ")), noremap = true; }
end

function M.map_xmd(...)
	return { (":%s<CR>"):format(table.concat(vim.tbl_flatten {...}, " ")), noremap = true; }
end

function M.err_message(...)
	api.nvim_err_writeln(table.concat(vim.tbl_flatten{...}, ' '))
	api.nvim_command 'redraw'
end

function M.schedule(fn, ...)
	--if not in_textlock() then
----	if not vim.in_fast_event() then
	--	fn(...)
	--end
	if select("#", ...) > 0 then
		return vim.schedule_wrap(fn)(...)
	end
	return vim.schedule(fn)
end

--[=[
" Clear undo history
function! ClearUndo()
  let save_cursor = getpos(".")
  " Inspired by: https://superuser.com/a/688962/301551
  " Disable undo level, move a line, move it back, clear modified, restore undo
  " Resets position to 0, though
  exe "setl ul=-1 | 0m. | m0 | set nomodified | set ul=".&ul
  call setpos(".", save_cursor)
endfunction
]=]
function M.clear_undo()
	local pos = api.nvim_win_get_cursor(0)
	local ul = -1
--	local ul = vim.bo.ul
	vim.bo.ul = -1
	api.nvim_command('0m. | m0')
	vim.bo.modified = false
	vim.bo.ul = ul
	-- api.nvim_command("setl ul=-1 | 0m. | m0 | set nomodified | setl ul=-1")
--	api.nvim_command("setl ul=-1 | 0m. | m0 | set nomodified | setl ul="..vim.bo.ul)
	api.nvim_win_set_cursor(0, pos)
end

function M.nvim_loaded_buffers()
	local result = {}
	local buffers = api.nvim_list_bufs()
	for _, buf in ipairs(buffers) do
		if api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
			table.insert(result, buf)
		end
	end
	return result
end

M._cmds = {}
M._bufcmds = buffer_local_map()

function M.nvim_create_commands(commands)
  local curbuf = api.nvim_get_current_buf()
  for cmd_name, cmd_conf in pairs(commands) do
    local parts = {"command!"}
    for k, v in pairs(cmd_conf) do
      if type(k) == 'string' then
        if v == true then
          table.insert(parts, '-'..k)
        elseif type(v) == 'string' then
          table.insert(parts, '-'..k.."="..v)
        end
      end
    end
    table.insert(parts, cmd_name)

    local args
    if cmd_conf.range then
      args = '{args={<f-args>};line1=<line1>;line2=<line2>}'
    else
      args = '(<f-args>)'
    end
    local rhs
    if cmd_conf.buffer then
      local bufnr = type(cmd_conf.buffer) == 'number' and cmd_conf.buffer or curbuf
      M._bufcmds[bufnr][cmd_name] = cmd_conf
      rhs = string.format('lua require"nvim_utils"._bufcmds[0][%q][1]%s', cmd_name, args)
    else
      M._cmds[cmd_name] = cmd_conf
      rhs = string.format('lua require"nvim_utils"._cmds[%q][1]%s', cmd_name, args)
    end
    table.insert(parts, rhs)

    -- table.insert(parts, string.format('lua COMMANDS[%q][1](<f-args>)', cmd_name))
    vim.cmd(table.concat(parts, ' '))
  end
end



-- local function in_textlock()
-- 	return (pcall(api.nvim_win_set_cursor, 0, api.nvim_win_get_cursor(0)))
-- end


-----
---- SPAWN UTILS
-----

--local function clean_handles()
--	local n = 1
--	while n <= #HANDLES do
--		if HANDLES[n]:is_closing() then
--			table.remove(HANDLES, n)
--		else
--			n = n + 1
--		end
--	end
--end

--HANDLES = {}

--function spawn(cmd, params, onexit)
--	local handle, pid
--	handle, pid = vim.loop.spawn(cmd, params, function(code, signal)
--		if type(onexit) == 'function' then onexit(code, signal) end
--		handle:close()
--		clean_handles()
--	end)
--	table.insert(HANDLES, handle)
--	return handle, pid
--end

----- MISC UTILS

--function epoch_ms()
--	local s, ns = vim.loop.gettimeofday()
--	return s * 1000 + math.floor(ns / 1000)
--end

--function epoch_ns()
--	local s, ns = vim.loop.gettimeofday()
--	return s * 1000000 + ns
--end

local tohex = require'bit'.tohex
function M.color_to_hex(color)
  local rgb = vim.api.nvim_get_color_by_name(color)
  if rgb == -1 then return end
  return '#'..tohex(rgb, 6)
end

local function log_pcall_err(message, status, ...)
  if not status then
    M.err_message(message..': '..select(1, ...))
    return
  end
  return ...
end
function M.pcall_log(message, fn, ...)
  assert(type(message) == 'string', 'need a message')
  return log_pcall_err(message, pcall(fn, ...))
end

return M

