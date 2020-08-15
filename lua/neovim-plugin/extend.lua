return function(r, ...)
  for i = 1, select("#", ...) do
    for _, v in ipairs((select(i, ...))) do
      r[#r+1] = v
    end
  end
  return r
end
