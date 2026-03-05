local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("LibStub", "IsInRaid")
local LibStub = upvalues.LibStub
local IsInRaid = upvalues.IsInRaid

GBankClassic_Core = LibStub("AceAddon-3.0"):NewAddon("GBankClassic", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceSerializer-3.0", "AceTimer-3.0")

local Core = GBankClassic_Core
local AceComm_SendCommMessage = Core.SendCommMessage

local CHECKSUM_SEPARATOR = "\030" -- ASCII record separator, not used by AceSerializer

function Core:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
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

-- Centralized whisper send with automatic online check
-- Returns true if sent, false if target offline or send failed
function Core:SendWhisper(prefix, text, target, prio, callbackFn, callbackArg)
    -- Strip realm suffix only for same-realm targets; cross-realm requires full name
    target = GBankClassic_Guild:NormalizeName(target, true)

    -- Check if target is online
    local isOnline = GBankClassic_Guild:IsPlayerOnlineMember(target)
    GBankClassic_Output:Debug("PROTOCOL", "SendWhisper called: prefix=%s, target=%s, isOnline=%s", prefix, target, tostring(isOnline))
    if not isOnline then
        GBankClassic_Output:Debug("WHISPER", "Cannot send %s whisper to %s - player is offline", prefix, target)

        return false
    end

    -- Send the whisper
    self:SendCommMessage(prefix, text, "WHISPER", target, prio, callbackFn, callbackArg)
    GBankClassic_Output:Debug("PROTOCOL", "SendCommMessage whisper completed for %s to %s", prefix, target)
    
    -- The player is online and whisper was sent
    return true
end

-- Called when the addon is loaded
function Core:OnInitialize()
    GBankClassic_Database:Init()
    GBankClassic_Chat:Init()
    GBankClassic_Options:Init()
    GBankClassic_UI:Init()

    -- -- Initialize module for item highlights
    -- if GBankClassic_ItemHighlight and GBankClassic_ItemHighlight.Initialize then
    --     GBankClassic_ItemHighlight:Initialize()
    -- end
end

-- Called when the addon is enabled
function Core:OnEnable()
    GBankClassic_Events:RegisterEvents()
end

-- Called when the addon is disabled
function Core:OnDisable()
    GBankClassic_Events:UnregisterEvents()
end

-- Checksum implementation for message integrity
-- Uses a simple but effective hash that detects corruption
function Core:Checksum(str)
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
function Core:SerializeWithChecksum(data)
    local serialized = self:Serialize(data)
    if not serialized then
        return nil
    end

    local checksum = self:Checksum(serialized)
end

-- Deserialize data and verify checksum; returns success, data (or nil, error)
function Core:DeserializeWithChecksum(message)
    if not message or type(message) ~= "string" then
        return false, "invalid message"
    end

    -- Find the checksum separator from the end (payload may contain separator)
    local sepPos = nil
    local sepByte = string.byte(CHECKSUM_SEPARATOR)
    for i = #message, 1, -1 do
        if string.byte(message, i) == sepByte then
            sepPos = i
            break
        end
    end
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

    local actualChecksum = self:Checksum(serialized)
    if actualChecksum ~= expectedChecksum then
        return false, "checksum mismatch (expected " .. expectedChecksum .. ", got " .. actualChecksum .. ")"
    end

    return self:Deserialize(serialized)
end