local provider_name = "tk_housing"
local resource_name = "tk_housing"

local function property_access(property, identifier)
    if property.owner == identifier then
        return "owner"
    end
    if property.permissions[identifier] then
        return "keyholder"
    end
    return nil
end

local function key_candidates(source, property)
    local candidates = {}
    local players = exports[resource_name]:getPlayersInProperty(property.id)
    assert(type(players) == "table", "[sky_phone] tk_housing:getPlayersInProperty returned invalid data.")
    for _, target in ipairs(players) do
        local identifier = Bridge.Framework.GetIdentifier(target)
        if target ~= source and identifier and not property_access(property, identifier) then
            local first_name, last_name = Bridge.Framework.GetCharacterName(target)
            local name = ((first_name or "") .. " " .. (last_name or "")):match("^%s*(.-)%s*$")
            candidates[#candidates + 1] = {
                id = target,
                name = name ~= "" and name or tostring(target),
            }
        end
    end
    table.sort(candidates, function(left, right)
        return string.lower(left.name) < string.lower(right.name)
    end)
    return candidates
end

local function prepare_action(source, action, data)
    if action == "open_cctv" then
        return nil, "cctv_unavailable"
    end
    if action ~= "set_waypoint" and action ~= "toggle_lock" and action ~= "key_candidates"
        and action ~= "grant_key" and action ~= "revoke_key"
    then
        return nil, "invalid_action"
    end

    local property_id = type(data.propertyId) == "string"
        and tonumber(data.propertyId:match("^tk_housing:(%d+)$")) or nil
    property_id = property_id and math.tointeger(property_id)
    if not property_id or property_id < 1 then
        return nil, "invalid_property"
    end
    local identifier = Bridge.Framework.GetIdentifier(source)
    if not identifier then
        return nil, "housing_unavailable"
    end
    local property = exports[resource_name]:getPropertyData(property_id)
    if not property then
        return nil, "property_not_found"
    end
    -- Entering an unlocked/unowned property is not proof of ownership or a key.
    if not property_access(property, identifier) then
        return nil, "property_access_denied"
    end

    if action == "set_waypoint" then
        local coords = Bridge.Normalize.Coordinates(property.coords)
        if not coords then
            Bridge.Debug("error", "[sky_phone] tk_housing property %s has invalid door coordinates.", property_id)
            return nil, "invalid_coordinates"
        end
        return { coords = coords }
    end

    local permission = action == "toggle_lock" and "lock" or "managePermissions"
    if not exports[resource_name]:hasPropertyPermission(source, property_id, permission) then
        return nil, "property_access_denied"
    end
    if action == "key_candidates" then
        return { candidates = key_candidates(source, property) }
    end

    local prepared = { providerId = tostring(property_id) }
    if action == "grant_key" then
        local target = tonumber(data.target)
        target = target and math.tointeger(target)
        if not target or target < 1 or target == source then
            return nil, "invalid_target"
        end
        local target_identifier = Bridge.Framework.GetIdentifier(target)
        if not target_identifier then
            return nil, "invalid_target"
        end
        if not exports[resource_name]:isPlayerInProperty(target, property_id) then
            return nil, "target_not_in_property"
        end
        if property_access(property, target_identifier) then
            return nil, "key_already_exists"
        end
        prepared.target = target
        prepared.identifier = target_identifier
    elseif action == "revoke_key" then
        if type(data.identifier) ~= "string" or data.identifier == identifier
            or data.identifier == property.owner
        then
            return nil, "invalid_target"
        end
        local keyholders = exports[resource_name]:getPropertyKeyholders(property_id)
        assert(type(keyholders) == "table", "[sky_phone] tk_housing:getPropertyKeyholders returned invalid data.")
        for _, keyholder in ipairs(keyholders) do
            if keyholder.identifier == data.identifier then
                prepared.identifier = keyholder.identifier
                break
            end
        end
        if not prepared.identifier then
            return nil, "key_not_found"
        end
    end
    return prepared
end

Bridge.Housing.RegisterProvider(provider_name, {
    resource_name = resource_name,
    is_available = function()
        return GetResourceState(resource_name) == "started"
    end,
    get_overview = function(source)
        local identifier = Bridge.Framework.GetIdentifier(source)
        if not identifier then
            return nil, "housing_unavailable"
        end
        local properties = exports[resource_name]:getProperties()
        assert(type(properties) == "table", "[sky_phone] tk_housing:getProperties returned invalid data.")
        local accessible = {}
        for _, property in ipairs(properties) do
            local access = property_access(property, identifier)
            if access then
                accessible[#accessible + 1] = { property = property, access = access }
            end
        end
        table.sort(accessible, function(left, right)
            if left.access ~= right.access then
                return left.access == "owner"
            end
            local left_name, right_name = string.lower(left.property.name), string.lower(right.property.name)
            if left_name ~= right_name then
                return left_name < right_name
            end
            return left.property.id < right.property.id
        end)

        local online = {}
        for _, player in ipairs(Bridge.Framework.GetPlayers()) do
            local player_identifier = Bridge.Framework.GetIdentifier(player)
            if player_identifier then
                online[player_identifier] = true
            end
        end
        local result = {}
        local maximum = math.max(0, math.floor(Config.Housing.MaximumProperties))
        for index = 1, math.min(#accessible, maximum) do
            local entry = accessible[index]
            local property = entry.property
            local property_id = assert(math.tointeger(property.id), "[sky_phone] tk_housing returned an invalid property ID.")
            local manage_keys = exports[resource_name]:hasPropertyPermission(source, property.id, "managePermissions")
            local keys
            if manage_keys then
                keys = {}
                local keyholders = exports[resource_name]:getPropertyKeyholders(property.id)
                assert(type(keyholders) == "table", "[sky_phone] tk_housing:getPropertyKeyholders returned invalid data.")
                for _, keyholder in ipairs(keyholders) do
                    keys[#keys + 1] = {
                        identifier = keyholder.identifier,
                        name = keyholder.name,
                        online = online[keyholder.identifier] or false,
                        revocable = keyholder.identifier ~= identifier and keyholder.identifier ~= property.owner,
                    }
                end
                table.sort(keys, function(left, right)
                    return string.lower(left.name) < string.lower(right.name)
                end)
            end
            local entrance = Bridge.Normalize.Coordinates(property.coords)
            result[#result + 1] = {
                id = provider_name .. ":" .. property_id,
                providerId = tostring(property_id),
                name = property.name,
                access = entry.access,
                locked = exports[resource_name]:isPropertyLocked(property.id),
                entrance = entrance,
                capabilities = {
                    lock = exports[resource_name]:hasPropertyPermission(source, property.id, "lock"),
                    keys = manage_keys,
                    waypoint = entrance ~= nil,
                    cctv = false,
                    garageStatus = false,
                },
                cctv = { enabled = false },
                keys = keys,
            }
        end
        return result
    end,
    prepare = prepare_action,
})

Bridge.Callbacks.Register("sky_phone:housing:tk_housing:execute", function(source, data)
    if type(data) ~= "table" then
        return { success = false, error = "invalid_request" }
    end
    local action = data.action
    if action ~= "toggle_lock" and action ~= "grant_key" and action ~= "revoke_key" then
        return { success = false, error = "invalid_action" }
    end
    if not SkyPhone.AllowOperation(source, "housing_tk_action", Config.Housing.ActionsPerMinute, 60) then
        return { success = false, error = "rate_limited" }
    end
    local session, error_response = SkyPhone.RequireSession(source)
    if not session then
        return error_response
    end
    local selected_provider = Bridge.Housing.ResolveProvider()
    if selected_provider ~= provider_name then
        return { success = false, error = "provider_unavailable" }
    end
    -- Recheck the property, actor permissions and target at the mutation boundary.
    local prepared, error_code = prepare_action(source, action, {
        propertyId = type(data.providerId) == "string" and provider_name .. ":" .. data.providerId or nil,
        target = data.target,
        identifier = data.identifier,
    })
    if not prepared then
        return { success = false, error = error_code }
    end
    local property_id = tonumber(prepared.providerId)
    local changed
    if action == "toggle_lock" then
        local locked = exports[resource_name]:isPropertyLocked(property_id)
        changed = exports[resource_name]:setPropertyLocked(property_id, not locked)
    elseif action == "grant_key" then
        changed = exports[resource_name]:addPropertyKeyholder(property_id, prepared.identifier)
    else
        changed = exports[resource_name]:removePropertyKeyholder(property_id, prepared.identifier)
    end
    return changed and { success = true } or { success = false, error = "provider_rejected" }
end)
