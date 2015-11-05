-- LL1 parser, which is somewhat limited :'(

local ll1 = {}

local utils = require 'utils'
local graph = require 'graph'
local worklist = require 'worklist'

local nonterminals = {}
local configurations = {}

local EPS = ''
local EOF = 256
local ERROR = -1

-- computes the first sets of nonterminals
local first_algorithm = worklist {
  -- what is the domain? Sets of tokens
  initialize = function(self, _, _)
    return {}
  end,
  transfer = function(self, node, _, graph, pred)
    local first_set = self:initialize(node)
    local configuration = unpack(graph.forward[pred][node])
    local nonterminals = configuration[node]
    for production in utils.loop(nonterminals) do
      for object in utils.loop(production) do
        if object:sub(1, 1) == '$' then
          local partial_first_set = self.partial_solution[object:sub(2)]
          first_set = self:merge(first_set, partial_first_set)
          if not partial_first_set[EPS] then break end
        else
          first_set[object] = true
          if object ~= EPS then break end
        end
      end
    end
    return first_set
  end,
  changed = function(self, old, new)
    -- assuming monotone in the new direction
    for key in pairs(new) do
      if not old[key] then
        return true
      end
    end
    return false
  end,
  merge = function(self, left, right)
    local merged = utils.copy(left)
    for key in pairs(right) do
      merged[key] = true
    end
    return merged
  end,
  tostring = function(self, _, node, input)
    local list = {}
    for key in pairs(input) do table.insert(list, key) end
    return node .. ' ' .. table.concat(list, ',')
  end
}

local follow_algorithm = worklist {
  -- what is the domain? Sets of tokens
  initialize = function(self, node, _)
    if node == 'root' then return {[EOF] = true} end
    return {}
  end,
  transfer = function(self, node, follow_pred, graph, pred)
    local follow_set = self:initialize(node)
    local configuration, suffix = unpack(graph.forward[pred][node])
    follow_set = self:merge(follow_set, ll1.first(configuration, suffix))
    if follow_set[EPS] then
      follow_set = self:merge(follow_set, follow_pred)
    end
    return follow_set
  end,
  changed = function(self, old, new)
    -- assuming monotone in the new direction
    for key in pairs(new) do
      if not old[key] then
        return true
      end
    end
    return false
  end,
  merge = function(self, left, right)
    local merged = utils.copy(left)
    for key in pairs(right) do
      merged[key] = true
    end
    return merged
  end,
  tostring = function(self, _, node, input)
    local list = {}
    for key in pairs(input) do table.insert(list, key) end
    return node .. ' ' .. table.concat(list, ',')
  end
}

local function get_nonterminal(configuration, variable)
  if variable:sub(1, 1) == '$' then
    return configuration[variable:sub(2)]
  end
  return
end

local function get_terminals_from(configuration)
  local terminals = {}
  for _, productions in pairs(configuration) do
    for production in utils.loop(productions) do
      for terminal in utils.loop(production) do
        if terminal ~= EPS and terminal ~= EOF then
          terminals[terminal] = true
        end
      end
    end
  end
  terminals[EOF] = true
  return terminals
end

function configurations:firsts()
  if not self.graph then
    local dependency_graph = graph.create()
    for _, nonterminal in pairs(self) do
      nonterminal:dependency(dependency_graph, self)
    end
    getmetatable(self)['__index']['graph'] = dependency_graph
  end
  if not self.cached_firsts then
    getmetatable(self)['__index']['cached_firsts'] = first_algorithm:forward(self.graph)
  end
  return utils.copy(self.cached_firsts)
end

function configurations:follows()
  if not self.graph then
    local dependency_graph = graph.create()
    for _, nonterminal in pairs(self) do
      nonterminal:dependency(dependency_graph, self)
    end
    getmetatable(self)['__index']['graph'] = dependency_graph
  end
  if not self.cached_follows then
    getmetatable(self)['__index']['cached_follows'] = follow_algorithm:forward(self.graph)
  end
  return utils.copy(self.cached_follows)
end

function configurations:first(variable)
  return self:firsts()[variable]
end

function configurations:follow(variable)
  return self:follows()[variable]
end

local function merge(left, right)
  local merged = utils.copy(left)
    for key in pairs(right) do
      merged[key] = true
    end
    return merged
end

function ll1.first(configuration, production)
  local first_set = {}
  for object in utils.loop(production) do
    if object:sub(1, 1) == '$' then
      local partial_first_set = configuration:first(object:sub(2))
      first_set = merge(first_set, partial_first_set)
      if not partial_first_set[EPS] then return first_set end
    else
      first_set[object] = true
      if object ~= EPS then return first_set end
    end
  end
  first_set[EPS] = true
  return first_set
end

function nonterminals:first(configuration)
  configuration:first(self.variable:sub(2))
end

function configurations:pretty()
  local str = ''
  for variable, nonterminals in pairs(self) do
    local productions = {}
    for production in utils.loop(nonterminals) do
      table.insert(productions, table.concat(production, ' '))
    end
    str = str .. variable .. '\t' .. '->    ' .. table.concat(productions, ' | ') .. '\n'
  end
  return str
end

function configurations:uses(x)
  -- returns set of {variable, suffix_production} such that
  -- y -> \alpha $x \beta, then return {$y, \beta} or {$y, ''}
  local uses = {}
  for y, nonterminal in pairs(self) do
    for _, production in ipairs(nonterminal) do
      for i, object in ipairs(production) do
        if object == x then
          local suffix = utils.sublist(production, i + 1)
          table.insert(uses, {'$' .. y, suffix})
        end
      end
    end
  end
  return uses
end

function nonterminals:dependency(graph, configuration)
  if graph.nodes[self.variable:sub(2)] then
    return graph
  end
  local uses = configuration:uses(self.variable)
  for variable, suffix in utils.uloop(uses) do
    get_nonterminal(configuration, variable):dependency(graph, configuration)
    setmetatable(
      suffix, 
      {__tostring = function(self) return table.concat(ll1.first(configuration, suffix), ', ') end})
    graph:edge(variable:sub(2), self.variable:sub(2), {configuration, suffix})
  end
  return graph
end


local yacc = {}

function ll1.configure(actions)
  -- Associate the correct set of metatables to the nonterminals
  local configuration = {}
  for variable, productions in pairs(actions) do
    setmetatable(productions, {__index = nonterminals})
    productions.variable = '$' .. variable
    configuration[variable] = productions
  end
  return setmetatable(configuration, {__index = utils.copy(configurations)})
end

function ll1.yacc(actions)
  -- Associate the correct set of metatables to the nonterminals
  local configuration = ll1.configure(actions)
  
  local first_sets = configuration:firsts()
  local follow_sets = configuration:follows()
  local terminals = get_terminals_from(configuration)
  local transition_table = {}
  
  for variable in pairs(configuration) do
    transition_table[variable] = {}
    for terminal in pairs(terminals) do
      transition_table[variable][terminal] = ERROR
    end
  end
  
  for variable, productions in pairs(configuration) do
    for i, production in ipairs(productions) do
      local firsts = ll1.first(configuration, production)
      for terminal in pairs(firsts) do
        if terminal ~= EPS then
          if transition_table[variable][terminal] ~= ERROR then 
            print('ERROR', variable, terminal, table.concat(transition_table[variable][terminal], ', '))
          else
            transition_table[variable][terminal] = i
          end
        end
      end
      if firsts[EPS] then
        local follows = follow_sets[variable]
        for terminal in pairs(follows) do
          if terminal ~= EPS then
            if transition_table[variable][terminal] ~= ERROR then 
              print('ERROR', variable, terminal, table.concat(transition_table[variable][terminal], ', '))
            else
              transition_table[variable][terminal] = i
            end
          end
        end
      end
    end
  end
  
  local y = utils.copy(yacc)
  y.configuration = configuration
  setmetatable(transition_table, {__index = y})
  
  return transition_table
end

local function consume(tokens)
  return table.remove(tokens, 1)
end
local function peek(tokens)
  return tokens[1]
end
local function enqueue(tokens, item)
  table.insert(tokens, 1, item)
end

function yacc:parse(tokens, state, trace)
  if not state then state = 'root' end
  if not trace then trace = {} end
  local token = peek(tokens)
  if not token then token = EOF end
  local production_index = self[state][token]
  local production = self.configuration[state][production_index]
  local local_trace = {state, token, utils.copy(tokens), production}
  table.insert(trace, local_trace)
  if production == ERROR then
    return ERROR, production
  end
  local args = {}
  for node in utils.loop(production) do
    if node:sub(1, 1) == '$' then
      local ret = self:parse(tokens, node:sub(2), trace)
      table.insert(args, ret)
    elseif token ~= EOF then
      local token = consume(tokens)
      assert(node == token, tostring(node) .. ' ~= ' .. tostring(token))
      table.insert(args, token)
    else
      assert(not consume(tokens))
    end
  end
  table.insert(local_trace, args)
  return production.action(unpack(args)), trace
end

function yacc:save(file)
  -- dump out the table
  -- if io.open(file, "r") then return end
  local serialized_dump = utils.dump {self, self.configuration}
  local stream = assert(io.open(file, "w"))
  stream:write('return ' .. serialized_dump)
  assert(stream:close())
  return self
end

function ll1.create(actions)
  actions = utils.copy(actions)
  local file = table.remove(actions)
  
  if not file then
    return ll1.yacc(actions)
  end
  
  local deserialize = loadfile(file)
  if not deserialize then
    local transitions = ll1.yacc(actions)
    return transitions:save(file)
  end
  
  local status, bundle = pcall(deserialize)
  if not status then
    return ll1.yacc(actions):save(file)
  end
  
  local transitions, configuration = unpack(bundle)
  setmetatable(configuration, {__index = configurations})
  local y = utils.copy(yacc)
  y.configuration = configuration
  setmetatable(transitions, {__index = y})
  local sane = true
  for variable, productions in pairs(configuration) do
    for index, production in ipairs(productions) do
      if not actions[variable] or not actions[variable][index] then
        sane = false
        break
      end
      local action = actions[variable][index]
      production.action = action.action
      for j, object in ipairs(production) do
        if object ~= action[j] then
          sane = false
          break
        end
      end
    end
  end
  if sane then
    return transitions
  else
    return ll1.yacc(actions):save(file)
  end
end

return setmetatable(ll1, {__call = function(self, ...) return self.create(...) end})