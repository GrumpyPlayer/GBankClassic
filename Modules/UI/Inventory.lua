GBankClassic_UI_Inventory = GBankClassic_UI_Inventory or {}

local UI_Inventory = GBankClassic_UI_Inventory

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("date")
local date = upvalues.date
local upvalues = Globals.GetUpvalues("GetServerTime", "GetCoinTextureString", "SecondsToTime", "IsShiftKeyDown", "IsControlKeyDown")
local GetServerTime = upvalues.GetServerTime
local GetCoinTextureString = upvalues.GetCoinTextureString
local SecondsToTime = upvalues.SecondsToTime
local IsShiftKeyDown = upvalues.IsShiftKeyDown
local IsControlKeyDown = upvalues.IsControlKeyDown

function UI_Inventory:Init()
    self:DrawWindow()
end

local function queryEmpty()
	local now = GetServerTime()
	local last = UI_Inventory.last_empty_sync or 0
	if now - last > 30 then
		UI_Inventory.last_empty_sync = now
		GBankClassic_Guild:Share()
	end
end

local function onClose(_)
    UI_Inventory.isOpen = false
    UI_Inventory.Window:Hide()
    GBankClassic_UI_Donations:Close()
    -- GBankClassic_UI_Requests:Close()
    GBankClassic_UI_Search:Close()
end

function UI_Inventory:Toggle()
    if self.isOpen then
        self:Close()
    else
        self:Open()
    end
end

function UI_Inventory:Open()
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

function UI_Inventory:Close()
	if not self.isOpen then
		return
	end
	if not self.Window then
		return
	end

    onClose(self.Window)
end

function UI_Inventory:DrawWindow()
    local window = GBankClassic_UI:Create("Frame")
    window:Hide()
    window:SetCallback("OnClose", onClose)
    window:SetTitle("GBankClassic")
    window:SetLayout("Flow")
    window:SetWidth(550)

	-- Persist window position/size across reloads
	if GBankClassic_Options and GBankClassic_Options.db then
		window:SetStatusTable(GBankClassic_Options.db.char.framePositions)
	end
    
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

	-- local requestsButton = GBankClassic_UI:Create("Button")
	-- requestsButton:SetText("Requests")
	-- requestsButton:SetCallback("OnClick", function(_)
	-- 	GBankClassic_UI_Requests:Toggle()
	-- end)
	-- requestsButton:SetWidth(175)
	-- requestsButton:SetHeight(24)
	-- buttonContainer:AddChild(requestsButton)

    local tabGroup = GBankClassic_UI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    window:AddChild(tabGroup)
    self.TabGroup = tabGroup
end

function UI_Inventory:DrawContent()
    local info = GBankClassic_Guild.Info
	local roster_alts = GBankClassic_Guild:GetRosterAlts()
	if not info or not roster_alts then
		queryEmpty()
		onClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")

		return
	end

    -- Rebuild search on next open
	GBankClassic_UI_Search.searchDataBuilt = false

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
        if alt and type(alt) == "table" then
            if not first_tab then
                first_tab = player
            end
            tabs[i] = { value = player, text = player }
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
            i = i + 1
        end
    end

	if #tabs == 0 then
		queryEmpty()
		onClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")

		return
	end

    self.TabGroup:SetTabs(tabs)

	local percent = total_slots > 0 and (slots / total_slots) or 0
	local color = self:GetPercentColor(percent)
    local defaultStatus
    if slots > 0 and total_slots > 0 then
	    defaultStatus = string.format("%s    |c%s%d/%d|r", GetCoinTextureString(total_gold), color, slots, total_slots)
    else
	    defaultStatus = string.format("%s    |c%s|r", GetCoinTextureString(total_gold), color)
    end
    self.Window:SetStatusText(defaultStatus)

    self.Window:SetCallback("OnEnterStatusBar", function(_)
        local tab = self.TabGroup.localstatus.selected
		local normTab = GBankClassic_Guild:NormalizeName(tab)
		local alt = info.alts[normTab] or nil
        if not alt or not alt.version then
            return
        end

        local datetime = date("%b %d, %Y %H:%M", alt.version)
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

		-- Add mail item count if available
		local mailCount = alt.mail and alt.mail.items and GBankClassic_Globals:Count(alt.mail.items) or 0

        local money = 0
        if alt.money then
            money = alt.money
        end

		local percent = slot_total > 0 and (slot_count / slot_total) or 0
		local color = self:GetPercentColor(percent)
		local mailText = ""
        local mailIcon = "|TInterface\\Icons\\INV_Letter_15:12:12:0:0|t"
		if mailCount > 0 then
			mailText = string.format("    |cff87ceeb%s %d item%s|r", mailIcon, mailCount, mailCount > 1 and "s" or "")
		end
        local status
        if slot_count > 0 and slot_total > 0 then
            status = string.format("As of %s    %s    |c%s%d/%d|r%s", datetime, GetCoinTextureString(money), color, slot_count, slot_total, mailText)
        else
            status = string.format("As of %s    %s    |c%s|r%s", datetime, GetCoinTextureString(money), color, mailText)
        end
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
            
            local normTab = GBankClassic_Guild:NormalizeName(tab)
            local alt = info.alts[normTab]
            
            -- Use alt.items if available
            -- Otherwise compute from sources for backward compatibility
            local items = {}
            
            if alt.items and next(alt.items) ~= nil then
                -- Use alt.items directly (may be array or key-value)
                for _, item in pairs(alt.items) do
                    table.insert(items, item)
                end
                GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: using alt.items (%d items)", tab, #items)
            else
                -- Fallback: compute from sources (backward compatibility for very old data)
                local bankItems = (alt.bank and alt.bank.items) or {}
                local bagItems = (alt.bags and alt.bags.items) or {}
                local mailItems = (alt.mail and alt.mail.items) or {}
                
                GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: computing from sources bank=%d, bags=%d, mail=%d", tab, #bankItems, #bagItems, #mailItems)
                
                -- Aggregate all sources (all are now in array format), then convert the key-value result to array
                local aggregated = GBankClassic_Item:Aggregate(bankItems, bagItems)
                aggregated = GBankClassic_Item:Aggregate(aggregated, mailItems)
                for _, item in pairs(aggregated) do
                    table.insert(items, item)
                end
            end
            
            GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: aggregated to %d unique items", tab, #items)
            
            if items and #items > 0 then
                -- Check for duplicate item IDs with different links
                local itemsByID = {}
                for _, item in pairs(items) do
                    if item and item.ID then
                        if not itemsByID[item.ID] then
                            itemsByID[item.ID] = {}
                        end
                        table.insert(itemsByID[item.ID], { Count = item.Count, Link = item.Link })
                    end
                end
                for itemID, entries in pairs(itemsByID) do
                    if #entries > 1 then
                        GBankClassic_Output:Debug("INVENTORY", "Duplicate item ID %d found with %d different entries:", itemID, #entries)
                        for i, entry in ipairs(entries) do
                            GBankClassic_Output:Debug("INVENTORY", "  Entry %d: count=%d, link=%s", i, entry.Count, entry.Link or "nil")
                        end
                    end
                end
                
                -- Validate and filter items before passing to GetItems
                local validItems = {}
                for i, item in ipairs(items) do
                    if item and item.ID and item.ID > 0 then
                        table.insert(validItems, item)
                    else
                        GBankClassic_Output:Debug("INVENTORY", "WARNING: Tab %s skipping invalid item at index %d (ID: %s, link: %s)", tab, i, tostring(item and item.ID or "nil item"), tostring(item and item.Link or "nil"))
                    end
                end
                
                GBankClassic_Item:GetItems(validItems, function(list)
                    GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: GetItems callback received %d items", tab, list and #list or 0)
                    GBankClassic_Item:Sort(list)

                    for _, item in pairs(list) do
                        if item and item.Info and item.Info.name then
                            GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: displaying %s with count %d (ID: %d)", tab, item.Info.name, item.Count or 0, item.ID)
                        end
                        local itemWidget = GBankClassic_UI:DrawItem(item, scroll)
                        if itemWidget then
                            itemWidget:SetCallback("OnClick", function(widget, event)
                                if IsShiftKeyDown() or IsControlKeyDown() then
                                    GBankClassic_UI:EventHandler(widget, event)

                                    return
                                end
                                -- GBankClassic_UI_Search:ShowRequestDialog(item, tab)
                            end)
                        end
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

function UI_Inventory:GetPercentColor(percent)
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