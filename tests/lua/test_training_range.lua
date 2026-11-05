-- Unit tests for app/lua/training_range.lua under plain Lua 5.1, with DCS and MOOSE stubbed.
-- Run from the repo root:  lua5.1 tests/lua/test_training_range.lua
-- (in Docker: see tests/range.py, which runs this too)

DMM_RANGE = {
  enemy_country = "CJTF_RED", difficulty = "normal",
  caps = { area = 3, aircraft = 4, total = 5 }, repeat_delay = 120, practice_respawn = 300,
  flags = { range = 9032, hook = 9030, reload = 9031 },
  systems = {
    sa11 = { label = "SA-11", kind = "ground", radar = true, templates = { ["2"] = "TR_TPL sa11" } },
    t72 = { label = "T-72 column", kind = "ground", radar = false, templates = { ["2"] = "TR_TPL t72" } },
    hq = { label = "Command post", kind = "static",
           statics = { { type = "Military staff", category = "Fortifications", bearing = 0, dist = 0 },
                       { type = "Barracks 2", category = "Fortifications", bearing = 90, dist = 80 } } },
    su27 = { label = "Su-27", kind = "air", helicopter = false, alt = 6500, speed = 220,
             templates = { ["2"] = "TR_TPL su27 x2", ["4"] = "TR_TPL su27 x4" } },
  },
  areas = {
    { id = "sead", label = "SEAD/DEAD", kind = "ground", center = { x = 0, y = 0 }, radius = 6000,
      slots = { { x = 1, y = 1 }, { x = 2, y = 2 }, { x = 3, y = 3 } },
      roles = { { id = "mr_sam", label = "Medium SAM", repeatable = false, systems = { "sa11" }, default = "sa11" } },
      practice = { { kind = "radar", label = "Radar", template = "TR_PT radar", pos = { x = 0, y = 0 } } } },
    { id = "cas", label = "CAS", kind = "ground", center = { x = 50000, y = 0 }, radius = 5000,
      slots = { { x = 1, y = 1 }, { x = 2, y = 2 }, { x = 3, y = 3 } },
      roles = { { id = "armour", label = "Armour column", repeatable = true, systems = { "t72" }, default = "t72" },
                { id = "buildings", label = "Buildings", repeatable = false, systems = { "hq" } } },
      practice = { { kind = "circle", label = "Bombing circle", statics = {
        { name = "TR_PT CAS circle 1", type = "White_Tyre", category = "Fortifications", x = 0, y = 0, heading = 0 } } } } },
    { id = "a2a", label = "Air-to-Air", kind = "air", center = { x = 0, y = 90000 }, radius = 40000, slots = {},
      roles = { { id = "fighter_pair", label = "Fighter pair", repeatable = true, size = 2, systems = { "su27" } },
                { id = "fighter_four", label = "Fighter 4-ship", repeatable = true, size = 4, systems = { "su27" } } },
      practice = {} },
  },
}

TR_NO_AUTOSTART = true
dofile("app/lua/training_range.lua")

-- ---------------------------------------------------------------- stubs
local now, timers, messages, groups, statics, flags, menus, alarms, tasks = 0, {}, {}, {}, {}, {}, {}, {}, {}
local menuId = 0
local env = TR.env
env.now = function() return now end
env.schedule = function(fn, delay) timers[#timers + 1] = { at = now + delay, fn = fn } end
env.message = function(text) messages[#messages + 1] = text end
env.log = function(text) error("logged: " .. text) end
env.landHeight = function() return 100 end
env.random = function() return 0.5 end
env.spawnGroup = function(tpl, alias, skill, pos, alt)
  groups[alias] = { tpl = tpl, skill = skill, pos = pos, alt = alt, size = 2 }
  return alias
end
env.groupAlive = function(name) return groups[name] and groups[name].size or 0 end
env.destroyGroup = function(name) groups[name] = nil end
env.addStatic = function(def) statics[def.name] = def return def.name end
env.staticAlive = function(name) return statics[name] ~= nil end
env.destroyStatic = function(name) statics[name] = nil end
env.setFlag = function(n, v) flags[n] = v end
env.setAlarm = function(name, state) alarms[name] = state end
env.taskAir = function(name, center, radius) tasks[name] = { center = center, radius = radius } end
env.menu.sub = function(name, parent)
  menuId = menuId + 1
  menus[menuId] = { name = name, parent = parent, kind = "sub", alive = true }
  return menuId
end
env.menu.cmd = function(name, parent, fn, arg)
  menuId = menuId + 1
  menus[menuId] = { name = name, parent = parent, kind = "cmd", fn = fn, arg = arg, alive = true }
  return menuId
end
env.menu.remove = function(id)
  local function kill(i)
    menus[i].alive = false
    for j, m in pairs(menus) do if m.parent == i and m.alive then kill(j) end end
  end
  kill(id)
end

local function run(seconds)
  local stop = now + seconds
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > stop then break end
    table.remove(timers, 1)
    now = t.at
    t.fn()
  end
  now = stop
end

local function children(parent)
  local out = {}
  for id, m in pairs(menus) do if m.alive and m.parent == parent then out[#out + 1] = { id = id, m = m } end end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

local function find(parent, name)
  for _, c in ipairs(children(parent)) do if c.m.name == name then return c.id, c.m end end
  error("no menu '" .. name .. "' under " .. tostring(parent))
end

local function press(...)
  local path, id = { ... }, nil
  for i, name in ipairs(path) do
    local m
    id, m = find(id, name)
    if i == #path then m.fn(m.arg) end
  end
end

local function last() return messages[#messages] end
local passed = 0
local function check(cond, what)
  if not cond then error("FAIL: " .. what .. " (last message: " .. tostring(last()) .. ")", 2) end
  passed = passed + 1
end
local function countAlive(prefix)
  local n = 0
  for name in pairs(groups) do if name:find(prefix, 1, true) then n = n + 1 end end
  return n
end

-- ---------------------------------------------------------------- tests
TR.start()
run(11)   -- the "ready" message
check(last():find("Training Range ready"), "ready message")
check(flags[9032] == 1, "range flag set at start")
check(countAlive("Radar") == 1, "radiating Practice Target spawned at start")
check(#children(nil) == 1, "one root menu")

-- menu shape: root > areas > roles > systems (> Once / Repeat), then Difficulty, Clear
local root = find(nil, "Training Range")
local sead = find(root, "SEAD/DEAD")
local names = {}
for _, c in ipairs(children(sead)) do names[#names + 1] = c.m.name end
check(table.concat(names, "|") == "Medium SAM|Difficulty: Normal (change)|Clear SEAD/DEAD", "SEAD menu items")
for _, c in ipairs(children(nil)) do
  local function depth(id, d)
    local kids = children(id)
    check(#kids <= 10, "F10 limit at " .. tostring(id))
    for _, k in ipairs(kids) do depth(k.id, d + 1) end
  end
  depth(c.id, 1)
end

-- spawn a SAM; radar on AUTO at Normal
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
check(last():find("SA%-11 spawned in SEAD/DEAD %(Normal%)"), "spawn message")
local sam = next(TR.areas.sead.spawns)
local samGroup = TR.areas.sead.spawns[sam].group
check(groups[samGroup].skill == "Good", "Normal = Good skill")
check(alarms[samGroup] == "auto", "Normal radar behaviour is AUTO")

-- difficulty cycles and rebuilds the menu in place
press("Training Range", "SEAD/DEAD", "Difficulty: Normal (change)")
check(TR.areas.sead.difficulty == "hard", "Normal -> Hard")
press("Training Range", "SEAD/DEAD", "Difficulty: Hard (change)")
check(TR.areas.sead.difficulty == "easy", "Hard -> Easy")
check(#children(nil) == 1, "menu rebuilt, not duplicated")
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
local easyGroup
for _, s in pairs(TR.areas.sead.spawns) do if s.group ~= samGroup then easyGroup = s.group end end
check(groups[easyGroup].skill == "Average" and alarms[easyGroup] == "red", "Easy = Average, radar always on")

-- per-area cap
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
check(last():find("SEAD/DEAD area is full %(3/3%)"), "area cap message")

-- server-wide cap (5): 3 in SEAD + statics + 1 armour = 5, the next is refused
press("Training Range", "CAS", "Buildings", "Command post")
local placed = 0
for name in pairs(statics) do if name:find("TR CAS Command post #", 1, true) then placed = placed + 1 end end
check(placed == 2, "static spawnable placed (2 statics)")
press("Training Range", "CAS", "Armour column", "T-72 column (era default)", "Once")
press("Training Range", "Air-to-Air", "Fighter pair", "Su-27", "Once")
check(last():find("The range is full %(5/5"), "total cap message")

-- Area Clear removes spawns and frees the cap; aircraft cap counts aircraft, not groups
press("Training Range", "SEAD/DEAD", "Clear SEAD/DEAD")
check(next(TR.areas.sead.spawns) == nil and groups[samGroup] == nil, "SEAD cleared")
press("Training Range", "Air-to-Air", "Fighter 4-ship", "Su-27", "Once")
check(last():find("Su%-27 spawned in Air%-to%-Air"), "4-ship spawned")
local four = next(TR.areas.a2a.spawns)
check(groups[TR.areas.a2a.spawns[four].group].tpl == "TR_TPL su27 x4", "4-ship uses the x4 template")
check(tasks[TR.areas.a2a.spawns[four].group].radius == 50000, "leashed to area + 10 km")
press("Training Range", "Air-to-Air", "Fighter pair", "Su-27", "Once")
check(last():find("Too many enemy aircraft %(4/4%)"), "aircraft cap message")

-- destroyed spawn is reported and frees its slot
local casSpawn
for _, s in pairs(TR.areas.cas.spawns) do if s.kind == "ground" then casSpawn = s end end
groups[casSpawn.group].size = 0
run(10)
check(last():find("T%-72 column destroyed in CAS%."), "destroyed message")

-- Repeating Spawn comes back after the delay, until the area is cleared
press("Training Range", "CAS", "Armour column", "T-72 column (era default)", "Repeat until cleared")
local rep
for _, s in pairs(TR.areas.cas.spawns) do if s.repeating then rep = s end end
groups[rep.group].size = 0
run(10)
check(last():find("Another one in 2 min"), "repeat announced")
run(125)
local again
for _, s in pairs(TR.areas.cas.spawns) do if s.repeating then again = s end end
check(again and again.id ~= rep.id, "repeat respawned")
groups[again.group].size = 0
run(10)
press("Training Range", "CAS", "Clear CAS")
run(200)
local none = true
for _, s in pairs(TR.areas.cas.spawns) do none = false end
check(none, "clearing cancels a pending repeat")

-- Practice Targets come back after 5 minutes, or at once on Area Clear
statics["TR_PT CAS circle 1"] = nil
run(60)
check(statics["TR_PT CAS circle 1"] == nil, "not back after 1 min")
run(300)
check(statics["TR_PT CAS circle 1"] ~= nil, "back after 5 min")
statics["TR_PT CAS circle 1"] = nil
TR.clearArea("cas")
check(statics["TR_PT CAS circle 1"] ~= nil, "Area Clear restores at once")
local radar = TR.areas.sead.practiceGroups.group1
groups[radar] = nil
run(310)
check(TR.areas.sead.practiceGroups.group1 ~= radar and groups[TR.areas.sead.practiceGroups.group1], "radar Practice Target respawned")

-- Range Reset clears every area
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
TR.resetRange()
check(last():find("Range Reset"), "range reset message")
local total = TR.totals()
check(total == 0, "nothing left after Range Reset")

print(string.format("training_range.lua: %d checks passed", passed))
