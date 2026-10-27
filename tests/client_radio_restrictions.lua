local function fixture()
    local e = setmetatable({}, { __index = _G })
    local state = {
        nui = {}, net = {}, events = {}, messages = {}, state_handlers = {}, global_state = {},
        joined = 0, left = 0, blocked = nil,
    }
    e.Config = { Radio = { AutoRejoin = false, Notifications = false, DefaultVolume = 50 } }
    e.Bridge = { Debug = function() end, Radio = {}, Callbacks = {}, PlayerState = {} }
    e.Bridge.PlayerState.GetBlockReason = function() return state.blocked end
    local radio = e.Bridge.Radio
    radio.SupportsSecondary = function() return true end
    radio.SupportsSpeaker = function() return false end
    radio.GetProvider = function() return state.provider or "yaca" end
    radio.GetSpeaker = function() return false end
    radio.Join = function() state.joined = state.joined + 1; if state.on_join then state.on_join() end; return true end
    radio.Leave = function() state.left = state.left + 1 end
    radio.SetVolume = function() end
    e.Bridge.Callbacks.Trigger = function(name)
        if state.on_request then state.on_request(name) end
        if state.reply then return state.reply(name) end
        return { success = true, data = { frequency = 150, secondaryFrequency = 160, connected = true } }
    end
    e.RegisterNUICallback = function(name, fn) state.nui[name] = fn end
    e.RegisterNetEvent = function(name, fn) state.net[name] = fn end
    e.AddEventHandler = function(name, fn) state.events[name] = fn end
    e.SendNUIMessage = function(message) state.messages[#state.messages + 1] = message end
    e.PlayerId = function() return 1 end
    e.GetPlayerServerId = function() return state.server_id or 1 end
    e.GlobalState = state.global_state
    e.AddStateBagChangeHandler = function(key, _, fn)
        local cookie = { key = key, fn = fn }
        state.state_handlers[#state.state_handlers + 1] = cookie
        return cookie
    end
    e.RemoveStateBagChangeHandler = function(cookie)
        for index, existing in ipairs(state.state_handlers) do
            if existing == cookie then
                table.remove(state.state_handlers, index)
                return
            end
        end
    end
    e.SetTimeout = function() end
    assert(loadfile("sky_phone/source/client/radio.lua", "t", e))()
    return state
end
local function connect(state)
    local result
    state.nui["radio:connect"]({ frequency = 150, secondaryFrequency = 160 }, function(value) result = value end)
    return result
end
local s = fixture()
s.blocked = "player_cuffed"
assert(connect(s).error == "player_cuffed" and s.joined == 0)
s.blocked = nil; assert(connect(s).success and s.joined == 1)
s.events["sky_phone:client:restricted"]("player_incapacitated")
assert(s.left == 1 and s.messages[#s.messages].type == "radio:disconnected")
for _, phase in ipairs({ "on_request", "on_join" }) do
    local r = fixture()
    r[phase] = function() r[phase] = nil; coroutine.yield() end
    local result
    local task = coroutine.create(function() result = connect(r) end)
    local ok, err = coroutine.resume(task); assert(ok, err)
    r.net["sky_phone:radio:disconnected"]({ reason = "phone_not_owned" })
    ok, err = coroutine.resume(task); assert(ok, err)
    assert(not result.success, phase)
    if phase == "on_request" then assert(r.joined == 0) else assert(r.left >= 2) end
end
local g = fixture()
g.on_request = function() g.on_request = nil; coroutine.yield() end
local response
local task = coroutine.create(function() g.nui["radio:get"]({}, function(value) response = value end) end)
assert(coroutine.resume(task))
g.net["sky_phone:radio:disconnected"]({ reason = "phone_not_owned" })
local ok, err = coroutine.resume(task); assert(ok, err)
assert(not response.success, "Late radio:get must not restore channel state after forced leave")
print("PASS client radio: blocked joins, local cleanup, late server replies, yielding providers and stale loads")

local y = fixture()
local requests = 0
y.on_request = function() requests = requests + 1 end
y.on_join = function()
    y.net["yaca:external:setRadioFrequency"](1, "150")
    y.net["yaca:external:setRadioFrequency"](2, "160")
end
assert(connect(y).success)
y.net["yaca:external:setRadioFrequency"](1, "150")
y.net["yaca:external:setRadioFrequency"](2, "160")
assert(requests == 1 and y.left == 0, "Yaca frequency confirmations must not duplicate/rate-limit the approved join")
y.net["sky_phone:radio:disconnected"]({ reason = "phone_not_owned" })
y.net["yaca:external:setRadioFrequency"](1, "0")
y.net["yaca:external:setRadioFrequency"](2, "0")
assert(requests == 1, "Yaca leave confirmations must not start recursive disconnects")
print("PASS Yaca: frequency echoes are idempotent during join, after approval and after forced leave")

local function hud_has_member(state, id)
    for index = #state.messages, 1, -1 do
        local message = state.messages[index]
        if message.type == "radio:hud-update" and type(message.data) == "table" then
            for _, member in ipairs(message.data.members or {}) do
                if member.id == id then return true end
            end
            return false
        end
    end
    return false
end

local early = fixture()
early.on_request = function(name)
    if name == "sky_phone:radio:connect" then
        early.net["sky_phone:radio:members"]({
            frequency = 150,
            members = { { id = 7, name = "Unit 7", badge = "" } },
        })
    end
end
assert(connect(early).success)
assert(hud_has_member(early, 7), "Roster sent before the joined frequency is stored must still reach the HUD")

local seeded = fixture()
seeded.reply = function()
    return {
        success = true,
        data = {
            frequency = 150,
            secondaryFrequency = 0,
            connected = true,
            members = { { id = 8, name = "Unit 8", badge = "" } },
        },
    }
end
assert(connect(seeded).success)
assert(hud_has_member(seeded, 8), "Connect result must seed the HUD roster")

local refresh = fixture()
assert(connect(refresh).success)
assert(not hud_has_member(refresh, 9), "An empty join must not invent HUD members")
refresh.reply = function(name)
    if name == "sky_phone:radio:get" then
        return {
            success = true,
            data = {
                frequency = 150,
                secondaryFrequency = 160,
                members = { { id = 9, name = "Unit 9", badge = "9" } },
                secondaryMembers = { { id = 10, name = "Unit 10", badge = "" } },
            },
        }
    end
    return { success = true, data = { frequency = 150, secondaryFrequency = 160, connected = true } }
end
refresh.events["sky_phone:configurator:updated"]()
assert(hud_has_member(refresh, 9), "Saving the configurator while connected must reload the primary roster")
assert(hud_has_member(refresh, 10), "Saving the configurator while connected must reload the secondary roster")
print("PASS radio HUD: early member events, connect payload and configurator refresh")

for _, transition in ipairs({ "disconnect", "reconnect", "external_frequency" }) do
    local stale = fixture()
    assert(connect(stale).success)
    stale.on_request = function(name)
        if name == "sky_phone:radio:get" then coroutine.yield() end
    end
    stale.reply = function(name)
        if name == "sky_phone:radio:get" then
            return { success = true, data = {
                frequency = 150, secondaryFrequency = 160,
                members = { { id = 99, name = "Old channel member", badge = "" } },
                secondaryMembers = {},
            } }
        end
        return { success = true, data = { frequency = 170, secondaryFrequency = 0, members = {} } }
    end
    local refresh_task = coroutine.create(stale.events["sky_phone:configurator:updated"])
    assert(coroutine.resume(refresh_task))
    if transition == "external_frequency" then
        stale.net["yaca:external:setRadioFrequency"](1, "170")
    else
        stale.net["sky_phone:radio:disconnected"]({ reason = "phone_not_owned" })
        if transition == "reconnect" then assert(connect(stale).success) end
    end
    local resumed, error_message = coroutine.resume(refresh_task)
    assert(resumed, error_message)
    assert(not hud_has_member(stale, 99), "Late configurator refresh must not restore an old roster after " .. transition)
end
print("PASS radio HUD: stale configurator refresh cannot restore disconnected or switched channels")

local function hud_member(state, id)
    for index = #state.messages, 1, -1 do
        local message = state.messages[index]
        if message.type == "radio:hud-update" and type(message.data) == "table" then
            for _, member in ipairs(message.data.members or {}) do
                if member.id == id then return member end
            end
            return nil
        end
    end
end

local function connected_members(state, members)
    state.reply = function()
        return {
            success = true,
            data = {
                frequency = 150,
                secondaryFrequency = 0,
                connected = true,
                members = members,
            },
        }
    end
    assert(connect(state).success)
end

local ignored = fixture()
connected_members(ignored, { { id = 1, name = "Unit 1", badge = "" } })
ignored.events["pma-voice:radioActive"](true)
assert(hud_member(ignored, 1).talking == false, "Yaca must ignore PMA radio talk")

local pma = fixture()
pma.provider = "pma"
pma.server_id = 1
connected_members(pma, {
    { id = 1, name = "Unit 1", badge = "" },
    { id = 2, name = "Unit 2", badge = "" },
})
pma.events["pma-voice:radioActive"](true)
assert(hud_member(pma, 1).talking == true, "Local PMA radio talk must highlight the speaker")
pma.net["pma-voice:setTalkingOnRadio"](2, true)
assert(hud_member(pma, 2).talking == true, "Another player's PMA radio talk must highlight that speaker")
assert(hud_member(pma, 1).talking == true, "Local highlight must remain while another member talks")
pma.events["pma-voice:radioActive"](false)
assert(hud_member(pma, 1).talking == false, "Releasing the PMA radio key must clear the local highlight")
assert(hud_member(pma, 2).talking == true)
pma.net["pma-voice:setTalkingOnRadio"](2, false)
assert(hud_member(pma, 2).talking == false, "PMA radio release must clear the other speaker")
print("PASS radio HUD: PMA radio talk highlights the local player and other members")

local function state_handler(state, key)
    for _, handler in ipairs(state.state_handlers) do
        if handler.key == key then return handler end
    end
end

local salty = fixture()
salty.provider = "saltychat"
connected_members(salty, {
    { id = 1, name = "Unit 1", badge = "" },
    { id = 2, name = "Unit 2", badge = "" },
})
local primary = state_handler(salty, "SaltyChat_RadioChannelSender:150")
assert(primary and #salty.state_handlers == 1, "SaltyChat must watch only the joined primary channel")
primary.fn("global", "SaltyChat_RadioChannelSender:1500", { { ServerId = 1 } })
assert(hud_member(salty, 1).talking == false, "A longer channel name must not match the sender bag")
primary.fn("global", primary.key, { { ServerId = 1 }, { ServerId = 2 } })
assert(hud_member(salty, 1).talking == true and hud_member(salty, 1).channel == 1)
assert(hud_member(salty, 2).talking == true, "Every SaltyChat sender in the bag must be highlighted")
primary.fn("global", primary.key, { { ServerId = 2 } })
assert(hud_member(salty, 1).talking == false, "Leaving the SaltyChat sender list must clear that highlight")
assert(hud_member(salty, 2).talking == true)
salty.nui["radio:disconnect"]({}, function() end)
assert(#salty.state_handlers == 0, "Leaving the radio must stop watching SaltyChat sender bags")

local salty_secondary = fixture()
salty_secondary.provider = "saltychat"
salty_secondary.reply = function()
    return {
        success = true,
        data = {
            frequency = 150,
            secondaryFrequency = 160,
            connected = true,
            members = {
                { id = 4, name = "Unit 4", badge = "" },
            },
        },
    }
end
assert(connect(salty_secondary).success)
local secondary = state_handler(salty_secondary, "SaltyChat_RadioChannelSender:160")
assert(secondary, "SaltyChat must watch the secondary channel separately")
secondary.fn("global", secondary.key, { { ServerId = 4 } })
assert(hud_member(salty_secondary, 4).talking == true and hud_member(salty_secondary, 4).channel == 2)
local overlapping_primary = state_handler(salty_secondary, "SaltyChat_RadioChannelSender:150")
overlapping_primary.fn("global", overlapping_primary.key, { { ServerId = 4 } })
assert(hud_member(salty_secondary, 4).channel == 1)
overlapping_primary.fn("global", overlapping_primary.key, {})
assert(hud_member(salty_secondary, 4).talking == true and hud_member(salty_secondary, 4).channel == 2,
    "Ending primary transmission must retain the active secondary transmission color")
print("PASS radio HUD: SaltyChat sender bags highlight primary and secondary transmitters")

-- Public YACA v3.4.0 exports: apps/yaca-client/src/yaca/radio.ts.
-- The volume export takes (channel, volume); selecting the same secondary channel toggles it off.
local function yaca_bridge_fixture(allow_secondary, version)
    version = version or "3.4.0"
    local state = {
        enabled = false,
        active = 1,
        secondary = -1,
        frequencies = { [1] = "0", [2] = "0" },
        muted = {},
        volumes = { [1] = 1, [2] = 1 },
    }
    local voice = {
        isEnabled = function() return true end,
        isRadioEnabled = function() return state.enabled end,
        enableRadio = function(_, enabled) state.enabled = enabled end,
        setActiveRadioChannel = function(_, channel) state.active = channel; return true end,
        getSecondaryRadioChannel = function() return state.secondary end,
        setSecondaryRadioChannel = function(_, channel)
            state.secondary = state.secondary == channel and -1 or channel
            return true
        end,
        changeRadioFrequency = function(_, frequency)
            state.frequencies[state.active] = frequency
            state.muted[state.active] = false
        end,
        changeRadioFrequencyRaw = function(_, channel, frequency)
            state.frequencies[channel] = frequency
            if frequency ~= "0" then state.muted[channel] = false end
        end,
        muteRadioChannelRaw = function() error("joins must not invoke the old toggle-only mute export") end,
        changeRadioChannelVolumeRaw = function(_, channel, volume)
            if version == "3.3.0" or version == "v3.3.0" then channel, volume = volume, channel end
            if state.volumes[channel] == nil then return false end
            state.volumes[channel] = math.max(0, math.min(1, volume))
            return true
        end,
    }
    if version == "1.0.0" or version == "2.2.1" then
        voice.isEnabled = nil
        voice.changeActiveRadioChannel = voice.setActiveRadioChannel
        voice.setActiveRadioChannel = nil
        voice.getSecondaryRadioChannel = nil
        voice.setSecondaryRadioChannel = nil
    end
    if version == "1.0.0" then voice.isRadioEnabled = nil end
    local environment = setmetatable({
        Config = { Radio = { VoiceProvider = "yaca", AllowSecondary = allow_secondary } },
        Bridge = {
            Radio = {},
            PlayerState = { GetBlockReason = function() end },
            Debug = function() end,
        },
        exports = { ["yaca-voice"] = voice },
        GetResourceState = function(resource) return resource == "yaca-voice" and "started" or "missing" end,
        GetResourceMetadata = function(resource, key, index)
            assert(resource == "yaca-voice" and key == "version" and index == 0)
            return version
        end,
        AddEventHandler = function() end,
        Wait = function() end,
    }, { __index = _G })
    assert(loadfile("sky_phone/source/bridge/yaca.lua", "t", environment))()
    assert(loadfile("sky_phone/source/bridge/client/radio.lua", "t", environment))()
    return environment.Bridge.Radio, state
end

local yaca_radio, yaca_state = yaca_bridge_fixture(true)
assert(yaca_radio.Join(150, 160) and yaca_state.enabled)
assert(yaca_state.frequencies[1] == "150" and yaca_state.frequencies[2] == "160")
for _, volume in ipairs({ 35, 0, 100 }) do
    yaca_radio.SetVolume(volume)
    assert(yaca_state.volumes[1] == volume / 100, "YACA primary volume must follow the phone slider")
    assert(yaca_state.volumes[2] == volume / 100, "YACA secondary volume must follow the phone slider")
end
assert(yaca_state.secondary == 2 and not yaca_state.muted[2])
assert(yaca_radio.Join(151, 161))
assert(yaca_state.secondary == 2, "reconnecting YACA must keep the secondary channel selected")
assert(yaca_state.frequencies[1] == "151" and yaca_state.frequencies[2] == "161")
yaca_radio.Leave()
assert(not yaca_state.enabled and yaca_state.frequencies[1] == "0" and yaca_state.frequencies[2] == "0")
assert(yaca_radio.Join(152, 162))
assert(yaca_state.secondary == 2, "rejoining after leaving YACA must restore secondary transmission")

local primary_radio, primary_state = yaca_bridge_fixture(false)
assert(primary_radio.Join(150, 160))
primary_radio.SetVolume(35)
assert(primary_state.volumes[1] == 0.35 and primary_state.volumes[2] == 1)
assert(primary_state.secondary == -1 and primary_state.frequencies[2] == "0")
for _, version in ipairs({ "1.0.0", "2.2.1", "3.3.0", "v3.3.0", "3.3.1", "3.6.0" }) do
    local radio, state = yaca_bridge_fixture(true, version)
    assert(radio.Join(150, 160) and state.enabled and state.active == 1, version)
    assert(state.frequencies[1] == "150" and state.frequencies[2] == "160", version)
    assert(not state.muted[2], "secondary reception must not be toggled off on old Yaca: " .. version)
    radio.SetVolume(35)
    assert(state.volumes[1] == 0.35 and state.volumes[2] == 0.35, "Yaca volume export order: " .. version)
    assert(radio.Join(151, 161), version)
    radio.Leave()
    assert(not state.enabled and state.frequencies[1] == "0" and state.frequencies[2] == "0", version)
end
print("PASS YACA bridge: slider volume, secondary reconnect, leave/rejoin and primary-only configuration")
