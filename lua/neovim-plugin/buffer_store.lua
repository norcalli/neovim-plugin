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
