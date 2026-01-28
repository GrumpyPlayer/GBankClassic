GBankClassic_Events = {}

function GBankClassic_Events:RegisterMessage(message, callback)
	if not callback then
		callback = message
	end
    GBankClassic_Core:RegisterMessage(message, callback)
end

function GBankClassic_Events:SendMessage(message, ...)
    GBankClassic_Core:SendMessage(message, ...)
end

function GBankClassic_Events:UnregisterMessage(message)
    GBankClassic_Core:UnregisterMessage(message)
end

function GBankClassic_Events:RegisterEvent(event, callback)
	if not callback then
		callback = event
	end
    GBankClassic_Core:RegisterEvent(event, function(...)
        self[callback](self, ...)
    end)
end

function GBankClassic_Events:UnregisterEvent(...)
    GBankClassic_Core:UnregisterEvent(...)
end

function GBankClassic_Events:RegisterEvents()
	if GBankClassic_Bank.eventsRegistered then
		return
	end

	self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("GUILD_RANKS_UPDATE")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
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
    self:RegisterEvent("BAG_UPDATE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")

    hooksecurefunc("ChatEdit_InsertLink", function(link)
        GBankClassic_UI:OnInsertLink(link)
    end)

	self:SetTimer()
	self:SetShareTimer()

    GBankClassic_Bank.eventsRegistered = true
end

function GBankClassic_Events:UnregisterEvents()
	if not GBankClassic_Bank.eventsRegistered then
		return
	end

    GBankClassic_Bank.eventsRegistered = false

	self:UnregisterEvent("PLAYER_LOGIN")
	self:UnregisterEvent("PLAYER_LOGOUT")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
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
    self:UnregisterEvent("BAG_UPDATE")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
end

function GBankClassic_Events:SetTimer()
	GBankClassic_Core:ScheduleTimer(function(...)
		GBankClassic_Events:OnTimer()
	end, TIMER_INTERVALS.ROSTER_AND_ALT_SYNC)
end

function GBankClassic_Events:OnTimer()
	GBankClassic_Events:Sync()
	self:SetTimer()
end

function GBankClassic_Events:SetShareTimer()
	GBankClassic_Core:ScheduleTimer(function(...)
		GBankClassic_Events:OnShareTimer()
	end, TIMER_INTERVALS.VERSION_BROADCAST)
end

function GBankClassic_Events:OnShareTimer()
	GBankClassic_Guild:Share("reply")
	self:SetShareTimer()
end

function GBankClassic_Events:Sync(priority)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	local version = GBankClassic_Guild:GetVersion()
	if version == nil then
		return
	end
	if version.roster == nil then
		return
	end

	local data = GBankClassic_Core:SerializeWithChecksum(version)
	-- Use provided priority or default to BULK for automatic timer-based syncs
	GBankClassic_Core:SendCommMessage("gbank-v", data, "Guild", nil, priority or "BULK")
end

-- Delta-specific version broadcast
function GBankClassic_Events:SyncDeltaVersion(priority)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	-- Only broadcast delta version if we support delta
	if not GBankClassic_Guild:ShouldUseDelta() then
		return
	end

	local version = GBankClassic_Guild:GetVersion()
	if version == nil then
		return
	end
	if version.roster == nil then
		return
	end

	-- Include banker status for pull-based protocol
	local player = GBankClassic_Guild:GetNormalizedPlayer()
	local isGuildBankAlt = player and GBankClassic_Guild:IsBank(player) or false
	version.isGuildBankAlt = isGuildBankAlt

	local data = GBankClassic_Core:SerializeWithChecksum(version)
	-- Use provided priority or default to NORMAL for automatic timer-based syncs
	GBankClassic_Core:SendCommMessage("gbank-dv", data, "Guild", nil, priority or "NORMAL")
end

function GBankClassic_Events:PLAYER_LOGIN(_)
	GBankClassic_Guild:GetPlayer()
end

function GBankClassic_Events:PLAYER_LOGOUT(_)
	-- Save persistent debug log to SavedVariables
	GBankClassic_Output:SavePersistentLog()
end

function GBankClassic_Events:PLAYER_ENTERING_WORLD(_)
	GBankClassic_Performance:RecordEvent("PLAYER_ENTERING_WORLD")
    -- Request initial guild roster update on world enter
	local GuildRoster = GuildRoster or C_GuildInfo.GuildRoster
    if GuildRoster then
        GuildRoster()
    end
	-- Initialize cache immediately in case GUILD_ROSTER_UPDATE is delayed
	GBankClassic_Guild:RefreshOnlineCache()
end

function GBankClassic_Events:GUILD_RANKS_UPDATE(_)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

	-- Load guild data and perform a one-time cleanup of malformed alt entries
	if GBankClassic_Guild:Init(guild) then
		GBankClassic_Options:InitGuild()

		if IsInRaid() then
			GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: ignoring guild ranks cleanup (in raid)")

			return
		end
        
		local cleaned = GBankClassic_Guild:CleanupMalformedAlts()
		if cleaned and cleaned > 0 then
			GBankClassic_Output:Info("Cleaned %d malformed alt entries from saved database", cleaned)
		end
        
        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
        end
	end
end

function GBankClassic_Events:GUILD_ROSTER_UPDATE(_)
	GBankClassic_Performance:RecordEvent("GUILD_ROSTER_UPDATE")
    -- Refresh online members cache when roster updates
	GBankClassic_Guild:RefreshOnlineCache()
	-- Invalidate banks cache when roster updates
	GBankClassic_Guild:InvalidateBanksCache()
	-- Rebuild guild bank alts roster from guild notes (local only, no network communication)
	GBankClassic_Guild:RebuildGuildBankAltsRoster()
	-- Clear delta error counters for offline players
	GBankClassic_DeltaComms:ClearOfflineErrorCounters(GBankClassic_Guild.Info and GBankClassic_Guild.Info.name)
end

function GBankClassic_Events:GUILD_RANKS_UPDATE(_)
	local guild = GBankClassic_Guild:GetGuild()
	if not guild then
		return
	end

    if GBankClassic_Guild:Init(guild) then
        GBankClassic_Options:InitGuild()
        
		if IsInRaid() then
			GBankClassic_Output:Debug("EVENTS", "GUILD_RANKS_UPDATE: ignoring guild ranks cleanup (in raid)")

			return
		end
        
		local cleaned = GBankClassic_Guild:CleanupMalformedAlts()
		if cleaned and cleaned > 0 then
			GBankClassic_Output:Info("Cleaned %d malformed alt entries from saved database", cleaned)
		end
        
        if GBankClassic_UI_Inventory.isOpen then
            GBankClassic_UI_Inventory:DrawContent()
        end
    end
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

local bagUpdateTimer = nil
function GBankClassic_Events:BAG_UPDATE(_)
    if bagUpdateTimer then return end
    bagUpdateTimer = C_Timer.NewTimer(2, function()
        GBankClassic_Bank:Scan()
        bagUpdateTimer = nil
    end)
end

function GBankClassic_Events:PLAYER_REGEN_DISABLED(_)
    if GBankClassic_Options:GetCombatHide() then
        GBankClassic_UI_Inventory:Close()
    end
end