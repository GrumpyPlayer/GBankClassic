GBankClassic_Guild = {}

GBankClassic_Guild.Info = nil

function GetPlayerWithNormalizedRealm(name)
    if(string.match(name, "(.*)%-(.*)")) then
		return name
	end
	return name.."-"..GetNormalizedRealmName("player")
end

local function NormalizePlayerName(name)
    if not name then return nil end
    -- Accept a few non-string shapes gracefully (some peers may send objects)
    if _G.type(name) ~= "string" then
        -- If it's a table with common fields, prefer them
        if _G.type(name.who) == "string" then
            name = name.who
        elseif _G.type(name.name) == "string" then
            name = name.name
        else
            -- Can't normalize unknown types
            return nil
        end
    end
    -- Canonicalize hyphen spacing: convert "Name - Realm" or "Name- Realm" to "Name-Realm"
    local normalized = string.gsub(name, "%s*%-%s*", "-")
    if string.match(normalized, "^(.-)%-(.-)$") then
        return normalized
    end
    -- If helper exists, use it
    if GetPlayerWithNormalizedRealm then
        return GetPlayerWithNormalizedRealm(name)
    end
    -- Fallback: append current realm
    return name.."-"..GetNormalizedRealmName("player")
end
GBankClassic_Guild.NormalizePlayerName = NormalizePlayerName

function GBankClassic_Guild:GetPlayer()
    if GBankClassic_Bank.player then return GBankClassic_Bank.player end

    -- The below code should never be called, but is here for safety
    local function try()
      local name, realm = UnitName("player"), GetNormalizedRealmName()
      if name and realm then
        GBankClassic_Bank.player = name .. "-" .. realm
        return true
      end
    end
    if try() then return GBankClassic_Bank.player end
    local count, max, delay, timer = 0, 10, 15
    timer = C_Timer.NewTicker(delay, function()
      count = count + 1
      if try() or count >= max then
        if timer then timer:Cancel() end
      end
    end)
  
    return nil
end

function GBankClassic_Guild:GetGuild()
    return IsInGuild("player") and GetGuildInfo("player") or nil
end

function GBankClassic_Guild:GetPlayerInfo(name)
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        player, _ = string.match(playerRealm, "(.*)%-(.*)")
        if playerRealm == name then
            return class
        end
    end
    return nil
end

function GBankClassic_Guild:Reset(name)
    if not name then return end

    GBankClassic_UI_Inventory:Close()
    GBankClassic_Database:Reset(name)
    GBankClassic_Core:Print("Reset database")
    self.Info = GBankClassic_Database:Load(name)
    
    if self.BuildRosterFromNotes then
        self:BuildRosterFromNotes()
    end
end

function GBankClassic_Guild:Init(name)
    if not name then return false end
    if self.Info and self.Info.name == name then return false end

    self.hasRequested = false
    self.requestCount = 0

    self.Info = GBankClassic_Database:Load(name)
    if self.Info then return true end

    self:Reset(name)
    return true
end

function GBankClassic_Guild:CleanupMalformedAlts()
    if not self.Info or not self.Info.alts then return 0 end

    local cleaned = 0
    for name, alt in pairs(self.Info.alts) do
        local remove = false
        if _G.type(alt) ~= "table" then
            remove = true
        else
            -- Ensure version is present, but malformed nested fields are problematic
            if alt.bank and _G.type(alt.bank) == "table" and alt.bank.items then
                for k, v in pairs(alt.bank.items) do
                    if not v or _G.type(v) ~= "table" or not v.ID then
                        alt.bank.items[k] = nil
                    end
                end
            end
            if alt.bags and _G.type(alt.bags) == "table" and alt.bags.items then
                for k, v in pairs(alt.bags.items) do
                    if not v or _G.type(v) ~= "table" or not v.ID then
                        alt.bags.items[k] = nil
                    end
                end
            end
            -- If after cleaning the alt has no meaningful fields (no version, no money, no items), remove it
            local hasData = false
            if alt.version then hasData = true end
            if alt.money then hasData = true end
            if alt.bank and next(alt.bank.items or {}) then hasData = true end
            if alt.bags and next(alt.bags.items or {}) then hasData = true end
            if not hasData then remove = true end
        end

        if remove then
            self.Info.alts[name] = nil
            cleaned = cleaned + 1
        end
    end

    -- Ensure roster.alts is a proper array (remove nils and non-strings)
    if self.Info.roster and self.Info.roster.alts then
        local new_alts = {}
        for _, v in pairs(self.Info.roster.alts) do
            if _G.type(v) == "string" and v ~= "" then
                table.insert(new_alts, v)
            end
        end
        self.Info.roster.alts = new_alts
    end

    return cleaned
end

function GBankClassic_Guild:GetBanks()
    local hasBanks = false
    local banks = {}
    local GuildRoster = GuildRoster or C_GuildInfo.GuildRoster
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    if GuildRoster then GuildRoster() end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, publicNote, officer_note, _, _, _ = GetGuildRosterInfo(i)
        if publicNote ~= nil or officer_note ~= nil then
            if (publicNote and string.match(publicNote, "(.*)gbank(.*)")) or (officer_note and string.match(officer_note, "(.*)gbank(.*)")) then
                table.insert(banks, name)
                hasBanks = true
            end
        end
    end
    if not hasBanks then return nil end
    return banks
end

function GBankClassic_Guild:IsBank(player)
    local banks = GBankClassic_Guild:GetBanks()
    if banks == nil then return false end

    local isBank = false
    for _, v in pairs(banks) do
        if v == player then
            isBank = true
        end
    end

    return isBank
end

function GBankClassic_Guild:CheckVersion(version)
    if not self.Info then return false end
    if not self.Info.roster or not self.Info.roster.version or not version then return false end

    if version > self.Info.roster.version then
        return false
    end

    return true
end

function GBankClassic_Guild:GetVersion()
    if not self.Info then return nil end

    local GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
    local versionInfo = GetAddOnMetadata("GBankClassic", "Version"):gsub("%.", "")
    local versionNumber = tonumber(versionInfo)
    local data = {
        addon = versionNumber,
        roster = nil,
        alts = {}
    }

    if self.Info.name then
        data.name = self.Info.name
    end

    if self.Info.roster.version then
        data.roster = self.Info.roster.version
    end

    for k, v in pairs(self.Info.alts) do
        if _G.type(v) == "table" and v.version then
            data.alts[k] = v.version
        end
    end

    return data
end

function GBankClassic_Guild:RequestRosterSync(player, version)
    self.hasRequested = true
    if self.requestCount == nil then self.requestCount = 1 else self.requestCount = self.requestCount + 1 end
    local data = GBankClassic_Core:Serialize({player = player, type = "roster", version = version})
    GBankClassic_Core:SendCommMessage("gbank-r", data, "Guild", nil, "BULK")
end

function GBankClassic_Guild:RequestAltSync(player, name, version)
    self.hasRequested = true
    if self.requestCount == nil then self.requestCount = 1 else self.requestCount = self.requestCount + 1 end
    local data = GBankClassic_Core:Serialize({player = player, type = "alt", name = name, version = version})
    GBankClassic_Core:SendCommMessage("gbank-r", data, "Guild", nil, "BULK")
    -- Start offer-collection for relays (in case owner does not respond quickly)
    if GBankClassic_Chat and GBankClassic_Chat.StartAltRequest then
        GBankClassic_Chat:StartAltRequest(name, player, version)
    end
end

function GBankClassic_Guild:SendRosterData(author)
    if not self.Info and not self.Info.roster then return end
    local payload = {type = "roster", roster = self.Info.roster}
    if author then payload.author = author end
    local data = GBankClassic_Core:Serialize(payload)
    GBankClassic_Core:SendCommMessage("gbank-d", data, "Guild", nil, "BULK")
end

local function SanitzeRoster(roster)
    if not roster or not roster.alts then return roster end
    local out = {}
    for _, v in pairs(roster.alts) do
        if _G.type(v) == 'string' then
            table.insert(out, v)
        elseif _G.type(v) == 'table' then
            if _G.type(v.who) == 'string' then
                table.insert(out, v.who)
            elseif _G.type(v.name) == 'string' then
                table.insert(out, v.name)
            end
        end
    end
    roster.alts = out
    return roster
end

function GBankClassic_Guild:ReceiveRosterData(roster)
    if not self.Info then return end
    if self.Info.roster.version and roster.version and roster.version < self.Info.roster.version then return end
    if self.hasRequested then
      if self.requestCount == nil then self.requestCount = 0 else self.requestCount = self.requestCount - 1 end
        if self.requestCount == 0 then
            self.hasRequested = false
            local shutup = GBankClassic_Options:GetBankVerbosity()
            if shutup == false then
                if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sync completed.") end
            end
        end
    end

    -- Sanitize roster entries to ensure alts is a list of strings
    roster = SanitzeRoster(roster)
    self.Info.roster = roster
end

function GBankClassic_Guild:BuildRosterFromNotes()
    local guild = GBankClassic_Guild:GetGuild()
    if not guild then return end

    local banks = self:GetBanks()
    if not banks or #banks == 0 then return false end

    self.Info = GBankClassic_Database:Load(guild)
    if not self.Info then return false end

    self.Info.roster = self.Info.roster or {}
    self.Info.roster.alts = banks
    self.Info.roster.version = self.Info.roster.version or nil
    return true
end

function GBankClassic_Guild:SenderHasGbankNote(sender)
    if not sender then return false end
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, _, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
        if playerRealm then
            local norm = NormalizePlayerName(playerRealm)
            if norm == sender then
                if (publicNote and string.match(publicNote, "(.*)gbank(.*)")) or (officer_note and string.match(officer_note, "(.*)gbank(.*)")) then
                    return true
                end
            end
        end
    end
    return false
end

function GBankClassic_Guild:SendAltData(name, force)
    if not name then return end
    local norm = NormalizePlayerName(name)
    -- Ensure we have the latest possible data before deciding we have nothing to send
    if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
        if GBankClassic_Bank and GBankClassic_Bank.Scan then
            GBankClassic_Bank:Scan()
        end
        if not self.Info or not self.Info.alts or not self.Info.alts[norm] then
            local shutup = GBankClassic_Options:GetBankVerbosity()
            if shutup == false then
                if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('No local data to share for', norm) end
            end
            return
        end
    end

    -- Bump the version so this transfer wins conflict resolution
    if force then
        self.Info.alts[norm].version = GetServerTime()
    end

    local data = GBankClassic_Core:Serialize({type = "alt", name = norm, alt = self.Info.alts[norm]})
    GBankClassic_Core:SendCommMessage("gbank-d", data, "Guild", nil, "BULK", OnChunkSent)
end

function OnChunkSent(arg, sent, total)
    local shutup = GBankClassic_Options:GetBankVerbosity()
    if shutup == false then
        if sent <= 255 then 
            if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sharing guild bank data...") end
        end
        if sent == total then
            if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sharing guild bank data has completed.") end
            -- If a peer discovery happened shortly before sending, report recipients
            if GBankClassic_Chat and GBankClassic_Chat.last_discovery then
                local names = {}
                for who, v in pairs(GBankClassic_Chat.last_discovery) do table.insert(names, who) end
                if #names > 0 then
                    GBankClassic_Core:Print("Sent guild bank data to addon peers: "..table.concat(names, ", "))
                end
                -- Clear discovery snapshot after reporting
                GBankClassic_Chat.last_discovery = nil
            end
        end
    end
end

function GBankClassic_Guild:ReceiveAltData(name, alt)
    if not self.Info then return end

    -- Sanitize incoming alt data
    local function sanitizeAlt(a)
        if not a or _G.type(a) ~= "table" then return nil end
        if a.bank and _G.type(a.bank) == "table" and a.bank.items then
            for k, v in pairs(a.bank.items) do
                if not v or _G.type(v) ~= "table" or not v.ID then a.bank.items[k] = nil end
            end
        end
        if a.bags and _G.type(a.bags) == "table" and a.bags.items then
            for k, v in pairs(a.bags.items) do
                if not v or _G.type(v) ~= "table" or not v.ID then a.bags.items[k] = nil end
            end
        end
        return a
    end

    alt = sanitizeAlt(alt)
    if not alt then return end

    local norm = NormalizePlayerName(name)
    local existing = self.Info.alts[norm]
    if existing and alt.version ~= nil and existing.version ~= nil and alt.version < existing.version then return end

    -- Accept incoming if newer version
    -- If same version, accept the alt with more items
    local function itemCount(a)
        local c = 0
        if a and a.bank and a.bank.items then for _, v in pairs(a.bank.items) do if v and v.ID then c = c + 1 end end end
        if a and a.bags and a.bags.items then for _, v in pairs(a.bags.items) do if v and v.ID then c = c + 1 end end end
        return c
    end

    if existing and existing.version and alt.version and alt.version < existing.version then
        -- Incoming is older; ignore
        return
    elseif existing and existing.version and alt.version and alt.version == existing.version then
        -- Tie-breaker: choose the one with more items
        if itemCount(alt) <= itemCount(existing) then
            return
        end
    end

    if self.Info.alts[norm] and alt.version ~= nil and self.Info.alts[norm].version ~= nil and alt.version < self.Info.alts[norm].version then return end
    if self.hasRequested then
        if self.requestCount == nil then self.requestCount = 0 else self.requestCount = self.requestCount - 1 end
        if self.requestCount == 0 then
            self.hasRequested = false
            local shutup = GBankClassic_Options:GetBankVerbosity()
            if shutup == false then
                if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sync completed.") end
            end
        end
    end

    self.Info.alts[norm] = alt

end

local function GetTableEntriesCount(a)
    local b=0
    for c,d in pairs(a) do 
        b=b+1 
    end
    return b 
end 

function GBankClassic_Guild:Hello(type)
    local addon_data = GBankClassic_Guild:GetVersion()
    local current_data = GBankClassic_Guild.Info
    if addon_data and current_data then
        local hello = "Hi! "..GBankClassic_Guild:GetPlayer().." is using version "..addon_data.addon.."."
        if GBankClassic_Chat and GBankClassic_Chat.debug then
            local roster_alts = ""
            local guild_bank_alts = ""
            if GetTableEntriesCount(current_data.roster) > 0 and GetTableEntriesCount(current_data.alts) > 0 then
                for _, v in pairs(current_data.roster.alts) do if roster_alts ~= "" then roster_alts = roster_alts..", " end roster_alts = roster_alts..v end
                if roster_alts ~= "" then roster_alts = " ("..roster_alts..")" end
                for k, _ in pairs(current_data.alts) do if guild_bank_alts ~= "" then guild_bank_alts = guild_bank_alts..", " end guild_bank_alts = guild_bank_alts..k end 
                if guild_bank_alts ~= "" then guild_bank_alts = " ("..guild_bank_alts..")" end
                if current_data.roster.alts then 
                    hello = hello.."\n"
                    hello = hello.."I know about "..#current_data.roster.alts.." guild bank alts"..roster_alts.." on the roster."
                    hello = hello.."\n"
                    hello = hello.."I have guild bank data from "..GetTableEntriesCount(current_data.alts).." alts"..guild_bank_alts.."." 
                end
            else
                hello = hello.." I know about 0 guild bank alts on the roster, and have guild bank data from 0 alts."
            end
            GBankClassic_Core:DebugPrint(hello)
        end
        local data = GBankClassic_Core:Serialize(hello)
        if type ~= "reply" then
            GBankClassic_Core:SendCommMessage("gbank-h", data, "Guild", nil, "BULK")
        else
            GBankClassic_Core:SendCommMessage("gbank-hr", data, "Guild", nil, "BULK")
        end
    end
end

function GBankClassic_Guild:Wipe(type)
    local guild = GBankClassic_Guild:GetGuild()
    local CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
    local canViewOfficerNote = CanViewOfficerNote()
    if not guild and not canViewOfficerNote then return end
    local wipe = "I wiped all addon data from "..guild.."."
    GBankClassic_Guild:Reset(guild)

    local data = GBankClassic_Core:Serialize(wipe)
    if type ~= "reply" then
        GBankClassic_Core:SendCommMessage("gbank-w", data, "Guild", nil, "BULK")
    else
        GBankClassic_Core:SendCommMessage("gbank-wr", data, "Guild", nil, "BULK")
    end
end

function GBankClassic_Guild:WipeMine(type)
    local guild = GBankClassic_Guild:GetGuild()
    if not guild then return end
    local wipe = "I wiped all my addon data from "..guild.."."
    GBankClassic_Guild:Reset(guild)
end

function GBankClassic_Guild:Share(type)
    local guild = GBankClassic_Guild:GetGuild()
    if not guild then return end

    self.Info = GBankClassic_Database:Load(guild)
    local player = GBankClassic_Guild:GetPlayer()
    local normPlayer = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(player) or player
    local share = "I'm sharing my bank data. Share yours please."

    if not self.Info.alts[normPlayer] then
        if type ~= "reply" then
            share = "Share your bank data please."
        else
            share = "Nothing to share."
        end
    end

    -- Perform a discovery so we can inform the user who will likely receive their share
    if GBankClassic_Chat and GBankClassic_Chat.DiscoverPeers then
        GBankClassic_Chat:DiscoverPeers(2, function(responses)
            local count = 0
            local names = {}
            for who, v in pairs(responses or {}) do
                count = count + 1
                table.insert(names, who)
            end
            local shutup = GBankClassic_Options:GetBankVerbosity()
            -- Determine if we have meaningful local data to share for the requesting player.
            local hasLocalData = false
            if self.Info and self.Info.alts and self.Info.alts[normPlayer] then
                local alt = self.Info.alts[normPlayer]
                if _G.type(alt) == 'table' then
                    -- Consider presence of a version or any bank/bag items as meaningful data
                    local hasBankItems = alt.bank and _G.type(alt.bank) == 'table' and alt.bank.items and next(alt.bank.items) ~= nil
                    local hasBagItems = alt.bags and _G.type(alt.bags) == 'table' and alt.bags.items and next(alt.bags.items) ~= nil
                    if alt.version or hasBankItems or hasBagItems then
                        hasLocalData = true
                    end
                end
            end
            if count == 0 then
                if shutup == false and type ~= "reply" then
                    if hasLocalData then
                        if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('Share: no addon-enabled peers responded; your data will be available when someone logs on.') end
                    else
                        if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('Share: no addon-enabled peers responded.') end
                    end
                end
            else
                if hasLocalData then
                    if shutup == false and type ~= "reply" then
                        if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('Share: detected '..count..' addon peers ('..table.concat(names, ', ')..'). Sending data...') end
                    end
                else
                    if shutup == false and type ~= "reply" then
                        if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('Share: detected '..count..' addon peers ('..table.concat(names, ', ')..'). You have no local bank data to send; requesting peers to share.') end
                    end
                end
            end
            
            -- Send alt data (if present) and broadcast share notice
            if hasLocalData then
                GBankClassic_Guild:SendAltData(normPlayer)
            end
            local data = GBankClassic_Core:Serialize(share)
            if type ~= "reply" then
                GBankClassic_Core:SendCommMessage("gbank-s", data, "Guild", nil, "BULK")
            else
                GBankClassic_Core:SendCommMessage("gbank-sr", data, "Guild", nil, "BULK")
            end
        end)
    else
        -- Fallback: just send without discovery
        if self.Info.alts[normPlayer] and GBankClassic_Guild:IsBank(normPlayer) then GBankClassic_Guild:SendAltData(normPlayer) end
        local data = GBankClassic_Core:Serialize(share)
        if type ~= "reply" then
            GBankClassic_Core:SendCommMessage("gbank-s", data, "Guild", nil, "BULK")
        else
            GBankClassic_Core:SendCommMessage("gbank-sr", data, "Guild", nil, "BULK")
        end
    end
end

function GBankClassic_Guild:AuthorRosterData()
    if not self.Info then return end
    local info = self.Info
    local isBank = false
    local banks = GBankClassic_Guild:GetBanks()
    local player = GBankClassic_Guild:GetPlayer()
    if banks then
        for _, v in pairs(banks) do
            if v == player then
                isBank = true
                break
            end
        end
    end
    local CanEditOfficerNote = CanEditOfficerNote or C_GuildInfo.CanEditOfficerNote
    if isBank or CanEditOfficerNote() then
        info.roster.alts = banks
        info.roster.version = GetServerTime()
        if not banks then info.roster.version = nil end
        local player = GBankClassic_Guild:GetPlayer()
        local normPlayer = GBankClassic_Guild.NormalizePlayerName and GBankClassic_Guild:NormalizePlayerName(player) or player
        local author = { who = normPlayer, role = "member" }
        if GBankClassic_Guild:SenderIsGM(player) then
            author.role = "gm"
        elseif GBankClassic_Guild:SenderHasGbankNote(player) then
            author.role = "bank"
        elseif CanEditOfficerNote() then
            author.role = "officer"
        end
        GBankClassic_Guild:SendRosterData(author)
        if banks then
            local characterNames = {}
            for _, bankChar in pairs(banks) do
                table.insert(characterNames, bankChar)
            end
            if #characterNames > 0 then
                if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sent updated roster containing the follow banks: " .. table.concat(characterNames, ", ")) end
            else
                if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sent empty roster.") end
            end
        else
            if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Sent empty roster.") end
        end
    end
end

function GBankClassic_Guild:SenderIsGM(player)
    if not player then return false end
    if not IsInGuild() then return false end
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    for i = 1, GetNumGuildMembers() do
        local playerRealm, _, rankIndex, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
        if playerRealm then
            local norm = GBankClassic_Guild.NormalizePlayerName(playerRealm)
            if rankIndex == 0 and norm == player then
                return true
            end
        end
    end
    return false
end

function GBankClassic_Guild:SenderIsOfficer(player)
    -- Robust officer detection:
    -- 1) If the roster indicates the player is GM/officer (rankIndex 0/1) -> accept immediately
    -- 2) If the player is already a trusted bank on our roster -> accept immediately
    -- 3) If we can *edit* officer notes and the player's officer note contains 'gbank' -> accept
    if not player then return false end
    if not IsInGuild() then return false end

    -- 1) GM check (rankIndex 0 is GM and is authoritative)
    if GBankClassic_Guild:SenderIsGM(player) then return true end

    -- 2) Trusted bank check (existing roster)
    if self and self.Info and self.Info.roster and self.Info.roster.alts then
        for _, v in pairs(self.Info.roster.alts) do
            if v == player then
                return true
            end
        end
    end

    -- 3) Officer note editability + content
    local GetNumGuildMembers = GetNumGuildMembers or C_GuildInfo.GetNumGuildMembers
    local GetGuildRosterInfo = GetGuildRosterInfo or C_GuildInfo.GetGuildRosterInfo
    local CanEditOfficerNote = CanEditOfficerNote or C_GuildInfo.CanEditOfficerNote
    if CanEditOfficerNote() then
        for i = 1, GetNumGuildMembers() do
            local playerRealm, _, _, _, _, _, publicNote, officer_note = GetGuildRosterInfo(i)
            if playerRealm then
                local norm = GBankClassic_Guild.NormalizePlayerName(playerRealm)
                if norm == player then
                    if officer_note and string.match(officer_note, "(.*)gbank(.*)") then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function GBankClassic_Guild:GetStatusReport()
    local guildName = self:GetGuild()
    local hasGuild = (guildName ~= nil)
    local info = self.Info
    local banksFound = 0
    local isAuthoritative = false
    
    if info and info.roster then
        if info.roster.version then isAuthoritative = true end
        if info.roster.alts then
             banksFound = #info.roster.alts
        end
    end
    
    local banks = self:GetBanks()
    local banksFromNotes = banks and #banks or 0
    local CanViewOfficerNote = CanViewOfficerNote or C_GuildInfo.CanViewOfficerNote
    
    if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("GBankClassic_Guild:GetStatusReport()", "hasGuild:", hasGuild, "guildName:", guildName, "banksFound:", banksFound, "banksFromNotes:", banksFromNotes, "isAuthoritative:", isAuthoritative, "canViewOfficerNote:", CanViewOfficerNote()) end

    return {
        hasGuild = hasGuild,
        guildName = guildName,
        banksFound = banksFound,
        banksFromNotes = banksFromNotes,
        isAuthoritative = isAuthoritative,
        canViewOfficerNote = CanViewOfficerNote()
    }
end
