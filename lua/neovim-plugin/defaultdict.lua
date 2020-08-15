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
