local function new_housing()
    local state = { actor = 1, started = true, allowed = true, session = true, writes = 0 }
    local players = {
        [1] = "char:owner", [2] = "char:keyholder", [3] = "char:visitor",
        [4] = "char:outsider", [5] = "char:manager",
    }
    local properties = {
        { id = 10.0, name = "Owner house", owner = players[1], coords = { x = 10, y = 20, z = 30 },
            permissions = { [players[2]] = { lock = true }, [players[5]] = { managePermissions = true },
                ["char:offline"] = {} } },
        { id = 20, name = "Shared house", owner = players[4], coords = { x = 40, y = 50, z = 60 },
            permissions = { [players[1]] = {} } },
        { id = 30, name = "Public house", owner = "", coords = { x = 70, y = 80, z = 90 }, permissions = {} },
        { id = 40, name = "Motel", owner = players[1], coords = { x = 1, y = 2, z = 3 }, permissions = {} },
        { id = 50, name = "Job house", owner = "job:police", coords = { x = 4, y = 5, z = 6 },
            permissions = { ["job:police"] = { lock = true } } },
    }
    local by_id = {}
    for _, property in ipairs(properties) do by_id[property.id] = property end
    local inside = { [1] = 10, [2] = 10, [3] = 10, [5] = 10 }
    local locked = { [10] = true, [20] = false, [40] = true }
    local callbacks, events = {}, {}
    local provider = {}
    function provider:getProperties() return properties end
    function provider:getPropertyData(id)
        assert(type(id) == "number", "TK property IDs must be numbers")
        return by_id[id]
    end
    function provider:hasPropertyPermission(source, id, permission)
        local property = assert(by_id[id])
        if id == 40 and permission == "managePermissions" then return false end
        if property.owner == players[source] then return true end
        return (property.permissions[players[source]] or {})[permission] or false
    end
    function provider:getPropertyKeyholders(id)
        local keys = {}
        for identifier, permissions in pairs(by_id[id].permissions) do
            if not identifier:match("^job:") then
                keys[#keys + 1] = { identifier = identifier, name = identifier, permissions = permissions }
            end
        end
        return keys
    end
    function provider:getPlayersInProperty(id)
        local result = {}
        for source, property_id in pairs(inside) do
            if property_id == id then result[#result + 1] = source end
        end
        return result
    end
    function provider:isPlayerInProperty(source, id) return inside[source] == id end
    function provider:isPropertyLocked(id) return locked[id] or false end
    function provider:setPropertyLocked(id, value)
        assert(type(value) == "boolean")
        state.writes = state.writes + 1
        if state.reject then return false end
        locked[id] = value
        return true
    end
    function provider:addPropertyKeyholder(id, identifier)
        state.writes = state.writes + 1
        if state.reject then return false end
        assert(not by_id[id].permissions[identifier], "must reject duplicate keys before mutation")
        by_id[id].permissions[identifier] = {}
        return true
    end
    function provider:removePropertyKeyholder(id, identifier)
        state.writes = state.writes + 1
        if state.reject then return false end
        assert(by_id[id].permissions[identifier], "must reject missing keys before mutation")
        by_id[id].permissions[identifier] = nil
        return true
    end
    local environment = setmetatable({
        Config = { Housing = { System = "auto", AutoPriority = { "tk_housing" },
            MaximumProperties = 50, OverviewRequestsPerMinute = 30, ActionsPerMinute = 12 } },
        exports = { tk_housing = provider },
        GetResourceState = function(name)
            assert(name == "tk_housing")
            return state.started and "started" or "stopped"
        end,
        AddEventHandler = function(name, handler) events[name] = handler end,
        SkyPhone = {
            AllowOperation = function() return state.allowed end,
            RequireSession = function()
                if state.session then return {} end
                return nil, { success = false, error = "device_locked" }
            end,
        },
    }, { __index = _G })
    local function load_script(path, target)
        assert(loadfile("sky_phone/source/" .. path, "t", target or environment))()
    end
    load_script("bridge/shared.lua")
    environment.Bridge.Debug = function() end
    environment.Bridge.Callbacks.Register = function(name, handler) callbacks[name] = handler end
    environment.Bridge.Framework = {
        GetIdentifier = function(source) return players[source] end,
        GetPlayers = function() return { 1, 2, 3, 4, 5 } end,
        GetCharacterName = function(source) return "Resident", tostring(source) end,
    }
    load_script("bridge/server/housing.lua")
    load_script("bridge/server/housing/tk_housing.lua")
    load_script("server/housing.lua")

    local client = setmetatable({ Bridge = { Callbacks = {
        Trigger = function(name, data) return callbacks[name](state.actor, data) end,
    } }, GetResourceState = environment.GetResourceState }, { __index = _G })
    load_script("bridge/client/housing.lua", client)
    load_script("bridge/client/housing/tk_housing.lua", client)
    function state.overview()
        return callbacks["sky_phone:housing:overview"](state.actor)
    end
    function state.prepare(action, id, fields)
        local data = fields or {}
        data.action, data.propertyId = action, id or "tk_housing:10"
        return callbacks["sky_phone:housing:prepare"](state.actor, data)
    end
    function state.execute(action, data)
        return client.Bridge.Housing.Execute("tk_housing", action, data)
    end
    function state.direct(data)
        return callbacks["sky_phone:housing:tk_housing:execute"](state.actor, data)
    end
    state.properties, state.players, state.inside, state.locked = by_id, players, inside, locked
    state.environment, state.provider, state.events = environment, provider, events
    return state
end

local count = 0
local function test(name, run)
    run(new_housing())
    count = count + 1
    print("PASS " .. name)
end

test("lists personal ownership and individual keys without leaking public/job properties", function(state)
    local response = state.overview()
    assert(response.success and response.data.provider == "tk_housing")
    local rows = response.data.properties
    assert(#rows == 3 and rows[1].id == "tk_housing:40" and rows[2].id == "tk_housing:10")
    assert(rows[3].access == "keyholder" and rows[3].id == "tk_housing:20")
    assert(not rows[1].capabilities.keys and rows[1].capabilities.lock, "respect motel permissions")
    assert(rows[2].capabilities.keys and rows[2].capabilities.lock and rows[2].locked)
    assert(rows[2].entrance.x == 10 and not rows[2].capabilities.cctv and not rows[2].capabilities.garageStatus)
    assert(not rows[3].capabilities.lock and rows[3].keys == nil)
    assert(state.properties[10].id == 10 and state.properties[10].capabilities == nil)
    rows[2].entrance.x = 999
    assert(state.properties[10].coords.x == 10, "normalization must not mutate provider tables")
    local keys = rows[2].keys
    assert(#keys == 3 and keys[1].online and not keys[3].online)
end)

test("handles empty results, sorted limits and unavailable providers", function(state)
    state.environment.Config.Housing.MaximumProperties = 1
    assert(state.overview().data.properties[1].id == "tk_housing:40")
    state.environment.Config.Housing.MaximumProperties = 0
    assert(#state.overview().data.properties == 0)
    state.started = false
    assert(not state.overview().data.available)
    local ok, reason = state.execute("toggle_lock", { providerId = "10" })
    assert(not ok and reason == "provider_unavailable")
    state.started = true
    state.events.onResourceStart("tk_housing")
    assert(state.overview().data.available)
    state.actor = 99
    assert(state.overview().error == "housing_unavailable")
end)

test("waypoints use authorized server coordinates and reject public access", function(state)
    local response = state.prepare("set_waypoint")
    assert(response.success and response.data.coords.x == 10 and response.data.provider == "tk_housing")
    assert(state.prepare("set_waypoint", "tk_housing:30").error == "property_access_denied")
    assert(state.prepare("set_waypoint", "other:10").error == "invalid_property")
    assert(state.prepare("set_waypoint", "tk_housing:999").error == "property_not_found")
    assert(state.prepare("open_cctv").error == "cctv_unavailable")
end)

test("candidates exclude existing access and carry the full character name", function(state)
    local response = state.prepare("key_candidates")
    assert(response.success and #response.data.candidates == 1)
    assert(response.data.candidates[1].id == 3 and response.data.candidates[1].name == "Resident 3")
    assert(state.prepare("key_candidates", "tk_housing:40").error == "property_access_denied")
end)

test("owner can toggle both directions and provider rejection is not success", function(state)
    local prepared = state.prepare("toggle_lock").data
    assert(state.execute("toggle_lock", prepared))
    assert(not state.locked[10])
    assert(state.execute("toggle_lock", prepared))
    assert(state.locked[10])
    state.reject = true
    local ok, reason = state.execute("toggle_lock", prepared)
    assert(not ok and reason == "provider_rejected" and state.locked[10])
end)

test("keyholder lock permission is checked again when executing", function(state)
    state.actor = 2
    local prepared = state.prepare("toggle_lock")
    assert(prepared.success)
    state.properties[10].permissions["char:keyholder"].lock = false
    local ok, reason = state.execute("toggle_lock", prepared.data)
    assert(not ok and reason == "property_access_denied" and state.writes == 0)
    state.properties[10].permissions["char:keyholder"].lock = true
    assert(state.execute("toggle_lock", prepared.data))
    assert(state.prepare("grant_key", nil, { target = 3 }).error == "property_access_denied")
end)

test("ownership changes invalidate prepared mutations", function(state)
    local prepared = state.prepare("revoke_key", nil, { identifier = "char:offline" }).data
    state.properties[10].owner = "char:outsider"
    local ok, reason = state.execute("revoke_key", prepared)
    assert(not ok and reason == "property_access_denied" and state.writes == 0)
end)

test("grant derives identity from the online target and rejects duplicates", function(state)
    local prepared = state.prepare("grant_key", nil, { target = 3 }).data
    prepared.identifier = "char:forged"
    assert(state.execute("grant_key", prepared))
    assert(state.properties[10].permissions["char:visitor"] and not state.properties[10].permissions["char:forged"])
    assert(state.prepare("grant_key", nil, { target = 3 }).error == "key_already_exists")
    local ok, reason = state.execute("grant_key", prepared)
    assert(not ok and reason == "key_already_exists" and state.writes == 1)
end)

test("recipient location and validity are checked again at execution", function(state)
    local prepared = state.prepare("grant_key", nil, { target = 3 }).data
    state.inside[3] = nil
    local ok, reason = state.execute("grant_key", prepared)
    assert(not ok and reason == "target_not_in_property" and state.writes == 0)
    state.players[3] = nil
    assert(state.direct({ action = "grant_key", providerId = "10", target = 3 }).error == "invalid_target")
    for _, target in ipairs({ 0, -1, 1, 2.5, "bad" }) do
        assert(state.prepare("grant_key", nil, { target = target }).error == "invalid_target")
    end
end)

test("managers may manage offline keys but cannot revoke themselves or the owner", function(state)
    state.actor = 5
    local overview = state.overview().data.properties[1]
    assert(overview.access == "keyholder" and overview.capabilities.keys and not overview.capabilities.lock)
    for _, key in ipairs(overview.keys) do
        if key.identifier == "char:manager" then assert(not key.revocable) end
    end
    assert(state.prepare("revoke_key", nil, { identifier = "char:owner" }).error == "invalid_target")
    assert(state.prepare("revoke_key", nil, { identifier = "char:manager" }).error == "invalid_target")
    assert(state.prepare("revoke_key", nil, { identifier = "job:police" }).error == "key_not_found")
    local prepared = state.prepare("revoke_key", nil, { identifier = "char:offline" }).data
    assert(state.execute("revoke_key", prepared))
    assert(state.properties[10].permissions["char:offline"] == nil)
    local ok, reason = state.execute("revoke_key", prepared)
    assert(not ok and reason == "key_not_found" and state.writes == 1)
end)

test("direct callbacks enforce session, limits, provider and input validation", function(state)
    local request = { action = "toggle_lock", providerId = "10" }
    state.session = false
    assert(state.direct(request).error == "device_locked")
    state.session, state.allowed = true, false
    assert(state.direct(request).error == "rate_limited")
    state.allowed, state.started = true, false
    assert(state.direct(request).error == "provider_unavailable")
    state.started = true
    assert(state.direct(nil).error == "invalid_request")
    assert(state.direct({ action = "set_waypoint" }).error == "invalid_action")
    assert(state.direct({ action = "toggle_lock", providerId = {} }).error == "invalid_property")
    state.actor = 4
    assert(state.direct(request).error == "property_access_denied")
    assert(state.writes == 0)
end)

test("provider contract errors remain failures instead of empty success", function(state)
    function state.provider:getProperties() error("fixture provider unavailable") end
    local ok, reason = pcall(state.overview)
    assert(not ok and tostring(reason):find("fixture provider unavailable", 1, true))
end)

print(("TK Housing: %d tests passed"):format(count))
