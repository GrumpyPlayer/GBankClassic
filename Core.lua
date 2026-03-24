local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("LibStub", "IsInRaid", "IsInInstance")
local LibStub = upvalues.LibStub
local IsInRaid = upvalues.IsInRaid
local IsInInstance = upvalues.IsInInstance

GBankClassic_Core = LibStub("AceAddon-3.0"):NewAddon("GBankClassic", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceSerializer-3.0", "AceTimer-3.0")

local Core = GBankClassic_Core
local AceComm_SendCommMessage = Core.SendCommMessage

local CHECKSUM_SEPARATOR = "\030" -- ASCII record separator, not used by AceSerializer

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

function Core:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
    local prefixDesc = COMM_PREFIX_DESCRIPTIONS[prefix] or "(Unknown)"
    if IsInInstance() or IsInRaid() then
		GBankClassic_Output:Debug("COMMS", ">", "(suppressing)", prefix, prefixDesc, "to", GBankClassic_Chat:ColorPlayerName(target), "(in instance or raid)")

        return
    end

    if not AceComm_SendCommMessage then
        return
    end

    GBankClassic_Output:Debug("COMMS", ">", prefix, prefixDesc, "via", string.upper(distribution), "to", target and GBankClassic_Chat:ColorPlayerName(target) or "guild", "(" .. (#text or 0) .. " bytes)")

    return AceComm_SendCommMessage(self, prefix, text, distribution, target, prio, callbackFn, callbackArg)
end

-- Centralized whisper send with automatic online check
-- Returns true if sent, false if target offline or send failed
function Core:SendWhisper(prefix, text, target, prio, callbackFn, callbackArg)
    local prefixDesc = COMM_PREFIX_DESCRIPTIONS[prefix] or "(Unknown)"

    -- Strip realm suffix only for same-realm targets; cross-realm requires full name
    target = GBankClassic_Guild:NormalizeName(target, true)

    -- Check if target is online
    local isOnline = GBankClassic_Guild:IsPlayerOnlineMember(target)
    GBankClassic_Output:Debug("WHISPER", "SendWhisper called: prefix=%s %s, target=%s, isOnline=%s", prefix, prefixDesc, target, tostring(isOnline))
    if not isOnline then
        GBankClassic_Output:Debug("WHISPER", "Cannot send %s %s to %s (player is offline)", prefix, prefixDesc, target)

        return false
    end

    -- Send the whisper
    self:SendCommMessage(prefix, text, "WHISPER", target, prio, callbackFn, callbackArg)
    GBankClassic_Output:Debug("WHISPER", "SendCommMessage completed for %s %s to %s", prefix, prefixDesc, target)

    -- The player is online and whisper was sent
    return true
end

-- Called when the addon is loaded
function Core:OnInitialize()
    GBankClassic_Database:Init()
    GBankClassic_Chat:Init()
    GBankClassic_Options:Init()
    GBankClassic_UI:Init()
end

-- Called when the addon is enabled
function Core:OnEnable()
    GBankClassic_Events:RegisterEvents()
end

-- Called when the addon is disabled
function Core:OnDisable()
    GBankClassic_Events:UnregisterEvents()
    GBankClassic_Chat:CancelAllDebounceTimers()
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

-- Serialize data
function Core:SerializePayload(data)
    --[[ NEW:
    local serializedData = LibSerialize:Serialize(data)
    local compressedData = LibDeflate:CompressDeflate(serializedData, {level = 6})
    local encodedData = LibDeflate:EncodeForWoWAddonChannel(compressedData)

    return encodedData
    ]]-- OLD:

    local serialized = self:Serialize(data)
    if not serialized then
        return nil
    end

    return serialized
end

-- Deserialize data; returns success, data (or nil, error)
function Core:DeSerializePayload(message)
    if not message or type(message) ~= "string" then
        return false, "invalid message"
    end

    --[[ NEW:
    local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
    local inflated = LibDeflate:DecompressDeflate(decoded)

    return success, data = LibSerialize:Deserialize(inflated)
    ]]-- OLD:

    -- Find the checksum separator from the end (payload may contain separator)
    -- TODO: Deprecate this legacy support at the right time (checksum is no longer added to messages as of v2.6.0)
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
        -- return LibCBOR:Deserialize(message)
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