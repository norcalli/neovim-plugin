local files = {
  'apply_commands',
  'apply_mappings',
  'buffer_store',
  'defaultdict',
  'extend',
  'mergein',
  'nvim',
  'validate',
}

local format = string.format
local concat = table.concat
local insert = table.insert

local content = {}

local function substitute_requires(data)
  for j, name in ipairs(files) do
    local require_name = format('neovim%%-plugin/%s', name)
    data = data:gsub("%srequire%s+'"..require_name.."'", format(' nvp_require(%q)', name))
  end
  return data
end

local function readfile(source)
  local file = assert(io.open(source))
  local data = file:read"*a"
  file:close()
  return data
end

for i, name in ipairs(files) do
  local source = format('lua/neovim-plugin/%s.lua', name)
  content[name] = substitute_requires(readfile(source))
end

local R = {
  [[
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
]]
}


for name, body in pairs(content) do
  insert(R, format("nvp_packages[%q] = function()", name))
  insert(R, body)
  insert(R, "end")
end

insert(R, substitute_requires(readfile("lua/neovim-plugin.lua")))

print(concat(R, '\n'))
