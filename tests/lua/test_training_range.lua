-- Unit tests for app/lua/training_range.lua under plain Lua 5.1, with DCS and MOOSE stubbed.
-- Run from the repo root:  lua5.1 tests/lua/test_training_range.lua
-- (in Docker: see tests/range.py, which runs this too)

DMM_RANGE = {
  enemy_country = "CJTF_RED", difficulty = "normal",
  caps = { area = 3, aircraft = 4, total = 5 }, repeat_delay = 120, practice_respawn = 300,
  flags = { range = 9032, hook = 9030, reload = 9031 },
  support = { { group = "Overlord", label = "AWACS Overlord" }, { group = "Texaco", label = "Tanker Texaco" } },
  support_respawn = 60,
  range_control = { "Enfield 9 - Range Control" },
  marker = { leash = 37040, clear_radius = 1852, difficulty = "normal" },
  reload_countdown = 60,
  systems = {
    sa11 = { label = "SA-11", kind = "ground", radar = true, templates = { ["2"] = "TR_TPL sa11" },
             aliases = { "sa-11", "buk" } },
    t72 = { label = "T-72 column", kind = "ground", radar = false, templates = { ["2"] = "TR_TPL t72" },
            aliases = { "t-72", "supply" } },
    hq = { label = "Command post", kind = "static", aliases = { "supply" },
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
local inAir = {}
groups["Overlord"] = { size = 1 }
groups["Texaco"] = { size = 1 }
inAir["Overlord"], inAir["Texaco"] = true, true
env.groupInAir = function(name) return groups[name] ~= nil and inAir[name] == true end
local respawned = {}
env.respawnGroup = function(template, alias)
  groups[alias] = { size = 1, tpl = template }
  inAir[alias] = true
  respawned[#respawned + 1] = { template = template, alias = alias }
  return alias
end
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

local hookFlag, eventHandler = 0, nil
local groupMenus, groupMessages, allMessages, marks, removedMarks = {}, {}, {}, {}, {}
env.getFlag = function(n) if n == 9030 then return hookFlag end return flags[n] or 0 end
env.watchEvents = function(handler) eventHandler = handler end
env.menu.groupSub = function(gid, name, parent)
  menuId = menuId + 1
  groupMenus[menuId] = { gid = gid, name = name, parent = parent, alive = true }
  return menuId
end
env.menu.groupCmd = function(gid, name, parent, fn, arg)
  menuId = menuId + 1
  groupMenus[menuId] = { gid = gid, name = name, parent = parent, fn = fn, arg = arg, alive = true }
  return menuId
end
env.menu.groupRemove = function(gid, id)
  local function kill(i)
    groupMenus[i].alive = false
    for j, m in pairs(groupMenus) do if m.parent == i and m.alive then kill(j) end end
  end
  kill(id)
end
env.messageGroup = function(gid, text) groupMessages[#groupMessages + 1] = { gid = gid, text = text } end
env.messageAll = function(text) allMessages[#allMessages + 1] = text end
env.markRemove = function(id) removedMarks[id] = true end
env.markAdd = function(id, text, pos) marks[id] = { text = text, pos = pos } end

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

-- Support aircraft: a lost AWACS and a landed tanker are both replaced from their templates
groups["Overlord"] = nil
run(10)
check(last():find("AWACS Overlord is off station"), "lost AWACS announced")
run(65)
check(respawned[1] and respawned[1].template == "Overlord", "AWACS replaced from its template")
check(last():find("AWACS Overlord is back on station"), "replacement announced")
inAir["Texaco"] = false            -- landed at bingo
run(20)
check(groups["Texaco"] ~= nil, "a tanker on the ground isn't replaced straight away")
run(30)
check(groups["Texaco"] == nil, "landed tanker removed after the grace period")
run(70)
check(respawned[2] and respawned[2].template == "Texaco", "tanker replaced")
local awacs = respawned[1].alias
groups[awacs] = nil
run(80)
check(respawned[3] and respawned[3].template == "Overlord", "a replacement is replaced too")

-- ---------------------------------------------------------------- Range Control and Marker Spawn
TR.resetRange()
check(eventHandler ~= nil, "events watched")
local function adminItems(gid)
  local rootId
  for id, m in pairs(groupMenus) do if m.alive and m.gid == gid and m.parent == nil then rootId = id end end
  if not rootId then return nil end
  local out = {}
  for id, m in pairs(groupMenus) do if m.alive and m.parent == rootId then out[#out + 1] = { id = id, m = m } end end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
local function itemNames(gid)
  local names = {}
  for _, c in ipairs(adminItems(gid) or {}) do names[#names + 1] = c.m.name end
  return table.concat(names, "|")
end
local function pressAdmin(gid, name)
  for _, c in ipairs(adminItems(gid)) do if c.m.name == name then return c.m.fn(c.m.arg) end end
  error("no admin item " .. name)
end

eventHandler({ kind = "birth", group = "Viper 1 - SEAD", groupId = 11 })
check(adminItems(11) == nil, "no admin menu for other flights")
eventHandler({ kind = "birth", group = "Enfield 9 - Range Control", groupId = 42 })
check(itemNames(42) == "Range Reset (clear everything)|Clear all Marker Spawns|Marker Spawn help",
  "admin menu without the hook: " .. itemNames(42))
check(groupMessages[#groupMessages].text:find("Range Admin"), "seat greeting")
eventHandler({ kind = "birth", group = "Enfield 9 - Range Control", groupId = 42 })
local roots = 0
for _, m in pairs(groupMenus) do if m.alive and m.gid == 42 and m.parent == nil then roots = roots + 1 end end
check(roots == 1, "a second birth in the seat doesn't duplicate the menu")
pressAdmin(42, "Marker Spawn help")
check(groupMessages[#groupMessages].text:find("spawn sa10"), "marker help")

-- parsing
local c = TR.parseMarker("  Spawn  SA-10   Hard Repeat ")
check(c.cmd == "spawn" and c.name == "sa-10" and c.difficulty == "hard" and c.repeating, "parse full command")
c = TR.parseMarker("spawn mig 29 easy")
check(c.name == "mig 29" and c.difficulty == "easy" and not c.repeating, "parse multi-word name")
check(TR.parseMarker("clear").cmd == "clear" and TR.parseMarker("Clear all markers").cmd == "clearall", "parse clear")
check(TR.parseMarker("tanker track here") == nil and TR.parseMarker("spawn") == nil, "ordinary markers ignored")
check(TR.lookup("SA11") == "sa11" and TR.lookup("Buk") == "sa11" and TR.lookup("t 72") == "t72", "lookup aliases")
local sid, why = TR.lookup("supply")
check(sid == nil and why:find("could be Command post or T%-72 column"), "ambiguous name: " .. tostring(why))
sid, why = TR.lookup("sa01")
check(sid == nil and why == "unknown system 'sa01'", "unknown name")

local function mark(idx, text, who, pos)
  eventHandler({ kind = "mark", idx = idx, text = text, group = who and who.group, groupId = who and who.id,
                 pos = pos or { x = 200000, y = 5000 } })
end
local admin = { group = "Enfield 9 - Range Control", id = 42 }
local viper = { group = "Viper 1 - SEAD", id = 11 }
local function lastMark() local best, text = -1, nil for id, m in pairs(marks) do if id > best then best, text = id, m.text end end return text end

mark(1, "my notes", admin)
check(not removedMarks[1], "ordinary marker left alone")
mark(2, "spawn sa11", viper)
check(removedMarks[2] and lastMark():find("^✘ Range Admins only"), "non-admin refused")
local logged = env.log
env.log = function() end
mark(3, "spawn sa11", nil)
env.log = logged
check(lastMark():find("^✘ can't tell who"), "unknown author refused")
check(TR.totals() == 0, "refused markers spawn nothing")

mark(4, "spawn sa-11 hard", admin, { x = 200000, y = 5000 })
check(removedMarks[4] and lastMark() == "✔ SA-11 (Hard)", "admin marker spawn: " .. tostring(lastMark()))
local m1 = next(TR.markers)
check(groups[TR.markers[m1].group].skill == "Excellent", "Hard marker spawn = Excellent")
check(groups[TR.markers[m1].group].pos.x == 200000, "spawned at the marker")
check(groupMessages[#groupMessages].gid == 42, "result told to the admin's group")
mark(5, "spawn su27 repeat", admin, { x = 300000, y = 0 })
check(lastMark() == "✔ Su-27 (Normal, repeating)", "fighter marker spawn: " .. tostring(lastMark()))
local fighter
for _, s in pairs(TR.markers) do if s.system == "su27" then fighter = s end end
check(tasks[fighter.group].radius == 37040 and tasks[fighter.group].center.x == 300000, "marker fighter leashed ~20 nm")
check(groups[fighter.group].tpl == "TR_TPL su27 x2", "marker fighter is a pair")
mark(6, "spawn hq repeat", admin, { x = 201000, y = 5000 })
check(lastMark() == "✔ Command post (Normal) (can't repeat)", "statics can't repeat: " .. tostring(lastMark()))
mark(7, "spawn sa01", admin)
check(lastMark() == "✘ unknown system 'sa01'", "unknown system on the marker")
local total = TR.totals()
check(total == 3, "marker spawns count toward the total cap")

-- caps: the total cap (5) applies to Marker Spawns
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
press("Training Range", "SEAD/DEAD", "Medium SAM", "SA-11 (era default)")
mark(8, "spawn t72", admin)
check(lastMark():find("^✘ The range is full"), "total cap applies: " .. tostring(lastMark()))
press("Training Range", "SEAD/DEAD", "Clear SEAD/DEAD")
check(TR.totals() == 3, "Area Clear leaves Marker Spawns")

-- repeating marker fighter comes back at the marker
groups[fighter.group].size = 0
run(10)
check(last():find("Marker Spawn Su%-27 destroyed%. Another one"), "marker repeat announced")
run(125)
local back
for _, s in pairs(TR.markers) do if s.system == "su27" then back = s end end
check(back and back.id ~= fighter.id and back.pos.x == 300000, "marker repeat respawned at the marker")

-- clear: only Marker Spawns within 1 nm
mark(9, "clear", admin, { x = 200500, y = 5000 })
check(lastMark() == "✔ cleared 2 Marker Spawn(s) within 1 nm", "clear nearby: " .. tostring(lastMark()))
check(TR.totals() == 1, "fighter far away is kept")
groups[back.group].size = 0
run(10)
mark(10, "clear all markers", admin)
check(lastMark() == "✔ cleared 0 Marker Spawn(s)", "clear all")
run(200)
check(TR.totals() == 0, "clear all cancels a pending marker repeat")
mark(11, "spawn t72", admin)
TR.resetRange()
check(TR.totals() == 0, "Range Reset clears Marker Spawns")

-- Mission Reload: only with the hook; 60 s countdown; can be cancelled
check(TR.requestReload(42) == false and groupMessages[#groupMessages].text:find("needs the DCS Mission Maker hook"),
  "reload needs the hook")
hookFlag = 1
run(10)
check(itemNames(42):find("Mission Reload %(60 s countdown%)|Cancel Mission Reload"), "hook adds reload items: " .. itemNames(42))
pressAdmin(42, "Mission Reload (60 s countdown)")
check(allMessages[#allMessages]:find("Mission Reload in 60 seconds"), "countdown announced to everyone")
check(TR.requestReload(42) == false, "only one countdown at a time")
run(31)
check(allMessages[#allMessages] == "Mission Reload in 30 seconds.", "30 s warning")
pressAdmin(42, "Cancel Mission Reload")
run(40)
check(flags[9031] == nil and allMessages[#allMessages] == "Mission Reload cancelled.", "cancelled reload doesn't fire")
pressAdmin(42, "Mission Reload (60 s countdown)")
run(59)
check(flags[9031] == nil, "not before the countdown ends")
run(2)
check(flags[9031] == 1 and allMessages[#allMessages] == "Reloading the mission now.", "reload flag set for the hook")
local st = TR.state()
check(st[#st].id == "markers", "state lists Marker Spawns")

print(string.format("training_range.lua: %d checks passed", passed))
