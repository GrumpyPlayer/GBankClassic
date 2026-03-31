local addonName, GBCR = ...

GBCR.Core = {}
local Core = GBCR.Core

GBCR.Addon = GBCR.Libs.AceAddon:NewAddon("GBankClassic", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

local Globals = GBCR.Globals
local IsInRaid = Globals.IsInRaid
local IsInInstance = Globals.IsInInstance
local GetAddOnMetadata = Globals.GetAddOnMetadata

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD
local prefixDescriptions = Constants.COMM_PREFIX_DESCRIPTIONS

-- _G[addonName] = GBCR --TODO: remove before release

-- Called when the addon is loaded
function GBCR.Addon:OnInitialize()
    GBCR.Database:Init()
    GBCR.Chat:Init()
    GBCR.Protocol:Init()
    GBCR.Core:LoadMetadata()
    GBCR.Options:Init()
    GBCR.UI:Init()
    GBCR.Donations:Init()
end

-- Called when the addon is enabled
function GBCR.Addon:OnEnable()
    GBCR.Events:RegisterEvents()
end

-- Called when the addon is disabled
function GBCR.Addon:OnDisable()
    GBCR.Events:UnregisterEvents()
    GBCR.Protocol:CancelAllDebounceTimers()
end

function Core:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
    local prefixDesc = prefixDescriptions[prefix] or "(Unknown)"
    if IsInInstance() or IsInRaid() then
		GBCR.Output:Debug("COMMS", ">", "(suppressing)", prefix, prefixDesc, "to", GBCR.Output:ColorPlayerName(target), "(in instance or raid)")

        return
    end

    if not Core.SendCommMessage then
        return
    end

    if GBCR.Options:IsDebugEnabled() then
        local success, data = Core:DeSerializePayload(text)
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
            GBCR.Output:Debug("COMMS", ">", prefix, prefixDesc, "via", string.upper(distribution), "to", target and target or "guild", "(" .. (#text or 0) .. " bytes)", "payload:", payload)
        end
    else
        GBCR.Output:Debug("COMMS", ">", prefix, prefixDesc, "via", string.upper(distribution), "to", target and GBCR.Output:ColorPlayerName(target) or "guild", "(" .. (#text or 0) .. " bytes)")
    end

    return GBCR.Addon:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
end

function Core:SendWhisper(prefix, text, target, prio, callbackFn, callbackArg)
    local prefixDesc = prefixDescriptions[prefix] or "(Unknown)"

    -- Strip realm suffix only for same-realm targets; cross-realm requires full name
    target = GBCR.Guild:NormalizeName(target, true)

    -- Check if target is online
    local isOnline = GBCR.Guild:IsPlayerOnlineMember(target)
    GBCR.Output:Debug("WHISPER", "SendWhisper called: prefix=%s %s, target=%s, isOnline=%s", prefix, prefixDesc, target, tostring(isOnline))
    if not isOnline then
        GBCR.Output:Debug("WHISPER", "Cannot send %s %s to %s (player is offline)", prefix, prefixDesc, target)

        return false
    end

    -- Send the whisper
    self:SendCommMessage(prefix, text, "WHISPER", target, prio, callbackFn, callbackArg)
    GBCR.Output:Debug("WHISPER", "SendCommMessage completed for %s %s to %s", prefix, prefixDesc, target)

    -- The player is online and whisper was sent
    return true
end

function Core:LoadMetadata()
    local addonTitle = GetAddOnMetadata("GBankClassic", "Title")
    local addonVersion = GetAddOnMetadata("GBankClassic", "Version")
    local addonVersionNumber = tonumber((addonVersion:gsub("%.", "")))
    local addonIsOutdated = GBCR.Protocol.isAddonOutdated and GBCR.Globals:Colorize(colorGold, " (a newer version is available)") or ""
    local addonHeader = addonTitle .. " v" .. addonVersion .. addonIsOutdated
	self.addonHeader = addonHeader
	self.addonVersion = addonVersion
	self.addonVersionNumber = addonVersionNumber
    if GBCR.UI.Inventory.Window then
        GBCR.UI.Inventory.Window:SetTitle(addonHeader)
    end
end

function Core:SerializePayload(data)
    local serializedData = GBCR.Libs.LibSerialize:Serialize(data)
    local compressedData = GBCR.Libs.LibDeflate:CompressDeflate(serializedData, {level = 6})
    local encodedData = GBCR.Libs.LibDeflate:EncodeForWoWAddonChannel(compressedData)

    return encodedData
end

function Core:DeSerializePayload(message)
    local decoded = GBCR.Libs.LibDeflate:DecodeForWoWAddonChannel(message)
    local inflated = GBCR.Libs.LibDeflate:DecompressDeflate(decoded)

    return GBCR.Libs.LibSerialize:Deserialize(inflated)
end