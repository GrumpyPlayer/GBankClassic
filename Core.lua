local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("LibStub", "IsInRaid", "IsInInstance", "GetAddOnMetadata")
local LibStub = upvalues.LibStub
local IsInRaid = upvalues.IsInRaid
local IsInInstance = upvalues.IsInInstance
local GetAddOnMetadata = upvalues.GetAddOnMetadata

GBankClassic_Core = LibStub("AceAddon-3.0"):NewAddon("GBankClassic", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceSerializer-3.0", "AceTimer-3.0")

local Core = GBankClassic_Core
local AceComm_SendCommMessage = Core.SendCommMessage

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

    if GBankClassic_Options:GetLogLevel() == LOG_LEVEL.DEBUG then
        local success, data = GBankClassic_Core:DeSerializePayload(text)
        if success then
            local tablePayload = {}
            local payload
            if type(data) == "table" then
                for k, v in pairs(data) do
                    table.insert(tablePayload, k .. "=" .. tostring(v))
                end
                payload = table.concat(tablePayload, ",")
            else
                payload = data
            end
            GBankClassic_Output:Debug("COMMS", ">", prefix, prefixDesc, "via", string.upper(distribution), "to", target and target or "guild", "(" .. (#text or 0) .. " bytes)", "payload:", payload)
        end
    else
        GBankClassic_Output:Debug("COMMS", ">", prefix, prefixDesc, "via", string.upper(distribution), "to", target and GBankClassic_Chat:ColorPlayerName(target) or "guild", "(" .. (#text or 0) .. " bytes)")
    end

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
    self:LoadMetadata()
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

-- Load metadata from the addon (called again when isAddonOutdated is set to true based on incoming messages)
function Core:LoadMetadata()
    local addonTitle = GetAddOnMetadata("GBankClassic", "Title")
    local addonVersion = GetAddOnMetadata("GBankClassic", "Version")
    local addonVersionNumber = tonumber((addonVersion:gsub("%.", "")))
    local addonIsOutdated = GBankClassic_Chat.isAddonOutdated and " |cffe6cc80(a newer version is available)|r" or ""
    local addonHeader = addonTitle .. " v" .. addonVersion .. addonIsOutdated
	self.addonHeader = addonHeader
	self.addonVersion = addonVersion
	self.addonVersionNumber = addonVersionNumber
    if GBankClassic_UI_Inventory.Window then
        GBankClassic_UI_Inventory.Window:SetTitle(addonHeader)
    end
end

-- Serialize data
function Core:SerializePayload(data)
    local serializedData = LibSerialize:Serialize(data)
    local compressedData = LibDeflate:CompressDeflate(serializedData, {level = 6})
    local encodedData = LibDeflate:EncodeForWoWAddonChannel(compressedData)

    return encodedData
end

-- Deserialize data; returns success, data (or nil, error)
function Core:DeSerializePayload(message)
    local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
    local inflated = LibDeflate:DecompressDeflate(decoded)

    return LibSerialize:Deserialize(inflated)
end