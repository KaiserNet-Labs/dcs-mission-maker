-- DCS Mission Maker: Training Range runtime.
--
-- Reads DMM_RANGE (written by the generator, see app/generator/range.py) and runs the
-- F10 > Training Range menu: spawn enemy forces into Range Areas, change each area's
-- difficulty, clear areas, and keep Practice Targets coming back. Range Control seats also get
-- F10 > Range Control (Range Reset, Mission Reload) and may use Marker Spawn: an F10 map marker
-- reading "spawn sa10 hard". Vocabulary: CONTEXT.md.
--
-- Every call into DCS or MOOSE goes through TR.env, so tests can run this file under plain
-- Lua 5.1 with stubs (tests/lua/). Needs MOOSE (SPAWN) loaded first.

TR = TR or {}
local C = DMM_RANGE

local SKILL = { easy = "Average", normal = "Good", hard = "Excellent" }
local DIFF_LABEL = { easy = "Easy", normal = "Normal", hard = "Hard" }
local NEXT_DIFF = { easy = "normal", normal = "hard", hard = "easy" }
local CHECK_EVERY = 10
local LEASH_MARGIN = 10000

-- ---------------------------------------------------------------- DCS / MOOSE adapter
local env = {}
TR.env = env

function env.now() return timer.getTime() end

function env.schedule(fn, delay)
  timer.scheduleFunction(function() fn() return nil end, nil, timer.getTime() + delay)
end

function env.message(text, seconds)
  trigger.action.outTextForCoalition(coalition.side.BLUE, text, seconds or 10)
end

-- DCS's own global "env" logs to dcs.log; this file's adapter is a local of the same name.
function env.log(text) if _G.env and _G.env.info then _G.env.info("TR: " .. text) end end

env.menu = {}
function env.menu.sub(name, parent)
  return missionCommands.addSubMenuForCoalition(coalition.side.BLUE, name, parent)
end
function env.menu.cmd(name, parent, fn, arg)
  return missionCommands.addCommandForCoalition(coalition.side.BLUE, name, parent, fn, arg)
end
function env.menu.remove(path)
  missionCommands.removeItemForCoalition(coalition.side.BLUE, path)
end
-- Menus only one group sees (Range Control seats).
function env.menu.groupSub(gid, name, parent)
  return missionCommands.addSubMenuForGroup(gid, name, parent)
end
function env.menu.groupCmd(gid, name, parent, fn, arg)
  return missionCommands.addCommandForGroup(gid, name, parent, fn, arg)
end
function env.menu.groupRemove(gid, path) missionCommands.removeItemForGroup(gid, path) end

function env.messageGroup(gid, text, seconds) trigger.action.outTextForGroup(gid, text, seconds or 10) end
function env.messageAll(text, seconds) trigger.action.outText(text, seconds or 10) end

-- F10 map markers: replace a player's marker with a read-only one showing the result.
function env.markRemove(id) trigger.action.removeMark(id) end
function env.markAdd(id, text, pos)
  trigger.action.markToCoalition(id, text, { x = pos.x, y = land.getHeight({ x = pos.x, y = pos.y }),
    z = pos.y }, coalition.side.BLUE, true)
end

-- Births and markers, turned into plain tables: { kind = "birth", group, groupId } and
-- { kind = "mark", idx, text, pos, group, groupId } (group/groupId nil when DCS doesn't say who).
function env.watchEvents(handler)
  local E = world.event
  world.addEventHandler({ onEvent = function(_, e)
    if not e then return end
    local function who(unit)
      if not unit or not unit.getGroup then return nil, nil end
      local okg, g = pcall(unit.getGroup, unit)
      if not okg or not g then return nil, nil end
      return g:getName(), g:getID()
    end
    local ok, err = pcall(function()
      if e.id == E.S_EVENT_BIRTH then
        local name, gid = who(e.initiator)
        if name then handler({ kind = "birth", group = name, groupId = gid }) end
      elseif e.id == E.S_EVENT_MARK_ADDED or e.id == E.S_EVENT_MARK_CHANGE then
        local name, gid = who(e.initiator)
        if not gid and e.groupID and e.groupID > 0 then gid = e.groupID end
        handler({ kind = "mark", idx = e.idx, text = e.text or "", group = name, groupId = gid,
                  pos = { x = e.pos.x, y = e.pos.z }, initiator = e.initiator ~= nil })
      end
    end)
    if not ok then env.log("event failed: " .. tostring(err)) end
  end })
end

function env.landHeight(pos) return land.getHeight({ x = pos.x, y = pos.y }) end

-- Clones a late-activated template. Returns the new group's name, or nil.
function env.spawnGroup(template, alias, skill, pos, alt)
  local sp = SPAWN:NewWithAlias(template, alias):InitSkill(skill)
  local g
  if alt then
    g = sp:SpawnFromVec3({ x = pos.x, y = alt, z = pos.y })
  else
    g = sp:SpawnFromVec2({ x = pos.x, y = pos.y })
  end
  return g and g:GetName() or nil
end

function env.groupAlive(name)
  local g = Group.getByName(name)
  if not g or not g:isExist() then return 0 end
  return g:getSize()
end

function env.destroyGroup(name)
  local g = Group.getByName(name)
  if g and g:isExist() then g:destroy() end
end

function env.addStatic(def)
  coalition.addStaticObject(country.id[C.enemy_country], def)
  return def.name
end

function env.staticAlive(name)
  local s = StaticObject.getByName(name)
  return s ~= nil and s:isExist() and (s:getLife() or 1) >= 1
end

function env.destroyStatic(name)
  local s = StaticObject.getByName(name)
  if s and s:isExist() then s:destroy() end
end

function env.setFlag(n, v) trigger.action.setUserFlag(n, v) end
function env.getFlag(n) return trigger.misc.getUserFlag(n) end

-- Radar behaviour: "red" = always radiating, "auto" = the AI decides.
function env.setAlarm(name, state)
  local g = Group.getByName(name)
  if not g then return end
  local vals = AI.Option.Ground.val.ALARM_STATE
  g:getController():setOption(AI.Option.Ground.id.ALARM_STATE,
    state == "red" and vals.RED or vals.AUTO)
end

-- Leash: orbit the area centre and only engage air targets inside it (plus a margin).
function env.taskAir(name, center, radius, alt, speed)
  local g = Group.getByName(name)
  if not g then return end
  g:getController():setTask({ id = "Mission", params = { route = { points = { {
    x = center.x, y = center.y, alt = alt, alt_type = "BARO", speed = speed,
    type = "Turning Point", action = "Turning Point",
    task = { id = "ComboTask", params = { tasks = {
      { number = 1, id = "EngageTargetsInZone", enabled = true, auto = false,
        params = { point = { x = center.x, y = center.y }, zoneRadius = radius,
                   targetTypes = { "Air" }, priority = 0 } },
      { number = 2, id = "Orbit", enabled = true, auto = false,
        params = { pattern = "Circle", point = { x = center.x, y = center.y },
                   altitude = alt, speed = speed } },
    } } },
  } } } } })
end

function env.random() return math.random() end

-- Support aircraft: is the group's lead flying?
function env.groupInAir(name)
  local g = Group.getByName(name)
  local u = g and g:isExist() and g:getUnit(1)
  return u ~= nil and u ~= false and u:inAir()
end

-- A fresh copy of a group from its mission template, where the template starts.
function env.respawnGroup(template, alias)
  local g = SPAWN:NewWithAlias(template, alias):Spawn()
  return g and g:GetName() or nil
end

-- ---------------------------------------------------------------- state
TR.areas = {}          -- id -> { cfg, difficulty, spawns = {}, epoch, practice = {} }
TR.order = {}          -- area ids in menu order
TR.counter = 0
TR.root = nil

local function msg(text, seconds) env.message(text, seconds) end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function TR.totals()
  local total, aircraft = 0, 0
  local function add(list)
    for _, s in pairs(list) do
      total = total + 1
      if s.kind == "air" then aircraft = aircraft + (s.size or 0) end
    end
  end
  for _, a in pairs(TR.areas) do add(a.spawns) end
  add(TR.markers or {})
  return total, aircraft
end

local function freeSlot(area)
  local used = {}
  for _, s in pairs(area.spawns) do if s.slot then used[s.slot] = true end end
  for i = 1, #area.cfg.slots do if not used[i] then return i end end
  return nil
end

local function offset(pos, bearing, dist)
  local r = math.rad(bearing)
  return { x = pos.x + math.cos(r) * dist, y = pos.y + math.sin(r) * dist }
end

local function systemLabel(sid) return C.systems[sid] and C.systems[sid].label or sid end

local function findRole(area, roleId)
  for _, r in ipairs(area.cfg.roles) do if r.id == roleId then return r end end
  return nil
end

-- ---------------------------------------------------------------- spawning
-- The server-wide caps (Marker Spawns count only against these). Returns nil or why not.
local function capsFull(sys, size)
  local total, aircraft = TR.totals()
  if total >= C.caps.total then
    return string.format("The range is full (%d/%d spawns). Clear an area first.",
      C.caps.total, C.caps.total)
  end
  if sys.kind == "air" and aircraft + size > C.caps.aircraft then
    return string.format("Too many enemy aircraft (%d/%d). Clear the Air-to-Air area or "
      .. "shoot some down first.", aircraft, C.caps.aircraft)
  end
  return nil
end

-- Puts one system on the map and fills spawn.group / spawn.statics. `at` is where ground
-- units and statics go and where aircraft appear; aircraft orbit `leash` (center, radius).
-- Returns true, or false and why not.
local function place(spawn, sys, name, difficulty, at, leash)
  local skill = SKILL[difficulty]
  if sys.kind == "air" then
    local alt = sys.alt
    if sys.helicopter then alt = env.landHeight(at) + sys.alt end
    local tpl = sys.templates[tostring(spawn.size)]
    spawn.group = env.spawnGroup(tpl, name, skill, at, alt)
    if spawn.group then env.taskAir(spawn.group, leash.center, leash.radius, alt, sys.speed) end
  elseif sys.kind == "static" then
    spawn.statics = {}
    for i, st in ipairs(sys.statics) do
      local p = offset(at, st.bearing, st.dist)
      local def = { name = string.format("%s-%d", name, i), type = st.type,
                    category = st.category, shape_name = st.shape_name,
                    x = p.x, y = p.y, heading = 0, dead = false }
      spawn.statics[#spawn.statics + 1] = env.addStatic(def)
    end
  else
    local _, tpl = next(sys.templates)
    spawn.group = env.spawnGroup(tpl, name, skill, at, nil)
    if spawn.group and sys.radar then
      env.setAlarm(spawn.group, difficulty == "easy" and "red" or "auto")
    end
  end
  if sys.kind ~= "static" and not spawn.group then
    return false, "Could not spawn " .. sys.label .. " (template missing?)"
  end
  return true
end

-- Places one Spawnable in a Range Area. Returns true and a message, or false and why not.
function TR.spawn(areaId, roleId, sid, repeating, epoch)
  local area = TR.areas[areaId]
  if not area then return false, "Unknown area " .. tostring(areaId) end
  if epoch and epoch ~= area.epoch then return false, "cleared" end   -- a stale repeat
  local role = findRole(area, roleId)
  local sys = C.systems[sid]
  if not role or not sys then return false, "Unknown spawn " .. tostring(sid) end
  local label = area.cfg.label

  if count(area.spawns) >= C.caps.area then
    return false, string.format("%s area is full (%d/%d). Use Clear %s or destroy something first.",
      label, C.caps.area, C.caps.area, label)
  end
  local size = role.size or sys.size or 2
  local full = capsFull(sys, size)
  if full then return false, full end

  local spawn = { area = areaId, role = roleId, system = sid, kind = sys.kind,
                  repeating = repeating and true or false, size = (sys.kind == "air") and size or nil }
  local at
  if sys.kind == "air" then
    at = offset(area.cfg.center, env.random() * 360, env.random() * area.cfg.radius * 0.5)
  else
    local slot = freeSlot(area)
    if not slot then return false, label .. " area has no free spot." end
    spawn.slot, at = slot, area.cfg.slots[slot]
  end
  TR.counter = TR.counter + 1
  local n = TR.counter
  spawn.id = n
  local ok, why = place(spawn, sys, string.format("TR %s %s #%d", label, sys.label, n),
    area.difficulty, at, { center = area.cfg.center, radius = area.cfg.radius + LEASH_MARGIN })
  if not ok then return false, why end
  area.spawns[n] = spawn
  local mode = spawn.repeating and ", repeating" or ""
  return true, string.format("%s spawned in %s (%s%s). %d/%d in this area.", sys.label, label,
    DIFF_LABEL[area.difficulty], mode, count(area.spawns), C.caps.area)
end

local function alive(spawn)
  if spawn.group then return env.groupAlive(spawn.group) > 0 end
  for _, s in ipairs(spawn.statics or {}) do
    if env.staticAlive(s) then return true end
  end
  return false
end

local function removeSpawn(spawn)
  if spawn.group then env.destroyGroup(spawn.group) end
  for _, s in ipairs(spawn.statics or {}) do env.destroyStatic(s) end
end

-- ---------------------------------------------------------------- Practice Targets
local function practiceStatics(area)
  local out = {}
  for _, pt in ipairs(area.cfg.practice or {}) do
    for _, st in ipairs(pt.statics or {}) do out[#out + 1] = st end
  end
  return out
end

local function restorePractice(area, force)
  local now = env.now()
  for _, st in ipairs(practiceStatics(area)) do
    if env.staticAlive(st.name) then
      area.deadSince[st.name] = nil
    else
      area.deadSince[st.name] = area.deadSince[st.name] or now
      if force or now - area.deadSince[st.name] >= C.practice_respawn then
        env.addStatic({ name = st.name, type = st.type, category = st.category,
                        shape_name = st.shape_name, x = st.x, y = st.y,
                        heading = st.heading or 0, dead = false })
        area.deadSince[st.name] = nil
      end
    end
  end
  for i, pt in ipairs(area.cfg.practice or {}) do
    if pt.template then
      local key = "group" .. i
      local current = area.practiceGroups[key]
      if current and env.groupAlive(current) > 0 then
        area.deadSince[key] = nil
      else
        area.deadSince[key] = area.deadSince[key] or now
        if force or not current or now - area.deadSince[key] >= C.practice_respawn then
          if current then env.destroyGroup(current) end
          TR.counter = TR.counter + 1
          area.practiceGroups[key] = env.spawnGroup(pt.template,
            string.format("TR %s %s #%d", area.cfg.label, pt.label, TR.counter), "Average", pt.pos, nil)
          if area.practiceGroups[key] then env.setAlarm(area.practiceGroups[key], "red") end
          area.deadSince[key] = nil
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- support aircraft
-- AWACS and tankers are replaced when they land (bingo) or are lost, so a long session keeps
-- them. A replacement starts where the original did, on its orbit.
local LANDED_GRACE = 30

local function checkSupport()
  local now = env.now()
  for _, s in ipairs(TR.support) do
    if s.pendingAt then
      if now >= s.pendingAt then
        TR.counter = TR.counter + 1
        local name = env.respawnGroup(s.template, string.format("%s #%d", s.template, TR.counter))
        s.pendingAt = nil
        if name then
          s.current, s.airborne, s.groundSince = name, false, nil
          msg(s.label .. " is back on station.", 10)
        end
      end
    else
      local alive = env.groupAlive(s.current) > 0
      local flying = alive and env.groupInAir(s.current)
      if flying then
        s.airborne, s.groundSince = true, nil
      elseif alive and s.airborne then
        s.groundSince = s.groundSince or now
      end
      local landed = s.groundSince and now - s.groundSince >= LANDED_GRACE
      if not alive or landed then
        if alive then env.destroyGroup(s.current) end
        s.pendingAt = now + C.support_respawn
        msg(string.format("%s is off station. A replacement checks in in about %d min.", s.label,
          math.max(1, math.floor(C.support_respawn / 60))), 10)
      end
    end
  end
end

-- ---------------------------------------------------------------- periodic check
local function checkMarkers()
  for n, spawn in pairs(TR.markers) do
    if not alive(spawn) then
      TR.markers[n] = nil
      local label = systemLabel(spawn.system)
      if spawn.repeating and not spawn.chain.cancelled then
        msg(string.format("Marker Spawn %s destroyed. Another one in %d min.", label,
          math.floor(C.repeat_delay / 60)), 10)
        TR.markerRepeats[spawn.chain] = spawn.pos
        env.schedule(function()
          TR.markerRepeats[spawn.chain] = nil
          local ok, text = TR.markerSpawn(spawn.system, spawn.difficulty, true, spawn.pos, spawn.chain)
          if text ~= "cleared" then msg("Marker Spawn: " .. text, 10) end
        end, C.repeat_delay)
      else
        msg(string.format("Marker Spawn %s destroyed.", label), 10)
      end
    end
  end
end

-- The hook sets its flag when the mission starts; Mission Reload appears once it has.
local function checkHook()
  local present = TR.hookPresent()
  if present ~= TR.hookSeen then
    TR.hookSeen = present
    for gid in pairs(TR.adminMenus) do TR.buildAdminMenu(gid) end
  end
end

function TR.check()
  checkSupport()
  checkMarkers()
  checkHook()
  for _, id in ipairs(TR.order) do
    local area = TR.areas[id]
    for n, spawn in pairs(area.spawns) do
      if not alive(spawn) then
        area.spawns[n] = nil
        local label = systemLabel(spawn.system)
        if spawn.repeating then
          local epoch = area.epoch
          msg(string.format("%s destroyed in %s. Another one in %d min.", label, area.cfg.label,
            math.floor(C.repeat_delay / 60)), 10)
          env.schedule(function()
            local ok, text = TR.spawn(id, spawn.role, spawn.system, true, epoch)
            if text ~= "cleared" then msg(text, 10) end
          end, C.repeat_delay)
        else
          msg(string.format("%s destroyed in %s.", label, area.cfg.label), 10)
        end
      end
    end
    restorePractice(area, false)
  end
end

local function loop()
  local ok, err = pcall(TR.check)
  if not ok then env.log("check failed: " .. tostring(err)) end
  env.schedule(loop, CHECK_EVERY)
end

-- ---------------------------------------------------------------- area controls
function TR.clearArea(id, quiet)
  local area = TR.areas[id]
  if not area then return end
  for n, spawn in pairs(area.spawns) do
    removeSpawn(spawn)
    area.spawns[n] = nil
  end
  area.epoch = area.epoch + 1      -- cancels pending repeats
  restorePractice(area, true)
  if not quiet then msg(area.cfg.label .. " area cleared. Practice Targets restored.", 10) end
end

function TR.resetRange()
  for _, id in ipairs(TR.order) do TR.clearArea(id, true) end
  TR.clearMarkers(nil)
  msg("Range Reset: every area and Marker Spawn cleared, Practice Targets restored.", 15)
end

function TR.cycleDifficulty(id)
  local area = TR.areas[id]
  area.difficulty = NEXT_DIFF[area.difficulty]
  TR.buildMenu()
  msg(string.format("%s difficulty: %s. Applies to new spawns.", area.cfg.label,
    DIFF_LABEL[area.difficulty]), 10)
end

-- ---------------------------------------------------------------- Marker Spawn
-- A Range Admin's F10 map marker: "spawn <system> [easy|normal|hard] [repeat]", "clear"
-- (Marker Spawns within 1 nm) or "clear all markers". Other markers are left alone.
local function norm(text) return (tostring(text):lower():gsub("[^%w]", "")) end
local function trim(text) return (tostring(text):gsub("^%s+", ""):gsub("%s+$", "")) end

function TR.parseMarker(text)
  local t = trim(text):lower():gsub("%s+", " ")
  if t == "clear all markers" or t == "clear all" then return { cmd = "clearall" } end
  if t == "clear" then return { cmd = "clear" } end
  local rest = t:match("^spawn%s+(.+)$")
  if not rest then return nil end
  local words = {}
  for w in rest:gmatch("%S+") do words[#words + 1] = w end
  local cmd = { cmd = "spawn", difficulty = nil, repeating = false }
  while #words > 1 do
    local last = words[#words]
    if SKILL[last] and not cmd.difficulty then cmd.difficulty = last
    elseif (last == "repeat" or last == "repeating") and not cmd.repeating then cmd.repeating = true
    else break end
    words[#words] = nil
  end
  cmd.name = table.concat(words, " ")
  return cmd
end

-- Marker Spawn name -> system id. Exact ids win; otherwise a name must match one system.
function TR.lookup(name)
  local key = norm(name)
  if key == "" then return nil, "no system named" end
  if C.systems[key] then return key end
  local found, labels = {}, {}
  for sid, sys in pairs(C.systems) do
    local names = { sid, sys.label }
    for _, a in ipairs(sys.aliases or {}) do names[#names + 1] = a end
    for _, n in ipairs(names) do
      if norm(n) == key and not found[sid] then
        found[sid] = true
        labels[#labels + 1] = sys.label
      end
    end
  end
  if #labels == 1 then return next(found) end
  if #labels > 1 then
    table.sort(labels)
    return nil, "'" .. name .. "' could be " .. table.concat(labels, " or ")
  end
  return nil, "unknown system '" .. name .. "'"
end

-- Group size and whether a system may repeat, from the Spawn Roles that offer it.
local function roleInfo(sid)
  local size, repeatable = nil, false
  for _, id in ipairs(TR.order) do
    for _, r in ipairs(TR.areas[id].cfg.roles) do
      for _, s in ipairs(r.systems) do
        if s == sid then
          size = size or r.size
          repeatable = repeatable or r.repeatable
        end
      end
    end
  end
  return size, repeatable
end

function TR.markerSpawn(sid, difficulty, repeating, pos, chain)
  if chain and chain.cancelled then return false, "cleared" end
  local sys = C.systems[sid]
  local size, repeatable = roleInfo(sid)
  size = size or sys.size or 2
  local full = capsFull(sys, size)
  if full then return false, full end
  local note = ""
  if repeating and not repeatable then repeating, note = false, " (can't repeat)" end
  TR.counter = TR.counter + 1
  local n = TR.counter
  local spawn = { id = n, system = sid, kind = sys.kind, size = (sys.kind == "air") and size or nil,
                  repeating = repeating, difficulty = difficulty, pos = pos,
                  chain = chain or { cancelled = false } }
  local ok, why = place(spawn, sys, string.format("TR Marker %s #%d", sys.label, n), difficulty, pos,
    { center = pos, radius = C.marker.leash })
  if not ok then return false, why end
  TR.markers[n] = spawn
  return true, string.format("%s (%s%s)%s", sys.label, DIFF_LABEL[difficulty],
    repeating and ", repeating" or "", note)
end

local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Removes Marker Spawns within `radius` of pos (all of them when pos is nil). Returns how many.
function TR.clearMarkers(pos, radius)
  local n = 0
  for chain, at in pairs(TR.markerRepeats) do        -- destroyed, waiting to come back
    if not pos or distance(pos, at) <= radius then
      chain.cancelled = true
      TR.markerRepeats[chain] = nil
    end
  end
  for id, spawn in pairs(TR.markers) do
    if not pos or distance(pos, spawn.pos) <= radius then
      spawn.chain.cancelled = true
      removeSpawn(spawn)
      TR.markers[id] = nil
      n = n + 1
    end
  end
  return n
end

-- true = a Range Admin, false = not, nil = DCS didn't say who placed the marker.
local function markerAdmin(e)
  if e.group then return TR.controlNames[e.group] == true end
  if e.groupId then return TR.controlIds[e.groupId] == true end
  return nil
end

function TR.onMark(e)
  local cmd = TR.parseMarker(e.text)
  if not cmd then return end
  local admin = markerAdmin(e)
  local ok, result = false, nil
  if admin == nil then
    result = "can't tell who placed this marker"
    env.log("marker without an initiator or group: " .. tostring(e.text))
  elseif not admin then
    result = "Range Admins only: take a Range Control seat"
  elseif cmd.cmd == "clearall" then
    ok, result = true, string.format("cleared %d Marker Spawn(s)", TR.clearMarkers(nil))
  elseif cmd.cmd == "clear" then
    ok, result = true, string.format("cleared %d Marker Spawn(s) within 1 nm",
      TR.clearMarkers(e.pos, C.marker.clear_radius))
  else
    local sid, why = TR.lookup(cmd.name)
    if sid then
      ok, result = TR.markerSpawn(sid, cmd.difficulty or C.marker.difficulty, cmd.repeating, e.pos)
    else
      result = why
    end
  end
  local text = (ok and "✔ " or "✘ ") .. result
  env.markRemove(e.idx)
  TR.markId = TR.markId + 1
  env.markAdd(TR.markId, text, e.pos)
  if e.groupId then env.messageGroup(e.groupId, "Marker Spawn: " .. text, 10) end
end

-- ---------------------------------------------------------------- Mission Reload
function TR.hookPresent() return env.getFlag(C.flags.hook) == 1 end

function TR.requestReload(gid)
  if not TR.hookPresent() then
    env.messageGroup(gid, "Mission Reload needs the DCS Mission Maker hook on the server.", 10)
    return false
  end
  if TR.reload then
    env.messageGroup(gid, "A Mission Reload is already counting down.", 10)
    return false
  end
  local token = {}
  TR.reload = token
  local wait = C.reload_countdown
  env.messageAll(string.format("Mission Reload in %d seconds: everyone goes back to slot selection "
    .. "and the range starts fresh.", wait), 15)
  for _, left in ipairs({ 30, 10 }) do
    if left < wait then
      env.schedule(function()
        if TR.reload == token then env.messageAll(string.format("Mission Reload in %d seconds.", left), 8) end
      end, wait - left)
    end
  end
  env.schedule(function()
    if TR.reload ~= token then return end
    env.messageAll("Reloading the mission now.", 10)
    env.setFlag(C.flags.reload, 1)
  end, wait)
  return true
end

function TR.cancelReload(gid)
  if not TR.reload then
    env.messageGroup(gid, "No Mission Reload is counting down.", 10)
    return false
  end
  TR.reload = nil
  env.messageAll("Mission Reload cancelled.", 10)
  return true
end

-- ---------------------------------------------------------------- Range Control menu
local MARKER_HELP = "Marker Spawn: put a marker on the F10 map and type\n"
  .. "  spawn sa10            (Normal difficulty)\n"
  .. "  spawn mig29 hard repeat\n"
  .. "  clear                 (Marker Spawns within 1 nm)\n"
  .. "  clear all markers\n"
  .. "Names as in the Training Range menu; dashes and spaces don't matter (sa-10, sa10, s300)."

function TR.buildAdminMenu(gid)
  if TR.adminMenus[gid] then env.menu.groupRemove(gid, TR.adminMenus[gid]) end
  local root = env.menu.groupSub(gid, "Range Control", nil)
  TR.adminMenus[gid] = root
  env.menu.groupCmd(gid, "Range Reset (clear everything)", root, function() TR.resetRange() end)
  env.menu.groupCmd(gid, "Clear all Marker Spawns", root, function()
    env.messageAll(string.format("Range Control cleared %d Marker Spawn(s).", TR.clearMarkers(nil)), 10)
  end)
  env.menu.groupCmd(gid, "Marker Spawn help", root, function() env.messageGroup(gid, MARKER_HELP, 30) end)
  if TR.hookPresent() then
    env.menu.groupCmd(gid, "Mission Reload (" .. C.reload_countdown .. " s countdown)", root,
      function() TR.requestReload(gid) end)
    env.menu.groupCmd(gid, "Cancel Mission Reload", root, function() TR.cancelReload(gid) end)
  end
end

function TR.onBirth(e)
  if not TR.controlNames[e.group] or not e.groupId then return end
  TR.controlIds[e.groupId] = true
  if not TR.adminMenus[e.groupId] then TR.buildAdminMenu(e.groupId) end
  env.messageGroup(e.groupId, "You're the Range Admin while you sit here: F10 > Other > Range Control. "
    .. "Use Marker Spawn help for map-marker commands.", 15)
end

function TR.onEvent(e)
  if e.kind == "birth" then TR.onBirth(e) elseif e.kind == "mark" then TR.onMark(e) end
end

-- ---------------------------------------------------------------- menu
local function onSpawn(args)
  local ok, text = TR.spawn(args.area, args.role, args.system, args.repeating)
  msg(text, 10)
end

function TR.buildMenu()
  if TR.root then env.menu.remove(TR.root) end
  TR.root = env.menu.sub("Training Range", nil)
  for _, id in ipairs(TR.order) do
    local area = TR.areas[id]
    local sub = env.menu.sub(area.cfg.label, TR.root)
    for _, role in ipairs(area.cfg.roles) do
      local rmenu = env.menu.sub(role.label, sub)
      for _, sid in ipairs(role.systems) do
        local label = systemLabel(sid)
        if sid == role.default then label = label .. " (era default)" end
        local args = { area = id, role = role.id, system = sid }
        if role.repeatable then
          local smenu = env.menu.sub(label, rmenu)
          env.menu.cmd("Once", smenu, onSpawn, args)
          env.menu.cmd("Repeat until cleared", smenu, onSpawn,
            { area = id, role = role.id, system = sid, repeating = true })
        else
          env.menu.cmd(label, rmenu, onSpawn, args)
        end
      end
    end
    env.menu.cmd("Difficulty: " .. DIFF_LABEL[area.difficulty] .. " (change)", sub,
      TR.cycleDifficulty, id)
    env.menu.cmd("Clear " .. area.cfg.label, sub, TR.clearArea, id)
  end
end

-- ---------------------------------------------------------------- state for the hook
function TR.state()
  local out = {}
  for _, id in ipairs(TR.order) do
    local area = TR.areas[id]
    local items = {}
    for _, s in pairs(area.spawns) do
      items[#items + 1] = { system = s.system, label = systemLabel(s.system),
                            repeating = s.repeating, slot = s.slot }
    end
    out[#out + 1] = { id = id, difficulty = area.difficulty, spawns = items }
  end
  local marks = {}
  for _, s in pairs(TR.markers) do
    marks[#marks + 1] = { system = s.system, label = systemLabel(s.system), repeating = s.repeating,
                          x = s.pos.x, y = s.pos.y }
  end
  out[#out + 1] = { id = "markers", spawns = marks }
  return out
end

-- ---------------------------------------------------------------- start
function TR.start()
  C = DMM_RANGE
  TR.areas, TR.order, TR.counter, TR.root = {}, {}, 0, nil
  TR.support, TR.markers, TR.markId, TR.reload = {}, {}, 900000, nil
  TR.markerRepeats = {}     -- chain -> marker position, for repeats waiting to respawn
  TR.controlNames, TR.controlIds, TR.adminMenus = {}, {}, {}
  for _, name in ipairs(C.range_control or {}) do TR.controlNames[name] = true end
  TR.hookSeen = TR.hookPresent()
  for _, s in ipairs(C.support or {}) do
    TR.support[#TR.support + 1] = { template = s.group, label = s.label, current = s.group,
                                    airborne = false }
  end
  for _, cfg in ipairs(C.areas) do
    TR.areas[cfg.id] = { cfg = cfg, difficulty = C.difficulty, spawns = {}, epoch = 0,
                         deadSince = {}, practiceGroups = {} }
    TR.order[#TR.order + 1] = cfg.id
  end
  for _, id in ipairs(TR.order) do restorePractice(TR.areas[id], false) end
  TR.buildMenu()
  env.setFlag(C.flags.range, 1)
  env.watchEvents(TR.onEvent)
  env.schedule(loop, CHECK_EVERY)
  env.schedule(function()
    msg("Training Range ready: F10 > Other > Training Range to spawn enemy forces. "
      .. "Range Areas are drawn in orange on the F10 map.", 20)
  end, 10)
end

if not TR_NO_AUTOSTART then
  local ok, err = pcall(TR.start)
  if not ok then env.log("start failed: " .. tostring(err)) end
end
