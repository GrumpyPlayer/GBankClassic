GBankClassic_UI_Search = GBankClassic_UI_Search or {}

local UI_Search = GBankClassic_UI_Search

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("GetCursorInfo", "ClearCursor", "IsShiftKeyDown", "IsControlKeyDown", "CreateFrame", "GameTooltip")
local GetCursorInfo = upvalues.GetCursorInfo
local ClearCursor = upvalues.ClearCursor
local IsShiftKeyDown = upvalues.IsShiftKeyDown
local IsControlKeyDown = upvalues.IsControlKeyDown
local CreateFrame = upvalues.CreateFrame
local GameTooltip = upvalues.GameTooltip
local upvalues = Globals.GetUpvalues("Item")
local Item = upvalues.Item

function UI_Search:Init()
    self:DrawWindow()
end

local function onClose(_)
    UI_Search.isOpen = false
    UI_Search.Window:Hide()
end

function UI_Search:Toggle()
    if self.isOpen then
        self:Close()
    else
        self:Open()
    end
end

function UI_Search:Open()
	if self.isOpen then
		return
	end

    self.isOpen = true

    if not self.Window then
        self:DrawWindow()
    end

	-- Rebuild search data when guild roster version changes
	-- Track roster version to detect when new data arrives (after /wipe, sync, etc.)
	local currentVersion = GBankClassic_Guild.Info and GBankClassic_Guild.Info.roster and GBankClassic_Guild.Info.roster.version or 0
	local needsRebuild = not self.searchDataBuilt or (self.lastRosterVersion ~= currentVersion)
	if needsRebuild then
		GBankClassic_Output:Debug("SEARCH", "Rebuilding search data (version changed: %s -> %s)", tostring(self.lastRosterVersion or "nil"), tostring(currentVersion))
		self:BuildSearchData()
		self.searchDataBuilt = true
		self.lastRosterVersion = currentVersion
	end

    self.Window:Show()
    if GBankClassic_UI_Inventory.isOpen and GBankClassic_UI_Inventory.Window then
        self.Window:ClearAllPoints()
        self.Window:SetPoint("TOPRIGHT", GBankClassic_UI_Inventory.Window.frame, "TOPLEFT", 0, 0)
    end

	-- Ensure window stays within screen bounds
	GBankClassic_UI:ClampFrameToScreen(self.Window)

    self:DrawContent()

    self.searchField:SetFocus()

    if _G["GBankClassic"] then
        _G["GBankClassic"]:Show()
    else
        GBankClassic_UI:Controller()
    end
end

function UI_Search:Close()
	if not self.isOpen then
		return
	end
	if not self.Window then
		return
	end

    onClose(self.Window)

    if GBankClassic_UI_Inventory.isOpen == false then
        _G["GBankClassic"]:Hide()
    end
end

function UI_Search:DrawWindow()
    local searchWindow = GBankClassic_UI:Create("Frame")
    searchWindow:Hide()
    searchWindow:SetCallback("OnClose", onClose)
    searchWindow:SetTitle("Search")
    searchWindow:SetLayout("Flow")
    searchWindow:EnableResize(false)
    searchWindow.frame:SetSize(250, 500)
    self.Window = searchWindow

    local searchLabel = searchWindow.frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    searchLabel:SetTextColor(1,.82,0)
    searchLabel:SetPoint("TOPLEFT", searchWindow.frame, "TOPLEFT", 17, -19)
    searchLabel:SetHeight(44)
    searchLabel:SetText("Item name")
    self.searchLabel = searchLabel

    local instructions = "Type at least 3 letters to search"
    local searchInput = CreateFrame("EditBox", "GBankClassicSearch", searchWindow.frame, "SearchBoxTemplate")
    searchInput:SetPoint("TOPLEFT", searchWindow.frame, "TOPLEFT", 24, -51)
    searchInput:SetSize(210, 20)
    searchInput.Instructions:SetText(instructions)
    searchInput:SetScript("OnEditFocusLost", function(input)
        if input:GetText() == "" then
            self.searchField.Instructions:SetText(instructions)
        end
    end)
	searchInput:SetScript("OnEnter", function()
		GameTooltip:SetOwner(searchInput, "ANCHOR_BOTTOM")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Search all guild banks")
		GameTooltip:AddLine("Find items across all bank characters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Type at least 3 letters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Or drag an item here.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	searchInput:SetScript("OnLeave", function()
		GBankClassic_UI:HideTooltip()
	end)
    searchInput:SetScript("OnTextChanged", function(input)
        local text = input:GetText()
        if text and text ~= "" then
            self.searchField.Instructions:SetText("")
        else
            self.searchField.Instructions:SetText(instructions)
        end
        self.SearchText = text
        self:DrawContent()
    end)
    searchInput:SetScript("OnEnterPressed", function(input)
        self.SearchText = input:GetText()
        self:DrawContent()
        self.searchField:ClearFocus()
    end)
    searchInput:SetScript("OnReceiveDrag", function(input)
        local type, _, info = GetCursorInfo()
        local itemName = info:match("%[(.+)%]")
        if type == "item" and itemName then
            self.SearchText = itemName
            self:DrawContent()
            ClearCursor()
            self.searchField:ClearFocus()
        end
    end)
    self.searchField = searchInput

    local scrollGroup = GBankClassic_UI:Create("SimpleGroup")
    scrollGroup:SetLayout("Fill")
    scrollGroup:SetFullWidth(true)
    scrollGroup:SetFullHeight(true)
    searchWindow:AddChild(scrollGroup)

    local resultGroup = GBankClassic_UI:Create("ScrollFrame")
    resultGroup:SetLayout("Table")
    resultGroup:SetUserData("table", {
        columns = {
            {
                width = 30,
                align = "middle",
            },
            {
                align = "start",
            },
        },
        spaceH = 5,
    })
    resultGroup.scrollframe:ClearAllPoints()
    resultGroup.scrollframe:SetPoint("TOPLEFT", 4, -51)
    resultGroup.scrollbar:ClearAllPoints()
    resultGroup.scrollbar:SetPoint("TOPLEFT", resultGroup.scrollframe, "TOPRIGHT", 2, -12)
    resultGroup.scrollbar:SetPoint("BOTTOMLEFT", resultGroup.scrollframe, "BOTTOMRIGHT", 2, 22)
    scrollGroup:AddChild(resultGroup)
    self.Results = resultGroup
end

function UI_Search:BuildSearchData()
    -- TODO: ideally this is only done for the guild bank alts with changed data instead of always rebuild the entire corpus for the smallest change
	GBankClassic_Output:Debug("SEARCH", "BuildSearchData called - clearing and rebuilding search data")
    self.SearchData = {
        Corpus = {},
        Lookup = {},
    }

    local info = GBankClassic_Guild.Info
	local roster_alts = GBankClassic_Guild:GetRosterGuildBankAlts()
	if not info or not roster_alts then
		GBankClassic_Output:Debug("SEARCH", "BuildSearchData: no info or roster_alts, returning early")

		return
	end

	local rosterCount = #roster_alts
	GBankClassic_Output:Debug("SEARCH", "BuildSearchData: processing %d roster alts", rosterCount)

    local items = {}
	for i = 1, #roster_alts do
        local guildBankAltName = roster_alts[i]
		local norm = GBankClassic_Guild:NormalizeName(guildBankAltName) or guildBankAltName
        local alt = info.alts[norm]
		GBankClassic_Output:Debug("SEARCH", "Search corpus loop: processing guildBankAltName=%s, norm=%s, has alt=%s", guildBankAltName, norm, tostring(alt ~= nil))
        if alt and type(alt) == "table" then
			if alt.items and next(alt.items) ~= nil then
				local beforeCount = #items
				items = GBankClassic_Item:Aggregate(items, alt.items)
				local afterCount = #items
				GBankClassic_Output:Debug("SEARCH", "Search corpus: using alt.items for %s (%d items before, %d after aggregation)", guildBankAltName, beforeCount, afterCount)
			end
        end
    end

    local itemNames = {}
	local corpusNamesSeen = {}

	-- Count items in hash table
	local itemCount = GBankClassic_Globals:Count(items)
	GBankClassic_Output:Debug("SEARCH", "About to validate %d items before GetItems", itemCount)

	-- Validate and filter items before passing to GetItems
	local validItems = {}
	local invalidCount = 0
	for key, item in pairs(items) do
		if item and item.ID and item.ID > 0 then
			table.insert(validItems, item)
		else
			invalidCount = invalidCount + 1
			GBankClassic_Output:Debug("SEARCH", "WARNING: Skipping invalid item at key %s (ID: %s, link: %s)", tostring(key), tostring(item and item.ID or "nil item"), tostring(item and item.Link or "nil"))
		end
	end

	GBankClassic_Output:Debug("SEARCH", "Passing %d valid items to GetItems (%d invalid skipped)", #validItems, invalidCount)

	GBankClassic_Item:GetItems(validItems, function(list)
		local listCount = GBankClassic_Globals:Count(list)
		GBankClassic_Output:Debug("SEARCH", "GetItems callback fired with %d items", listCount)
        for _, v in pairs(list) do
            -- Skip malformed list entries
			if v and v.ID and v.Info and v.Info.name then
				local itemIdentity = tostring(v.ID)

				-- For weapons/armor, include link key to catch suffix differences
				if v.Link and GBankClassic_Item:NeedsLink(v.Link) then
					local linkKey = GBankClassic_Item:GetImprovedItemKey(v.Link)
					if linkKey and linkKey ~= "" then
						itemIdentity = linkKey
					end
				end

				-- Map item identity to name (for lookup table building later)
				if not itemNames[itemIdentity] then
					itemNames[itemIdentity] = v.Info.name
				end

				-- Only add each unique name to corpus once
				if not corpusNamesSeen[v.Info.name] then
					corpusNamesSeen[v.Info.name] = true
					table.insert(self.SearchData.Corpus, v.Info.name)
					GBankClassic_Output:Debug("SEARCH", "Corpus: added unique name '%s' (ID: %d)", v.Info.name, v.ID)
				else
					GBankClassic_Output:Debug("SEARCH", "Corpus: skipping duplicate name '%s' (ID: %d already in corpus)", v.Info.name, v.ID)
				end
			end
        end

        for i = 1, #roster_alts do
            local player = roster_alts[i]
            local altItems = {}
			local norm = GBankClassic_Guild:NormalizeName(player) or player
            local alt = info.alts[norm]
			GBankClassic_Output:Debug("SEARCH", "Search results loop: processing player=%s, norm=%s, has alt=%s", player, norm, tostring(alt ~= nil))
            if alt and type(alt) == "table" then
				if alt.items and next(alt.items) ~= nil then
					for _, item in pairs(alt.items) do
						table.insert(altItems, item)
					end
					GBankClassic_Output:Debug("SEARCH", "Search results: using alt.items for %s", player)
				end
            end

            for _, itemEntry in pairs(altItems) do
				local itemIdentity = tostring(itemEntry.ID)

				-- For weapons/armor, include link key to catch suffix differences
				if itemEntry.Link and GBankClassic_Item:NeedsLink(itemEntry.Link) then
					local linkKey = GBankClassic_Item:GetImprovedItemKey(itemEntry.Link)
					if linkKey and linkKey ~= "" then
						itemIdentity = linkKey
					end
				end

                local name = itemNames[itemIdentity]
                if name then
					GBankClassic_Output:Debug("SEARCH", "Search results: adding %s with count %d for player %s to lookup", name, itemEntry.Count or 0, player)
                    if not self.SearchData.Lookup[name] then
                        self.SearchData.Lookup[name] = {}
                    end
                    local found = false
                    for _, existingEntry in pairs(self.SearchData.Lookup[name]) do
						if existingEntry.alt == player and existingEntry.item.Link and itemEntry.Link and existingEntry.item.Link == itemEntry.Link then
                            found = true
							GBankClassic_Output:Debug("SEARCH", "Search results: duplicate found - skipping %s (ID: %d) for %s", name, itemEntry.ID, player)
                            break
						elseif existingEntry.alt == player and not existingEntry.item.Link and not itemEntry.Link and existingEntry.item.ID == itemEntry.ID then
                            found = true
							GBankClassic_Output:Debug("SEARCH", "Search results: duplicate found - skipping %s (ID: %d) for %s", name, itemEntry.ID, player)
                            break
                        end
                    end
                    if not found then
                        local itemInfo = GBankClassic_Item:GetInfo(itemEntry.ID, itemEntry.Link)
                        table.insert(self.SearchData.Lookup[name], { alt = player, item = { ID = itemEntry.ID, Count = itemEntry.Count, Link = itemEntry.Link, Info = itemInfo } })
                    end
                end
            end
        end
    end)
end

function UI_Search:DrawContent()
	if not self.Results then
		return
	end

    self.Results:ReleaseChildren()
    self.Window:SetStatusText("")
    self.Results:DoLayout()

	if not self.SearchText then
		return
	end

    if self.SearchText then
        self.searchField:SetText(self.SearchText)
        local searchLength = string.len(self.SearchText)
        self.searchField:SetCursorPosition(searchLength)
    end

    local search = self.SearchText
    if search and string.sub(search, 0, 2) == "|c" then
        self.searchField:SetText("")
        local item = Item:CreateFromItemLink(search)
		if item and item.itemID then
			item:ContinueOnItemLoad(function()
				local name = item:GetItemName()
				if name then
					self.SearchText = name
					self.searchField:SetText(name)
					self:DrawContent()
					self.searchField:ClearFocus()
				end
			end)
		end

		return
    end

    local searchText = search:lower()
	if string.len(searchText) < 3 then
		return
	end

    local searchData = self.SearchData
	if not searchData then
		return
	end

	GBankClassic_Output:Debug("SEARCH", "Search for '%s': Corpus has %d entries", searchText, #searchData.Corpus)

    local count = 0
	local matchedNames = 0
    for _, v in pairs(searchData.Corpus) do
        if not v then
            -- Skip malformed corpus entries
        else
            local result = string.find(v:lower(), searchText)
            if result ~= nil then
				matchedNames = matchedNames + 1
				GBankClassic_Output:Debug("SEARCH", "Match #%d: '%s' contains '%s'", matchedNames, v, searchText)
                local lookupList = searchData.Lookup[v]
                if not lookupList then
                    -- No lookup for this name; skip
					GBankClassic_Output:Debug("SEARCH", "Search display: '%s' matched search but has NO lookup entries", v)
                else
					local lookupCount = GBankClassic_Globals:Count(lookupList)
					GBankClassic_Output:Debug("SEARCH", "Search display: '%s' matched search, has %d lookup entries", v, lookupCount)
                    for _, vv in pairs(lookupList) do
						local resultItem = vv.item
						local bankAlt = vv.alt
						GBankClassic_Output:Debug("SEARCH", "Search display: showing %s with %d items for %s", resultItem.Info and resultItem.Info.name or "Unknown", resultItem.Count or 0, bankAlt)
						local itemWidget = GBankClassic_UI:DrawItem(resultItem, self.Results, 30, 35, 30, 30, 0, 5)
						if itemWidget then
							itemWidget:SetCallback("OnClick", function(widget, event)
								if IsShiftKeyDown() or IsControlKeyDown() then
									GBankClassic_UI:EventHandler(widget, event)

									return
								end
							end)
						end

                        local label = GBankClassic_UI:Create("Label")
                        label:SetText(bankAlt)
                        label.label:SetSize(170, 30)
                        label.label:SetJustifyV("MIDDLE")
                        self.Results:AddChild(label)

                        count = count + 1
                    end
                end
            end
        end
    end

	GBankClassic_Output:Debug("SEARCH", "Search complete: matched %d names, displayed %d result widgets", matchedNames, count)

    local plural = (count ~= 1 and "s" or "")
    self.Window:SetStatusText(count .. " result" .. plural)

    self.Results:DoLayout()
end