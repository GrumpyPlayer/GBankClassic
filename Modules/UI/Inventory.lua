GBankClassic_UI_Inventory = {}

function GBankClassic_UI_Inventory:Init()
    self:DrawWindow()
end

local function QueryEmpty()
	local now = GetServerTime()
	local last = GBankClassic_UI_Inventory.last_empty_sync or 0
	if now - last > 30 then
		GBankClassic_UI_Inventory.last_empty_sync = now
		GBankClassic_Guild:Share()
	end
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
	if self.isOpen then
		return
	end

    self.isOpen = true
    
    if not self.Window then
        self:DrawWindow()
    end
    self.Window:Show()

    self:DrawContent()

	-- Perform full sync (same as /bank sync command)
    GBankClassic_Chat:PerformSync()

    if _G["GBankClassic"] then
        _G["GBankClassic"]:Show()
    else
        GBankClassic_UI:Controller()
    end
end

function GBankClassic_UI_Inventory:Close()
	if not self.isOpen then
		return
	end
    
	if not self.Window then
		return
	end

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
    window.frame:SetScript("OnKeyDown", function(self, event)
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

function GBankClassic_UI_Inventory:DrawContent()
    local info = GBankClassic_Guild.Info
	local roster_alts = GBankClassic_Guild:GetRosterAlts()
	if not info or not roster_alts then
		QueryEmpty()
		OnClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")
		return
	end

    GBankClassic_UI_Search:BuildSearchData()

    local players = {}
    local n = 0
	for _, v in pairs(roster_alts) do
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

    for _, player in pairs(players) do
		local norm = GBankClassic_Guild:NormalizeName(player)
		local alt = info.alts[norm]
        if not first_tab then
            first_tab = player
        end
        tabs[i] = { value = player, text = player }
        if alt and _G.type(alt) == "table" then
            if alt.money then
                total_gold = total_gold + alt.money
            end
			if alt.bank and alt.bank.slots then
                slots = slots + alt.bank.slots.count
                total_slots = total_slots + alt.bank.slots.total
            end
			if alt.bags and alt.bags.slots then
                slots = slots + alt.bags.slots.count
                total_slots = total_slots + alt.bags.slots.total
            end
        end
        i = i + 1
    end

	if #tabs == 0 then
		QueryEmpty()
		OnClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")

		return
	end

    self.TabGroup:SetTabs(tabs)

	local percent = total_slots > 0 and (slots / total_slots) or 0
	local color = GBankClassic_UI_Inventory:GetPercentColor(percent)
	local defaultStatus = string.format("%s    |c%s%d/%d|r", GetCoinTextureString(total_gold), color, slots, total_slots)
    self.Window:SetStatusText(defaultStatus)

    self.Window:SetCallback("OnEnterStatusBar", function(_)
        local tab = self.TabGroup.localstatus.selected
		local normTab = GBankClassic_Guild:NormalizeName(tab)
		local alt = info.alts[normTab] or nil
        if not alt or not alt.version then
            return
        end

        local datetime = date("%Y-%m-%d %H:%M:%S", alt.version)
        local slot_count = 0
        local slot_total = 0
        if alt.bank and alt.bank.slots then
            slot_count = slot_count + alt.bank.slots.count
            slot_total = slot_total + alt.bank.slots.total
        end
        if alt.bags and alt.bags.slots then
            slot_count = slot_count + alt.bags.slots.count
            slot_total = slot_total + alt.bags.slots.total
        end

        local money = 0
        if alt.money then
            money = alt.money
        end

        local color = GBankClassic_UI_Inventory:GetPercentColor(slot_count / slot_total)
        local status = string.format("As of %s    %s    |c%s%d/%d|r", datetime, GetCoinTextureString(money), color, slot_count, slot_total)
        self.Window:SetStatusText(status)
    end)

    self.Window:SetCallback("OnLeaveStatusBar", function(_)
        self.Window:SetStatusText(defaultStatus)
    end)

    self.TabGroup:SetCallback("OnGroupSelected", function(group)
        local tab = group.localstatus.selected

        self.TabGroup:ReleaseChildren()

        local g = GBankClassic_UI:Create("SimpleGroup")
        g:SetFullWidth(true)
        g:SetFullHeight(true)
        g:SetLayout("Flow")
        self.TabGroup:AddChild(g)

        local alt = info.alts and info.alts[tab] or nil
        if not alt then
            -- Placeholder view for missing guild bank alt data
            local isLocal = (GBankClassic_Guild and GBankClassic_Guild:GetPlayer() == tab)
            local label = GBankClassic_UI:Create("Label")
            if isLocal then
                local msg = "|cffaad372This is you!|r\n\nNo data has been scanned yet.\n\n|cffFFd100To populate your bank data:|r\n1. |cff33ff99Enable reporting and scanning|r of your data via the addon options.\n2. Visit the |cff33ff99Bank|r to scan your bank and bag slots.\n3. Close your bank.\n4. If other guild members are online, |cff33ff99wait|r for the share to complete.\n"                 
                label:SetText(msg)
            else
                label:SetText("No data available for this bank; sync pending.")
            end
            label:SetFullWidth(true)
            g:AddChild(label)
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
                GBankClassic_Item:GetItems(items, function(list)
                    GBankClassic_Item:Sort(list)
                    for _, item in pairs(list) do
                        GBankClassic_UI:DrawItem(item, scroll)
                    end
                end)
            end
        end
    end)

	-- Preserve currently selected tab instead
	-- Only select first_tab if no tab is currently selected
	local currentTab = self.TabGroup.localstatus and self.TabGroup.localstatus.selected
	if currentTab and info.alts[currentTab] then
		-- Preserve current selection if it's still valid
		self.TabGroup:SelectTab(currentTab)
	else
		-- No current selection or invalid tab, select first tab
		self.TabGroup:SelectTab(first_tab)
	end
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