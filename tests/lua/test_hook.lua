-- Tests for the Training Range parts of dcs-hook/dmm_reporter.lua under plain Lua 5.1, with
-- DCS's hook API stubbed. Run from the repo root:  lua5.1 tests/lua/test_hook.lua [password]

local password = ... or "s3cret"
local src = assert(io.open("dcs-hook/dmm_reporter.lua")):read("*a")
src = src:gsub("__RANGE_PASSWORD__", password):gsub("__AUTO_RELOAD_HOURS__", "6")

local realTime, flags, chats, loaded, callbacks = 0, {}, {}, {}, nil
local players = { 1 }
local units = { [101] = "Enfield 9 - Range Control", [102] = "Viper 1 - SEAD" }
log = { INFO = 1, ERROR = 2, write = function() end }
lfs = { writedir = function() return "/nonexistent/" end }
DCS = {
  UNIT_NAME = 1, UNIT_GROUPNAME = 2,
  setUserCallbacks = function(cb) callbacks = cb end,
  getRealTime = function() return realTime end,
  getModelTime = function() return realTime end,
  getMissionFilename = function() return "C:\\Saved Games\\DCS.server\\Missions\\range.miz" end,
  getUnitProperty = function(id, what) if what == 2 then return units[id] end return nil end,
}
net = {
  dostring_in = function(state, code)
    if state ~= "server" then return nil end
    local n = code:match("getUserFlag%((%d+)%)")
    if n then return tostring(flags[tonumber(n)] or 0) end
    local sn, v = code:match("setUserFlag%((%d+), (%d+)%)")
    if sn then flags[tonumber(sn)] = tonumber(v) return "ok" end
  end,
  send_chat_to = function(text, id) chats[#chats + 1] = { id = id, text = text } end,
  get_player_list = function() return players end,
  get_my_player_id = function() return 1 end,
  load_mission = function(path) loaded[#loaded + 1] = path return true end,
  lua2json = function() return "{}" end,
}
assert(loadstring(src))()

local passed = 0
local function check(cond, what)
  if not cond then error("FAIL: " .. what, 2) end
  passed = passed + 1
end
local function tick(seconds)
  local stop = realTime + seconds
  while realTime < stop do realTime = realTime + 1 callbacks.onSimulationFrame() end
end

-- an ordinary mission: nothing happens
callbacks.onMissionLoadBegin()
callbacks.onSimulationStart()
tick(10)
check(flags[9030] == nil, "no hook flag in an ordinary mission")

-- a Training Range: the hook flags itself, then reloads when asked
callbacks.onMissionLoadBegin()
flags = { [9032] = 1 }
callbacks.onSimulationStart()
tick(6)
check(flags[9030] == 1, "hook flag set in a Training Range")
flags[9031] = 1
tick(6)
check(#loaded == 1 and loaded[1]:find("range%.miz$"), "reload on the Range Control flag")
tick(10)
check(#loaded == 1, "only one reload")

-- automatic reload: after 6 h, only while nobody is connected
callbacks.onMissionLoadBegin()
flags = { [9032] = 1 }
callbacks.onSimulationStart()
players = { 1, 7 }
tick(6 * 3600 + 10)
check(#loaded == 1, "no automatic reload with a player on")
players = { 1 }
tick(10)
check(#loaded == 2, "automatic reload once the server is empty")

if password == "" then         -- no password in Settings: seats open, "-rc" explains
  check(callbacks.onPlayerTryChangeSlot(7, 2, "101") == nil, "Range Control open without a password")
  check(callbacks.onPlayerTrySendChat(7, "-rc x", true) == "" and chats[#chats].text:find("aren't locked"),
    "-rc explains there's no lock")
  print(string.format("dmm_reporter.lua (Training Range, no password): %d checks passed", passed))
  return
end

-- Range Control seat lock
check(callbacks.onPlayerTryChangeSlot(7, 2, "102") == nil, "other seats open")
check(callbacks.onPlayerTryChangeSlot(7, 2, "101") == false, "Range Control seat locked")
check(chats[#chats].text:find("%-rc <password>"), "told how to unlock")
check(callbacks.onPlayerTryChangeSlot(7, 2, "101_2") == false, "second crew seat locked too")
check(callbacks.onPlayerTrySendChat(7, "-rc wrong", true) == "", "wrong password hidden from chat")
check(chats[#chats].text == "Wrong Range Control password.", "wrong password told")
check(callbacks.onPlayerTrySendChat(7, "hello all", true) == nil, "ordinary chat untouched")
check(callbacks.onPlayerTrySendChat(7, " -rc " .. password .. " ", true) == "", "password hidden from chat")
check(callbacks.onPlayerTryChangeSlot(7, 2, "101") == nil, "seat open after the password")
check(callbacks.onPlayerTryChangeSlot(8, 2, "101") == false, "still locked for another player")
for _ = 1, 5 do callbacks.onPlayerTrySendChat(8, "-rc guess", true) end
callbacks.onPlayerTrySendChat(8, "-rc " .. password, true)
check(chats[#chats].text:find("Too many wrong"), "password guessing stops after 5 tries")
check(callbacks.onPlayerTryChangeSlot(8, 2, "101") == false, "guesser stays locked")
callbacks.onPlayerDisconnect(7)
check(callbacks.onPlayerTryChangeSlot(7, 2, "101") == false, "unlock ends when the player leaves")

print(string.format("dmm_reporter.lua (Training Range): %d checks passed", passed))
