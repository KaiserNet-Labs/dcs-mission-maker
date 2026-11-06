-- DCS Mission Maker: Training Range runtime.
--
-- Reads DMM_RANGE (written by the generator, see app/generator/range.py) and runs the
-- F10 > Training Range menu: spawn enemy forces into Range Areas, change each area's
-- difficulty, clear areas, and keep Practice Targets coming back. Vocabulary: CONTEXT.md.
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
  for _, a in pairs(TR.areas) do
    for _, s in pairs(a.spawns) do
      total = total + 1
      if s.kind == "air" then aircraft = aircraft + (s.size or 0) end
    end
  end
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
-- Places one Spawnable. Returns true and a message, or false and why not.
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
  local total, aircraft = TR.totals()
  if total >= C.caps.total then
    return false, string.format("The range is full (%d/%d spawns). Clear an area first.",
      C.caps.total, C.caps.total)
  end
  local size = role.size or sys.size or 2
  if sys.kind == "air" and aircraft + size > C.caps.aircraft then
    return false, string.format("Too many enemy aircraft (%d/%d). Clear the Air-to-Air area or "
      .. "shoot some down first.", aircraft, C.caps.aircraft)
  end

  TR.counter = TR.counter + 1
  local n = TR.counter
  local spawn = { id = n, area = areaId, role = roleId, system = sid, kind = sys.kind,
                  repeating = repeating and true or false, size = (sys.kind == "air") and size or nil }
  local name = string.format("TR %s %s #%d", label, sys.label, n)
  local skill = SKILL[area.difficulty]

  if sys.kind == "air" then
    local r = area.cfg.radius * 0.5
    local pos = offset(area.cfg.center, env.random() * 360, env.random() * r)
    local alt = sys.alt
    if sys.helicopter then alt = env.landHeight(pos) + sys.alt end
    local tpl = sys.templates[tostring(size)]
    spawn.group = env.spawnGroup(tpl, name, skill, pos, alt)
    if spawn.group then
      env.taskAir(spawn.group, area.cfg.center, area.cfg.radius + LEASH_MARGIN, alt, sys.speed)
    end
  else
    local slot = freeSlot(area)
    if not slot then return false, label .. " area has no free spot." end
    spawn.slot = slot
    local pos = area.cfg.slots[slot]
    if sys.kind == "static" then
      spawn.statics = {}
      for i, st in ipairs(sys.statics) do
        local p = offset(pos, st.bearing, st.dist)
        local def = { name = string.format("%s-%d", name, i), type = st.type,
                      category = st.category, shape_name = st.shape_name,
                      x = p.x, y = p.y, heading = 0, dead = false }
        spawn.statics[#spawn.statics + 1] = env.addStatic(def)
      end
    else
      local _, tpl = next(sys.templates)
      spawn.group = env.spawnGroup(tpl, name, skill, pos, nil)
      if spawn.group and sys.radar then
        env.setAlarm(spawn.group, area.difficulty == "easy" and "red" or "auto")
      end
    end
  end
  if sys.kind ~= "static" and not spawn.group then
    return false, "Could not spawn " .. sys.label .. " (template missing?)"
  end
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
function TR.check()
  checkSupport()
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
  msg("Range Reset: every area cleared and Practice Targets restored.", 15)
end

function TR.cycleDifficulty(id)
  local area = TR.areas[id]
  area.difficulty = NEXT_DIFF[area.difficulty]
  TR.buildMenu()
  msg(string.format("%s difficulty: %s. Applies to new spawns.", area.cfg.label,
    DIFF_LABEL[area.difficulty]), 10)
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
  return out
end

-- ---------------------------------------------------------------- start
function TR.start()
  C = DMM_RANGE
  TR.areas, TR.order, TR.counter, TR.root = {}, {}, 0, nil
  TR.support = {}
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
