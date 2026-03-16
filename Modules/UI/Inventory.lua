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
    self.filterType = "any"
    self.filterSlot = "any"
    self.filterRarity = "any"
    self.filterMinLevel = nil
    self.filterMaxLevel = nil
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
	if GBankClassic_Options.db then
		window:SetStatusTable(GBankClassic_Options.db.char.framePositions)
	end

    window.frame:SetResizeBounds(500, 500)
    window.frame:EnableKeyboard(true)
    window.frame:SetPropagateKeyboardInput(true)
    window.frame:SetScript("OnKeyDown", function(self, event)
        GBankClassic_UI:EventHandler(self, event)
    end)
    self.Window = window

    -- Button container (3 columns)
    local buttonContainer = GBankClassic_UI:Create("SimpleGroup")
    buttonContainer:SetLayout("Table")
    buttonContainer:SetUserData("table", {
        columns = {
            { width = 0.25, align = "bottomleft" },
            { width = 0.25, align = "start" },
            { width = 0.25, align = "bottomleft" },
            { width = 0.25, align = "end" },
        },
    })
    buttonContainer:SetFullWidth(true)
    window:AddChild(buttonContainer)

    -- Search button (opens a separate search pane on the left)
    local searchButton = GBankClassic_UI:Create("Button")
    searchButton:SetText("Search")
    searchButton:SetCallback("OnClick", function(_)
        GBankClassic_UI_Search:Toggle()
    end)
    searchButton:SetWidth(160)
    searchButton:SetHeight(24)
    buttonContainer:AddChild(searchButton)

    -- Sort dropdown
    local sortList = {
        ["default"] = "Default (rarity/type)",
        ["alpha"]   = "Alphabetical",
        ["type"]    = "By type (class/slot)"
    }
    local sortOrder = { "default", "alpha", "type" }
    local sortDropdown = GBankClassic_UI:Create("Dropdown")
    sortDropdown:SetLabel("Sort")
    sortDropdown:SetList(sortList, sortOrder)
    sortDropdown:SetWidth(160)
    sortDropdown:SetFullWidth(false)
    local initMode = (GBankClassic_Options.db and GBankClassic_Options.db.char.sortMode) or "default"
    sortDropdown:SetValue(initMode)
    sortDropdown:SetCallback("OnValueChanged", function(widget, _, value)
        local db = GBankClassic_Options.db and GBankClassic_Options.db.char
        if not db then
            return
        end
        db.sortMode = value
        self:RefreshCurrentTab()
    end)
    self.SortDropdown = sortDropdown
    buttonContainer:AddChild(sortDropdown)

    -- Requests button
	local requestsButton = GBankClassic_UI:Create("Button")
	requestsButton:SetText("Requests")
    requestsButton:SetDisabled(true)
	-- requestsButton:SetCallback("OnClick", function(_)
	-- 	GBankClassic_UI_Requests:Toggle()
	-- end)
	requestsButton:SetWidth(160)
	requestsButton:SetHeight(24)
	buttonContainer:AddChild(requestsButton)

    -- Donations button (opens a donations pane on the right)
    local donationsButton = GBankClassic_UI:Create("Button")
    donationsButton:SetText("Donations")
    donationsButton:SetCallback("OnClick", function(_)
        GBankClassic_UI_Donations:Toggle()
    end)
    donationsButton:SetWidth(160)
    donationsButton:SetHeight(24)
    buttonContainer:AddChild(donationsButton)

    -- Filter row (below buttons)
    local filterContainer = GBankClassic_UI:Create("SimpleGroup")
    filterContainer:SetLayout("Table")
    filterContainer:SetUserData("table", {
        columns = {
            { width = 0.25, align = "start" },
            { width = 0.25, align = "start" },
            { width = 0.25, align = "start" },
            { width = 0.25, align = "end" },
        },
    })
    filterContainer:SetFullWidth(true)
    window:AddChild(filterContainer)

    -- Filter: item type
    local filterTypeList = {
        ["any"]       = "All types",
        ["armor"]     = "Armor",
        ["weapon"]    = "Weapons",
        ["consumable"]= "Consumables",
        ["trade"]     = "Trade goods",
        ["container"] = "Container",
        ["recipe"]    = "Recipe",
        ["quest"]     = "Quest items",
        ["misc"]      = "Everything else"
    }
    local filterTypeOrder = { "any", "armor", "weapon", "consumable", "trade", "container", "recipe", "quest", "misc" }
    local filterTypeDropdown = GBankClassic_UI:Create("Dropdown")
    filterTypeDropdown:SetLabel("Type")
    filterTypeDropdown:SetList(filterTypeList, filterTypeOrder)
    filterTypeDropdown:SetWidth(160)
    filterTypeDropdown:SetValue("any")
    filterTypeDropdown:SetCallback("OnValueChanged", function(_, _, value)
        self.filterType = value
        self:RefreshCurrentTab()
    end)
    self.FilterTypeDropdown = filterTypeDropdown
    filterContainer:AddChild(filterTypeDropdown)

    -- Filter: equip slot
    local filterSlotList = {
        ["any"]       = "All slots",
        ["head"]      = "Head",
        ["neck"]      = "Neck",
        ["shoulder"]  = "Shoulder",
        ["back"]      = "Back",
        ["chest"]     = "Chest",
        ["shirt"]     = "Shirt",
        ["tabard"]    = "Tabard",
        ["wrist"]     = "Wrist",
        ["hands"]     = "Hands",
        ["waist"]     = "Waist",
        ["legs"]      = "Legs",
        ["feet"]      = "Feet",
        ["finger"]    = "Finger",
        ["trinket"]   = "Trinket",
        ["onehand"]   = "One-hand",
        ["shield"]    = "Shield",
        ["twohand"]   = "Two-hand",
        ["ranged"]    = "Ranged",
        ["mainhand"]  = "Main hand",
        ["offhand"]   = "Off hand",
        ["holdable"]  = "Held in off-hand",
        ["bag"]       = "Bag",
        ["robe"]      = "Robe"
    }
    local filterSlotOrder = { "any", "head", "neck", "shoulder", "shirt", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket", "back", "onehand", "mainhand", "offhand", "twohand", "ranged", "shield", "holdable", "tabard", "bag" }
    local filterSlotDropdown = GBankClassic_UI:Create("Dropdown")
    filterSlotDropdown:SetLabel("Slot")
    filterSlotDropdown:SetList(filterSlotList, filterSlotOrder)
    filterSlotDropdown:SetWidth(160)
    filterSlotDropdown:SetValue("any")
    filterSlotDropdown:SetCallback("OnValueChanged", function(_, _, value)
        self.filterSlot = value
        self:RefreshCurrentTab()
    end)
    self.FilterSlotDropdown = filterSlotDropdown
    filterContainer:AddChild(filterSlotDropdown)

    -- Filter: rarity
    local filterRarityList = {
        ["any"]       = "All qualities",
        ["poor"]      = "Poor (grey)",
        ["common"]    = "Common (white)",
        ["uncommon"]  = "Uncommon (green)",
        ["rare"]      = "Rare (blue)",
        ["epic"]      = "Epic (purple)",
        ["legendary"] = "Legendary (orange)"
    }
    local filterRarityOrder = { "any", "poor", "common", "uncommon", "rare", "epic", "legendary" }
    local filterRarityDropdown = GBankClassic_UI:Create("Dropdown")
    filterRarityDropdown:SetLabel("Quality")
    filterRarityDropdown:SetList(filterRarityList, filterRarityOrder)
    filterRarityDropdown:SetWidth(160)
    filterRarityDropdown:SetValue("any")
    filterRarityDropdown:SetCallback("OnValueChanged", function(_, _, value)
        self.filterRarity = value
        self:RefreshCurrentTab()
    end)
    self.FilterRarityDropdown = filterRarityDropdown
    filterContainer:AddChild(filterRarityDropdown)

    -- Reset filters button
    local resetButton = GBankClassic_UI:Create("Button")
    resetButton:SetText("Reset filters")
    resetButton:SetWidth(160)
    resetButton:SetHeight(24)
    resetButton:SetCallback("OnClick", function(_)
        self:ResetFilters()
    end)
    resetButton:SetDisabled(true)
    self.ResetFiltersButton = resetButton
    filterContainer:AddChild(resetButton)

    local tabGroup = GBankClassic_UI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    window:AddChild(tabGroup)
    self.TabGroup = tabGroup

    -- Initialize filter state
    self:ResetFilters()
end

function UI_Inventory:UpdateStatusText(filteredCount, totalCount, goldAmount, version)
    filteredCount = filteredCount or 0
    totalCount = totalCount or 0

    local activeFilters = self:GetActiveFilterCount()
    local pluralFilters = (activeFilters ~= 1 and "s" or "")
    local filterText = activeFilters > 0 and string.format(" |cff87ceeb(%d filter%s active)|r", activeFilters, pluralFilters) or ""
    local pluralItems = (totalCount ~= 1 and "s" or "")

    if activeFilters > 0 then
        local statusText = string.format("Showing %d of %d item%s%s", filteredCount, totalCount, pluralItems, filterText)
        self.Window:SetStatusText(statusText)
        self.filteredCount = filteredCount
        self.totalCount = totalCount
    else
        local defaultStatus
        if goldAmount > 0 then
            local updatedAt = ""
            if version ~= "" then
                updatedAt = string.format(" as of %s", version)
            end
            defaultStatus = string.format("%s%s", GetCoinTextureString(goldAmount), updatedAt)
        else
            defaultStatus = "No available data"
        end
        self.Window:SetStatusText(defaultStatus)
    end
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

    for i = 1, #roster_alts do
        local guildBankAltName = roster_alts[i]
		local norm = GBankClassic_Guild:NormalizeName(guildBankAltName) or guildBankAltName
		local alt = info.alts[norm]
        if alt and type(alt) == "table" then
            if not first_tab then
                first_tab = guildBankAltName
            end
            tabs[i] = { value = guildBankAltName, text = guildBankAltName }
        end
    end

	if #tabs == 0 then
		queryEmpty()
		onClose()
		GBankClassic_Output:Response("Database is empty; wait for sync.")

		return
	end

    self.TabGroup:SetTabs(tabs)
    self:UpdateStatusText(self.filteredCount or "", self.totalCount or "", 0, "")

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

        local normTab = GBankClassic_Guild:NormalizeName(tab) or tab
        local alt = info.alts[normTab]
        local scroll = GBankClassic_UI:Create("ScrollFrame")
        scroll:SetLayout("Flow")
        scroll:SetFullHeight(true)
        scroll:SetFullWidth(true)
        g:AddChild(scroll)

        -- Track scroll container to prevent race conditions
        scroll.callbackProcessed = false

        local items = {}
        if alt.items and next(alt.items) ~= nil then
            for _, item in pairs(alt.items) do
                table.insert(items, item)
            end
            GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: using alt.items (%d items)", tab, #items)
        end

        GBankClassic_Output:Debug("INVENTORY", "Inventory tab %s: aggregated to %d unique items", tab, #items)

        -- Show loading indicator immediately
        local loadingLabel = GBankClassic_UI:Create("Label")
        local isLocal = (GBankClassic_Guild:GetNormalizedPlayer() == tab)
        if isLocal then
            local msg = "|cffaad372This is you!|r\n\nNo data has been scanned yet.\n\n|cffFFd100To populate your guild bank data:|r\n1. |cff33ff99Enable reporting and scanning|r of your data via the addon options.\n2. Visit the |cff33ff99Bank|r to scan your bank and bag.\n3. Close your bank.\n4. Open and close your mailbox.\n5. If other guild members are online, |cff33ff99wait|r for the share to complete.\n"
            loadingLabel:SetText(msg)
        else
            loadingLabel:SetText("|cff808080No available data for this guild bank alt.|r")
            self:UpdateStatusText("", "", 0, "")
        end
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
                GBankClassic_Item:Sort(list, GBankClassic_Options.db and GBankClassic_Options.db.char.sortMode)


                -- Apply filters
                local filteredList = {}
                local filteredCount = 0
                for _, item in ipairs(list) do
                    if self:PassesFilters(item) then
                        table.insert(filteredList, item)
                        filteredCount = filteredCount + 1
                    end
                end

                -- Update status text to show filter results
                self:UpdateStatusText(filteredCount, #list, alt.money or 0, alt.version and date("%b %d, %Y %H:%M", alt.version) or "")

                -- Release loading label and display filtered items
                if self:GetActiveFilterCount() > 0 then
                    UI_Inventory.ResetFiltersButton:SetDisabled(false)
                end
                scroll:ReleaseChildren()
                for _, item in pairs(filteredList) do
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

                -- Show "no results" message if all items filtered out
                if filteredCount == 0 and #list > 0 then
                    local noResultsLabel = GBankClassic_UI:Create("Label")
                    noResultsLabel:SetText("|cff808080No items match current filters.|r")
                    noResultsLabel:SetFullWidth(true)
                    scroll:AddChild(noResultsLabel)
                end
            end)
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

function UI_Inventory:ResetFilters()
    -- Disable the filter reset button
    UI_Inventory.ResetFiltersButton:SetDisabled(true)

    -- Reset filter state
    self.filterType = "any"
    self.filterSlot = "any"
    self.filterRarity = "any"
    self.filterMinLevel = nil
    self.filterMaxLevel = nil

    -- Reset dropdown values
    if self.FilterTypeDropdown then
        self.FilterTypeDropdown:SetValue("any")
    end
    if self.FilterSlotDropdown then
        self.FilterSlotDropdown:SetValue("any")
    end
    if self.FilterRarityDropdown then
        self.FilterRarityDropdown:SetValue("any")
    end

    -- Refresh current tab
    self:RefreshCurrentTab()
end

function UI_Inventory:PassesFilters(item)
    if not item or not item.Info then
        return true
    end

    local info = item.Info

    -- Type filter
    if self.filterType and self.filterType ~= "any" then
        local class = info.class or 0
        local subClass = info.subClass or 0

        --[[
        local t = Enum.ItemClass
        for k, v in pairs(t) do
            print(k.."=".. v)
        end

        Enum.ItemClass

        ++Armor=4
        ++Weapon=2
        ++Consumable=0
        ++Tradegoods=7
        ++Container=1
        ++Recipe=9
        ++Questitem=12

        Miscellaneous=15
        Reagent=5
        CurrencyTokenObsolete=10
        Key=13
        PermanentObsolete=14
        Gem=3
        ItemEnhancement=8
        Quiver=11
        Projectile=6

        Profession=19
        WoWToken=18
        Battlepet=17
        Glyph=16
        ]]--

        if self.filterType == "armor" and class ~= 4 then
            return false
        elseif self.filterType == "weapon" and class ~= 2 then
            return false
        elseif self.filterType == "consumable" and class ~= 0 then
            return false
        elseif self.filterType == "trade" and class ~= 7 then
            return false
        elseif self.filterType == "container" and class ~= 1 then
            return false
        elseif self.filterType == "recipe" and class ~= 9 then
            return false
        elseif self.filterType == "quest" and class ~= 12 then
            return false
        elseif self.filterType == "misc" and class ~= 15 and class ~= 5 and class ~= 10 and class ~= 13 and class ~= 14 and class ~= 3 and class ~= 8 and class ~= 11 and class ~= 6 then
            return false
        end
    end

    -- Slot filter
    if self.filterSlot and self.filterSlot ~= "any" then
        local equipId = info.equipId or 0

        --[[
        local t = Enum.InventoryType
        for k, v in pairs(t) do
            print(k.."=".. v)
        end

        Enum.InventoryType
        
        IndexNonEquipType=0

        IndexHeadType=1
        IndexNeckType=2
        IndexShoulderType=3
        IndexBodyType=4
        IndexChestType=5
        IndexWaistType=6
        IndexLegsType=7
        IndexFeetType=8
        IndexWristType=9
        IndexHandType=10
        IndexFingerType=11
        IndexTrinketType=12
        IndexWeaponType=13
        IndexShieldType=14

        IndexRangedType=15

        IndexCloakType=16
        Index2HweaponType=17
        IndexBagType=18
        IndexTabardType=19
        IndexRobeType=20
        IndexWeaponmainhandType=21
        IndexWeaponoffhandType=22
        IndexHoldableType=23

        IndexAmmoType=24
        IndexThrownType=25

        IndexRangedrightType=26

        IndexQuiverType=27
        IndexRelicType=28
        IndexProfessionToolType=29
        IndexProfessionGearType=30
        IndexEquipablespellOffensiveType=31
        IndexEquipablespellUtilityType=32
        IndexEquipablespellDefensiveType=33
        IndexEquipablespellWeaponType=34
        
        ]]--

        local slotMap = {
            head = 1, neck = 2, shoulder = 3, shirt = 4, chest = 5, waist = 6, legs = 7, feet = 8, wrist = 9, hands = 10, finger = 11, trinket = 12, onehand = 13, shield = 14, ranged = 26, back = 16, twohand = 17, bag = 18, tabard = 19, robe = 20, mainhand = 21, offhand = 22, holdable = 23
        }
        local targetSlot = slotMap[self.filterSlot]
        if targetSlot and targetSlot ~= equipId then
            if self.filterSlot == "bag" and equipId ~= 0 then
                return false
            elseif self.filterSlot ~= "bag" and equipId ~= targetSlot then
                return false
            end
        end
    end

    -- Rarity filter
    if self.filterRarity and self.filterRarity ~= "any" then
        local rarity = info.rarity or 1
        local rarityMap = {
            poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5
        }
        local targetRarity = rarityMap[self.filterRarity]
        if targetRarity and rarity ~= targetRarity then
            return false
        end
    end

    -- Level filter
    if self.filterMinLevel and info.level and info.level < self.filterMinLevel then
        return false
    end
    if self.filterMaxLevel and info.level and info.level > self.filterMaxLevel then
        return false
    end

    return true
end

function UI_Inventory:GetActiveFilterCount()
    local count = 0

    if self.filterType and self.filterType ~= "any" then
        count = count + 1
    end
    if self.filterSlot and self.filterSlot ~= "any" then
        count = count + 1
    end
    if self.filterRarity and self.filterRarity ~= "any" then
        count = count + 1
    end
    if self.filterMinLevel or self.filterMaxLevel then
        count = count + 1
    end

    return count
end