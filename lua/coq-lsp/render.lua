local M = {}

-- TODO: Render goals nicely.
-- * see also lean.nvim infoview stuff
-- * handle multi-line pp
-- * different types for Pp (pp_type)

---@param i integer
---@param n integer
---@param goal coqlsp.Goal
---@return string[]
function M.Goal(i, n, goal)
  local lines = {}
  lines[#lines + 1] = 'Goal ' .. i .. ' / ' .. n
  for _, hyp in ipairs(goal.hyps) do
    local line = table.concat(hyp.names, ', ') .. ' : ' .. hyp.ty
    if hyp.def then
      line = line .. ' := ' .. hyp.def
    end
    vim.list_extend(lines, vim.split(line, '\n'))
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '========================================'
  lines[#lines + 1] = ''
  vim.list_extend(lines, vim.split(goal.ty, '\n'))
  return lines
end

---@param goals coqlsp.Goal[]
---@return string[]
function M.Goals(goals)
  local lines = {}
  for i, goal in ipairs(goals) do
    if i > 1 then
      lines[#lines + 1] = ''
      lines[#lines + 1] = ''
      lines[#lines + 1] =
        '────────────────────────────────────────────────────────────'
      lines[#lines + 1] = ''
    end
    vim.list_extend(lines, M.Goal(i, #goals, goal))
  end
  return lines
end

---@param message coqlsp.Message
---@return string[]
function M.Message(message)
  local lines = {}
  vim.list_extend(lines, vim.split(message.text, '\n'))
  return lines
end

---@param messages coqlsp.Pp[] | coqlsp.Message[]
---@return string[]
function M.Messages(messages)
  local lines = {}
  for _, msg in ipairs(messages) do
    if type(msg) == 'string' then
      vim.list_extend(lines, vim.split(msg, '\n'))
    else
      vim.list_extend(lines, M.Message(msg))
    end
  end
  return lines
end

---@param answer coqlsp.GoalAnswer
---@param position MarkPosition
---@return string[]
function M.GoalAnswer(answer, position)
  local lines = {}

  local bufnr = vim.uri_to_bufnr(answer.textDocument.uri)
  lines[#lines + 1] = vim.fn.bufname(bufnr) .. ':' .. position[1] .. ':' .. (position[2] + 1)

  if answer.goals then
    if #answer.goals.goals > 0 then
      vim.list_extend(lines, M.Goals(answer.goals.goals))
    end
  end

  if #answer.messages > 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = ''
    lines[#lines + 1] =
      'Messages ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    lines[#lines + 1] = ''
    vim.list_extend(lines, M.Messages(answer.messages))
  end

  if answer.goals then
    if #answer.goals.shelf > 0 then
      lines[#lines + 1] = ''
      lines[#lines + 1] = ''
      lines[#lines + 1] =
        'Shelved ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      lines[#lines + 1] = ''
      vim.list_extend(lines, M.Goals(answer.goals.shelf))
    end
    if #answer.goals.given_up > 0 then
      lines[#lines + 1] = ''
      lines[#lines + 1] = ''
      lines[#lines + 1] =
        'Given Up ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
      lines[#lines + 1] = ''
      vim.list_extend(lines, M.Goals(answer.goals.given_up))
    end
  end

  if answer.error then
    lines[#lines + 1] = ''
    lines[#lines + 1] = ''
    lines[#lines + 1] =
      'Error ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    lines[#lines + 1] = ''
    vim.list_extend(lines, vim.split(answer.error, '\n'))
  end

  return lines
end

return M
