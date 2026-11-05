-- Loads generated DMM_RANGE configs into the real runtime (DCS stubbed), builds the menu and
-- presses every spawn command, so a mismatch between app/generator/range.py and
-- app/lua/training_range.lua shows up here rather than in DCS.
-- Usage: lua5.1 tests/lua/test_generated_config.lua <config.lua> [more configs...]

local configs = { ... }
assert(#configs > 0, "pass one or more generated dmm_range_config.lua files")

local function runOne(path)
  DMM_RANGE = nil
  dofile(path)
  assert(type(DMM_RANGE) == "table", path .. ": no DMM_RANGE")
  TR_NO_AUTOSTART = true
  TR = nil
  dofile("app/lua/training_range.lua")

  local menus, menuId, groups, statics, messages, timers = {}, 0, {}, {}, {}, {}
  local env = TR.env
  env.now = function() return 0 end
  env.schedule = function(fn, delay) timers[#timers + 1] = fn end
  env.message = function(text) messages[#messages + 1] = text end
  env.log = function(text) error(path .. ": logged " .. text) end
  env.landHeight = function() return 0 end
  env.random = function() return 0.3 end
  env.spawnGroup = function(tpl, alias)
    assert(type(tpl) == "string" and tpl:find("^TR_"), path .. ": bad template " .. tostring(tpl))
    groups[alias] = 2
    return alias
  end
  env.groupAlive = function(name) return groups[name] or 0 end
  env.destroyGroup = function(name) groups[name] = nil end
  env.addStatic = function(def)
    assert(def.type and def.category and def.x and def.y, path .. ": incomplete static " .. tostring(def.name))
    statics[def.name] = true
    return def.name
  end
  env.staticAlive = function(name) return statics[name] ~= nil end
  env.destroyStatic = function(name) statics[name] = nil end
  env.setFlag = function() end
  env.setAlarm = function() end
  env.taskAir = function(_, center, radius, alt, speed)
    assert(center.x and radius > 0 and alt and speed, path .. ": bad air task")
  end
  env.menu.sub = function(name, parent)
    menuId = menuId + 1
    menus[menuId] = { name = name, parent = parent, alive = true }
    return menuId
  end
  env.menu.cmd = function(name, parent, fn, arg)
    menuId = menuId + 1
    menus[menuId] = { name = name, parent = parent, fn = fn, arg = arg, alive = true }
    return menuId
  end
  env.menu.remove = function(id)
    local function kill(i)
      menus[i].alive = false
      for j, m in pairs(menus) do if m.parent == i and m.alive then kill(j) end end
    end
    kill(id)
  end

  TR.start()
  local commands, levels = {}, 0
  local function walk(parent, trail)
    local kids = {}
    for id, m in pairs(menus) do if m.alive and m.parent == parent then kids[#kids + 1] = id end end
    assert(#kids <= 10, path .. ": " .. #kids .. " items under " .. trail)
    levels = levels + 1
    table.sort(kids)
    for _, id in ipairs(kids) do
      local m = menus[id]
      if m.fn then
        commands[#commands + 1] = { m = m, trail = trail .. " > " .. m.name }
      else
        walk(id, trail .. " > " .. m.name)
      end
    end
  end
  walk(nil, "F10")

  local spawned = 0
  for _, c in ipairs(commands) do
    local arg = c.m.arg
    if type(arg) == "table" and arg.system then
      local before = #messages
      c.m.fn(arg)
      local text = messages[#messages]
      assert(#messages > before, path .. ": no reply to " .. c.trail)
      if text:find("spawned in") then
        spawned = spawned + 1
      elseif not text:find("full") and not text:find("Too many") then
        error(path .. ": " .. c.trail .. " -> " .. text)
      end
      TR.clearArea(arg.area, true)
    end
  end
  TR.resetRange()
  return #commands, spawned, levels
end

local total = 0
for _, path in ipairs(configs) do
  local cmds, spawned = runOne(path)
  total = total + spawned
end
print(string.format("generated configs: %d checked, %d spawns pressed", #configs, total))
