return function(res, ...)
  for i = 1, select("#", ...) do
    for k, v in pairs((select(i, ...))) do
      rawset(res, k, v)
      -- res[k] = v
    end
  end
  return res
end
