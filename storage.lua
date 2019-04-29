-- Simple wrapper around Castle's storage API
-- https://castle.games/documentation/storage-api-reference

local storage = {}

-- --------------------------------------------------------
-- USER STORAGE
-- --------------------------------------------------------

-- Get "User" storage value for given key
-- (or use the default value specified)
storage.getUserValue = function(key,default)
    local retValue = nil
    -- set the default while we wait for response
    storage[key] = default

    network.async(function()
        local retValue = castle.storage.get(key)
        print("getUserValue["..key.."]:"..(retValue or "<nil>"))
        -- store the final setting (or default if none found)
        storage[key] = retValue or default
    end)
end

-- Set "User" storage value (if null passed - key will be deleted)
storage.setUserValue = function(key,value)
    local retValue = nil
    print("setUserValue["..key.."]:"..(value or "<nil>"))
    network.async(function()
        castle.storage.set(key, value)
    end)
end

-- --------------------------------------------------------
-- GLOBAL STORAGE
-- --------------------------------------------------------

-- Get "Global" storage value for given key
-- (or use the default value specified)
storage.getGlobalValue = function(key,default)
    local retValue = nil
    -- set the default while we wait for response
    storage[key] = default

    network.async(function()
        local retValue = castle.storage.getGlobal(key)
        print("getGlobalValue["..key.."]:"..(retValue or "<nil>"))
        -- store the final setting (or default if none found)
        storage[key] = retValue or default
    end)
end

-- Set "Global" storage value (if null passed - key will be deleted)
storage.setGlobalValue = function(key,value)
    local retValue = nil
    print("setGlobalValue["..key.."]:"..(value or "<nil>"))
    network.async(function()
        castle.storage.setGlobal(key, value)
    end)
end

return storage