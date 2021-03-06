-- Compiles and loads a piece of lua code
local parser = require 'lua.parser'
local compiler = require 'lua.compiler'
local dump = require 'bytecode.dump'
local utils = require 'common.utils'

local function main(file)
  local tree = parser(io.open(file, 'r'):read('*all'))
  local prototype = compiler(tree)
  local bytecode = dump.dump(prototype)
  local func, err = loadstring(tostring(bytecode))

  local function dumper_(proto, level)
    local indent = ('   '):rep(level)
    print(indent .. 'Level ' .. level)
    print(indent .. "Code")
    for pc, op in ipairs(proto.code) do
      print(indent .. pc, '(line ' .. proto.debug.lineinfo[pc] .. ')',  op)
    end
    print(indent .. "Constants")
    for id, const in ipairs(proto.constants) do
      print(indent .. id, const)
    end
    print(indent .. "Upvalues")
    for id, up in ipairs(proto.upvalues) do
      print(indent .. id - 1, proto.debug.upvalues[id], up.instack == 1 and 'local' or 'upval', up.index)
    end
    for func in utils.loop(proto.constants.functions) do
      dumper_(func, level + 1)
    end
  end
  local function dumper()
    dumper_(prototype, 0)
  end

  if err then
    print("Error during bytecode loading, dumping state...")
    dumper()
    error(err)
  end
  return func, bytecode, prototype, dumper
end

return main