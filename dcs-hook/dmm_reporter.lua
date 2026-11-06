-- DCS Mission Maker: server-side load check.
--
-- Install on the machine running DCS (dedicated server or the PC you host from):
--   Saved Games\DCS.server\Scripts\Hooks\dmm_reporter.lua   (or Saved Games\DCS\...)
-- Download it from the app (/dcs-hook.lua) so APP_URL below is filled in.
--
-- 1. Load check: a minute after a mission starts it scans dcs.log for script
--    errors logged since the mission began loading and reports them to the app
--    ("Recent missions" and the Briefing Room).
-- 2. Debrief: it records kills, losses, ejections, crashes, take-offs and
--    landings, reads the mission's objective flags (9000 = all done, 9001+ =
--    each objective), and sends them to the app every minute and when the
--    mission ends. The Briefing Room's Debrief tab shows the result.
-- 3. Liveries: once per DCS session it lists the liveries installed on this
--    machine (DCS install and Saved Games\Liveries) so the app's livery
--    dropdowns show every livery your server has, by its in-game name.
-- 4. Training Range missions: tells the mission the hook is here (so Range Control
--    gets Mission Reload), reloads the mission when Range Control asks, reloads it by
--    itself every few hours while nobody is connected, and, when a Range Control
--    password is set in the app's Settings, locks the Range Control seats until a
--    player types  -rc <password>  in chat.
-- EXPERIMENTAL: not yet tested inside DCS.

local APP_URL = "__APP_URL__"
local CHECK_AFTER_SECONDS = 60
local DEBRIEF_EVERY_SECONDS = 60
local FIRST_FLAG, LAST_FLAG = 9000, 9010
local MAX_EVENTS = 500

-- Training Range (filled in by the app when you download this file)
local RANGE_PASSWORD = "__RANGE_PASSWORD__"          -- "" = Range Control seats open to anyone
local AUTO_RELOAD_HOURS = tonumber("__AUTO_RELOAD_HOURS__") or 6   -- 0 = never
local RANGE_FLAG, HOOK_FLAG, RELOAD_FLAG = 9032, 9030, 9031
local CONTROL_SUFFIX = " - Range Control"
local RANGE_POLL_SECONDS = 5
local MAX_PASSWORD_TRIES = 5
if RANGE_PASSWORD:find("^__") then RANGE_PASSWORD = "" end

package.path = package.path .. ";.\\LuaSocket\\?.lua"
package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll"
local ok_http, http = pcall(require, "socket.http")
local ok_ltn, ltn12 = pcall(require, "ltn12")

local dmm = { logOffset = 0, checkAt = nil, mission = "", events = {}, sent = 0, debriefAt = nil,
              liveriesSent = false, missionPath = nil, isRange = false, rangeAt = nil,
              startedAt = nil, reloading = false, unlocked = {}, tries = {} }
local logPath = lfs.writedir() .. "Logs\\dcs.log"

local function fileSize(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end")
  f:close()
  return size or 0
end

local function jsonString(s)
  s = tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', ''):gsub('\n', '\\n')
  return '"' .. s:gsub('[%c]', ' ') .. '"'
end

local function scanErrors()
  local f = io.open(logPath, "rb")
  if not f then return { "Could not open dcs.log" } end
  f:seek("set", dmm.logOffset)
  local errors = {}
  for line in f:lines() do
    if line:find("ERROR") and (line:find("SCRIPTING") or line:find("LuaNET")
        or line:find("Mission script error") or line:find("DO SCRIPT")) then
      errors[#errors + 1] = line:sub(1, 400)
      if #errors >= 25 then break end
    end
  end
  f:close()
  return errors
end

local function post(path, body)
  if not (ok_http and ok_ltn) then
    log.write("DMM", log.ERROR, "LuaSocket not available; can't report to " .. APP_URL)
    return nil
  end
  local _, code = http.request({
    url = APP_URL .. path, method = "POST",
    headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body) },
    source = ltn12.source.string(body),
  })
  return code
end

local function report(errors)
  local parts = {}
  for i, e in ipairs(errors) do parts[i] = jsonString(e) end
  local body = '{"mission":' .. jsonString(dmm.mission) .. ',"errors":[' .. table.concat(parts, ",") .. ']}'
  local code = post("/api/reports", body)
  log.write("DMM", log.INFO, "Reported " .. #errors .. " error(s) for " .. dmm.mission .. " -> HTTP " .. tostring(code))
end

-- ------------------------------------------------------------------- debrief
local function unitName(unitId)
  if not unitId then return nil end
  local ok, name = pcall(DCS.getUnitProperty, tonumber(unitId), DCS.UNIT_NAME)
  if ok and name and name ~= "" then return name end
  return nil
end

local function playerName(id)
  if not id or id < 1 then return nil end
  local ok, name = pcall(net.get_player_info, id, "name")
  if ok then return name end
  return nil
end

-- The slot (unit) a player is in, e.g. "Viper 1-2 (Mitsu)".
local function playerUnit(id)
  if not id or id < 1 then return nil end
  local ok, slot = pcall(net.get_player_info, id, "slot")
  if ok and slot and slot ~= "" then return unitName(slot) end
  return nil
end

local function record(e)
  if #dmm.events >= MAX_EVENTS then return end
  e.t = math.floor(DCS.getModelTime())
  dmm.events[#dmm.events + 1] = e
end

local function readFlag(n)
  local code = "return tostring(trigger.misc.getUserFlag(" .. n .. "))"
  for _, state in ipairs({ "server", "mission" }) do
    local ok, value = pcall(net.dostring_in, state, code)
    if ok and value and tonumber(value) then return tonumber(value) end
  end
  return nil
end

local function sendDebrief(final)
  local flags = {}
  for n = FIRST_FLAG, LAST_FLAG do
    local v = readFlag(n)
    if v then flags[tostring(n)] = v end
  end
  local fresh = {}
  for i = dmm.sent + 1, #dmm.events do fresh[#fresh + 1] = dmm.events[i] end
  if #fresh == 0 and not final and next(flags) == nil then return end
  local ok, body = pcall(net.lua2json, {
    mission = dmm.mission, from = dmm.sent, events = fresh, flags = flags,
    final = final and true or false, time = math.floor(DCS.getModelTime()),
  })
  if not ok then
    log.write("DMM", log.ERROR, "Could not encode debrief: " .. tostring(body))
    return
  end
  local code = post("/api/debrief", body)
  if code == 200 then dmm.sent = dmm.sent + #fresh end
end

-- ------------------------------------------------------------------ liveries
local MAX_PER_TYPE = 400

local function liveryName(dir)
  local f = io.open(dir .. "\\description.lua", "r")
  if not f then return nil end
  local text = f:read("*a") or ""
  f:close()
  return text:match('[^_%w]name%s*=%s*"([^"]+)"') or text:match("^name%s*=%s*\"([^\"]+)\"")
end

-- Adds every <type>\<livery> under a Liveries folder to found[type].
local function scanLiveries(root, found)
  if lfs.attributes(root, "mode") ~= "directory" then return end
  for typeName in lfs.dir(root) do
    local typeDir = root .. "\\" .. typeName
    if typeName ~= "." and typeName ~= ".." and lfs.attributes(typeDir, "mode") == "directory" then
      local list = found[typeName] or {}
      found[typeName] = list
      for entry in lfs.dir(typeDir) do
        local path = typeDir .. "\\" .. entry
        local mode = lfs.attributes(path, "mode")
        if #list < MAX_PER_TYPE and entry ~= "." and entry ~= ".." then
          if mode == "directory" then
            list[#list + 1] = { id = entry, name = liveryName(path) or entry }
          elseif mode == "file" and entry:lower():match("%.zip$") then
            local id = entry:sub(1, -5)
            list[#list + 1] = { id = id, name = id }
          end
        end
      end
    end
  end
end

-- Liveries live in Bazar, in each module's own folder, and in Saved Games.
local function installedLiveries()
  local found, install = {}, lfs.currentdir()
  if not install:match("[\\/]$") then install = install .. "\\" end
  scanLiveries(install .. "Bazar\\Liveries", found)
  for _, base in ipairs({ "CoreMods\\aircraft", "Mods\\aircraft", "CoreMods\\WWII Units" }) do
    local dir = install .. base
    if lfs.attributes(dir, "mode") == "directory" then
      for module in lfs.dir(dir) do
        if module ~= "." and module ~= ".." then scanLiveries(dir .. "\\" .. module .. "\\Liveries", found) end
      end
    end
  end
  local saved = lfs.writedir()
  if not saved:match("[\\/]$") then saved = saved .. "\\" end
  scanLiveries(saved .. "Liveries", found)
  return found
end

local function sendLiveries()
  local ok, body = pcall(net.lua2json, { types = installedLiveries() })
  if not ok then
    log.write("DMM", log.ERROR, "Could not encode liveries: " .. tostring(body))
    return
  end
  local code = post("/api/liveries", body)
  dmm.liveriesSent = code == 200
  log.write("DMM", log.INFO, "Sent installed liveries -> HTTP " .. tostring(code))
end

-- ------------------------------------------------------------- training range
local function setFlag(n, v)
  local code = "trigger.action.setUserFlag(" .. n .. ", " .. v .. ") return 'ok'"
  local ok, res = pcall(net.dostring_in, "server", code)
  if ok and res == "ok" then return true end
  ok = pcall(net.dostring_in, "mission", 'a_do_script("trigger.action.setUserFlag(' .. n .. ', ' .. v .. ')")')
  return ok
end

local function playersOnline()
  local ok, ids = pcall(net.get_player_list)
  if not ok or type(ids) ~= "table" then return 0 end
  local me = net.get_my_player_id and net.get_my_player_id() or 1
  local n = 0
  for _, id in ipairs(ids) do if id ~= me then n = n + 1 end end
  return n
end

local function reloadMission(why)
  if dmm.reloading or not dmm.missionPath then return end
  dmm.reloading = true
  log.write("DMM", log.INFO, "Training Range: reloading " .. dmm.missionPath .. " (" .. why .. ")")
  local ok, err = pcall(net.load_mission, dmm.missionPath)
  if not ok then   -- stays "reloading", so a broken reload isn't retried every 5 s
    log.write("DMM", log.ERROR, "Training Range: reload failed: " .. tostring(err))
  end
end

local function pollRange()
  if not dmm.isRange then
    dmm.isRange = readFlag(RANGE_FLAG) == 1
    if not dmm.isRange then return end
    log.write("DMM", log.INFO, "Training Range mission: Range Control reload and seat lock active")
  end
  if readFlag(HOOK_FLAG) ~= 1 then setFlag(HOOK_FLAG, 1) end
  if readFlag(RELOAD_FLAG) == 1 then
    reloadMission("asked for by Range Control")
  elseif AUTO_RELOAD_HOURS > 0 and dmm.startedAt
      and DCS.getRealTime() - dmm.startedAt >= AUTO_RELOAD_HOURS * 3600 and playersOnline() == 0 then
    reloadMission("automatic, server empty")
  end
end

-- The group a slot belongs to ("123" or "123_2" for a second crew seat).
local function slotGroup(slotID)
  local id = tonumber(tostring(slotID or ""):match("^(%d+)"))
  if not id then return nil end
  local ok, name = pcall(DCS.getUnitProperty, id, DCS.UNIT_GROUPNAME)
  if ok and type(name) == "string" then return name end
  return nil
end

local function isControlSlot(slotID)
  local group = slotGroup(slotID)
  return group ~= nil and group:sub(-#CONTROL_SUFFIX) == CONTROL_SUFFIX
end

local function tell(playerID, text) pcall(net.send_chat_to, text, playerID) end

local events = {}

function events.kill(killerId, killerType, killerSide, victimId, victimType, victimSide, weapon)
  record({ type = "kill", player = playerName(killerId), unit = playerUnit(killerId),
           killer_type = killerType, killer_side = killerSide, victim_player = playerName(victimId),
           victim_unit = playerUnit(victimId), victim_type = victimType, victim_side = victimSide,
           weapon = weapon })
end

for _, name in ipairs({ "crash", "eject", "pilot_death" }) do
  events[name] = function(playerId, unitId)
    record({ type = name, player = playerName(playerId), unit = unitName(unitId) or playerUnit(playerId) })
  end
end

for _, name in ipairs({ "takeoff", "landing" }) do
  events[name] = function(playerId, unitId, place)
    record({ type = name, player = playerName(playerId), unit = unitName(unitId) or playerUnit(playerId),
             place = place })
  end
end

function events.friendly_fire(playerId, weapon, victimId)
  record({ type = "friendly_fire", player = playerName(playerId), unit = playerUnit(playerId),
           victim_player = playerName(victimId), weapon = weapon })
end

function events.mission_end(winner, msg)
  record({ type = "mission_end", winner = winner, text = msg })
end

local callbacks = {}

function callbacks.onMissionLoadBegin()
  dmm.logOffset = fileSize(logPath)
  dmm.checkAt = nil
  dmm.events, dmm.sent, dmm.debriefAt = {}, 0, nil
  dmm.isRange, dmm.rangeAt, dmm.reloading = false, nil, false
end

function callbacks.onSimulationStart()
  dmm.mission = DCS.getMissionFilename and DCS.getMissionFilename() or DCS.getMissionName()
  dmm.missionPath = DCS.getMissionFilename and DCS.getMissionFilename() or nil
  dmm.mission = tostring(dmm.mission):match("([^\\/]+)$") or dmm.mission
  dmm.startedAt = DCS.getRealTime()
  dmm.rangeAt = DCS.getRealTime() + RANGE_POLL_SECONDS
  dmm.checkAt = DCS.getRealTime() + CHECK_AFTER_SECONDS
  dmm.debriefAt = DCS.getRealTime() + DEBRIEF_EVERY_SECONDS
  if not dmm.liveriesSent then
    local ok, err = pcall(sendLiveries)
    if not ok then log.write("DMM", log.ERROR, "liveries: " .. tostring(err)) end
  end
end

function callbacks.onGameEvent(name, ...)
  local handler = events[name]
  if handler and dmm.mission ~= "" then
    local ok, err = pcall(handler, ...)
    if not ok then log.write("DMM", log.ERROR, "event " .. tostring(name) .. ": " .. tostring(err)) end
  end
end

function callbacks.onSimulationStop()
  if dmm.mission ~= "" then
    local ok, err = pcall(sendDebrief, true)
    if not ok then log.write("DMM", log.ERROR, tostring(err)) end
  end
  dmm.debriefAt, dmm.rangeAt = nil, nil
end

-- Range Control seats: locked until "-rc <password>" when a password is set (ADR 0001).
function callbacks.onPlayerTryChangeSlot(playerID, side, slotID)
  if RANGE_PASSWORD == "" or dmm.unlocked[playerID] then return end
  local ok, control = pcall(isControlSlot, slotID)
  if ok and control then
    tell(playerID, "Range Control is locked. Type  -rc <password>  in chat, then take the seat again.")
    return false
  end
end

function callbacks.onPlayerTrySendChat(playerID, msg, all)
  local given = tostring(msg or ""):match("^%s*%-rc%s+(.-)%s*$")
  if not given then return end
  if RANGE_PASSWORD == "" then
    tell(playerID, "Range Control seats aren't locked on this server: just take one.")
  elseif (dmm.tries[playerID] or 0) >= MAX_PASSWORD_TRIES then
    tell(playerID, "Too many wrong Range Control passwords. Reconnect to try again.")
  elseif given == RANGE_PASSWORD then
    dmm.unlocked[playerID] = true
    tell(playerID, "Range Control unlocked: take a Range Control seat.")
  else
    dmm.tries[playerID] = (dmm.tries[playerID] or 0) + 1
    tell(playerID, "Wrong Range Control password.")
  end
  return ""     -- never show the password in chat
end

function callbacks.onPlayerDisconnect(playerID)
  dmm.unlocked[playerID], dmm.tries[playerID] = nil, nil
end

function callbacks.onSimulationFrame()
  if dmm.checkAt and DCS.getRealTime() >= dmm.checkAt then
    dmm.checkAt = nil
    local ok, err = pcall(function() report(scanErrors()) end)
    if not ok then log.write("DMM", log.ERROR, tostring(err)) end
  end
  if dmm.rangeAt and DCS.getRealTime() >= dmm.rangeAt then
    dmm.rangeAt = DCS.getRealTime() + RANGE_POLL_SECONDS
    local ok, err = pcall(pollRange)
    if not ok then log.write("DMM", log.ERROR, "range: " .. tostring(err)) end
  end
  if dmm.debriefAt and DCS.getRealTime() >= dmm.debriefAt then
    dmm.debriefAt = DCS.getRealTime() + DEBRIEF_EVERY_SECONDS
    local ok, err = pcall(sendDebrief, false)
    if not ok then log.write("DMM", log.ERROR, tostring(err)) end
  end
end

DCS.setUserCallbacks(callbacks)
log.write("DMM", log.INFO, "DCS Mission Maker reporter loaded, reporting to " .. APP_URL)
