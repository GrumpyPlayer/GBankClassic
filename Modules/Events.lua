GBankClassic_Events = {}

function GBankClassic_Events:RegisterMessage(message, callback)
    if not callback then callback = message end
    GBankClassic_Core:RegisterMessage(message, callback)
end

function GBankClassic_Events:SendMessage(message, ...) GBankClassic_Core:SendMessage(message, ...) end

function GBankClassic_Events:UnregisterMessage(message) GBankClassic_Core:UnregisterMessage(message) end

function GBankClassic_Events:RegisterEvent(event, callback)
    if not callback then callback = event end
    GBankClassic_Core:RegisterEvent(event, function(...) self[callback](self, ...) end)
end

function GBankClassic_Events:UnregisterEvent(...) GBankClassic_Core:UnregisterEvent(...) end

function GBankClassic_Events:RegisterEvents()
    if GBankClassic_Bank.eventsRegistered then return end

    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_GUILD_UPDATE")
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("BANKFRAME_CLOSED")
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_INBOX_UPDATE")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterEvent("TRADE_SHOW")
    self:RegisterEvent("TRADE_CLOSED")
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("MERCHANT_CLOSED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("BAG_UPDATE")
    hooksecurefunc("ChatEdit_InsertLink", function(link) GBankClassic_UI:OnInsertLink(link) end)

    GBankClassic_Bank.eventsRegistered = true
end

function GBankClassic_Events:UnregisterEvents()
    if not GBankClassic_Bank.eventsRegistered then return end
    GBankClassic_Bank.eventsRegistered = false

    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    self:UnregisterEvent("PLAYER_GUILD_UPDATE")
    self:UnregisterEvent("BANKFRAME_OPENED")
    self:UnregisterEvent("BANKFRAME_CLOSED")
    self:UnregisterEvent("MAIL_SHOW")
    self:UnregisterEvent("MAIL_INBOX_UPDATE")
    self:UnregisterEvent("MAIL_CLOSED")
    self:UnregisterEvent("TRADE_SHOW")
    self:UnregisterEvent("TRADE_CLOSED")
    self:UnregisterEvent("AUCTION_HOUSE_SHOW")
    self:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    self:UnregisterEvent("MERCHANT_SHOW")
    self:UnregisterEvent("MERCHANT_CLOSED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("BAG_UPDATE")
end

function GBankClassic_Events:PLAYER_GUILD_UPDATE(_)
    local guild = GBankClassic_Guild:GetGuild()
    if guild and GBankClassic_Guild and GBankClassic_Guild:Init(guild) then
        GBankClassic_Options:InitGuild()
        
        if IsInRaid() then
            if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('Ignoring cleanup', prefix, 'from', sender, '(in raid)') end
            return
        end
        local cleaned = GBankClassic_Guild:CleanupMalformedAlts()
        if cleaned and cleaned > 0 then
            if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Cleaned " .. cleaned .. " malformed alt entries from saved database") end
        end

        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
        end
    end
end

local scan_debounce = 4
local update_timer = nil
function GBankClassic_Events:GUILD_ROSTER_UPDATE(...)
    local now = GetServerTime()
    if self._lastScan and now - self._lastScan < scan_debounce then
        return
    end
    self._lastScan = now

    if update_timer then return end
    update_timer = C_Timer.NewTimer(2, function()
        update_timer = nil

        -- Fired when guild members come online and go offline
        -- Fired when notes are changed
        GBankClassic_Options:InitGuild()
        
        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
        end

        -- Update list of peers and then the UI
        GBankClassic_Chat:DiscoverPeers(2, function() 
            if GBankClassic_UI_Inventory.isOpen then 
                GBankClassic_UI_Inventory:DrawContent()
            end
        end)

        --TODO: Share data with newly online peer only and nominate one player to do this instead of all peers doing this
        GBankClassic_Guild:AuthorRosterData()
        GBankClassic_Guild:Share("reply")
        GBankClassic_Events:Sync()
    end)
end

local bag_update_timer = nil
function GBankClassic_Events:BAG_UPDATE(_)
    if bag_update_timer then return end
    bag_update_timer = C_Timer.NewTimer(2, function()
        GBankClassic_Bank:Scan()
        bag_update_timer = nil
    end)
end

function GBankClassic_Events:Sync()
    local version = GBankClassic_Guild:GetVersion()
    if version == nil then return end
    if version.roster == nil then return end
    local data = GBankClassic_Core:Serialize(version)
    if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Broadcasting our version data to online peers.", version) end
    GBankClassic_Core:SendCommMessage("gbank-v", data, "Guild", nil, "BULK")
end

function GBankClassic_Events:BANKFRAME_OPENED(_)
    GBankClassic_Bank:OnUpdateStart()
end

function GBankClassic_Events:BANKFRAME_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function GBankClassic_Events:MAIL_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
    GBankClassic_Mail.isOpen = true
    GBankClassic_Mail:Check()
end

function GBankClassic_Events:MAIL_INBOX_UPDATE(_)
    GBankClassic_Mail:Scan()
end

function GBankClassic_Events:MAIL_CLOSED(_)
    GBankClassic_Mail.isOpen = false
    GBankClassic_Mail.isScanning = false
    GBankClassic_Bank:OnUpdateStop()
    GBankClassic_UI_Mail:Close()
end

function GBankClassic_Events:TRADE_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
end

function GBankClassic_Events:TRADE_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function GBankClassic_Events:AUCTION_HOUSE_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
end

function GBankClassic_Events:AUCTION_HOUSE_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function GBankClassic_Events:MERCHANT_SHOW(_)
    GBankClassic_Bank:OnUpdateStart()
end

function GBankClassic_Events:MERCHANT_CLOSED(_)
    GBankClassic_Bank:OnUpdateStop()
end

function GBankClassic_Events:PLAYER_REGEN_DISABLED(_)
    if GBankClassic_Options:GetCombatHide() then
        GBankClassic_UI_Inventory:Close()
    end
end