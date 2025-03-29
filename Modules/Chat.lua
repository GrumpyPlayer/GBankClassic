GBankClassic_Chat = {}

function GBankClassic_Chat:Init()
    GBankClassic_Core:RegisterChatCommand("bank", function(input)
        return GBankClassic_Chat:ChatCommand(input)
    end)

    self.addon_outdated = false
    self.last_roster_sync = nil
    self.last_alt_sync = {}
    self.sync_queue = {}
    self.is_syncing = false

    GBankClassic_Core:RegisterComm("gbank-d", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)

    GBankClassic_Core:RegisterComm("gbank-v", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)

    GBankClassic_Core:RegisterComm("gbank-r", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)

    ---START CHANGES
    GBankClassic_Core:RegisterComm("gbank-h", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)

    GBankClassic_Core:RegisterComm("gbank-hr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)

    GBankClassic_Core:RegisterComm("gbank-s", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-sr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)

    GBankClassic_Core:RegisterComm("gbank-w", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    GBankClassic_Core:RegisterComm("gbank-wr", function (prefix, message, distribution, sender)
        GBankClassic_Chat:OnCommReceived(prefix, message, distribution, sender)
    end)
    ---END CHANGES
end

function GBankClassic_Chat:OnCommReceived(prefix, message, _, sender)
    if IsInRaid() then return end
    local player = GBankClassic_Guild:GetPlayer()
    ---START CHANGES
    sender = GetPlayerWithNormalizedRealm(sender)
    ---END CHANGES
    if player == sender then
        ---START CHANGES
        return
        ---END CHANGES
    end

    if prefix == "gbank-v" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            local current_data = GBankClassic_Guild:GetVersion()
            if current_data then
                if data.name then
                    if current_data.name ~= data.name then
                        GBankClassic_Core:Print("A non-guild version!")
                        return
                    end
                end
                if data.addon and current_data.addon then
                    if data.addon > current_data.addon then
                        if not self.addon_outdated then
                            -- only make the callout once
                            self.addon_outdated = true
                            GBankClassic_Core:Print("A newer version is available! Download it from https://www.curseforge.com/wow/addons/gbankclassic-revived/")
                        end
                    end
                end
                if data.roster then
                    if current_data.roster == nil or data.roster > current_data.roster then
                        GBankClassic_Guild:RequestRosterSync(sender, data.roster)
                    end
                end
                if data.alts then
                    for k, v in pairs(data.alts) do
                        if not current_data.alts[k] or v > current_data.alts[k] then
                            GBankClassic_Guild:RequestAltSync(sender, k, v)
                        end
                    end
                end
            end
        end
    end

    if prefix == "gbank-r" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            if data.player == player then
                if data.type == "roster" then
                    local time = GetServerTime()
                    if self.last_roster_sync == nil or time - self.last_roster_sync > 300 then
                        self.last_roster_sync = time
                        GBankClassic_Guild:SendRosterData()
                    end
                end

                if data.type == "alt" then
                    table.insert(self.sync_queue, data.name)
                    if not self.is_syncing then
                        GBankClassic_Chat:ProcessQueue()
                    end
                end
            end
        end
    end

    if prefix == "gbank-d" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            if data.type == "roster" then
                GBankClassic_Guild:ReceiveRosterData(data.roster)
            end

            if data.type == "alt" then
                GBankClassic_Guild:ReceiveAltData(data.name, data.alt)
            end
        end
    end
    
    ---START CHANGES
    if prefix == "gbank-h" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            GBankClassic_Guild:Hello("reply")
        end
    end
	if prefix == "gbank-hr" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
			GBankClassic_Core:Print(data)
        end
    end	
    if prefix == "gbank-s" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            GBankClassic_Guild:Share("reply")
        end
    end
    if prefix == "gbank-w" then
        local success, data = GBankClassic_Core:Deserialize(message)
        if success then
            GBankClassic_Guild:Wipe("reply")
        end
    end
    ---END CHANGES
end

function GBankClassic_Chat:ChatCommand(input)
    if input == nil or input == "" then
        GBankClassic_UI_Inventory:Toggle()
    else
        local commands = {
            ["sync"] = function ()
                GBankClassic_Events:Sync()
            end,
            ---START CHANGES
            ["reset"] = function ()
                local guild = GBankClassic_Guild:GetGuild()
                if not guild then return end
                GBankClassic_Guild:Reset(guild)
            end,
            ["share"] = function ()
                GBankClassic_Bank:OnUpdateStart()
                GBankClassic_Bank:OnUpdateStop()
                GBankClassic_Guild:Share()
            end,
            ["help"] = function ()
                GBankClassic_Chat:ShowHelp()
            end,
            ["hello"] = function ()
                GBankClassic_Guild:Hello()
            end,
            ["wipeall"] = function ()
                GBankClassic_Guild:Wipe()
            end,
            ["wipe"] = function ()
                GBankClassic_Guild:WipeMine()
            end,
            ["roster"] = function ()
                GBankClassic_Guild:AuthorRosterData()
            end,
            ---END CHANGES
        }

        local prefix, _ = GBankClassic_Core:GetArgs(input, 1)
        local cmd = commands[prefix]
        if cmd ~= nil then
            cmd()
        else
            GBankClassic_UI_Inventory:Toggle()
        end
    end

    return false
end

function GBankClassic_Chat:ShowHelp()
    GBankClassic_Core:Print("\n|cff33ff99Commands:|r\n|cffe6cc80/bank|r (to display the GBankClassic interface) \n|cffe6cc80/bank help|r (this message) \n|cffe6cc80/bank sync|r (to manually receive the latest data from other online users with guild bank data; this is done every 10 minutes automatically) \n|cffe6cc80/bank share|r (to manually share the contents of your guild bank with other online users of GBankClassic; this is done every 3 minutes automatically), \n|cffe6cc80/bank reset|r (to reset your own GBankClassic database)\n")
    GBankClassic_Core:Print("\n|cff33ff99Expert commands:|r\n|cffe6cc80/bank roster|r (guild banks and members that can read the officer note can use this command to share updated roster data with online guild members)\n|cffe6cc80/bank hello|r (understand which online guild members use which addon version and know what guild bank data; needs corresponding weakaura to print deserliazed addon communication)\n|cffe6cc80/bank wipe|r (reset your own GBankClassic database)\n|cffe6cc80/bank wipeall|r (officer only: reset your own GBankClassic database and that of all online guild members)")
    GBankClassic_Core:Print("\n|cff33ff99Instructions for setting up a new guild bank:|r\n1. Log in with the guild bank character, ensuring they are in the guild.\n2. Add |cffe6cc80gbank|r to their guild or officer note, then type |cffe6cc80/reload|r.\n3. In addon options (Escape -> Options -> Addons -> GBankClassic - Revived), click on the |cffe6cc80-|r icon (expand/collapse) to the left of the entry, enable reporting and scanning for the bank character in the |cffe6cc80Bank|r section.\n4. Open and close your mailbox, bags, and bank.\n5. Type |cffe6cc80/bank roster|r and confirm your bank character is included in the sent roster.\n6. Type |cffe6cc80/reload|r.  Wait up to 3 minutes (or type |cffe6cc80/bank share|r for immediate sharing) until |cffe6cc80Sharing guild bank data...|r completes.\n7. Verify with a guild member (they type |cffe6cc80/bank|r).\n")
    GBankClassic_Core:Print("\n|cff33ff99Instructions for removing a guild bank:|r\n1. Log in with an officer or another bank character in the same guild (or a character from a different guild).\n2. If the bank character is still in the guild, remove |cffe6cc80gbank|r from their notes.\n3. Type |cffe6cc80/bank roster|r and confirm the bank character is no longer listed or the roster is empty.\n4. Verify with a guild member (they type |cffe6cc80/bank|r).\n")
end

function GBankClassic_Chat:ProcessQueue()
    if IsInRaid() then return end
    if #self.sync_queue == 0 then
        self.is_syncing = false
        return
    end

    self.is_syncing = true

    local time = GetServerTime()

    local name = table.remove(self.sync_queue)
    if not self.last_alt_sync[name] or time - self.last_alt_sync[name] > 180 then
        self.last_alt_sync[name] = time
        GBankClassic_Guild:SendAltData(name)
    end

    GBankClassic_Chat:ReprocessQueue()
end

function GBankClassic_Chat:ReprocessQueue()
    GBankClassic_Core:ScheduleTimer(function (...) GBankClassic_Chat:OnTimer() end, 5)
end

function GBankClassic_Chat:OnTimer()
    GBankClassic_Chat:ProcessQueue()
end
