GBankClassic_UI_Inventory = GBankClassic_UI_Inventory or {}

local UI_Inventory = GBankClassic_UI_Inventory

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("date")
local date = upvalues.date
local upvalues = Globals.GetUpvalues("GetServerTime", "GetCoinTextureString", "IsShiftKeyDown", "IsControlKeyDown")
local GetServerTime = upvalues.GetServerTime
local GetCoinTextureString = upvalues.GetCoinTextureString
local IsShiftKeyDown = upvalues.IsShiftKeyDown
local IsControlKeyDown = upvalues.IsControlKeyDown

function UI_Inventory:Init()
    self:DrawWindow()
end

local function queryEmpty()
	local now = GetServerTime()
	local last = UI_Inventory.lastEmptySync or 0
	if now - last > 30 then
		UI_Inventory.lastEmptySync = now
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

	-- Ensure window stays within screen bounds
	GBankClassic_UI:ClampFrameToScreen(self.Window)

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
	if not self.isOpen or not self.Window then
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
	local roster_alts = GBankClassic_Guild:GetRosterGuildBankAlts()
	if not info or not roster_alts then
		queryEmpty()
		onClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")

		return
	end

    -- Rebuild search on next open
	GBankClassic_UI_Search.searchDataBuilt = false

    local tabs = {}
    local first_tab = nil
    local total_gold = 0

    for i = 1, #roster_alts do
        local guildBankAltName = roster_alts[i]
		local norm = GBankClassic_Guild:NormalizeName(guildBankAltName) or guildBankAltName
		local alt = info.alts[norm]
        if alt and type(alt) == "table" then
            if not first_tab then
                first_tab = guildBankAltName
            end
            tabs[i] = { value = guildBankAltName, text = guildBankAltName }
            if alt.money then
                total_gold = total_gold + alt.money
            end
        end
    end

	if #tabs == 0 then
		queryEmpty()
		onClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")

		return
	end

    self.TabGroup:SetTabs(tabs)
    local defaultStatus = string.format("%s    ", GetCoinTextureString(total_gold))
    self.Window:SetStatusText(defaultStatus)

    self.Window:SetCallback("OnEnterStatusBar", function(_)
        local tab = self.TabGroup.localstatus.selected
		local normTab = GBankClassic_Guild:NormalizeName(tab) or tab
		local alt = info.alts[normTab] or nil
        if not alt or not alt.version then
            return
        end

        local datetime = date("%b %d, %Y %H:%M", alt.version)
		local mailCount = alt.mail and alt.mail.items and GBankClassic_Globals:Count(alt.mail.items) or 0
        local money = 0
        if alt.money then
            money = alt.money
        end
		local mailText = ""
        local mailIcon = "|TInterface\\Icons\\INV_Letter_15:12:12:0:0|t"
		if mailCount > 0 then
			mailText = string.format("    |cff87ceeb%s %d item%s|r", mailIcon, mailCount, mailCount > 1 and "s" or "")
		end
        local status = string.format("As of %s    %s    %s", datetime, GetCoinTextureString(money), mailText)
        self.Window:SetStatusText(status)
    end)

    self.Window:SetCallback("OnLeaveStatusBar", function(_)
        self.Window:SetStatusText(defaultStatus)
    end)

    self.TabGroup:SetCallback("OnGroupSelected", function(group)
        local tab = group.localstatus.selected
        self.currentTab = tab
        self.tabLoaded = false
        GBankClassic_Output:Debug("INVENTORY", "Loading tab %s", tab)

        self.TabGroup:ReleaseChildren()

        local g = GBankClassic_UI:Create("SimpleGroup")
        g:SetFullWidth(true)
        g:SetFullHeight(true)
        g:SetLayout("Flow")
        self.TabGroup:AddChild(g)

        local alt = info.alts and info.alts[tab] or nil
        if not alt then
            -- Placeholder view for missing guild bank alt data
            local isLocal = (GBankClassic_Guild and GBankClassic_Guild:GetNormalizedPlayer() == tab)
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

            -- Track scroll container to prevent race conditions
            scroll.callbackProcessed = false

            local normTab = GBankClassic_Guild:NormalizeName(tab) or tab
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

            -- Show loading indicator immediately
            local loadingLabel = GBankClassic_UI:Create("Label")
            loadingLabel:SetText("|cff808080Please wait...|r")
            loadingLabel:SetFullWidth(true)
            scroll:AddChild(loadingLabel)

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

                local selectedTab = tab
                GBankClassic_Item:GetItems(validItems, function(list)
                    -- Prevent callback from running twice on same scroll container
                    if scroll.callbackProcessed then
                        GBankClassic_Output:Debug("INVENTORY", "Ignoring duplicate callback for tab %s", tab)

                        return
                    end

                    -- Verify we're still on the same tab (user may have switched)
                    if self.currentTab ~= selectedTab then
                        GBankClassic_Output:Debug("INVENTORY", "Ignoring callback for old tab %s (now on %s)", selectedTab, self.currentTab)

                        return
                    end

                    scroll.callbackProcessed = true
                    self.tabLoaded = true

                    GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: GetItems callback received %d items", tab, list and #list or 0)
                    scroll:ReleaseChildren()
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
        -- Don't call SelectTab if it's already the current tab (prevents reload on sync)
        -- The tab is already displayed, no need to trigger OnGroupSelected again
        if self.currentTab ~= currentTab then
            self.TabGroup:SelectTab(currentTab)
        end
	else
		-- No current selection or invalid tab, select first tab
		self.TabGroup:SelectTab(first_tab)
	end
end

function UI_Inventory:RefreshCurrentTab()
    local group = self.TabGroup
    if not group then
        return
    end

    local current = group.localstatus.selected
    if not current then
        return
    end

    group:ReleaseChildren()
    group:Fire("OnGroupSelected", current)
end