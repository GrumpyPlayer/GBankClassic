GBankClassic_UI_Inventory = {}

function GBankClassic_UI_Inventory:Init()
    self:DrawWindow()
end

local function OnClose(_)
    GBankClassic_UI_Inventory.isOpen = false
    GBankClassic_UI_Inventory.Window:Hide()
    GBankClassic_UI_Donations:Close()
    GBankClassic_UI_Search:Close()
end

function GBankClassic_UI_Inventory:Toggle()
    if self.isOpen then
        self:Close()
    else
        self:Open()
    end
end

function GBankClassic_UI_Inventory:Open()
    if self.isOpen then return end
    self.isOpen = true
    if not self.Window then
        self:DrawWindow()
    end
    self.Window:Show()
    self:DrawContent()
    if _G["GBankClassic"] then
        _G["GBankClassic"]:Show()
    else
        GBankClassic_UI:Controller()
    end
end

function GBankClassic_UI_Inventory:Close()
    if not self.isOpen then return end
    if not self.Window then return end
    OnClose(self.Window)
end

function GBankClassic_UI_Inventory:DrawWindow()
    local window = GBankClassic_UI:Create("Frame")
    window:Hide()
    window:SetCallback("OnClose", OnClose)
    window:SetTitle("GBankClassic")
    window:SetLayout("Flow")
    window:SetWidth(550)
    window.frame:SetResizeBounds(500, 500)
    window.frame:EnableKeyboard(true)
    window.frame:SetPropagateKeyboardInput(true)
    window.frame:SetScript("OnKeyDown", function (self, event)
        GBankClassic_UI:EventHandler(self, event)
    end)
    self.Window = window

    local buttonContainer = GBankClassic_UI:Create("SimpleGroup")
    buttonContainer:SetLayout("Table")
    buttonContainer:SetUserData("table", {
        columns = {
            {
                width = 0.5,
                align = "start",
            },
            {
                width = 0.5,
                align = "end",
            },
        },
    })
    buttonContainer:SetFullWidth(true)
    buttonContainer.frame:ClearAllPoints()
    buttonContainer.content:SetPoint("TOPLEFT", 0, 5)
    buttonContainer.content:SetPoint("BOTTOMRIGHT", 0, -5)
    window:AddChild(buttonContainer)

    local searchButton = GBankClassic_UI:Create("Button")
    searchButton:SetText("Search")
    searchButton:SetCallback("OnClick", function(_)
        GBankClassic_UI_Search:Toggle()
    end)
    searchButton:SetWidth(175)
    searchButton:SetHeight(24)
    buttonContainer:AddChild(searchButton)

    local scoreboardButton = GBankClassic_UI:Create("Button")
    scoreboardButton:SetText("Donations")
    scoreboardButton:SetCallback("OnClick", function(_)
        GBankClassic_UI_Donations:Toggle()
    end)
    scoreboardButton:SetWidth(175)
    scoreboardButton:SetHeight(24)
    buttonContainer:AddChild(scoreboardButton)

    local tabGroup = GBankClassic_UI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    window:AddChild(tabGroup)
    self.TabGroup = tabGroup
end

function GBankClassic_UI_Inventory:DrawStatusScreen(status)
    self.TabGroup:SetTabs({})

    local container = GBankClassic_UI:Create("SimpleGroup")
    container:SetFullWidth(true)
    container:SetLayout("Flow")
    self.TabGroup:AddChild(container)
    
    local title = GBankClassic_UI:Create("Label")
    title:SetText("GBankClassic Revived\n")
    title:SetFontObject(GameFontNormalLarge)
    title:SetFullWidth(true)
    container:AddChild(title)

    local helpText = "Welcome to GBankClassic!\n\nWaiting for data...\n\n"
    if status.hasGuild and status.guildName then
        helpText = helpText .. "- Guild: " .. status.guildName .. "\n"
        if status.banksFromNotes > 0 then
            helpText = helpText .. "- Banks defined in notes: " .. status.banksFromNotes .. "\n"
        else
            helpText = helpText .. "- Banks defined in notes: 0\n"
            helpText = helpText .. "  (no 'gbank' found in any player's public note)\n"
            if status.canViewOfficerNote == false then
                helpText = helpText .. "  Officer notes are unreadable due to your rank in this guild.\n\n"
                helpText = helpText .. "  Please wait for an officer or another player to come online to sync,\n"
                helpText = helpText .. "  or ask if your guild is using this addon.\n"
            else
                helpText = helpText .. "  (no 'gbank' found in any player's officer note either)\n"
                helpText = helpText .. "  To use this addon, add 'gbank' to the public or officer note of a bank character.\n"
            end
        end
        
        local peers = 0
        if GBankClassic_Chat and GBankClassic_Chat.last_discovery then
            for _ in pairs(GBankClassic_Chat.last_discovery) do peers = peers + 1 end
        elseif GBankClassic_Chat and GBankClassic_Chat.peer_discovery and GBankClassic_Chat.peer_discovery.responses then
            for _ in pairs(GBankClassic_Chat.peer_discovery.responses) do peers = peers + 1 end
        end
        helpText = helpText .. "- Peers detected: " .. peers .. "\n\n"
        
        helpText = helpText .. "If this is your first time, please wait for a peer or bank to send data.\n"
        helpText = helpText .. "Ensure someone else with the latest version of this addon is online.\n"
    else
        helpText = helpText .. "- Guild: not detected!\n"
    end

    local label = GBankClassic_UI:Create("Label")
    label:SetText(helpText)
    label:SetFullWidth(true)
    container:AddChild(label)
    
    local btn = GBankClassic_UI:Create("Button")
    btn:SetText("Scan for peers now")
    btn:SetCallback("OnClick", function() 
        GBankClassic_Chat:DiscoverPeers(2, function() 
            if self.isOpen then 
                self:DrawContent()
            end
        end)
    end)
    container:AddChild(btn)
end

function GBankClassic_UI_Inventory:DrawContent()
    local info = GBankClassic_Guild.Info
    if not info or not info.roster or not info.roster.alts or #info.roster.alts == 0 then
        if GBankClassic_Guild and GBankClassic_Guild.BuildRosterFromNotes then
            local built = GBankClassic_Guild:BuildRosterFromNotes()
            if built then
                local shutup =   GBankClassic_Options:GetBankVerbosity()
                if shutup == false then
                    if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint('Roster inferred from guild notes; showing placeholders for banks and awaiting sync.') end
                end
            elseif self.isOpen then
                -- Player is either not in a guild or the initialization might not be completed
                -- Show the status screen when the database is empty
                local status = GBankClassic_Guild.GetStatusReport and GBankClassic_Guild:GetStatusReport()
                self.TabGroup:ReleaseChildren()
                self:DrawStatusScreen(status)
                return
            end
        end

        if not info or not info.roster or not info.roster.alts or #info.roster.alts == 0 then
            self.TabGroup:SetTabs({})
            self.TabGroup:ReleaseChildren()
            return
        end
    end

    GBankClassic_UI_Search:BuildSearchData()

    local players = {}
    local n = 0
    for _, v in pairs(info.roster.alts) do
        n = n + 1
        players[n] = v
    end
    table.sort(players)

    local tabs = {}
    local first_tab = nil
    local total_gold = 0
    local slots = 0
    local total_slots = 0
    local i = 1
    local unselect = true

    for _, player in pairs(players) do
        local norm = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild:NormalizePlayerName(player) or player
        local alt = info.alts and info.alts[norm] or nil
        if not first_tab then
            first_tab = player
        end
        if self.TabGroup.localstatus.selected == player then
            unselect = false
        end
        tabs[i] = {value = player, text = player}
        if alt and _G.type(alt) == "table" then
            if alt.money then
                total_gold = total_gold + alt.money
            end
            if alt.bank then
                slots = slots + alt.bank.slots.count
                total_slots = total_slots + alt.bank.slots.total
            end
            if alt.bags then
                slots = slots + alt.bags.slots.count
                total_slots = total_slots + alt.bags.slots.total
            end
        end
        i = i + 1
    end

    self.TabGroup:SetTabs(tabs)
    if #tabs == 1 or unselect == true then
        self.TabGroup:SelectTab(first_tab)
    else
        self.TabGroup:SelectTab(self.TabGroup.localstatus.selected)
    end

    local defaultStatus
    if total_slots == 0 or slots == 0 then
        defaultStatus = "No bank data; sync pending."
    else
        local color = GBankClassic_UI_Inventory:GetPercentColor(slots / total_slots)
        defaultStatus = string.format("%s    |c%s%d/%d|r", GetCoinTextureString(total_gold), color, slots, total_slots)
    end
    self.Window:SetStatusText(defaultStatus)

    self.Window:SetCallback("OnEnterStatusBar", function(_)
        local tab = self.TabGroup.localstatus.selected
        local normTab = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(tab) or tab
        local alt = info.alts and info.alts[normTab] or nil
        if not alt or not alt.version then return end

        local datetime = date("%Y-%m-%d %H:%M:%S", alt.version)
        local slot_count = 0
        local slot_total = 0
        if alt.bank then
            slot_count = slot_count + alt.bank.slots.count
            slot_total = slot_total + alt.bank.slots.total
        end
        if alt.bags then
            slot_count = slot_count + alt.bags.slots.count
            slot_total = slot_total + alt.bags.slots.total
        end

        local money = 0
        if alt.money then
            money = alt.money
        end

        local color = GBankClassic_UI_Inventory:GetPercentColor(slot_count / slot_total)
        local status = string.format("As of %s    %s    |c%s%d/%d|r", datetime, GetCoinTextureString(money),    color, slot_count, slot_total)
        self.Window:SetStatusText(status)
    end)

    self.Window:SetCallback("OnLeaveStatusBar", function(_)
        self.Window:SetStatusText(defaultStatus)
    end)

    self.TabGroup:SetCallback("OnGroupSelected", function (group)
        local tab = group.localstatus.selected

        self.TabGroup:ReleaseChildren()

        local g = GBankClassic_UI:Create("SimpleGroup")
        g:SetFullWidth(true)
        g:SetFullHeight(true)
        g:SetLayout("Flow")
        self.TabGroup:AddChild(g)

        if not GBankClassic_Guild:IsBank(tab) then
            if GBankClassic_Chat.debug then
                GBankClassic_Core:DebugPrint(tab .. " is no longer a guild bank. Cleaning up.")
            end
            
            local guild = GBankClassic_Guild:GetGuild()
            if guild then
                GBankClassic_Database:ResetPlayer(guild, tab)
                if info.alts then info.alts[tab] = nil end
                if info.roster and info.roster.alts then
                    for idx, v in ipairs(info.roster.alts) do
                        if v == tab then
                            table.remove(info.roster.alts, idx)
                            break
                        end
                    end
                end
            end
            
            self.TabGroup:ReleaseChildren()
            self:DrawContent()
            return
        end

        local alt = info.alts and info.alts[tab] or nil
        if not alt then
            -- Placeholder view for missing alt data
            local isLocal = (GBankClassic_Guild and GBankClassic_Guild:GetPlayer() == tab)
            local label = GBankClassic_UI:Create("Label")
            if isLocal then
                local msg = "|cffaad372This is you!|r\n\nNo data has been scanned yet.\n\n|cffFFd100To populate your bank data:|r\n1. |cff33ff99Logout|r and login or /reload.\n2. |cff33ff99Enable reporting and scanning|r of your data via the addon options.\n3. Visit the |cff33ff99Bank|r to scan your bank and bag slots.\n4. Close your bank.\n5. If other guild members are online, |cff33ff99wait|r a few minutes for the share to complete.\n"                 
                label:SetText(msg)
            else
                label:SetText("No data available for this bank; sync pending.")
            end
            
            label:SetFullWidth(true)
            g:AddChild(label)

            if not isLocal then
                local button = GBankClassic_UI:Create("Button")
                button:SetText("Request sync")
                button:SetWidth(200)
                button:SetCallback("OnClick", function(_)
                    -- Trigger a guild-wide request for this owner's data
                    if GBankClassic_Guild and GBankClassic_Guild.RequestAltSync then
                        GBankClassic_Guild:RequestAltSync(tab, tab, nil)
                    end
                    local shutup = GBankClassic_Options:GetBankVerbosity()
                    if shutup == false then
                        if GBankClassic_Options and not GBankClassic_Options:GetPreferDirect() then
                            GBankClassic_Core:Print('Requested sync for '..tab..' (asking owner and peers)...')
                        else
                            GBankClassic_Core:Print('Requested sync for '..tab..'. If that player is offline, consider enabling peer relay.')
                        end
                    end
                end)
                g:AddChild(button)
            end
        else
            local scroll = GBankClassic_UI:Create("ScrollFrame")
            scroll:SetLayout("Flow")
            scroll:SetFullHeight(true)
            scroll:SetFullWidth(true)
            g:AddChild(scroll)

            local bank = nil
            if alt.bank then
                bank = alt.bank.items
            end
            if alt.bags then
                local items = GBankClassic_Item:Aggregate(bank, alt.bags.items)
                GBankClassic_Item:GetItems(items, function (list)
                    GBankClassic_Item:Sort(list)
                    for _, item in pairs(list) do
                        GBankClassic_UI:DrawItem(item, scroll)
                    end
                end)
            end
        end
    end)
end

function GBankClassic_UI_Inventory:GetPercentColor(percent)
    local color = nil
    if percent <= 0.25 then
        color = "ffffffff"
    elseif percent <= 0.5 then
        color = "ff00ff00"
    elseif percent <= 0.75 then
        color = "ffffff00"
    elseif percent <= 0.9 then
        color = "ffff9900"
    elseif percent > 0.9 then
        color = "ffff0000"
    end
    return color
end