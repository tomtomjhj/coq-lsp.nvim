local M = {}

-- TODO: Render goals nicely.
-- * see also lean.nvim infoview stuff
-- * handle multi-line pp
-- * different types for Pp (pp_type)

---@param i integer
---@param n integer
---@param goal coqlsp.Goal
---@return string
function M.Goal(i, n, goal)
  local lines = {}
  lines[#lines + 1] = 'Goal ' .. i .. ' / ' .. n
  for _, hyp in ipairs(goal.hyps) do
    local line = table.concat(hyp.names, ', ') .. ' : ' .. hyp.ty
    if hyp.def then
      line = line .. ' := ' .. hyp.def
    end
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '========================================'
  lines[#lines + 1] = ''
  lines[#lines + 1] = goal.ty
  return table.concat(lines, '\n')
end

return M
