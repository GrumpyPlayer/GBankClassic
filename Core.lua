GBankClassic_Core = LibStub("AceAddon-3.0"):NewAddon("GBankClassic", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceSerializer-3.0", "AceTimer-3.0")
local AceComm_SendCommMessage = GBankClassic_Core.SendCommMessage

function GBankClassic_Core:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
    local prefixDesc = COMM_PREFIX_DESCRIPTIONS[prefix] or "(Unknown)"
    if IsInRaid() then
        GBankClassic_Output:Debug("COMMS", "< (suppressing) %s %s (in raid)", prefix, prefixDesc)

        return
    end

    if not AceComm_SendCommMessage then
        return
    end

    local bytes = text and #text or 0
    GBankClassic_Output:Debug("COMMS", "< %s %s to %s (%d bytes)", prefix, prefixDesc, distribution, bytes)

    return AceComm_SendCommMessage(self, prefix, text, distribution, target, prio, callbackFn, callbackArg)
end

-- Centralized WHISPER send with automatic online check
-- Returns true if sent, false if target offline or send failed
function GBankClassic_Core:SendWhisper(prefix, text, target, prio, callbackFn, callbackArg)
    -- Check if target is online
    if not GBankClassic_Guild:IsPlayerOnline(target) then
        GBankClassic_Output:Debug("WHISPER", "Cannot send %s WHISPER to %s - player is offline", prefix, target)

        return false
    end

    -- Strip realm suffix for WHISPER (WoW requires name-only)
    -- Target may be "Name-Realm" format, but WHISPER needs just "Name"
    local nameOnly = target
    if target and string.find(target, "-") then
        nameOnly = string.match(target, "^(.-)%-")
    end

    -- Send the whisper
    self:SendCommMessage(prefix, text, "WHISPER", nameOnly, prio, callbackFn, callbackArg)
    
    return true
end

function GBankClassic_Core:OnInitialize()
    -- Called when the addon is loaded
    GBankClassic_Output:Init()
    GBankClassic_Performance:Initialize()
    GBankClassic_Database:Init()
    GBankClassic_Chat:Init()
    GBankClassic_Options:Init()
    GBankClassic_UI:Init()

    -- Initialize module for item highlights
    if GBankClassic_ItemHighlight and GBankClassic_ItemHighlight.Initialize then
        GBankClassic_ItemHighlight:Initialize()
    end
end

function GBankClassic_Core:OnEnable()
    -- Called when the addon is enabled
    GBankClassic_Events:RegisterEvents()
end

function GBankClassic_Core:OnDisable()
    -- Called when the addon is disabled
    GBankClassic_Events:UnregisterEvents()
end

-- Checksum implementation for message integrity
-- Uses a simple but effective hash that detects corruption
local CHECKSUM_SEPARATOR = "\030" -- ASCII record separator, not used by AceSerializer

local function ComputeChecksum(str)
    if not str or type(str) ~= "string" then
        return 0
    end
    -- Simple additive checksum with bit mixing for better distribution
    local sum = 0
    local len = #str
    for i = 1, len do
        local byte = string.byte(str, i)
        sum = (sum * 31 + byte) % 2147483647
    end
    -- Include length to catch truncation
    sum = (sum * 31 + len) % 2147483647
    return sum
end

-- Serialize data with appended checksum for integrity verification
function GBankClassic_Core:SerializeWithChecksum(data)
    local serialized = self:Serialize(data)
    if not serialized then
        return nil
    end
    local checksum = ComputeChecksum(serialized)
    return serialized .. CHECKSUM_SEPARATOR .. tostring(checksum)
end

-- Deserialize data and verify checksum; returns success, data (or nil, error)
function GBankClassic_Core:DeserializeWithChecksum(message)
    if not message or type(message) ~= "string" then
        return false, "invalid message"
    end

    -- Find the checksum separator from the end
    local sepPos = string.find(message, CHECKSUM_SEPARATOR, 1, true)
    if not sepPos then
        -- No checksum found - fall back to regular deserialize for backwards compatibility
        return self:Deserialize(message)
    end

    local serialized = string.sub(message, 1, sepPos - 1)
    local checksumStr = string.sub(message, sepPos + 1)
    local expectedChecksum = tonumber(checksumStr)

    if not expectedChecksum then
        return false, "invalid checksum format"
    end

    local actualChecksum = ComputeChecksum(serialized)
    if actualChecksum ~= expectedChecksum then
        return false, "checksum mismatch (expected " .. expectedChecksum .. ", got " .. actualChecksum .. ")"
    end

    return self:Deserialize(serialized)
end

-- Delta functions
function GBankClassic_Core:ValidateDeltaStructure(delta)
	return GBankClassic_DeltaComms:ValidateDeltaStructure(delta)
end

function GBankClassic_Core:ValidateItemDelta(itemDelta)
	return GBankClassic_DeltaComms:ValidateItemDelta(itemDelta)
end

function GBankClassic_Core:SanitizeDelta(delta)
	return GBankClassic_DeltaComms:SanitizeDelta(delta)
end

function GBankClassic_Core:SanitizeItemDelta(itemDelta)
	return GBankClassic_DeltaComms:SanitizeItemDelta(itemDelta)
end

function GBankClassic_Core:ComputeInventoryHash(bank, bags, money)
	return GBankClassic_DeltaComms:ComputeInventoryHash(bank, bags, money)
end