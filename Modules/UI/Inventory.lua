local addonName, GBCR = ...

GBCR.UI.Inventory = {}
local UI_Inventory = GBCR.UI.Inventory

local Globals = GBCR.Globals
local date = Globals.date
local debugprofilestop = Globals.debugprofilestop
local ipairs = Globals.ipairs
local math_abs = Globals.math_abs
local math_ceil = Globals.math_ceil
local math_floor = Globals.math_floor
local math_max = Globals.math_max
local math_min = Globals.math_min
local next = Globals.next
local pairs = Globals.pairs
local select = Globals.select
local string_find = Globals.string_find
local string_format = Globals.string_format
local string_gmatch = Globals.string_gmatch
local string_gsub = Globals.string_gsub
local string_len = Globals.string_len
local string_lower = Globals.string_lower
local string_match = Globals.string_match
local strsplit = Globals.strsplit
local table_concat = Globals.table_concat
local table_remove = Globals.table_remove
local table_sort = Globals.table_sort
local table_unpack = Globals.table_unpack
local tonumber = Globals.tonumber
local tostring = Globals.tostring
local type = Globals.type
local wipe = Globals.wipe

local Enum = Globals.Enum
local GetGameTime = Globals.GetGameTime
local GetItemSubClassInfo = Globals.GetItemSubClassInfo
local GetItemClassInfo = Globals.GetItemClassInfo
local CreateFrame = Globals.CreateFrame
local UIParent = Globals.UIParent
local UISpecialFrames = Globals.UISpecialFrames
local GetCursorPosition = Globals.GetCursorPosition
local GameFontNormal = Globals.GameFontNormal
local GameFontHighlight = Globals.GameFontHighlight
local ChatEdit_InsertLink = Globals.ChatEdit_InsertLink
local DressUpItemLink = Globals.DressUpItemLink
local IsControlKeyDown = Globals.IsControlKeyDown
local IsShiftKeyDown = Globals.IsShiftKeyDown
local PickupItem = Globals.PickupItem
local GetCursorInfo = Globals.GetCursorInfo
local ClearCursor = Globals.ClearCursor
local After = Globals.After
local GetItemInfo = Globals.GetItemInfo
local GetItemInventoryTypeByID = Globals.GetItemInventoryTypeByID
local GameTooltip = Globals.GameTooltip
local NewTimer = Globals.NewTimer
local GetItemQualityColor = Globals.GetItemQualityColor
local SearchBoxTemplate_OnTextChanged = Globals.SearchBoxTemplate_OnTextChanged
local IsInGuild = Globals.IsInGuild
local shouldYield = Globals.ShouldYield
local GetServerTime = Globals.GetServerTime

local GetRealmName = Globals.GetRealmName
local NewTicker = Globals.NewTicker

local Constants = GBCR.Constants
local colorGray = Constants.COLORS.GRAY
local colorYellow = Constants.COLORS.YELLOW

local IMPORT_PREFIX = Constants.IMPORT_PREFIX
local DISCORD_MAX = Constants.LIMITS.DISCORD_MAX

local aceGUI = GBCR.Libs.AceGUI

---
local VirtualScroll = {}
VirtualScroll.__index = VirtualScroll

function VirtualScroll:New(aceParent, rowHeight, renderFn)
    local vs = setmetatable({}, VirtualScroll)
    vs.rowHeight = rowHeight or 20
    vs.renderFn = renderFn
    vs.data = {}
    vs.pool = {}

    local SB_W = 16

    local sf = CreateFrame("ScrollFrame", nil, aceParent.content)
    sf:SetPoint("TOPLEFT", aceParent.content, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", aceParent.content, "BOTTOMRIGHT", -SB_W, 0)
    sf:EnableMouse(true)
    vs.sf = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(sf:GetWidth())
    content:SetHeight(1)
    sf:SetScrollChild(content)
    vs.content = content

    local sb = CreateFrame("Slider", nil, sf, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPRIGHT", aceParent.content, "TOPRIGHT", 0, -16)
    sb:SetPoint("BOTTOMRIGHT", aceParent.content, "BOTTOMRIGHT", 0, 16)
    sb:SetWidth(SB_W)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    sb:SetValueStep(rowHeight)
    sb:SetObeyStepOnDrag(true)
    sb:Hide()
    vs.scrollbar = sb

    sb:SetScript("OnValueChanged", function(_, val, isUser)
        if isUser then
            sf:SetVerticalScroll(val)
            vs:_repaint()
        end
    end)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sf:GetVerticalScroll()
        local maxScr = math_max(0, vs.content:GetHeight() - sf:GetHeight())
        local newVal = math_max(0, math_min(maxScr, cur - delta * vs.rowHeight * 3))
        sf:SetVerticalScroll(newVal)
        if sb:IsShown() then
            sb:SetValue(newVal)
        end
        vs:_repaint()
    end)

    sf:SetScript("OnVerticalScroll", function(_, offset)
        vs:_repaint()
    end)

    sf:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(w)
        vs:Refresh()
    end)

    return vs
end

function VirtualScroll:Destroy()
    if self.sf then
        self.sf:SetScript("OnMouseWheel", nil)
        self.sf:SetScript("OnVerticalScroll", nil)
        self.sf:SetScript("OnSizeChanged", nil)
        self.sf:Hide()
        self.sf:SetParent(nil)
    end
    if self.scrollbar then
        self.scrollbar:SetScript("OnValueChanged", nil)
        self.scrollbar:Hide()
        self.scrollbar:SetParent(nil)
    end
    if self.content then
        self.content:Hide()
        self.content:SetParent(nil)
    end
    for _, f in ipairs(self.pool) do
        f:Hide()
        f:SetParent(nil)
    end
    self.pool = {}
    self.data = {}
    self.renderFn = nil
    self.sf = nil
    self.content = nil
    self.scrollbar = nil
end

function VirtualScroll:SetData(dataArray)
    self.data = dataArray or {}
    self:Refresh()
end

function VirtualScroll:Refresh()
    local total = #self.data
    local rowH = self.rowHeight
    local sfH = self.sf:GetHeight()
    local totalH = math_max(1, total * rowH)

    self.content:SetHeight(totalH)

    local sb = self.scrollbar
    if sb then
        local maxScr = math_max(0, totalH - sfH)
        if maxScr > 0 then
            sb:SetMinMaxValues(0, maxScr)
            local cur = math_min(self.sf:GetVerticalScroll(), maxScr)
            self.sf:SetVerticalScroll(cur)
            sb:SetValue(cur)
            sb:Show()
        else
            sb:SetMinMaxValues(0, 0)
            sb:SetValue(0)
            sb:Hide()
            self.sf:SetVerticalScroll(0)
        end
    end

    local visible = math_ceil(sfH / rowH) + 2
    self:_ensurePool(visible)
    self:_repaint()
end

-- Ensures the pool has at least `needed` frames
function VirtualScroll:_ensurePool(needed)
    while #self.pool < needed do
        local f = CreateFrame("Frame", nil, self.content)
        f:SetHeight(self.rowHeight)
        f:Hide()
        self.pool[#self.pool + 1] = f
    end
end

-- Repositions pool frames to cover the currently visible slice
function VirtualScroll:_repaint()
    local data = self.data
    local total = #data
    local rowH = self.rowHeight
    local scroll = self.sf:GetVerticalScroll()
    local sfH = self.sf:GetHeight()

    local firstRow = math_floor(scroll / rowH) -- 0-based
    local lastRow = math_floor((scroll + sfH) / rowH) -- 0-based
    firstRow = math_max(0, firstRow - 1) -- 1-row overscan top
    lastRow = math_min(total - 1, lastRow + 1) -- 1-row overscan bottom

    -- Hide all pool frames first
    for _, f in ipairs(self.pool) do
        f:Hide()
    end

    local poolIndex = 1
    for rowIndex = firstRow, lastRow do
        local dataIndex = rowIndex + 1 -- 1-based
        if dataIndex > total then
            break
        end

        local f = self.pool[poolIndex]
        if not f then
            break
        end

        poolIndex = poolIndex + 1

        f:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -rowIndex * rowH)
        f:SetWidth(self.content:GetWidth())
        f:Show()
        self.renderFn(f, data[dataIndex], dataIndex)
    end
end
---

local function setUILoading(self, isLoading)
    -- print("setUILoading", self.itemsList and #self.itemsList, isLoading, self.isDataPending, self.isReady)

    if not self.window or not self.window.frame then
        return
    end

    -- 1. Create the dark overlay if it doesn't exist
    if not self.loadingOverlay then
        self.loadingOverlay = CreateFrame("Frame", nil, self.window.frame, "BackdropTemplate")
        self.loadingOverlay:SetAllPoints(self.window.frame)
        self.loadingOverlay:SetFrameStrata("TOOLTIP")
        self.loadingOverlay:EnableMouse(true)
        self.loadingOverlay:SetScript("OnMouseWheel", function()
        end)

        local bg = self.loadingOverlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)

        local text = self.loadingOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        text:SetPoint("CENTER")
        text:SetText("Loading data, please wait...")
        self.loadingOverlayText = text
    end

    -- 2. Physically disable interactive elements for visual feedback
    if self.filters then
        if self.searchField then
            self.searchField:EnableMouse(not isLoading)
            self.searchField:SetAlpha(isLoading and 0.5 or 1.0)
        end
        if self.filters.sortDropdown then
            self.filters.sortDropdown:SetDisabled(isLoading)
        end
        if self.filters.rarity then
            self.filters.rarity:SetDisabled(isLoading)
        end
        if self.filters.bankDropdown then
            self.filters.bankDropdown:SetDisabled(isLoading)
        end
    end

    local tab = self.currentTab
    local isDataTab = (tab == "browse" or tab == "cart" or tab == "export" or not tab)
    local shouldShow = (isLoading or self.isDataPending or not self.isReady) and isDataTab

    if shouldShow then
        -- print("...loading data, please wait...")
        self.loadingOverlay:Show()
        if self.emptyLabel then
            self.emptyLabel:Hide()
        end
    else
        -- print("...overlay hidden (either finished or on a non-data tab)")
        self.loadingOverlay:Hide()
    end
end

local function invalidateDataCache(self, isFullRebuild)
    self.itemsHydrated = false
    self.needsFullRebuild = isFullRebuild == true
    self.pendingCorpusBuild = false
    self.lastAggregatedView = nil
    self.filteredCount = 0
    wipe(self.itemInfoCache)
    wipe(self.corpus)
    wipe(self.aggregatedMap)
    wipe(self.itemsList)
    if GBCR.Inventory then
        wipe(GBCR.Inventory.cachedItemKeys)
        wipe(GBCR.Inventory.cachedSourcesPerItem)
    end
end

-- Mark a guild bank alt as dirty when receiving new data
local function markAltDirty(self, altName)
    self.dirtyAlts[altName] = true
    invalidateDataCache(self, false)
end

-- Mark all data as dirty (e.g., database reset, initial login)
local function markAllDirty(self)
    invalidateDataCache(self, true)
end

-- Sort items displayed in the UI based on the selected sort mode
local function sort(self, items, mode)
    if not items then
        return
    end

    table_sort(items, Constants.SORT_COMPARATORS[mode] or Constants.SORT_COMPARATORS.default)
end

--
-- Splits "q:rare lvl>40 sword" into {"q:rare", "lvl>40", "sword"}
local function parseSearchQuery(queryText)
    local tokens = {}

    if not queryText or queryText == "" then
        return tokens
    end

    for word in string_gmatch(string_lower(queryText), "%S+") do
        tokens[#tokens + 1] = word
    end

    return tokens
end

-- Evaluates a single item against a list of parsed tokens
local function advancedSearchMatch(item, tokens)
    if not tokens or #tokens == 0 then
        return true
    end

    local info = item.itemInfo
    if not info then
        return false
    end

    local name = item.lowerName or ""
    local typeL = info.typeLower or ""
    local subL = info.subTypeLower or ""
    local equipL = info.equipLower or ""
    local ilvl = info.level or 0
    local minLvl = info.minLevel or 0
    local rarity = info.rarity or 1

    for _, token in ipairs(tokens) do
        local matched = false
        local prefix, op, val = string_match(token, "^(%a+)([<>=]+)(.+)$")

        if prefix then
            local nVal = tonumber(val) or 0

            if prefix == "lvl" or prefix == "req" then
                if op == ">" then
                    matched = minLvl > nVal
                elseif op == "<" then
                    matched = minLvl < nVal
                elseif op == ">=" then
                    matched = minLvl >= nVal
                elseif op == "<=" then
                    matched = minLvl <= nVal
                elseif op == "=" or op == "==" then
                    matched = minLvl == nVal
                end
            elseif prefix == "ilvl" then
                if op == ">" then
                    matched = ilvl > nVal
                elseif op == "<" then
                    matched = ilvl < nVal
                elseif op == ">=" then
                    matched = ilvl >= nVal
                elseif op == "<=" then
                    matched = ilvl <= nVal
                elseif op == "=" or op == "==" then
                    matched = ilvl == nVal
                end
            elseif prefix == "q" and (op == "=" or op == "==") then
                local numVal = nVal > 0 and nVal or Constants.FILTER.RARITY_MAP[val]
                if numVal then
                    matched = (rarity == numVal)
                end
            end
        else
            prefix, val = string_match(token, "^(%a+):(.+)$")
            if prefix == "q" then
                local numVal = tonumber(val) or Constants.FILTER.RARITY_MAP[val]
                if numVal then
                    matched = (rarity == numVal)
                end
            elseif prefix == "t" then
                matched = (string_find(typeL, val, 1, true) or string_find(subL, val, 1, true)) and true or false
            elseif prefix == "s" then
                matched = string_find(equipL, val, 1, true) and true or false
            end
        end

        if not matched and not prefix then
            matched = string_find(name, token, 1, true) and true or false
        end

        if not matched then
            return false
        end
    end

    return true
end

local function eventHandler(item, event)
    if not item then
        return false
    end

    if event == "OnClick" then
        local link = (item.itemInfo and item.itemInfo.realLink) or item.itemLink

        if IsShiftKeyDown() and link then
            ChatEdit_InsertLink(link)

            return true
        elseif IsControlKeyDown() and link then
            DressUpItemLink(link)

            return true
        end
    elseif event == "OnDragStart" then
        local itemId = item.itemId
        if itemId then
            PickupItem(itemId)

            return true
        end
    end

    return false
end

local function populateCustomTooltip()
    -- print("populateCustomTooltip called")
    local frame = UI_Inventory.customTooltip
    local itemLink = UI_Inventory.preview.selectedItem and
                         ((UI_Inventory.preview.selectedItem.itemInfo and UI_Inventory.preview.selectedItem.itemInfo.realLink) or
                             UI_Inventory.preview.selectedItem.itemLink) or nil
    local targetWidth = UI_Inventory.preview.scroll.frame:GetWidth() - 40

    -- 1. Clear existing lines
    for _, line in ipairs(frame.lines) do
        line.left:Hide()
        if line.right then
            line.right:Hide()
        end
    end
    if not itemLink then
        return
    end

    -- 2. Fetch the actual data (Modern API)
    UI_Inventory.tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
    UI_Inventory.tooltipScanner:SetHyperlink(itemLink)

    local yOffset = -10
    local padding = 10
    local textWidth = targetWidth - (padding * 2)
    local numLines = UI_Inventory.tooltipScanner:NumLines()

    -- 3. Iterate through the lines data
    for i = 1, numLines do
        local leftTextObj = _G["GBCR_TooltipScannerTextLeft" .. i]
        local rightTextObj = _G["GBCR_TooltipScannerTextRight" .. i]

        if not frame.lines[i] then
            frame.lines[i] = {
                left = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
                right = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            }
        end

        local line = frame.lines[i]
        local txt = leftTextObj:GetText()

        if txt and txt ~= "" then
            -- Set up the Left side
            line.left:SetWidth(textWidth)
            line.left:SetJustifyH("LEFT")
            line.left:SetWordWrap(true)
            line.left:ClearAllPoints()
            line.left:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, yOffset)

            -- Copy Color
            line.left:SetTextColor(leftTextObj:GetTextColor())
            line.left:SetText(txt)
            line.left:Show()

            -- Check for Right-side text (Stats like "+5 Intellect" or gold costs)
            local rTxt = rightTextObj:GetText()
            if rTxt and rTxt ~= "" and rightTextObj:IsShown() then
                line.right:ClearAllPoints()
                line.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padding, yOffset)
                line.right:SetTextColor(rightTextObj:GetTextColor())
                line.right:SetText(rTxt)
                line.right:Show()

                -- Constrain left side so it doesn't overlap the right side
                local rWidth = line.right:GetStringWidth()
                line.left:SetWidth(math_max(1, textWidth - rWidth - 5))
            end

            -- Increment Y offset based on the height of the wrapped text
            yOffset = yOffset - (line.left:GetStringHeight() + 2)
        end
    end

    -- 4. Finalize height
    local totalHeight = math_abs(yOffset) + 8
    frame:SetHeight(totalHeight)
    frame:SetWidth(targetWidth)
    frame:Show()

    -- 5. CRITICAL: Update the AceGUI Scroll Container
    local content = frame:GetParent()
    content:SetHeight(totalHeight + 4)
    if content.obj and content.obj.FixScroll then
        content.obj:FixScroll()
    end
end

-- Helper callbacks for the browse tab
local function onBrowseItemClick(widget, event, item)
    if eventHandler(item, "OnClick") then
        return
    end

    local self = UI_Inventory
    self.preview.selectedItem = item

    local itemKey = item.itemString or tostring(item.itemId or 0)
    -- self.preview.label:SetText("Selected item: " .. (item.itemInfo and item.itemInfo.name or itemKey))

    local alreadyInCart = self.cartData[itemKey] and self.cartData[itemKey].qty or 0
    local availableToRequest = item.itemCount - alreadyInCart

    if availableToRequest > 0 then
        self.preview.slider:SetDisabled(false)
        self.preview.slider:SetSliderValues(1, availableToRequest, 1)
        self.preview.slider:SetValue(1)
        self.preview.button:SetDisabled(false)
    else
        self.preview.slider:SetDisabled(true)
        self.preview.slider:SetValue(0)
        self.preview.button:SetDisabled(true)
    end

    if not self.preview.isScrollAttached then
        self.preview:AddChild(self.preview.scroll)
        self.preview.isScrollAttached = true
        self.preview:PerformLayout()
    end

    populateCustomTooltip()
end
local function onBrowseItemDrag(widget, event, item)
    eventHandler(item, "OnDragStart")
end
local function onBrowseItemEnter(widget, event, item)
    local link = (item.itemInfo and item.itemInfo.realLink) or item.itemLink
    GBCR.UI:ShowItemTooltip(link, item.sources)
end
local function onBrowseItemLeave()
    GBCR.UI:HideTooltip()
end

-- Helper function to contain the grid logic to avoid creating an anonymous closure on every frame/scroll update
local function doUpdateGridLogic(self, scroll, availableWidth, frameHeight)
    local itemCount = self.filteredCount or 0
    if itemCount == 0 then
        if self.itemPool then
            for _, widget in ipairs(self.itemPool) do
                widget.frame:Hide()
            end
        end
        scroll.content:SetHeight(1)
        scroll:FixScroll()
        if scroll.scrollbar then
            scroll.scrollbar:Hide()
        end

        return
    end

    local itemSize, itemPadding = 40, 4
    local columnWidth, rowHeight = itemSize + itemPadding, itemSize + itemPadding

    local initialGuess = math_floor(availableWidth / columnWidth)
    local projectedRows = math_ceil(itemCount / math_max(1, initialGuess))
    local needsScroll = (projectedRows * rowHeight) > frameHeight

    local usableWidth = availableWidth - (needsScroll and 20 or 0)
    local itemsPerRow = math_max(1, math_floor(usableWidth / columnWidth))
    local totalRows = math_ceil(itemCount / itemsPerRow)
    local newTotalHeight = totalRows * rowHeight
    local maxScroll = math_max(0, newTotalHeight - frameHeight)

    scroll.content:SetHeight(newTotalHeight)
    scroll:FixScroll()
    if scroll.scrollbar then
        if needsScroll then
            scroll.scrollbar:Show()
        else
            scroll.scrollbar:Hide()
        end
    end

    local visibleRows = math_ceil(frameHeight / rowHeight) + 2
    local poolSize = visibleRows * itemsPerRow

    self.itemPool = self.itemPool or {}
    for i = 1, poolSize do
        if not self.itemPool[i] then
            local btn = aceGUI:Create(self.itemButtonWidgetType)
            btn.frame:SetParent(scroll.content)
            btn.frame:ClearAllPoints()
            btn:SetCallback("OnClick", onBrowseItemClick)
            btn:SetCallback("OnDragStart", onBrowseItemDrag)
            btn:SetCallback("OnEnter", onBrowseItemEnter)
            btn:SetCallback("OnLeave", onBrowseItemLeave)
            btn._parentedToGrid = true
            self.itemPool[i] = btn
        end
    end
    for i = poolSize + 1, #self.itemPool do
        if self.itemPool[i] then
            self.itemPool[i].frame:Hide()
        end
    end

    local offset = 0
    if scroll.scrollbar then
        local minVal, maxVal = scroll.scrollbar:GetMinMaxValues()
        local val = scroll.scrollbar:GetValue() or 0
        local range = maxVal - minVal
        if range > 0 then
            offset = ((val - minVal) / range) * maxScroll
        end
    end
    offset = math_min(math_max(0, offset), maxScroll) -- Hard clamp for safety

    local startRow = math_floor(offset / rowHeight)
    local maxStartRow = math_max(0, totalRows - visibleRows)
    local clampedStartRow = math_min(startRow, maxStartRow)
    local startIndex = (clampedStartRow * itemsPerRow) + 1

    local poolIndex = 1
    local baseLevel = scroll.content:GetFrameLevel() + 5
    scroll.frame:SetClipsChildren(true)

    for row = 0, visibleRows - 1 do
        for col = 0, itemsPerRow - 1 do
            local dataIndex = startIndex + (row * itemsPerRow) + col
            local item = self.cachedFilteredList[dataIndex]
            local slot = self.itemPool[poolIndex]
            if not slot then
                break
            end

            if item then
                if not slot._parentedToGrid then
                    slot.frame:SetParent(scroll.content)
                    slot.frame:SetFrameLevel(baseLevel)
                    slot._parentedToGrid = true
                end
                slot:SetIcon(item.itemInfo and item.itemInfo.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                slot:SetCount(item.itemCount)
                slot.userData = item

                if item.itemInfo and item.itemInfo.rarity then
                    local r, g, b = GetItemQualityColor(item.itemInfo.rarity)
                    slot.border:SetVertexColor(r, g, b)
                else
                    slot.border:SetVertexColor(1, 1, 1)
                end
                slot.border:Show()

                local drawRow = clampedStartRow + row
                local x = col * columnWidth
                local y = -(drawRow * rowHeight)

                slot.frame:ClearAllPoints()
                slot.frame:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", x, y)
                slot.frame:Show()
            else
                slot.frame:Hide()
            end
            poolIndex = poolIndex + 1
        end
    end

    for i = poolIndex, #self.itemPool do
        if self.itemPool[i] then
            self.itemPool[i].frame:Hide()
        end
    end
end

-- Update the virtual grid used in the browse tab
local function updateVirtualGrid(self)
    if self.currentTab ~= "browse" then
        return
    end

    local scroll = self.grid and self.grid.scroll
    if not scroll or not scroll.content then
        return
    end

    local availableWidth = scroll.frame:GetWidth()
    local frameHeight = scroll.frame:GetHeight()
    if availableWidth < 10 or frameHeight < 10 then
        return
    end

    if self.isUpdatingScroll then
        return
    end
    self.isUpdatingScroll = true

    local ok, err = pcall(doUpdateGridLogic, self, scroll, availableWidth, frameHeight)

    self.isUpdatingScroll = false

    if not ok then
        GBCR.Output:Error("updateVirtualGrid error: %s", tostring(err))
    end
end

-- Prototype methods for our own button widget
local widgetMethods = {
    OnRelease = function(self)
        self.frame:ClearAllPoints()
        self.frame:Hide()
        self.frame:SetParent(UIParent)
        self.userData = nil
    end,
    OnAcquire = function(self)
        self.frame:Show()
    end,
    SetIcon = function(self, iconTexture)
        self.icon:SetTexture(iconTexture)
    end,
    SetCount = function(self, itemCount)
        self.text:SetText((itemCount and itemCount > 1) and itemCount or "")
    end
}

-- Helper to create our own button widget
local function itemButtonWidget()
    local frame = CreateFrame("Button", nil, UIParent)
    frame:SetSize(40, 40)

    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    border:SetAllPoints(frame)
    border:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local fontName, fontHeight = text:GetFont()
    text:SetFont(fontName, fontHeight, "OUTLINE")
    text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 2)
    text:SetJustifyH("RIGHT")

    local widget = {
        frame = frame,
        icon = icon,
        border = border,
        text = text,
        type = UI_Inventory.itemButtonWidgetType,
        width = 40,
        height = 40
    }

    for methodName, methodFunc in pairs(widgetMethods) do
        widget[methodName] = methodFunc
    end

    frame:SetScript("OnClick", function()
        widget:Fire("OnClick", widget.userData)
    end)

    frame:SetScript("OnEnter", function()
        widget:Fire("OnEnter", widget.userData)
    end)

    frame:SetScript("OnLeave", function()
        widget:Fire("OnLeave", widget.userData)
    end)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        widget:Fire("OnDragStart", widget.userData)
    end)

    return aceGUI:RegisterAsWidget(widget)
end

-- Helper to create our own custom resizer akin to what the tree group container uses
local function getResizer(content, onUpdateMath)
    if not content.paneResizer then
        local resizer = CreateFrame("Button", nil, content, "BackdropTemplate")
        resizer:SetWidth(8)

        local resizerBackdrop = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = nil,
            tile = true,
            tileSize = 16,
            edgeSize = 1,
            insets = {left = 3, right = 3, top = 7, bottom = 7}
        }
        resizer:SetBackdrop(resizerBackdrop)
        resizer:SetBackdropColor(1, 1, 1, 0)
        resizer:EnableMouse(true)
        resizer:RegisterForDrag("LeftButton")

        resizer:SetScript("OnEnter", function(self)
            self:SetBackdropColor(1, 1, 1, 0.8)
        end)

        resizer:SetScript("OnLeave", function(self)
            if not self.isDragging then
                self:SetBackdropColor(1, 1, 1, 0)
            end
        end)

        resizer:SetScript("OnDragStart", function(self)
            self.isDragging = true
            self:SetBackdropColor(1, 1, 1, 0.8)
            self:SetScript("OnUpdate", self.UpdateMath)
        end)

        resizer:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self.isDragging = false
            if not self:IsMouseOver() then
                self:SetBackdropColor(1, 1, 1, 0)
            end
        end)

        content.paneResizer = resizer

        local originalOnRelease = content.obj.OnRelease
        content.obj.OnRelease = function(widget)
            if widget.content.paneResizer then
                widget.content.paneResizer:Hide()
                widget.content.paneResizer:ClearAllPoints()
            end
            -- Continue with normal AceGUI cleanup
            if originalOnRelease then
                originalOnRelease(widget)
            end
        end
    end

    content.paneResizer.UpdateMath = onUpdateMath

    return content.paneResizer
end

-- Helper to register our custom widget and custom layouts with AceGUI
local function registerCustomUI(self)
    aceGUI:RegisterWidgetType(self.itemButtonWidgetType, itemButtonWidget, self.itemButtonWidgetVersion)

    aceGUI:RegisterLayout("GBCR_AppLayout", function(content, children)
        local topBar = children[1]
        local tabs = children[2]
        local bottomBar = children[3]

        local topH, bottomH = 0, 0
        local contentWidth = content:GetWidth() or 0

        if topBar then
            topBar.frame:ClearAllPoints()
            topBar.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            topBar.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            topBar:SetWidth(contentWidth)
            topBar.frame:SetHeight(16)
            topBar.frame:Show()
            topH = 16

            -- Reposition clock label and notice text after every layout pass.
            -- The GBCR_NoLayout on topBar is a no-op so we own all child positioning here.
            local inv = UI_Inventory
            if inv.clockLabel then
                inv.clockLabel.frame:ClearAllPoints()
                inv.clockLabel.frame:SetPoint("LEFT", topBar.content, "LEFT", 14, 0)
                inv.clockLabel.frame:SetWidth(32)
                inv.clockLabel.frame:SetHeight(16)
                if inv.clockLabel.label then
                    inv.clockLabel.label:SetJustifyV("MIDDLE")
                end
            end
            if inv.topBar and inv.topBar.topBarText then
                local tt = inv.topBar.topBarText
                tt.frame:ClearAllPoints()
                tt.frame:SetPoint("LEFT", topBar.content, "LEFT", 60, 0)
                tt.frame:SetPoint("RIGHT", topBar.content, "RIGHT", -8, 0)
                tt.frame:SetHeight(16)
                tt:SetWidth(700)
                if tt.label then
                    tt.label:SetJustifyV("MIDDLE")
                end
            end
            -- Re-anchor sync dot (parented to topBar.frame; stays stable on resize).
            if inv.syncDot then
                inv.syncDot:ClearAllPoints()
                inv.syncDot:SetPoint("LEFT", topBar.frame, "LEFT", 2, 0)
            end
        end

        if bottomBar then
            bottomBar.frame:ClearAllPoints()
            bottomBar.frame:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
            bottomBar.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
            bottomBar:SetWidth(contentWidth)
            bottomBar.frame:Show()

            if bottomBar.PerformLayout then
                bottomBar:PerformLayout()
            end
            bottomH = math_max(bottomBar.frame:GetHeight(), 26)
            bottomBar.frame:SetHeight(bottomH)
        end

        if tabs then
            tabs.frame:ClearAllPoints()
            tabs.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -topH)
            tabs.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, bottomH)
            tabs.frame:Show()
            tabs:SetWidth(content:GetWidth())
            tabs:SetHeight(content:GetHeight() - topH - bottomH)

            if tabs.PerformLayout then
                tabs:PerformLayout()
            end
        end
    end)

    aceGUI:RegisterLayout("GBCR_TopBottom", function(content, children)
        local topWidget = children[1]
        local bottomWidget = children[2]

        local w = content:GetWidth() or 0
        local h = content:GetHeight() or 0
        local topH = 0

        if topWidget then
            topWidget.frame:ClearAllPoints()
            topWidget.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            topWidget.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            topWidget:SetWidth(w)
            topWidget.frame:Show()

            if topWidget.PerformLayout then
                topWidget:PerformLayout()
            end
            topH = topWidget.frame:GetHeight()
        end

        if bottomWidget then
            bottomWidget.frame:ClearAllPoints()
            bottomWidget.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -topH)
            bottomWidget.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
            bottomWidget.frame:Show()
            bottomWidget:SetHeight(h - topH)
            bottomWidget:SetWidth(w)

            if bottomWidget.PerformLayout then
                bottomWidget:PerformLayout()
            end
        end
    end)

    aceGUI:RegisterLayout("GBCR_TwoPane", function(content, children)
        local leftPane = children[1]
        local rightPane = children[2]

        local w = content:GetWidth() or 0
        local h = content:GetHeight() or 0

        local resizer = getResizer(content, function(self)
            local uiScale = content:GetEffectiveScale()
            local cursorX = GetCursorPosition() / uiScale
            local leftEdge = content:GetLeft()
            local newWidth = cursorX - leftEdge
            local maxLeftWidth = content:GetWidth() - 200 - self:GetWidth()

            if newWidth < 200 then
                newWidth = 200
            end
            if newWidth > maxLeftWidth then
                newWidth = maxLeftWidth
            end

            UI_Inventory.activeCartLeftPaneWidth = newWidth

            if GBCR.db then
                GBCR.db.profile.framePositions.panes = GBCR.db.profile.framePositions.panes or {}
                GBCR.db.profile.framePositions.panes.cartLeft = newWidth
            end

            content.obj:PerformLayout()
        end)

        local maxAllowedLeft = w - 300 - resizer:GetWidth()
        local effectiveLeftWidth = UI_Inventory.activeCartLeftPaneWidth

        if effectiveLeftWidth > maxAllowedLeft then
            effectiveLeftWidth = maxAllowedLeft
        end
        if effectiveLeftWidth < 300 then
            effectiveLeftWidth = 300
        end

        if leftPane then
            leftPane.frame:ClearAllPoints()
            leftPane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            leftPane.frame:SetWidth(effectiveLeftWidth)
            leftPane.frame:SetHeight(h)
            leftPane.frame:Show()

            if leftPane.PerformLayout then
                leftPane:PerformLayout()
            end
        end

        resizer:ClearAllPoints()
        resizer:SetPoint("TOPLEFT", content, "TOPLEFT", effectiveLeftWidth, 0)
        resizer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", effectiveLeftWidth, 0)
        resizer:Show()

        if rightPane then
            rightPane.frame:ClearAllPoints()
            rightPane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", effectiveLeftWidth + resizer:GetWidth(), 0)
            rightPane.frame:SetWidth(w - effectiveLeftWidth - resizer:GetWidth())
            rightPane.frame:SetHeight(h)
            rightPane.frame:Show()

            if rightPane.PerformLayout then
                rightPane:PerformLayout()
            end
        end
    end)

    aceGUI:RegisterLayout("GBCR_ThreePane", function(content, children)
        local topPanel = children[1]
        local gridPanel = children[2]
        local previewPanel = children[3]

        local contentWidth = content:GetWidth() or 0
        local topHeight = 40

        if topPanel then
            topPanel.frame:ClearAllPoints()
            topPanel.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            topPanel.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            topPanel:SetWidth(contentWidth)
            topPanel.frame:Show()

            if topPanel.PerformLayout then
                topPanel:PerformLayout()
            end
            topHeight = topPanel.frame:GetHeight()
            if topHeight < 40 then
                topHeight = 40
            end
        end

        local resizer = getResizer(content, function(self)
            local uiScale = content:GetEffectiveScale()
            local cursorX = GetCursorPosition() / uiScale
            local rightEdge = content:GetRight()
            local newWidth = rightEdge - cursorX
            local maxPreviewWidth = content:GetWidth() - 202 - self:GetWidth()

            if newWidth < 200 then
                newWidth = 200
            end
            if newWidth > maxPreviewWidth then
                newWidth = maxPreviewWidth
            end

            UI_Inventory.activePreviewRightPaneWidth = newWidth

            if GBCR.db then
                GBCR.db.profile.framePositions.panes = GBCR.db.profile.framePositions.panes or {}
                GBCR.db.profile.framePositions.panes.previewRight = newWidth
            end

            content.obj:PerformLayout()
        end)

        local contentWidth = content:GetWidth()
        local maxAllowedPreview = contentWidth - 218 - resizer:GetWidth()

        local effectivePreviewWidth = UI_Inventory.activePreviewRightPaneWidth

        if effectivePreviewWidth > maxAllowedPreview then
            effectivePreviewWidth = maxAllowedPreview
        end
        if effectivePreviewWidth < 200 then
            effectivePreviewWidth = 200
        end

        if gridPanel then
            gridPanel.frame:ClearAllPoints()
            gridPanel.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -topHeight)
            gridPanel.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -effectivePreviewWidth - resizer:GetWidth(), 0)
            gridPanel.frame:Show()
            gridPanel:SetWidth(contentWidth - effectivePreviewWidth - resizer:GetWidth())
            gridPanel:SetHeight(content:GetHeight() - topHeight)

            if gridPanel.PerformLayout then
                gridPanel:PerformLayout()
            end
        end

        if gridPanel and previewPanel then
            resizer:ClearAllPoints()
            resizer:SetPoint("TOPLEFT", content, "TOPRIGHT", -effectivePreviewWidth - resizer:GetWidth(), -topHeight)
            resizer:SetPoint("BOTTOMLEFT", content, "BOTTOMRIGHT", -effectivePreviewWidth - resizer:GetWidth(), 0)
            resizer:Show()
        end

        if previewPanel then
            previewPanel.frame:ClearAllPoints()
            previewPanel.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -topHeight)
            previewPanel.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
            previewPanel.frame:Show()
            previewPanel:SetWidth(effectivePreviewWidth)
            previewPanel:SetHeight(content:GetHeight() - topHeight)

            if previewPanel.PerformLayout then
                previewPanel:PerformLayout()
            end
        end
    end)

    aceGUI:RegisterLayout("GBCR_VirtualGrid", function(content, children)
    end)

    aceGUI:RegisterLayout("GBCR_RosterRows", function(content, children)
    end)

    aceGUI:RegisterLayout("GBCR_ConfigTwoPane", function(content, children)
        local left = children[1]
        local right = children[2]
        local w = content:GetWidth() or 0
        local h = content:GetHeight() or 0
        local half = math_max(1, math_floor((w - 6) / 2))

        if left then
            left.frame:ClearAllPoints()
            left.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            left.frame:SetWidth(half)
            left.frame:SetHeight(h)
            left.frame:Show()
            left:SetWidth(half)
            left:SetHeight(h)
            if left.PerformLayout then
                left:PerformLayout()
            end
        end
        if right then
            right.frame:ClearAllPoints()
            right.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            right.frame:SetWidth(half)
            right.frame:SetHeight(h)
            right.frame:Show()
            right:SetWidth(half)
            right:SetHeight(h)
            if right.PerformLayout then
                right:PerformLayout()
            end
        end
    end)
end

-- Helper to count how many unique items are in the cart
local function getCartUniqueCount(self)
    return UI_Inventory.cartCount
end

-- Helper to extract the enchant from a tooltip
local function getEnchantTextFromTooltip(self, itemLink)
    if not itemLink then
        return nil
    end

    local itemString = string_match(itemLink, "(item:[%-?%d:]+)")
    if not itemString then
        return nil
    end

    local _, _, enchantStr = strsplit(":", itemString)
    local enchantID = tonumber(enchantStr) or 0
    if enchantID == 0 then
        return nil
    end

    self.tooltipScanner:ClearLines()
    self.tooltipScanner:SetHyperlink(itemLink)

    for i = 1, self.tooltipScanner:NumLines() do
        local fontString = _G["GBCR_TooltipScannerTextLeft" .. i]
        if fontString then
            local text = fontString:GetText()
            if text then
                local r, g, b = fontString:GetTextColor()
                -- Enchants are rendered in pure green (r=0, g=1, b=0)
                if g > 0.9 and r < 0.2 and b < 0.2 then
                    -- Ignore "Equip:", "Use:", and "Set:" bonuses which are also green
                    if not string_match(text, "^Equip:") and not string_match(text, "^Use:") and not string_match(text, "^Set:") then
                        -- Remove any UI escape sequences just in case
                        return string_gsub(string_gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
                    end
                end
            end
        end
    end

    return "Enchanted"
end

local function formatTimeAgo(timestamp)
    if not timestamp or timestamp == 0 then
        return "never"
    end

    local diff = GetServerTime() - timestamp
    if diff < 60 then
        return "just now"
    end

    if diff < 3600 then
        return math_floor(diff / 60) .. "m ago"
    end

    if diff < 86400 then
        return math_floor(diff / 3600) .. "h ago"
    end

    return math_floor(diff / 86400) .. "d ago"
end

local function generateImportString(sortedCartItems)
    if not sortedCartItems or #sortedCartItems == 0 then
        return nil
    end

    local items = {}
    for _, entry in ipairs(sortedCartItems) do
        local data = entry.data
        local itemId = data.itemLink and tonumber(string_match(data.itemLink, "|Hitem:(%d+):"))
        if itemId then
            items[#items + 1] = {itemId, data.qty}
        end
    end

    if #items == 0 then
        return nil
    end

    local _myNorm = GBCR.Guild:GetNormalizedPlayerName()
    local _myEntry = GBCR.Guild.cachedGuildMembers and GBCR.Guild.cachedGuildMembers[_myNorm]
    local _myRank = (_myEntry and _myEntry.rankIndex) or 0
    local payload = {r = _myNorm, t = GetServerTime(), i = items, rk = _myRank}
    local serialized = GBCR.Libs.LibSerialize:Serialize(payload)
    local compressed = GBCR.Libs.LibDeflate:CompressDeflate(serialized, {level = 9})

    return IMPORT_PREFIX .. GBCR.Libs.LibDeflate:EncodeForPrint(compressed)
end

local function parseImportString(str)
    if not str then
        return nil, "empty input"
    end

    local encoded = string_match(str, "^" .. IMPORT_PREFIX .. "(.+)$")
    if not encoded then
        return nil, "not a valid import string"
    end

    local compressed = GBCR.Libs.LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return nil, "decode failed"
    end

    local decompressed = GBCR.Libs.LibDeflate:DecompressDeflate(compressed)
    if not decompressed then
        return nil, "decompress failed"
    end

    local ok, data = GBCR.Libs.LibSerialize:Deserialize(decompressed)
    if not ok or type(data) ~= "table" or not data.r or not data.i then
        return nil, "invalid payload"
    end

    return data, nil
end

-- Split lines into Discord-sized chunks and append the import string to the last.
local function buildDiscordMessages(lines, importStr)
    local messages, current, currentLen = {}, {}, 0
    local function flush()
        if #current > 0 then
            messages[#messages + 1] = table_concat(current, "\n")
            current, currentLen = {}, 0
        end
    end

    for _, line in ipairs(lines) do
        local need = string_len(line) + 1
        if currentLen + need > DISCORD_MAX then
            flush()
        end
        current[#current + 1] = line
        currentLen = currentLen + need
    end

    if importStr then
        local suffix = "\n**Import code (paste in guild bank request tab):**\n`" .. importStr .. "`"
        if currentLen + string_len(suffix) <= DISCORD_MAX then
            current[#current + 1] = suffix
        else
            flush()
            current[#current + 1] = suffix
        end
    end

    flush()

    return messages
end

-- Classic WoW has no EditBox:Copy() API. This dialog pre-populates text and highlights it; the user presses Ctrl + C
local function ShowCopyDialog(title, text)
    local f = aceGUI:Create("Frame")
    f:SetTitle(title or "Copy")
    f:SetWidth(520)
    f:SetHeight(380)
    f:SetLayout("Fill")
    f:SetCallback("OnClose", function(w)
        aceGUI:Release(w)
    end)
    f.frame:SetClampedToScreen(true)
    f.frame:SetPoint("CENTER", Globals.UIParent, "CENTER")

    -- local hint = aceGUI:Create("Label")
    -- hint:SetFullWidth(true)
    -- hint:SetText("Press Ctrl + A then Ctrl + C to copy")
    -- f:AddChild(hint)
    -- local messageCount = #GBCR.Output.debugMessageBuffer
    f:SetStatusText("Select text and press Ctrl + C to copy")

    local box = aceGUI:Create("MultiLineEditBox")
    box:SetLabel("")
    box:DisableButton(true)
    box:SetFullWidth(true)
    box:SetFullHeight(true)
    box:SetText(text)
    f:AddChild(box)

    f:Show()
    if box.editBox then
        box.editBox:SetFocus()
        box.editBox:HighlightText()
    end
end

-- Streams lines from an iterator function into a VirtualScroll viewer
-- lineIteratorFn() must return the next string or nil when done
-- Returns the VirtualScroll instance
local function RenderStreamingTextArea(container, lineIteratorFn, onDone)
    -- Single wrapper with GBCR_TopBottom: controls on top, scroll fills rest.
    -- This is required because container uses Fill layout; two bare children
    -- would collapse the scroll area.
    local wrapper = aceGUI:Create("SimpleGroup")
    wrapper:SetFullWidth(true)
    wrapper:SetFullHeight(true)
    wrapper:SetLayout("GBCR_TopBottom")
    container:AddChild(wrapper)

    -- Top row: progress label + copy button
    local controlRow = aceGUI:Create("SimpleGroup")
    controlRow:SetFullWidth(true)
    controlRow:SetLayout("Flow")
    wrapper:AddChild(controlRow)

    local progressLabel = aceGUI:Create("Label")
    progressLabel:SetText("Building export...")
    progressLabel:SetWidth(220)
    controlRow:AddChild(progressLabel)

    local copyBtn = aceGUI:Create("Button")
    copyBtn:SetText("Copy all")
    copyBtn:SetWidth(90)
    copyBtn:SetDisabled(true)
    controlRow:AddChild(copyBtn)

    -- Bottom: virtual scroll
    local vsGroup = aceGUI:Create("SimpleGroup")
    vsGroup:SetFullWidth(true)
    vsGroup:SetFullHeight(true)
    vsGroup:SetLayout("Fill")
    wrapper:AddChild(vsGroup)

    local vs = VirtualScroll:New(vsGroup, 18, function(frame, row)
        if not frame._exportFS then
            frame._exportFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            frame._exportFS:SetPoint("LEFT", frame, "LEFT", 4, 0)
            frame._exportFS:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
            frame._exportFS:SetJustifyH("LEFT")
            frame._exportFS:SetWordWrap(false)
        end
        frame._exportFS:SetText(row.text or "")
        frame._exportFS:Show()
    end)

    -- Generation counter: incremented when AceGUI releases the group (tab
    -- switch, re-render). Any in-flight After(0, collect) sees a stale gen
    -- and exits before touching the destroyed VirtualScroll.
    local streamGen = 0
    vsGroup:SetCallback("OnRelease", function()
        streamGen = streamGen + 1
        vs:Destroy()
    end)

    -- Two parallel arrays:
    --   allLines   → {text = string}  consumed by VirtualScroll:SetData
    --   allStrings → plain strings    consumed by table_concat in copy dialog
    local allLines = {}
    local allStrings = {}
    local BATCH = 300
    local myGen = streamGen

    local function collect()
        if myGen ~= streamGen then
            return
        end -- aborted: tab switched mid-stream

        local count = 0
        while count < BATCH do
            local line = lineIteratorFn()
            if line == nil then
                vs:SetData(allLines)
                progressLabel:SetText(string_format("Lines: %d", #allStrings))
                copyBtn:SetDisabled(false)
                copyBtn:SetCallback("OnClick", function()
                    ShowCopyDialog("Export", table_concat(allStrings, "\n"))
                end)

                if onDone then
                    onDone(allStrings)
                end

                return
            end

            allLines[#allLines + 1] = {text = line}
            allStrings[#allStrings + 1] = line
            count = count + 1
        end

        -- Partial update so user sees progress
        vs:SetData(allLines)
        progressLabel:SetText(string_format("Loading... %d lines", #allStrings))

        After(0, collect)
    end

    After(0, collect)

    return vs
end

-- Helper callback to generate an export for Discord to manually request the contents of the cart
local function generateExport()
    local self = UI_Inventory
    if getCartUniqueCount(self) == 0 then
        if self.cart and self.cart.exportArea then
            self.cart.exportArea:ReleaseChildren()
            local lbl = aceGUI:Create("Label")
            lbl:SetFullWidth(true)
            lbl:SetText("Your request list is empty, browse to add items")
            self.cart.exportArea:AddChild(lbl)
            self.cart.exportArea:DoLayout()
        end
        return
    end

    -- 1. Build allocations (fast, synchronous: cart is bounded to a few dozen items)
    local allocationsByBank = {}
    local unassignedItems = {}

    for _, sortedItem in ipairs(self.sortedCartItems) do
        local plainName = sortedItem.name
        local data = sortedItem.data
        local remaining = data.qty
        local enchant = data.enchantText
        if not enchant and data.itemLink then
            enchant = getEnchantTextFromTooltip(self, data.itemLink)
            data.enchantText = enchant
        end
        if enchant then
            plainName = plainName .. " (" .. enchant .. ")"
        end

        if data.sources then
            local banks = {}
            for bn in pairs(data.sources) do
                banks[#banks + 1] = bn
            end
            table_sort(banks)
            for _, bn in ipairs(banks) do
                if remaining <= 0 then
                    break
                end
                local avail = data.sources[bn]
                if avail > 0 then
                    local take = math_min(remaining, avail)
                    if not allocationsByBank[bn] then
                        allocationsByBank[bn] = {}
                    end
                    allocationsByBank[bn][#allocationsByBank[bn] + 1] = string_format("   - %dx [%s]", take, plainName)
                    remaining = remaining - take
                end
            end
        end
        if remaining > 0 then
            unassignedItems[#unassignedItems + 1] = string_format("   - %dx [%s]", remaining, plainName)
        end
    end

    local lines = {
        "**GUILD BANK REQUEST**",
        "**Requested by:** " .. GBCR.Guild:GetNormalizedPlayerName() .. "",
        "",
        "**Requested items:**",
        ""
    }

    local bankNames = {}
    for bn in pairs(allocationsByBank) do
        bankNames[#bankNames + 1] = bn
    end
    table_sort(bankNames)
    local sv_alts = GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts or {}

    for _, bn in ipairs(bankNames) do
        local ver = sv_alts[bn] and sv_alts[bn].version or 0
        local age = ver > 0 and formatTimeAgo(ver) or "never"
        lines[#lines + 1] = string_format("- From **%s** (last updated: %s):", bn, age)
        for _, ln in ipairs(allocationsByBank[bn]) do
            lines[#lines + 1] = ln
        end
        lines[#lines + 1] = ""
    end

    if #unassignedItems > 0 then
        lines[#lines + 1] = "- From an **unknown location**:"
        for _, ln in ipairs(unassignedItems) do
            lines[#lines + 1] = ln
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "_Generated by " .. GBCR.Core.addonHeader .. "_"

    -- 3. Populate import code box
    local importStr = generateImportString(self.sortedCartItems)
    if self.cart and self.cart.importBox then
        self.cart.importBox:SetText(importStr or "nothing to do")
        self.cart.importBox:SetDisabled(false)
        if self.cart.copyImportBtn then
            self.cart.copyImportBtn:SetDisabled(importStr == nil)
        end
    end

    -- 4. Measure Discord chunk info
    local totalChars = 0
    for _, ln in ipairs(lines) do
        totalChars = totalChars + string_len(ln) + 1
    end
    local numChunks = math_ceil(totalChars / DISCORD_MAX)

    local chunkNote = numChunks > 1 and Globals.ColorizeText(Constants.COLORS.ORANGE,
                                                             string_format(
                                                                 "Note: %d characters, split into %d Discord messages (maximum %d characters each)",
                                                                 totalChars, numChunks, DISCORD_MAX)) or
                          Globals.ColorizeText(colorGray, string_format("%d characters, fits in one Discord message", totalChars))

    -- 5. Stream Discord text into exportArea (same pattern as Ledger/Export tabs)
    if not (self.cart and self.cart.exportArea) then
        return
    end
    self.cart.exportArea:ReleaseChildren()

    local idx = 1
    local function nextLine()
        if idx > #lines then
            return nil
        end
        local ln = lines[idx];
        idx = idx + 1;
        return ln
    end

    -- Info label above the stream (shows chunk count)
    local infoWrapper = aceGUI:Create("SimpleGroup")
    infoWrapper:SetFullWidth(true)
    infoWrapper:SetLayout("GBCR_TopBottom")
    self.cart.exportArea:AddChild(infoWrapper)

    local infoLabel = aceGUI:Create("Label")
    infoLabel:SetFullWidth(true)
    infoLabel:SetText(chunkNote)
    infoWrapper:AddChild(infoLabel)

    local streamGroup = aceGUI:Create("SimpleGroup")
    streamGroup:SetFullWidth(true)
    streamGroup:SetFullHeight(true)
    streamGroup:SetLayout("Fill")
    infoWrapper:AddChild(streamGroup)

    RenderStreamingTextArea(streamGroup, nextLine)
end

-- Helper to update the bottom bar cart count
local function updateBottomBar(self)
    if not self.bottomBar then
        return
    end

    local tab = self.currentTab
    local count = getCartUniqueCount(self)
    local pluralItems = count ~= 1 and "s" or ""

    -- Label always shows request count for context
    self.bottomBar.bottomBarText:SetText(string_format("%d item%s in request list", count, pluralItems))

    local btn = self.bottomBar.button
    if tab == "browse" then
        btn:SetText("View request list")
        btn:SetDisabled(count == 0)
        btn:SetCallback("OnClick", function()
            UI_Inventory.tabs:SelectTab("cart")
        end)
        -- btn:Show()
    elseif tab == "cart" then
        btn:SetText("Prepare export")
        btn:SetDisabled(count == 0)
        btn:SetCallback("OnClick", generateExport)
        -- btn:Show()
    elseif tab == "network" then
        self.bottomBar.bottomBarText:SetText("")
        btn:SetText("Force sync")
        btn:SetDisabled(false)
        btn:SetCallback("OnClick", function()
            if GBCR.Protocol:PerformSync() then
                GBCR.Output:Response("Checking for missing guild bank data from online members...")
            end
        end)
        -- btn:Show()
    else
        -- btn:SetText("Nothing to do")
        -- btn:SetDisabled(true)
        btn:SetText("View request list")
        btn:SetDisabled(count == 0)
        btn:SetCallback("OnClick", function()
            UI_Inventory.tabs:SelectTab("cart")
        end)
    end
end

-- Helper to fetch localized names for the tree filtering
local function addCategoryToTree(self, tree, value, classID, subClassID, invSlotID, overrideName)
    local name

    if value == "any" then
        name = "Everything"
        classID = -1
        subClassID = -1
    elseif overrideName then
        name = overrideName
    else
        name = subClassID and GetItemSubClassInfo(classID, subClassID) or GetItemClassInfo(classID)
    end

    local node = {value = value, text = name}
    tree[#tree + 1] = node

    self.filterCategories[value] = {classID = classID, subClassID = subClassID, invSlotID = invSlotID}

    return node
end

-- Helper to sort a node's children alphabetically by their localized name
local function sortTreeNodeChildren(node)
    if node and node.children then
        table_sort(node.children, function(a, b)
            return a.text < b.text
        end)
    end
end

-- Hook for dragging an item directly into the search box
local function onChatEdit_InsertLink(self, itemLink)
    if not self.searchField or not self.searchField:HasFocus() then
        return
    end

    local plainName = string_match(itemLink, "%[(.+)%]") or itemLink
    self.searchField:SetText(plainName)
    UI_Inventory.searchText = string_lower(plainName)

    if self.searchTimer then
        self.searchTimer:Cancel()
    end
    self.searchTimer = NewTimer(Constants.TIMER_INTERVALS.SEARCH_DEBOUNCE, function()
        UI_Inventory:Refresh()
    end)
    self.searchField:ClearFocus()
end

UI_Inventory.OnChatEdit_InsertLink = onChatEdit_InsertLink -- Expose globally for your Event Hooking module!

-- Helpers callbacks for the cart tab
local function onCartIconEnter(widget)
    local data = widget:GetUserData("itemData")
    GBCR.UI:ShowItemTooltip(data.itemLink, data.sources)
end
local function onCartIconClick(widget, event)
    local data = widget:GetUserData("itemData")
    eventHandler(data, "OnClick")
end
local function onCartIconDrag(widget, event)
    local data = widget:GetUserData("itemData")
    eventHandler(data, "OnDragStart")
end
local function onCartIconLeave()
    GBCR.UI:HideTooltip()
end
local function onCartSliderChanged(widget, event, value)
    local itemKey = widget:GetUserData("itemKey")
    UI_Inventory.cartData[itemKey].qty = value
    updateBottomBar(UI_Inventory)
    -- Mark as stale rather than re-streaming on every slider change
    if UI_Inventory.cart and UI_Inventory.cart.importBox then
        UI_Inventory.cart.importBox:SetText("change detected, click 'Prepare export'")
        UI_Inventory.cart.importBox:SetDisabled(true)
    end
    if UI_Inventory.cart.copyImportBtn then
        UI_Inventory.cart.copyImportBtn:SetDisabled(true)
    end
    -- Reset export area to placeholder
    if UI_Inventory.cart.exportArea then
        UI_Inventory.cart.exportArea:ReleaseChildren()
        local lbl = aceGUI:Create("Label")
        lbl:SetText("change detected, click 'Prepare export'")
        lbl:SetFullWidth(true)
        UI_Inventory.cart.exportArea:AddChild(lbl)
        UI_Inventory.cart.exportArea:DoLayout()
    end
end
local function onCartItemRemove(widget)
    local itemKey = widget:GetUserData("itemKey")
    UI_Inventory.cartData[itemKey] = nil
    UI_Inventory.cartCount = UI_Inventory.cartCount - 1
    updateBottomBar(UI_Inventory)
    UI_Inventory.tabs:SelectTab("cart")
end

local function getCartItemName(data, key)
    -- itemInfo is always stored at add-to-cart time; use it as the canonical source
    if data.itemInfo and not data.itemInfo.isFallback and data.itemInfo.name then
        return data.itemInfo.name
    end

    -- Real item links have the form [Thunderfury] not [item:19019]
    if data.itemLink then
        local n = string_match(data.itemLink, "%[(.-)%]")
        if n and not string_match(n, "^item:%d") then
            return n
        end
    end

    return "Item #" .. tostring(key)
end

-- Helper to draw the cart tab with a left pane for cart review and a right pane for copying text
local function drawCartTab(self, container)
    container:SetLayout("Fill")

    self.sortedCartItems = {}
    for itemKey, data in pairs(self.cartData) do
        local plainName = getCartItemName(data, itemKey)
        self.sortedCartItems[#self.sortedCartItems + 1] = {key = itemKey, data = data, name = plainName}
    end
    table_sort(self.sortedCartItems, function(a, b)
        if a.name == b.name then
            return a.key < b.key
        end

        return a.name < b.name
    end)

    local split = aceGUI:Create("SimpleGroup")
    split:SetLayout("GBCR_TwoPane")
    self.cart = split
    container:AddChild(split)

    -- Left pane
    local leftWrapper = aceGUI:Create("SimpleGroup")
    leftWrapper:SetLayout("GBCR_TopBottom")
    split:AddChild(leftWrapper)

    -- Left pane: top action buttons
    local cartActions = aceGUI:Create("SimpleGroup")
    cartActions:SetFullWidth(true)
    cartActions:SetLayout("Flow")
    leftWrapper:AddChild(cartActions)
    self.cart.actions = cartActions

    local emptyCartBtn = aceGUI:Create("Button")
    emptyCartBtn:SetText("Clear all")
    emptyCartBtn:SetRelativeWidth(0.48)
    emptyCartBtn:SetCallback("OnClick", function()
        wipe(UI_Inventory.cartData)
        UI_Inventory.cartCount = 0
        updateBottomBar(UI_Inventory)

        -- Reset import code box
        if UI_Inventory.cart.importBox then
            UI_Inventory.cart.importBox:SetText("click 'prepare export' to generate")
            UI_Inventory.cart.importBox:SetDisabled(true)
        end
        if UI_Inventory.cart.copyImportBtn then
            UI_Inventory.cart.copyImportBtn:SetDisabled(true)
        end

        -- Reset export area to placeholder
        if UI_Inventory.cart.exportArea then
            UI_Inventory.cart.exportArea:ReleaseChildren()
            local lbl = aceGUI:Create("Label")
            lbl:SetText("Your request list is empty")
            lbl:SetFullWidth(true)
            UI_Inventory.cart.exportArea:AddChild(lbl)
            UI_Inventory.cart.exportArea:DoLayout()
        end

        UI_Inventory.tabs:SelectTab("cart")
    end)
    cartActions:AddChild(emptyCartBtn)
    self.cart.actions.emptyCart = emptyCartBtn

    local refreshExportBtn = aceGUI:Create("Button")
    refreshExportBtn:SetText("Prepare export")
    refreshExportBtn:SetRelativeWidth(0.48)
    refreshExportBtn:SetCallback("OnClick", generateExport)
    cartActions:AddChild(refreshExportBtn)
    self.cart.actions.refreshExport = refreshExportBtn

    -- Left pane: grouping beneath top action buttons
    local leftPane = aceGUI:Create("InlineGroup")
    leftPane:SetTitle("")
    leftPane:SetLayout("Fill")
    leftWrapper:AddChild(leftPane)
    self.cart.leftPane = leftPane

    -- Left pane: scroll list within the grouping
    local cartScroll = aceGUI:Create("ScrollFrame")
    cartScroll:SetLayout("Flow")
    leftPane:AddChild(cartScroll)
    self.cart.leftPane.scroll = cartScroll

    -- -- Right pane
    -- local rightPane = aceGUI:Create("InlineGroup")
    -- rightPane:SetTitle("Final step: export your request")
    -- rightPane:SetLayout("Fill")
    -- split:AddChild(rightPane)
    -- self.cart.rightPane = rightPane

    -- -- Right pane: text that can be copied and pasted in Discord for manually requesting the contents of the cart
    -- local exportBox = aceGUI:Create("MultiLineEditBox")
    -- exportBox:SetLabel("")
    -- exportBox:SetText(
    --     "How to request items from guild banks?\n\n1. Browse for items and add to your request list\n\n2. Review and modify your request list\n\n3. Click the prepare export button\n\n4. Since guild banks aren't always online, simply copy your list and paste it into your guild's Discord\n\n5. Check your in-game mail later")
    -- exportBox:DisableButton(true)
    -- exportBox:SetDisabled(true)
    -- exportBox.label:SetFontObject(GameFontNormal)
    -- local function testfn()
    --     exportBox.editBox:HighlightText()
    -- end
    -- -- exportBox.editBox:HookScript("OnCursorChanged", testfn)
    -- -- exportBox.editBox:HookScript("OnEditFocusLost", testfn)
    -- -- exportBox.editBox:HookScript("OnEnter", testfn)
    -- -- exportBox.editBox:HookScript("OnEscapePressed", testfn)
    -- -- exportBox.editBox:HookScript("OnLeave", testfn)
    -- -- exportBox.editBox:HookScript("OnMouseDown", testfn)
    -- -- exportBox.editBox:HookScript("OnReceiveDrag", testfn)
    -- -- exportBox.editBox:HookScript("OnTextChanged", testfn)
    -- -- exportBox.editBox:HookScript("OnTextSet", testfn)
    -- -- exportBox.editBox:HookScript("OnEditFocusGained", testfn)
    -- rightPane:AddChild(exportBox)
    -- self.cart.rightPane.exportBox = exportBox

    local rightWrapper = aceGUI:Create("SimpleGroup")
    rightWrapper:SetLayout("GBCR_TopBottom")
    split:AddChild(rightWrapper)
    self.cart.rightPane = rightWrapper -- keep reference name for compatibility

    -- TOP: Import code (compact, always present after export)
    local importGroup = aceGUI:Create("InlineGroup")
    importGroup:SetTitle("Import code")
    importGroup:SetFullWidth(true)
    importGroup:SetLayout("List")
    rightWrapper:AddChild(importGroup)

    local importHint = aceGUI:Create("Label")
    importHint:SetFullWidth(true)
    importHint:SetText("Share with guild banks to fulfill your request:")
    importGroup:AddChild(importHint)

    local importBox = aceGUI:Create("EditBox")
    importBox:SetLabel("")
    importBox:SetFullWidth(true)
    importBox:SetText("click 'Prepare export' to generate")
    importBox:SetDisabled(true)
    importGroup:AddChild(importBox)
    self.cart.importBox = importBox

    local copyImportBtn = aceGUI:Create("Button")
    copyImportBtn:SetText("Copy import code")
    copyImportBtn:SetFullWidth(true)
    copyImportBtn:SetDisabled(true)
    copyImportBtn:SetCallback("OnClick", function()
        local code = UI_Inventory.cart and UI_Inventory.cart.importBox and UI_Inventory.cart.importBox:GetText()
        if code and string_match(code, "^" .. IMPORT_PREFIX) then
            ShowCopyDialog("Import code", code)
        end
    end)
    importGroup:AddChild(copyImportBtn)
    self.cart.copyImportBtn = copyImportBtn

    -- BOTTOM: Discord export (streaming, same pattern as Ledger/Export tabs)
    local exportArea = aceGUI:Create("SimpleGroup")
    exportArea:SetFullWidth(true)
    exportArea:SetFullHeight(true)
    exportArea:SetLayout("Fill")
    rightWrapper:AddChild(exportArea)
    self.cart.exportArea = exportArea

    local placeholder = aceGUI:Create("Label")
    placeholder:SetFullWidth(true)
    placeholder:SetText("How to request items from guild banks:\n\n" .. "1. Browse and add items to your request list\n\n" ..
                            "2. Click 'Prepare export' to generate both the import code and Discord text\n\n" ..
                            "3. Since guild banks aren't always online, simply share the import code (above) and paste it into your guild's Discord\n\n" ..
                            "4. Guild banks paste the import code in a secret 'Request fulfillment' tab to see exactly what to pull and mail\n\n" ..
                            "5. Check your in-game mail later for the items")
    exportArea:AddChild(placeholder)

    if getCartUniqueCount(self) == 0 then
        local empty = aceGUI:Create("Label")
        empty:SetText("Your request list is empty, browse to add items")
        empty:SetFullWidth(true)
        empty:SetFontObject(GameFontHighlight)
        cartScroll:AddChild(empty)
    else
        for _, sortedItem in ipairs(self.sortedCartItems) do
            local itemKey = sortedItem.key
            local data = sortedItem.data
            local plainName = sortedItem.name

            local row = aceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Table")
            row:SetUserData("table", {columns = {50, 1, 110}}) -- icon, slider (fill), button

            local btn = aceGUI:Create(self.itemButtonWidgetType)
            btn:SetWidth(40)
            btn:SetIcon(data.itemInfo and data.itemInfo.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            if data.itemInfo and data.itemInfo.rarity then
                local r, g, b = GetItemQualityColor(data.itemInfo.rarity)
                btn.border:SetVertexColor(r, g, b)
                btn.border:Show()
            else
                btn.border:SetVertexColor(1, 1, 1)
                btn.border:Show()
            end
            btn:SetUserData("itemData", data)
            btn:SetCallback("OnEnter", onCartIconEnter)
            btn:SetCallback("OnClick", onCartIconClick)
            btn:SetCallback("OnDragStart", onCartIconDrag)
            btn:SetCallback("OnLeave", onCartIconLeave)
            row:AddChild(btn)

            local qtySlider = aceGUI:Create("Slider")
            qtySlider:SetFullWidth(true)
            qtySlider:SetLabel(plainName)
            qtySlider:SetSliderValues(1, data.itemCount, 1)
            qtySlider:SetValue(data.qty)
            qtySlider:SetUserData("itemKey", itemKey)
            qtySlider:SetCallback("OnValueChanged", onCartSliderChanged)
            row:AddChild(qtySlider)

            local delBtn = aceGUI:Create("Button")
            delBtn:SetText("Remove")
            delBtn:SetWidth(100)
            delBtn:SetUserData("itemKey", itemKey)
            delBtn:SetCallback("OnClick", onCartItemRemove)
            row:AddChild(delBtn)

            cartScroll:AddChild(row)
        end
    end

    -- generateExport()
end

local function buildExportMetadata()
    local sv = GBCR.Database and GBCR.Database.savedVariables
    local guild = (sv and sv.guildName) or "Unknown Guild"
    local realm = (sv and sv.realm) or GetRealmName() or "Unknown Realm"
    local player = GBCR.Guild:GetNormalizedPlayerName()
    local version = GBCR.Core.addonVersion or "?"
    local now = GetServerTime()

    return {exportTime = date("%Y-%m-%d %H:%M:%S", now), guild = guild, realm = realm, character = player, version = version}
end

local function metadataHeader(meta, formatLabel)
    return table_concat({
        "-- GBankClassic Revived Export (" .. formatLabel .. ") --",
        "Generated : " .. meta.exportTime,
        "Guild     : " .. meta.guild .. " @ " .. meta.realm,
        "Character : " .. meta.character,
        "Addon     : " .. meta.version,
        ""
    }, "\n")
end

-- Helper to draw the ledger tab
local function drawLedgerTab(self, container)
    container:SetLayout("GBCR_TopBottom")
    local sv = GBCR.Database.savedVariables

    -- Track active sub-view: "ledger", "export", or "donors"
    local currentView = "ledger"

    -- Top container
    local controlGroup = aceGUI:Create("SimpleGroup")
    controlGroup:SetFullWidth(true)
    controlGroup:SetLayout("Flow")
    container:AddChild(controlGroup)

    local altDropdown = aceGUI:Create("Dropdown")
    altDropdown:SetLabel("Filter on guild bank")
    altDropdown:SetWidth(250)
    local altList = {["Show all guild banks"] = "Show all guild banks"}
    local altOrder = {"Show all guild banks"}
    if sv and sv.alts then
        local sorted = {}
        for name in pairs(sv.alts) do
            sorted[#sorted + 1] = name
        end
        table_sort(sorted)
        for _, name in ipairs(sorted) do
            altList[name] = name
            altOrder[#altOrder + 1] = name
        end
    end
    altDropdown:SetList(altList, altOrder)
    altDropdown:SetValue("Show all guild banks")
    controlGroup:AddChild(altDropdown)

    local ledgerBtn = aceGUI:Create("Button")
    ledgerBtn:SetText("Show ledger")
    ledgerBtn:SetWidth(140)
    controlGroup:AddChild(ledgerBtn)

    local donorsBtn = aceGUI:Create("Button")
    donorsBtn:SetText("Show donors")
    donorsBtn:SetWidth(140)
    controlGroup:AddChild(donorsBtn)

    local exportBtn = aceGUI:Create("Button")
    exportBtn:SetText("Prepare export")
    exportBtn:SetWidth(140)
    controlGroup:AddChild(exportBtn)

    -- Bottom container
    local bottomArea = aceGUI:Create("SimpleGroup")
    bottomArea:SetFullWidth(true)
    bottomArea:SetFullHeight(true)
    bottomArea:SetLayout("Fill")
    container:AddChild(bottomArea)

    local ledgerVS = nil

    local function renderLedgerRow(frame, row, index)
        if not frame.GBCR_ledger_init then
            frame.GBCR_ledger_init = true

            local headerBg = frame:CreateTexture(nil, "BACKGROUND")
            headerBg:SetAllPoints(frame)
            headerBg:SetColorTexture(0.18, 0.18, 0.18, 0.85)
            frame.headerBg = headerBg

            local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerText:SetPoint("LEFT", frame, "LEFT", 6, 0)
            headerText:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
            headerText:SetJustifyH("LEFT")
            headerText:SetJustifyV("MIDDLE")
            frame.headerText = headerText

            local iconTex = frame:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(20, 20)
            iconTex:SetPoint("LEFT", frame, "LEFT", 2, 0)
            frame.iconTex = iconTex

            local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            timeText:SetPoint("LEFT", frame, "LEFT", 26, 0)
            timeText:SetWidth(46)
            timeText:SetJustifyH("LEFT")
            timeText:SetJustifyV("MIDDLE")
            frame.timeText = timeText

            local descText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            descText:SetPoint("LEFT", frame, "LEFT", 76, 0)
            descText:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
            descText:SetJustifyH("LEFT")
            descText:SetJustifyV("MIDDLE")
            descText:SetWordWrap(false)
            frame.descText = descText
        end

        frame.headerBg:Hide()
        frame.headerText:Hide()
        frame.iconTex:Hide()
        frame.timeText:Hide()
        frame.descText:Hide()

        if row.isHeader then
            frame.headerBg:Show()
            frame.headerText:SetText(Globals.ColorizeText(colorYellow, row.text))
            frame.headerText:Show()
        else
            frame.iconTex:SetTexture(row.iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
            frame.iconTex:Show()
            frame.timeText:SetText(Globals.ColorizeText(colorGray, row.timeStr or ""))
            frame.timeText:Show()
            frame.descText:SetText(row.desc or "")
            frame.descText:Show()
        end
    end

    local function startBuildLedgerRows(entries, getVS, myGen, getGen)
        local rows = {}
        local currentDate = ""
        local ROW_BATCH = 30
        local index = 1

        local function buildRows()
            if getGen() ~= myGen then
                return
            end

            local endIndex = math_min(index + ROW_BATCH - 1, #entries)
            for i = index, endIndex do
                local w = entries[i]
                local entryDate = date("%b %d, %Y", w.entry[1])
                if entryDate ~= currentDate then
                    currentDate = entryDate
                    rows[#rows + 1] = {isHeader = true, text = entryDate}
                end
                local timeStr, iconPath, desc = GBCR.Ledger:FormatEntry(w.entry, w.altName)
                if timeStr and desc then
                    rows[#rows + 1] = {timeStr = timeStr, iconPath = iconPath, desc = desc}
                end
            end
            index = endIndex + 1
            local vs = getVS()
            if index <= #entries then
                if vs then
                    vs:SetData(rows)
                end
                After(0, buildRows)
            else
                if #rows == 0 then
                    rows[1] = {isHeader = true, text = "No ledger entries yet"}
                end
                if vs then
                    vs:SetData(rows)
                end
            end
        end
        After(0, buildRows)
    end

    local populateLedgerGen = 0
    local donorsViewGen = 0

    local function populateLedger(selectedAlt)
        populateLedgerGen = populateLedgerGen + 1
        local myGen = populateLedgerGen

        -- Phase 1: collect entries (async for "Show all guild banks" due to potential 20k+ entries)
        -- Phase 2: sort once (sync; capped at MAX_ENTRIES)
        -- Phase 3: build VirtualScroll rows via batched FormatEntry (async)

        local MAX_ENTRIES = 5000 -- cap before sort to keep sort < 5ms
        local DISPLAY_CAP = 300 -- rows shown in live view
        local COLLECT_BATCH = 1000 -- entries collected per frame
        local ROW_BATCH = 30 -- FormatEntry calls per frame (each may call GetItemInfo)

        if selectedAlt ~= "Show all guild banks" then
            -- Single alt: small ledger, can collect synchronously
            local altData = sv and sv.alts and sv.alts[selectedAlt]
            local entries = {}
            if altData and altData.ledger then
                for _, e in ipairs(altData.ledger) do
                    entries[#entries + 1] = {entry = e, altName = selectedAlt}
                end
            end
            -- Single alt ledger is at most LEDGER.MAX_ENTRIES=200, sort is instant
            table_sort(entries, function(a, b)
                return a.entry[1] > b.entry[1]
            end)

            -- Async row build
            startBuildLedgerRows(entries, function()
                return ledgerVS
            end, myGen, function()
                return populateLedgerGen
            end)

            return
        end

        -- "Show all guild banks": async collection across all alts
        local entries = {}
        local altPairs = {}
        if sv and sv.alts then
            for name, data in pairs(sv.alts) do
                if data.ledger and #data.ledger > 0 then
                    altPairs[#altPairs + 1] = {name = name, ledger = data.ledger}
                end
            end
        end

        local altIndex = 1
        local entryIndex = 1

        local function collectBatch()
            if myGen ~= populateLedgerGen then
                return
            end

            local collected = 0
            while altIndex <= #altPairs and #entries < MAX_ENTRIES do
                local alt = altPairs[altIndex]
                while entryIndex <= #alt.ledger and #entries < MAX_ENTRIES do
                    entries[#entries + 1] = {entry = alt.ledger[entryIndex], altName = alt.name}
                    entryIndex = entryIndex + 1
                    collected = collected + 1
                    if collected >= COLLECT_BATCH then
                        After(0, collectBatch)

                        return
                    end
                end
                altIndex = altIndex + 1
                entryIndex = 1
            end

            -- Collection done, sort once (<5000 entries, fast in C)
            table_sort(entries, function(a, b)
                return a.entry[1] > b.entry[1]
            end)

            -- Keep only the most recent DISPLAY_CAP entries
            for i = DISPLAY_CAP + 1, #entries do
                entries[i] = nil
            end

            -- Async row build
            startBuildLedgerRows(entries, function()
                return ledgerVS
            end, myGen, function()
                return populateLedgerGen
            end)
        end

        After(0, collectBatch)
    end

    local function clearLedgerBottomArea()
        populateLedgerGen = populateLedgerGen + 1
        donorsViewGen = donorsViewGen + 1

        if ledgerVS then
            ledgerVS:Destroy()
            ledgerVS = nil
        end
        bottomArea:ReleaseChildren()
    end

    local function ShowLedgerView()
        currentView = "ledger"
        clearLedgerBottomArea()

        local vsGroup = aceGUI:Create("SimpleGroup")
        vsGroup:SetFullWidth(true)
        vsGroup:SetFullHeight(true)
        vsGroup:SetLayout("Fill")

        vsGroup:SetCallback("OnRelease", function()
            if ledgerVS then
                ledgerVS:Destroy()
                ledgerVS = nil
            end
        end)

        bottomArea:AddChild(vsGroup)
        ledgerVS = VirtualScroll:New(vsGroup, 26, renderLedgerRow)
        populateLedger(altDropdown:GetValue())
    end

    local function ShowExportView(headerText, altName)
        currentView = "export"
        clearLedgerBottomArea()

        bottomArea:SetLayout("Fill")

        -- Build a line iterator for the requested alt(s)
        local headerLines = {}
        for line in string_gmatch(headerText .. "\n", "([^\n]*)\n") do
            headerLines[#headerLines + 1] = line
        end

        local altsToExport = {}
        if altName ~= "Show all guild banks" then
            altsToExport[1] = altName
        else
            if sv and sv.alts then
                for name in pairs(sv.alts) do
                    altsToExport[#altsToExport + 1] = name
                end
                table_sort(altsToExport)
            end
        end

        local hIndex = 1
        local aIndex = 1
        local eIndex = 1
        local curLed = nil -- current alt's ledger array

        local function nextLine()
            -- 1. Yield header lines first
            if hIndex <= #headerLines then
                local l = headerLines[hIndex]
                hIndex = hIndex + 1

                return l
            end
            -- 2. Yield ledger entries per alt
            while aIndex <= #altsToExport do
                local name = altsToExport[aIndex]
                local altData = sv and sv.alts and sv.alts[name]
                if not curLed then
                    curLed = altData and altData.ledger or {}
                    eIndex = 1

                    if #altsToExport > 1 then
                        return string_format("=== %s ===", name)
                    end
                end
                while eIndex <= #curLed do
                    local e = curLed[eIndex]
                    eIndex = eIndex + 1

                    local _, _, desc = GBCR.Ledger:FormatEntry(e, name)
                    if desc then
                        return string_format("[%s] %s", date("%Y-%m-%d %H:%M", e[1]), desc)
                    end
                end
                -- Move to next alt
                curLed = nil
                aIndex = aIndex + 1
            end

            return nil -- done
        end

        RenderStreamingTextArea(bottomArea, nextLine)
    end

    local function ShowDonorsView()
        donorsViewGen = donorsViewGen + 1
        local myDonorsGen = donorsViewGen

        currentView = "donors"
        clearLedgerBottomArea()

        local priceCache = {}
        local donations = {}

        local selectedAlt = altDropdown:GetValue()

        -- Collect alts to process
        local altPairs = {}
        if sv and sv.alts then
            for name, data in pairs(sv.alts) do
                if (selectedAlt == "Show all guild banks" or name == selectedAlt) and data.ledger and #data.ledger > 0 then
                    altPairs[#altPairs + 1] = {name = name, ledger = data.ledger}
                end
            end
        end

        local altIndex = 1
        local ledgerIndex = 1
        local BATCH = 500

        -- Loading indicator
        local loadLabel = aceGUI:Create("Label")
        loadLabel:SetFullWidth(true)
        loadLabel:SetText("Calculating donors...")
        bottomArea:AddChild(loadLabel)

        local function processBatch()
            if myDonorsGen ~= donorsViewGen then
                return
            end

            local count = 0

            while altIndex <= #altPairs do
                local alt = altPairs[altIndex]

                while ledgerIndex <= #alt.ledger do
                    local e = alt.ledger[ledgerIndex]
                    local itemId = e[2]
                    local cnt = e[5]
                    local actorUid = e[6]
                    local opCode = e[7]

                    if (opCode == Constants.LEDGER_OPERATION.MAIL_IN or opCode == Constants.LEDGER_OPERATION.TRADE_IN) and
                        actorUid and actorUid ~= "" then

                        local value = 0
                        if itemId == 0 then
                            value = cnt
                        else
                            if not priceCache[itemId] then
                                local price = select(11, GetItemInfo(itemId))
                                priceCache[itemId] = (price and price > 0) and price or 1
                            end
                            value = priceCache[itemId] * cnt
                        end
                        donations[actorUid] = (donations[actorUid] or 0) + value
                    end

                    ledgerIndex = ledgerIndex + 1

                    count = count + 1
                    if count >= BATCH then
                        After(0, processBatch)

                        return
                    end
                end

                altIndex = altIndex + 1
                ledgerIndex = 1
            end

            if myDonorsGen ~= donorsViewGen then
                return
            end

            clearLedgerBottomArea()

            local sortedDonors = {}
            for uid, val in pairs(donations) do
                sortedDonors[#sortedDonors + 1] = {uid = uid, val = val}
            end
            table_sort(sortedDonors, function(a, b)
                return a.val > b.val
            end)

            local scroll = aceGUI:Create("ScrollFrame")
            scroll:SetLayout("Table")
            scroll:SetUserData("table", {columns = {{width = 30}, {width = 0.6}, {width = 0.4}}, spaceH = 10, spaceV = 5})
            scroll:SetFullWidth(true)
            scroll:SetFullHeight(true)

            local function hdr(txt)
                local l = aceGUI:Create("Label")
                l:SetText(txt)
                scroll:AddChild(l)
            end

            hdr("")
            hdr("Top 30 donors")
            hdr("Vendor value")

            -- header3:SetCallback("OnEnter", function(widget)
            --     GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
            --     GameTooltip:SetText("Total value to sell to a vendor", 1, 1, 1, 1, true)
            --     GameTooltip:AddLine("Items with no sell price are valued at 1 copper for the ledger", 1, 1, 1, true)
            --     GameTooltip:Show()
            -- end)
            -- header3:SetCallback("OnLeave", function()
            --     GameTooltip:Hide()
            -- end)

            local guild = GBCR.Guild
            for index = 1, math_min(30, #sortedDonors) do
                local d = sortedDonors[index]
                local color = colorGray
                local playerName = guild:FindGuildMemberByUid(d.uid)
                local cls = playerName and guild:GetGuildMemberInfo(playerName)
                if cls then
                    color = select(4, Globals.GetClassColor(cls))
                end

                local rankLbl = aceGUI:Create("Label")
                rankLbl:SetText(string_format((index < 10) and "  %d)" or " %d)", index))
                scroll:AddChild(rankLbl)

                local nameLbl = aceGUI:Create("Label")
                nameLbl:SetText(Globals.ColorizeText(color, playerName or d.uid))
                scroll:AddChild(nameLbl)

                local valLbl = aceGUI:Create("Label")
                valLbl:SetText(Globals.ColorizeText(color, Globals.GetCoinTextureString(math_floor(d.val))))
                scroll:AddChild(valLbl)
            end

            if #sortedDonors == 0 then
                local empty = aceGUI:Create("Label")
                empty:SetText("No donations recorded yet")
                scroll:AddChild(empty)
            end

            bottomArea:AddChild(scroll)
        end

        After(0, processBatch)
    end

    -- local function ShowDonorsView()
    --     currentView = "donors"
    --     clearLedgerBottomArea()

    --     local scrollContainer = aceGUI:Create("ScrollFrame")
    --     scrollContainer:SetLayout("Table")
    --     scrollContainer:SetUserData("table", {
    --         columns = {
    --             {width = 30, align = "CENTERRIGHT"},
    --             {width = 0.6, alignH = "start", alignV = "middle"},
    --             {width = 0.4, alignH = "end", alignV = "middle"}
    --         },
    --         spaceH = 10,
    --         spaceV = 5
    --     })
    --     scrollContainer:SetFullWidth(true)
    --     scrollContainer:SetFullHeight(true)

    --     local selectedAlt = altDropdown:GetValue()
    --     local donations = {}

    --     local function processLedgerForDonations(ledger)
    --         for _, e in ipairs(ledger) do
    --             local itemId, count, actorUid, opCode = e[2], e[5], e[6], e[7]

    --             -- Check for valid player contributions
    --             if (opCode == Constants.LEDGER_OPERATION.MAIL_IN or opCode == Constants.LEDGER_OPERATION.TRADE_IN) and
    --                 (actorUid and actorUid ~= "") then

    --                 local value = 0
    --                 if itemId == 0 then
    --                     value = count
    --                 else
    --                     local price = select(11, GetItemInfo(itemId))
    --                     local effectivePrice = (price and price > 0) and price or 1
    --                     value = effectivePrice * count
    --                 end

    --                 donations[actorUid] = (donations[actorUid] or 0) + value
    --             end
    --         end
    --     end

    --     if selectedAlt == "Show all guild banks" then
    --         if sv and sv.alts then
    --             for _, altData in pairs(sv.alts) do
    --                 if altData.ledger then
    --                     processLedgerForDonations(altData.ledger)
    --                 end
    --             end
    --         end
    --     else
    --         local altData = sv and sv.alts and sv.alts[selectedAlt]
    --         if altData and altData.ledger then
    --             processLedgerForDonations(altData.ledger)
    --         end
    --     end

    --     local sortedDonors = {}
    --     for uid, val in pairs(donations) do
    --         sortedDonors[#sortedDonors + 1] = {uid = uid, val = val}
    --     end
    --     table_sort(sortedDonors, function(a, b)
    --         return a.val > b.val
    --     end)

    --     local header1 = aceGUI:Create("Label")
    --     header1:SetText("")
    --     scrollContainer:AddChild(header1)
    --     local header2 = aceGUI:Create("Label")
    --     header2:SetText("Top 30 donors")
    --     scrollContainer:AddChild(header2)

    --     local header3 = aceGUI:Create("InteractiveLabel")
    --     header3:SetText("Vendor value")
    --     header3:SetCallback("OnEnter", function(widget)
    --         GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
    --         GameTooltip:SetText("Total value to sell to a vendor", 1, 1, 1, 1, true)
    --         GameTooltip:AddLine("Items with no sell price are valued at 1 copper for the ledger", 1, 1, 1, true)
    --         GameTooltip:Show()
    --     end)
    --     header3:SetCallback("OnLeave", function()
    --         GameTooltip:Hide()
    --     end)
    --     scrollContainer:AddChild(header3)

    --     local guild = GBCR.Guild
    --     for index, data in ipairs(sortedDonors) do
    --         -- if index <= 30 then
    --         local rank = aceGUI:Create("Label")
    --         rank:SetText(string_format((index < 10) and "  %d)" or " %d)", index))
    --         scrollContainer:AddChild(rank)

    --         local color = colorGray
    --         local playerClass = guild:GetGuildMemberInfo(data.uid)
    --         if playerClass then
    --             color = select(4, Globals.GetClassColor(playerClass))
    --         end

    --         local donatedBy = aceGUI:Create("Label")
    --         donatedBy:SetText(Globals.ColorizeText(color, data.uid))
    --         scrollContainer:AddChild(donatedBy)

    --         local donationValue = aceGUI:Create("Label")
    --         donationValue:SetText(Globals.ColorizeText(color, Globals.GetCoinTextureString(math_floor(data.val))))
    --         scrollContainer:AddChild(donationValue)
    --         -- end
    --     end

    --     if #sortedDonors == 0 then
    --         local empty = aceGUI:Create("Label")
    --         empty:SetText("No donations recorded yet")
    --         scrollContainer:AddChild(empty)
    --     end

    --     bottomArea:AddChild(scrollContainer)
    -- end

    ledgerBtn:SetCallback("OnClick", function()
        ShowLedgerView()
    end)

    donorsBtn:SetCallback("OnClick", function()
        ShowDonorsView()
    end)

    exportBtn:SetCallback("OnClick", function()
        local meta = buildExportMetadata()
        local selected = altDropdown:GetValue()
        ShowExportView(metadataHeader(meta, "Ledger"), selected)
        -- local lines = {metadataHeader(meta, "Ledger")}

        -- if selected ~= "Show all guild banks" then
        --     -- Single alt: async export, show view when done
        --     ShowExportView("Building ledger export, please wait...")
        --     GBCR.Ledger:ExportLedger(selected, function(text)
        --         lines[#lines + 1] = text
        --         ShowExportView(table_concat(lines, "\n"))
        --     end)

        --     return
        -- end

        -- ShowExportView("Building ledger export, please wait...")
        -- if not sv or not sv.alts then
        --     ShowExportView(table_concat(lines, "\n"))

        --     return
        -- end

        -- local altNames = {}
        -- for name in pairs(sv.alts) do
        --     altNames[#altNames + 1] = name
        -- end
        -- local altIndex = 1

        -- -- processNextAlt chains async ExportLedger calls: each alt yields to the next
        -- -- frame between its own batches, and processNextAlt itself yields between alts
        -- local function processNextAlt()
        --     if altIndex > #altNames then
        --         ShowExportView(table_concat(lines, "\n"))

        --         return
        --     end

        --     local name = altNames[altIndex]
        --     altIndex = altIndex + 1
        --     GBCR.Ledger:ExportLedger(name, function(text)
        --         if text and text ~= "No ledger entries" and text ~= "" then
        --             lines[#lines + 1] = text
        --             lines[#lines + 1] = ""
        --         end
        --         After(0, processNextAlt)
        --     end)
        -- end

        -- After(0, processNextAlt)
    end)

    altDropdown:SetCallback("OnValueChanged", function(_, _, value)
        if currentView == "ledger" then
            if ledgerVS then
                populateLedger(value)
            else
                ShowLedgerView()
            end
        elseif currentView == "donors" then
            ShowDonorsView()
        else
            ShowLedgerView()
        end
    end)

    self.refreshLedger = function()
        -- print(" -- refreshLedger called -- ")
        if currentView == "ledger" and ledgerVS then
            populateLedger(altDropdown:GetValue())
        elseif currentView == "donors" then
            ShowDonorsView()
        end
    end

    ShowLedgerView()
end

-- Helper to draw the request import/management tab
local function drawFulfillmentTab(self, container)
    container:SetLayout("GBCR_TopBottom")

    -- Generation counter: incremented by the tab-switch callback before ReleaseChildren.
    -- Any in-flight batch sees a stale generation and exits cleanly.
    self.requestsTabGeneration = (self.requestsTabGeneration or 0) + 1
    local myGen = self.requestsTabGeneration

    -- Top controls (stacked vertically so label, input, button, status are aligned)
    local topGroup = aceGUI:Create("SimpleGroup")
    topGroup:SetFullWidth(true)
    topGroup:SetLayout("List")
    topGroup:SetCallback("OnRelease", function()
        if self.inputLabel then
            self.inputLabel:Hide()
            self.inputLabel:SetParent(UIParent)
        end
    end)
    self.fulfillmentTopGroup = topGroup
    container:AddChild(topGroup)

    local inputLabel = self.inputLabel
    if not inputLabel then
        inputLabel = topGroup.frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        self.inputLabel = inputLabel
    end
    inputLabel:SetText("Paste import code (starts with " .. Constants.IMPORT_PREFIX .. ")")
    inputLabel:SetFontObject(GameFontNormal)
    inputLabel:SetParent(topGroup.frame)
    inputLabel:ClearAllPoints()
    inputLabel:SetPoint("TOPLEFT", topGroup.frame, "TOPLEFT", 0, 16)
    inputLabel:SetHeight(44)
    inputLabel:Show()
    self.fulfillmentInputLabel = inputLabel

    local inputLabelOriginal = aceGUI:Create("Label")
    inputLabelOriginal:SetFullWidth(true)
    inputLabelOriginal:SetText(" ")
    inputLabelOriginal.label:SetFontObject(GameFontNormal)
    self.fulfillmentInputLabelOriginal = inputLabelOriginal
    topGroup:AddChild(inputLabelOriginal)

    -- Row: editbox fills width, button is fixed on the right
    local inputRow = aceGUI:Create("SimpleGroup")
    inputRow:SetFullWidth(true)
    inputRow:SetLayout("Table")
    inputRow:SetUserData("table", {columns = {0.8, 0.2}})
    self.fulfillmentInputRow = inputRow
    topGroup:AddChild(inputRow)

    local importInput = aceGUI:Create("EditBox")
    importInput:SetLabel("") -- label text moved above
    importInput:SetFullWidth(true)
    if importInput.label then
        importInput.label:Hide()
    end
    self.fulfillmentImportInput = importInput
    inputRow:AddChild(importInput)

    local parseBtn = aceGUI:Create("Button")
    parseBtn:SetText("Load request")
    parseBtn:SetFullWidth(true)
    self.fulfillmentParseBtn = parseBtn
    inputRow:AddChild(parseBtn)

    local statusLabel = aceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    statusLabel:SetText("")
    statusLabel.label:SetFontObject(GameFontNormal)
    self.fulfillmentStatusLabel = statusLabel
    topGroup:AddChild(statusLabel)

    -- Bottom: fulfillment table
    local bottomGroup = aceGUI:Create("InlineGroup")
    bottomGroup:SetTitle("What to retrieve from where")
    bottomGroup:SetFullWidth(true)
    bottomGroup:SetFullHeight(true)
    bottomGroup:SetLayout("Fill")
    bottomGroup.titletext:ClearAllPoints()
    bottomGroup.titletext:SetPoint("TOPLEFT", bottomGroup.frame, "TOPLEFT", 0, 0)
    self.fulfillmentBottomGroup = bottomGroup
    container:AddChild(bottomGroup)

    local scroll = aceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    bottomGroup:AddChild(scroll)

    local function renderFulfillment(requestData)
        scroll:ReleaseChildren()

        -- Fixed header
        local hdr = aceGUI:Create("Label")
        hdr:SetFullWidth(true)
        hdr:SetText(string_format("Request from %s, created %s",
                                  Globals.ColorizeText(Constants.COLORS.GOLD, requestData.r or "unknown"),
                                  formatTimeAgo(requestData.t or 0)))
        scroll:AddChild(hdr)

        local sp1 = aceGUI:Create("Label")
        sp1:SetText(" ")
        scroll:AddChild(sp1)

        -- Rank gate
        do
            local _rf = GBCR.Options:GetRankFulfillment()
            local _rk = requestData.rk
            if _rk ~= nil and next(_rf) ~= nil and not _rf[_rk + 1] then
                local _rkName = GBCR.Guild.cachedGuildRankNames and GBCR.Guild.cachedGuildRankNames[_rk]
                local _rkLabel = _rkName and string_format(" (%s)", _rkName) or string_format(" (rank %d)", _rk)
                local _denied = aceGUI:Create("Label")
                _denied:SetFullWidth(true)
                _denied:SetText(Globals.ColorizeText(Constants.COLORS.RED, "Access restricted: this bank does not serve" ..
                                                         _rkLabel .. ".\nNo items should be sent to this requester."))
                scroll:AddChild(_denied)

                return
            end
        end

        -- Per-location item counts (always fast; cache is in-memory)
        local myName = GBCR.Guild:GetNormalizedPlayerName()
        local sv_ = GBCR.Database.savedVariables
        local myAlt = sv_ and sv_.alts and sv_.alts[myName]
        local cache = myAlt and myAlt.cache

        local function countById(arr)
            local t = {}
            for _, item in ipairs(arr or {}) do
                local id = tonumber(string_match(item.itemString or "", "^(%d+)"))
                if id then
                    t[id] = (t[id] or 0) + (item.itemCount or 0)
                end
            end

            return t
        end
        local inBags = countById(cache and cache.bags)
        local inBank = countById(cache and cache.bank)
        local inMail = countById(cache and cache.mail)

        -- Column header row (fixed, not part of the async batch)
        local colHdr = aceGUI:Create("SimpleGroup")
        colHdr:SetFullWidth(true)
        colHdr:SetLayout("Table")
        colHdr:SetUserData("table", {columns = {0, 55, 55, 55, 55}})
        local function hLabel(txt)
            local l = aceGUI:Create("Label")
            l:SetText(Globals.ColorizeText(Constants.COLORS.GOLD, txt))
            colHdr:AddChild(l)
        end
        hLabel("Item")
        hLabel("Need")
        hLabel("Bags")
        hLabel("Bank")
        hLabel("Mail")
        scroll:AddChild(colHdr)

        -- Async batch state
        local itemEntries = requestData.i or {}
        local totalEntries = #itemEntries
        local batchPosition = 1
        local BATCH = 20
        local canSendItems = {}
        local totalUnmet = 0

        -- Summary section built after all item rows are created
        local function addSummarySection()
            local sp2 = aceGUI:Create("Label")
            sp2:SetText(" ")
            scroll:AddChild(sp2)

            local pluralItems = (#canSendItems ~= 1 and "s" or "")
            local pluralUnmet = (totalUnmet ~= 1 and "s" or "")

            if totalUnmet > 0 then
                local warn = aceGUI:Create("Label")
                warn:SetFullWidth(true)
                warn:SetText(Globals.ColorizeText(Constants.COLORS.ORANGE, string_format(
                                                      "Warning: %d item%s cannot be fully fulfilled from current stock.",
                                                      totalUnmet, pluralUnmet)))
                scroll:AddChild(warn)
            end

            if #canSendItems == 0 then
                local none = aceGUI:Create("Label")
                none:SetFullWidth(true)
                none:SetText(Globals.ColorizeText(Constants.COLORS.GRAY,
                                                  "Nothing sendable from bags right now. Pull items from bank first."))
                scroll:AddChild(none)

                return
            end

            local note = aceGUI:Create("Label")
            note:SetFullWidth(true)
            note:SetText(string_format("%d item%s ready in bags.\nItems in bank must be taken out before mailing.\n" ..
                                           "Each mail holds up to 12 unique item stacks.", #canSendItems, pluralItems))
            scroll:AddChild(note)

            local sp3 = aceGUI:Create("Label")
            sp3:SetText(" ")
            scroll:AddChild(sp3)

            for batchStart = 1, #canSendItems, 12 do
                local batchEnd = math_min(batchStart + 11, #canSendItems)
                local batchNum = math_ceil(batchStart / 12)
                local totalBatches = math_ceil(#canSendItems / 12)
                local batchCount = batchEnd - batchStart + 1
                local pluralBatch = (batchCount ~= 1 and "s" or "")

                local btnLabel = totalBatches > 1 and
                                     string_format("Pre-fill mail #%d of %d (%d item%s)", batchNum, totalBatches, batchCount,
                                                   pluralBatch) or "Pre-fill mail recipient"

                local mailBtn = aceGUI:Create("Button")
                mailBtn:SetText(btnLabel)
                mailBtn:SetFullWidth(true)

                local batchItems = {}
                for i = batchStart, batchEnd do
                    batchItems[#batchItems + 1] = canSendItems[i]
                end
                local recipient = requestData.r

                mailBtn:SetCallback("OnClick", function()
                    if not Globals.MailFrame or not Globals.MailFrame:IsShown() then
                        GBCR.Output:Response("Open the mailbox first, then click this button")

                        return
                    end
                    local toName = GBCR.Guild:NormalizePlayerName(recipient, true)
                    if Globals.SendMailNameEditBox then
                        Globals.SendMailNameEditBox:SetText(toName)
                    end
                    local attachLines = {"Attach from your bags:"}
                    for _, it in ipairs(batchItems) do
                        attachLines[#attachLines + 1] = string_format("  - %dx %s", it.qty, it.name)
                    end
                    GBCR.Output:Response(table_concat(attachLines, "\n"))
                end)
                scroll:AddChild(mailBtn)
            end

            scroll:DoLayout()
        end

        -- Async item-row creation: 20 rows per frame prevents main-thread freeze
        local function processBatch()
            if self.requestsTabGeneration ~= myGen then
                return
            end

            local endPosition = math_min(batchPosition + BATCH - 1, totalEntries)

            for i = batchPosition, endPosition do
                local entry = itemEntries[i]
                local itemId, qty = entry[1], entry[2]
                if itemId and qty then
                    local bags = inBags[itemId] or 0
                    local bank = inBank[itemId] or 0
                    local mail = inMail[itemId] or 0
                    local avail = bags + bank + mail
                    local canSend = math_min(qty, bags)

                    local rawName = GetItemInfo(itemId)
                    local name = rawName or ("item:" .. itemId)

                    local row = aceGUI:Create("SimpleGroup")
                    row:SetFullWidth(true)
                    row:SetLayout("Table")
                    row:SetUserData("table", {columns = {0, 55, 55, 55, 55}})

                    local nameLabel = aceGUI:Create("Label")
                    nameLabel:SetText(name)
                    row:AddChild(nameLabel)

                    local function numLbl(n, isNeed)
                        local l = aceGUI:Create("Label")
                        local col = isNeed and Constants.COLORS.WHITE or
                                        (n > 0 and Constants.COLORS.GREEN or Constants.COLORS.GRAY)
                        l:SetText(Globals.ColorizeText(col, tostring(n)))
                        row:AddChild(l)
                    end
                    numLbl(qty, true)
                    numLbl(bags, false)
                    numLbl(bank, false)
                    numLbl(mail, false)

                    scroll:AddChild(row)

                    if canSend > 0 then
                        canSendItems[#canSendItems + 1] = {itemId = itemId, qty = canSend, name = name}
                    end
                    if avail < qty then
                        totalUnmet = totalUnmet + (qty - avail)
                    end
                end
            end

            batchPosition = endPosition + 1
            if batchPosition <= totalEntries then
                After(0, processBatch)
            else
                addSummarySection()
            end
        end

        if totalEntries > 0 then
            After(0, processBatch)
        else
            addSummarySection()
        end
    end

    local function doLoad()
        local input = importInput:GetText()
        local data, err = parseImportString(input)
        if not data then
            local statusTxt = Globals.ColorizeText(Constants.COLORS.RED, "Error: " .. (err or "unknown error"))
            statusLabel:SetText(statusTxt)
            container:DoLayout()

            return
        end

        local pluralItems = ((data.i or {}) ~= 1 and "s" or "")
        local statusTxt = Globals.ColorizeText(Constants.COLORS.GREEN, string_format("Success: loaded %d item%s from %s",
                                                                                     #(data.i or {}), pluralItems, data.r or "?"))
        statusLabel:SetText(statusTxt)
        container:DoLayout()
        renderFulfillment(data)
    end

    parseBtn:SetCallback("OnClick", doLoad)
    importInput:SetCallback("OnEnterPressed", function(w)
        doLoad()
        w:ClearFocus()
    end)
end

-- Helper to draw the officer configuration tab
local function drawOfficerConfigurationTab(self, container)
    container:SetLayout("Fill")
    GBCR.Libs.AceConfigDialog:Open(addonName, container, "officer")
end

-- Helper to draw the bank configuration tab
local function drawBankConfigurationTab(self, container)
    container:SetLayout("Fill")
    GBCR.Libs.AceConfigDialog:Open(addonName, container, "bank")
end

-- Helper to draw the configuration tab
local function drawConfigurationTab(self, container)
    container:SetLayout("Fill")
    if container.SetTitle then
        container.SetTitle = function()
        end
    end
    GBCR.Libs.AceConfigDialog:Open(addonName, container)
end

-- Helper to build an auction house style filter tree with classes, subclasses, and slots
local function drawBrowseFilterTree(self)
    local tree = {}

    addCategoryToTree(self, tree, "any")

    local cWeapons = Enum.ItemClass.Weapon
    local nodeWeapons = addCategoryToTree(self, tree, "weapons", cWeapons)
    nodeWeapons.children = {}

    local weaponTypes = {
        Enum.ItemWeaponSubclass.Axe1H,
        Enum.ItemWeaponSubclass.Axe2H,
        Enum.ItemWeaponSubclass.Bows,
        Enum.ItemWeaponSubclass.Guns,
        Enum.ItemWeaponSubclass.Mace1H,
        Enum.ItemWeaponSubclass.Mace2H,
        Enum.ItemWeaponSubclass.Polearm,
        Enum.ItemWeaponSubclass.Sword1H,
        Enum.ItemWeaponSubclass.Sword2H,
        Enum.ItemWeaponSubclass.Staff,
        Enum.ItemWeaponSubclass.Unarmed,
        Enum.ItemWeaponSubclass.Generic,
        Enum.ItemWeaponSubclass.Dagger,
        Enum.ItemWeaponSubclass.Thrown,
        Enum.ItemWeaponSubclass.Crossbow,
        Enum.ItemWeaponSubclass.Wand,
        Enum.ItemWeaponSubclass.Fishingpole
    }
    for _, subID in ipairs(weaponTypes) do
        addCategoryToTree(self, nodeWeapons.children, "weapons_" .. subID, cWeapons, subID)
    end

    local nodeWeaponSlots = addCategoryToTree(self, nodeWeapons.children, "weapons_slots", cWeapons, -1, nil, "By Slot")
    nodeWeaponSlots.children = {}
    local wSlots = {"onehand", "twohand", "mainhand", "offhand", "ranged"}
    for _, slotKey in ipairs(wSlots) do
        addCategoryToTree(self, nodeWeaponSlots.children, "wslot_" .. slotKey, cWeapons, -1, Constants.FILTER.SLOT_MAP[slotKey],
                          Constants.FILTER.SLOT_LIST[slotKey])
    end

    sortTreeNodeChildren(nodeWeapons)

    local cArmor = Enum.ItemClass.Armor
    local nodeArmor = addCategoryToTree(self, tree, "armor", cArmor)
    nodeArmor.children = {}

    local armorMaterials = {
        Enum.ItemArmorSubclass.Cloth,
        Enum.ItemArmorSubclass.Leather,
        Enum.ItemArmorSubclass.Mail,
        Enum.ItemArmorSubclass.Plate
    }
    local armorSlots = {"head", "shoulder", "chest", "wrist", "hands", "waist", "legs", "feet"}
    for _, subID in ipairs(armorMaterials) do
        local subNode = addCategoryToTree(self, nodeArmor.children, "armor_" .. subID, cArmor, subID)
        subNode.children = {}
        for _, slotKey in ipairs(armorSlots) do
            local invSlotID = Constants.FILTER.SLOT_MAP[slotKey]
            addCategoryToTree(self, subNode.children, "armor_" .. subID .. "_" .. slotKey, cArmor, subID, invSlotID,
                              Constants.FILTER.SLOT_LIST[slotKey])
        end
        sortTreeNodeChildren(subNode)
    end

    local nodeArmorMisc = addCategoryToTree(self, nodeArmor.children, "armor_misc", cArmor, Enum.ItemArmorSubclass.Generic, nil,
                                            "Miscellaneous")
    nodeArmorMisc.children = {}
    local miscSlots = {"neck", "back", "shirt", "tabard", "finger", "trinket", "holdable"}
    for _, slotKey in ipairs(miscSlots) do
        local invSlotID = Constants.FILTER.SLOT_MAP[slotKey]
        addCategoryToTree(self, nodeArmorMisc.children, "armor_misc_" .. slotKey, cArmor, Enum.ItemArmorSubclass.Generic,
                          invSlotID, Constants.FILTER.SLOT_LIST[slotKey])
    end
    sortTreeNodeChildren(nodeArmorMisc)

    addCategoryToTree(self, nodeArmor.children, "armor_shield", cArmor, Enum.ItemArmorSubclass.Shield,
                      Constants.FILTER.SLOT_MAP.shield, Constants.FILTER.SLOT_LIST.shield)
    local relicTypes = {Enum.ItemArmorSubclass.Libram, Enum.ItemArmorSubclass.Idol, Enum.ItemArmorSubclass.Totem}
    for _, subID in ipairs(relicTypes) do
        addCategoryToTree(self, nodeArmor.children, "armor_" .. subID, cArmor, subID)
    end

    sortTreeNodeChildren(nodeArmor)

    local cContainer = Enum.ItemClass.Container
    local nodeContainers = addCategoryToTree(self, tree, "containers", cContainer)
    nodeContainers.children = {}
    for subID = 0, 3 do
        addCategoryToTree(self, nodeContainers.children, "containers_" .. subID, cContainer, subID)
    end
    sortTreeNodeChildren(nodeContainers)

    addCategoryToTree(self, tree, "consumables", Enum.ItemClass.Consumable)
    addCategoryToTree(self, tree, "tradegoods", Enum.ItemClass.Tradegoods)

    local cRecipe = Enum.ItemClass.Recipe
    local nodeRecipes = addCategoryToTree(self, tree, "recipes", cRecipe)
    nodeRecipes.children = {}
    for subID = 0, 10 do
        addCategoryToTree(self, nodeRecipes.children, "recipes_" .. subID, cRecipe, subID)
    end
    sortTreeNodeChildren(nodeRecipes)

    addCategoryToTree(self, tree, "reagents", Enum.ItemClass.Reagent)
    addCategoryToTree(self, tree, "projectile", Enum.ItemClass.Projectile)
    addCategoryToTree(self, tree, "quiver", Enum.ItemClass.Quiver)
    addCategoryToTree(self, tree, "quest", Enum.ItemClass.Questitem)
    addCategoryToTree(self, tree, "misc", Enum.ItemClass.Miscellaneous)

    return tree
end

local function CreateCustomTooltip(parent)
    local frame = CreateFrame("Frame", "GBCR_CustomTooltip", parent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetWidth(parent:GetWidth() or 150)
    frame.lines = {}

    return frame
end

-- local function onSearchReceiveDrag(frame)
--    local cursorType, _, info = GetCursorInfo()
--    if info then
--       local itemName = string_match(info, "%[(.+)%]")
--       if cursorType == "item" and itemName then
--          local search = UI_Inventory.filters.search
--          search:SetText(itemName)
--          search:Fire("OnTextChanged", itemName)
--          ClearCursor()
--          frame:ClearFocus()
--       end
--    end
-- end

local function onRequestAddToCart(widget, event)
    local self = UI_Inventory
    if not self.preview.selectedItem then
        return
    end

    local item = self.preview.selectedItem
    local amount = self.preview.slider:GetValue()
    local itemKey = item.itemString or tostring(item.itemId or 0)

    local enchantText = (self.cartData[itemKey] and self.cartData[itemKey].enchantText)
    if not enchantText and item.itemLink then
        enchantText = getEnchantTextFromTooltip(self, item.itemLink)
    end

    if self.cartData[itemKey] then
        local newQty = self.cartData[itemKey].qty + amount
        self.cartData[itemKey].qty = math_min(newQty, item.itemCount)
    else
        self.cartData[itemKey] = {
            itemLink = item.itemLink,
            qty = amount,
            itemCount = item.itemCount,
            sources = item.sources,
            itemInfo = item.itemInfo,
            enchantText = enchantText
        }
        self.cartCount = self.cartCount + 1
    end

    self.preview.selectedItem = item

    local alreadyInCart = self.cartData[itemKey] and self.cartData[itemKey].qty or 0
    local availableToRequest = item.itemCount - alreadyInCart

    if availableToRequest > 0 then
        self.preview.slider:SetDisabled(false)
        self.preview.slider:SetSliderValues(1, availableToRequest, 1)
        self.preview.slider:SetValue(1)
        self.preview.button:SetDisabled(false)
    else
        self.preview.slider:SetDisabled(true)
        self.preview.slider:SetValue(0)
        self.preview.button:SetDisabled(true)
    end

    if not self.preview.isScrollAttached then
        self.preview:AddChild(self.preview.scroll)
        self.preview.isScrollAttached = true
        self.preview:PerformLayout()
    end

    updateBottomBar(self)
end

-- Retrieve uncached item information for the UI via batched processing
local function getItems(self, itemsArray, callback)
    if not itemsArray or type(itemsArray) ~= "table" or #itemsArray == 0 then
        if callback then
            callback(itemsArray or {})
        end

        return
    end

    local totalItems = #itemsArray
    local currentIndex = 1
    local callbackFired = false
    local newFallbacks = 0
    local resolved = 0

    local function processBatch()
        local startTime = debugprofilestop()
        local processedThisFrame = 0

        while currentIndex <= totalItems do
            local item = itemsArray[currentIndex]

            if item and item.itemString then
                local key = item.itemString
                local cached = UI_Inventory.itemInfoCache[key]

                local needsFetch = not cached or (cached.isFallback and not cached.fetchAttempted)

                if needsFetch then
                    local name, link, rarity, level, minLevel, itemType, itemSubType, _, equipLoc, icon, price, itemClassId,
                          itemSubClassId = GetItemInfo(item.itemLink or key)

                    if name then
                        local wasFallback = cached and cached.isFallback
                        local equipId = GetItemInventoryTypeByID(item.itemId) or 0

                        UI_Inventory.itemInfoCache[key] = {
                            class = itemClassId or 0,
                            subClass = itemSubClassId or 0,
                            equipId = equipId,
                            rarity = rarity or 1,
                            name = name,
                            level = level or 1,
                            minLevel = minLevel or 0,
                            price = price or 0,
                            icon = icon or 134400,
                            typeLower = string_lower(itemType or ""),
                            subTypeLower = string_lower(itemSubType or ""),
                            equipLower = string_lower(equipLoc or ""),
                            realLink = link,
                            isFallback = false
                        }

                        if wasFallback then
                            resolved = resolved + 1
                        end
                    else
                        if not cached then
                            local p1 = strsplit(":", key)
                            local numId = tonumber(p1)

                            UI_Inventory.itemInfoCache[key] = {
                                class = 0,
                                subClass = 0,
                                equipId = 0,
                                rarity = 1,
                                name = "Loading...",
                                level = 1,
                                minLevel = 0,
                                price = 0,
                                icon = 134400,
                                typeLower = "",
                                subTypeLower = "",
                                equipLower = "",
                                realLink = nil,
                                isFallback = true,
                                fetchAttempted = true
                            }
                            newFallbacks = newFallbacks + 1

                            if numId and numId > 0 then
                                GBCR.Inventory.pendingItemInfoLoads[numId] = true
                            end
                        end
                    end
                end

                item.itemInfo = UI_Inventory.itemInfoCache[key]
                item.lowerName = item.itemInfo.name and string_lower(item.itemInfo.name) or ""
                item.itemLink = item.itemInfo.realLink or item.itemLink
            end

            currentIndex = currentIndex + 1
            processedThisFrame = processedThisFrame + 1

            if shouldYield(startTime, processedThisFrame, 50, 300) then
                After(0, processBatch)

                return
            end
        end

        if not callbackFired then
            callbackFired = true

            if resolved > 0 then
                self.pendingCorpusBuild = true
                GBCR.Output:Debug("UI", "getItems: resolved %d fallbacks, corpus will rebuild", resolved)
            end

            if callback then
                callback(itemsArray)
            end
        end
    end

    processBatch()
end

-- MASTER DATA AGGREGATION
local function getPooledAggItem(self)
    self.aggItemPoolCount = self.aggItemPoolCount + 1

    local entry = self.aggItemPool[self.aggItemPoolCount]
    if not entry then
        entry = {sources = {}}
        self.aggItemPool[self.aggItemPoolCount] = entry
    else
        wipe(entry.sources)
        entry.itemInfo = nil
        entry.lowerName = nil
        entry.itemLink = nil
        entry.itemString = nil
        entry.itemCount = nil
        entry.itemId = nil
    end

    return entry
end

local function updateItemsList(self, callback)
    self.itemsList = self.itemsList or {}
    self.aggregatedMap = self.aggregatedMap or {}
    self.aggItemPool = self.aggItemPool or {}
    self.aggItemPoolCount = 0
    self.aggregationGeneration = (self.aggregationGeneration or 0) + 1
    local currentAggGen = self.aggregationGeneration

    wipe(self.itemsList)
    wipe(self.aggregatedMap)

    local savedVariables = GBCR.Database and GBCR.Database.savedVariables
    if not savedVariables or not savedVariables.alts then
        GBCR.Output:Debug("UI", "updateItemsList: savedVariables not ready, aborting")

        wipe(self.itemsList)
        wipe(self.aggregatedMap)
        self.aggItemPoolCount = 0
        if callback then
            callback()
        end

        return
    end

    local altsToScan = {}
    if self.currentView == "Show all guild banks" then
        for altName in pairs(savedVariables.alts) do
            altsToScan[#altsToScan + 1] = altName
        end
    elseif savedVariables.alts[self.currentView] then
        altsToScan[1] = self.currentView
    end

    local tasks = {}
    local taskCount = 0
    for i = 1, #altsToScan do
        local altData = savedVariables.alts[altsToScan[i]]
        local items = altData.items
        if not items and altData.itemsCompressed then
            items = GBCR.Database.DecompressData(altData.itemsCompressed)
        end
        if items and #items > 0 then
            taskCount = taskCount + 1
            tasks[taskCount] = {altName = altsToScan[i], items = items}
        end
    end

    local currentTaskIndex = 1
    local currentItemIndex = 1
    local listCount = 0

    local function processAggregationBatch()
        if currentAggGen ~= self.aggregationGeneration then
            return
        end

        local startTime = debugprofilestop()
        local processedThisFrame = 0

        while currentTaskIndex <= taskCount do
            local task = tasks[currentTaskIndex]
            local items = task.items
            local itemsCount = #items
            local altName = task.altName

            while currentItemIndex <= itemsCount do
                local item = items[currentItemIndex]

                local key = item.itemString
                if key then
                    local aggItem = self.aggregatedMap[key]

                    if not aggItem then
                        aggItem = getPooledAggItem(self)
                        aggItem.itemString = key
                        aggItem.itemCount = 0

                        -- Extract values to reconstruct the valid WoW API string
                        local p1, p2, p3 = strsplit(":", key)
                        local derivedId = tonumber(p1) or 0
                        aggItem.itemId = derivedId

                        -- Build the valid WoW string ONCE per unique item
                        local validWoWString = string_format("item:%d:%s:0:0:0:0:%s:0:0:0:0:0:0", derivedId, p2 or "0", p3 or "0")
                        aggItem.validWoWString = validWoWString

                        -- Build a temporary fallback link ONCE per unique item
                        aggItem.itemLink = string_format("|cffffffff|H%s|h[item:%d]|h|r", validWoWString, derivedId)

                        -- Link directly to shared cache memory
                        aggItem.itemInfo = self.itemInfoCache[key] or item.itemInfo
                        if aggItem.itemInfo and aggItem.itemInfo.name then
                            aggItem.lowerName = string_lower(aggItem.itemInfo.name)
                        end

                        wipe(aggItem.sources)
                        self.aggregatedMap[key] = aggItem

                        listCount = listCount + 1
                        self.itemsList[listCount] = aggItem
                    end

                    local count = item.itemCount or 1
                    aggItem.itemCount = aggItem.itemCount + count
                    aggItem.sources[altName] = (aggItem.sources[altName] or 0) + count
                end

                currentItemIndex = currentItemIndex + 1
                processedThisFrame = processedThisFrame + 1

                if shouldYield(startTime, processedThisFrame, 50, 300) then
                    After(0, processAggregationBatch)

                    return
                end
            end

            currentTaskIndex = currentTaskIndex + 1
            currentItemIndex = 1
        end

        if currentAggGen ~= self.aggregationGeneration then
            return
        end

        local pool = self.aggItemPool
        local cap = #pool
        for i = self.aggItemPoolCount + 1, cap do
            pool[i] = nil
        end

        if callback then
            callback()
        end
    end

    processAggregationBatch()
end

-- Helper to draw the export tab
local function drawExportTab(self, container)
    container:SetLayout("GBCR_TopBottom")

    -- Controls (top)
    local controlGroup = aceGUI:Create("SimpleGroup")
    controlGroup:SetFullWidth(true)
    controlGroup:SetLayout("Flow")
    container:AddChild(controlGroup)

    local formatDropdown = aceGUI:Create("Dropdown")
    formatDropdown:SetLabel("Format")
    formatDropdown:SetList({["byitem"] = "By item (all guild banks)", ["bybank"] = "By bank (items per guild bank)"},
                           {"byitem", "bybank"})
    formatDropdown:SetValue("byitem")
    formatDropdown:SetWidth(250)
    controlGroup:AddChild(formatDropdown)

    local exportBtn = aceGUI:Create("Button")
    exportBtn:SetText("Prepare export")
    exportBtn:SetWidth(140)
    controlGroup:AddChild(exportBtn)

    -- Box (bottom)
    local boxContainer = aceGUI:Create("SimpleGroup")
    boxContainer:SetFullWidth(true)
    boxContainer:SetFullHeight(true)
    boxContainer:SetLayout("Fill")
    container:AddChild(boxContainer)

    local exportBox = aceGUI:Create("MultiLineEditBox")
    exportBox:SetLabel("")
    exportBox:DisableButton(true)
    exportBox:SetFullWidth(true)
    exportBox:SetFullHeight(true)
    boxContainer:AddChild(exportBox)

    exportBtn:SetCallback("OnClick", function()
        local meta = buildExportMetadata()
        local format = formatDropdown:GetValue()

        -- Clear old content area and replace with streamed view
        boxContainer:ReleaseChildren()
        boxContainer:SetLayout("Fill")

        if format == "byitem" then
            local function ensureReady(callback)
                if not UI_Inventory.itemsList or #UI_Inventory.itemsList == 0 then
                    updateItemsList(UI_Inventory, function()
                        getItems(UI_Inventory, UI_Inventory.itemsList, callback)
                    end)
                elseif UI_Inventory.fallbackCount and UI_Inventory.fallbackCount > 50 then
                    getItems(UI_Inventory, UI_Inventory.itemsList, callback)
                else
                    callback(UI_Inventory.itemsList)
                end
            end

            ensureReady(function(list)
                local header = metadataHeader(meta, "By Item")
                local phase = 1 -- 1 = header, 2 = count, 3 = blank, 4+ = items
                local iIndex = 1

                local function nextLine()
                    if phase == 1 then
                        phase = 2

                        return header
                    end

                    if phase == 2 then
                        phase = 3

                        return string_format("Total unique items: %d", #list)
                    end

                    if phase == 3 then
                        phase = 4

                        return ""
                    end

                    if iIndex > #list then
                        return nil
                    end

                    local item = list[iIndex]
                    iIndex = iIndex + 1

                    local info = item.itemInfo
                    local name = (info and not info.isFallback and info.name) or ("item:" .. (item.itemString or "?"))

                    local parts = {}
                    if item.sources then
                        for an, cnt in pairs(item.sources) do
                            parts[#parts + 1] = an .. " x" .. cnt
                        end
                        table_sort(parts)
                    end

                    return string_format("%s | total: %d | %s | %s", name, item.itemCount, item.itemString or "",
                                         table_concat(parts, ", "))
                end

                RenderStreamingTextArea(boxContainer, nextLine)
            end)

        else -- bybank
            local sv_ = GBCR.Database.savedVariables
            local roster = GBCR.Database:GetRosterGuildBankAlts() or {}
            local header = metadataHeader(meta, "By Bank")

            local phase = 1 -- 1 = header
            local rIndex = 1
            local curItems, iIndex, pendingMeta = nil, 1, {}

            local function nextLine()
                if phase == 1 then
                    phase = 2

                    return header
                end

                while true do
                    -- Drain pendingMeta
                    if #pendingMeta > 0 then
                        return table_remove(pendingMeta, 1)
                    end

                    -- Drain current alt items
                    if curItems then
                        if iIndex <= #curItems then
                            local it = curItems[iIndex]
                            iIndex = iIndex + 1
                            local info = UI_Inventory.itemInfoCache[it.itemString]
                            local nm = (info and not info.isFallback and info.name) or ("item:" .. (it.itemString or "?"))

                            return string_format("  %s x%d  (%s)", nm, it.itemCount or 1, it.itemString or "")
                        end

                        curItems = nil

                        return "" -- blank line after each alt
                    end

                    if rIndex > #roster then
                        return nil
                    end

                    local altName = roster[rIndex]
                    rIndex = rIndex + 1
                    local altData = sv_ and sv_.alts and sv_.alts[altName]

                    pendingMeta = {string_format("=== %s ===", altName)}

                    if altData then
                        local ver = altData.version
                        local money = altData.money or 0
                        pendingMeta[#pendingMeta + 1] = "Last updated : " ..
                                                            (ver and ver > 0 and date("%Y-%m-%d %H:%M", ver) or "never")
                        pendingMeta[#pendingMeta + 1] = string_format("Money        : %dg %ds %dc", math_floor(money / 10000),
                                                                      math_floor((money % 10000) / 100), money % 100)
                        local items = altData.items
                        if not items and altData.itemsCompressed then
                            items = GBCR.Database.DecompressData(altData.itemsCompressed)
                        end
                        if items and #items > 0 then
                            curItems = items
                            iIndex = 1
                        else
                            pendingMeta[#pendingMeta + 1] = "  (no items)"
                        end
                    else
                        pendingMeta[#pendingMeta + 1] = "  (no data)"
                    end
                end
            end

            RenderStreamingTextArea(boxContainer, nextLine)
        end
    end)

    -- exportBtn:SetCallback("OnClick", function()
    --     local meta = buildExportMetadata()
    --     local format = formatDropdown:GetValue()

    --     if format == "byitem" then
    --         local needsBuild = not UI_Inventory.itemsList or #UI_Inventory.itemsList == 0
    --         local needsHydrate = (not needsBuild) and (UI_Inventory.fallbackCount and UI_Inventory.fallbackCount > 50)

    --         local function runByItemExport()
    --             local list = UI_Inventory.itemsList or {}
    --             if #list == 0 then
    --                 exportBox:SetText(table_concat({metadataHeader(meta, "By Item"), "No items found", ""}, "\n"))

    --                 return
    --             end

    --             exportBox:SetText("Building export, please wait...")
    --             local lines = {metadataHeader(meta, "By Item"), string_format("Total unique items: %d", #list), ""}
    --             local index = 1
    --             local BATCH = 500

    --             local function processBatch()
    --                 local endIndex = math_min(index + BATCH - 1, #list)
    --                 for i = index, endIndex do
    --                     local item = list[i]
    --                     local info = item.itemInfo
    --                     local name = (info and not info.isFallback and info.name) or ("item:" .. (item.itemString or "?"))
    --                     local srcParts = {}
    --                     if item.sources then
    --                         for altName, count in pairs(item.sources) do
    --                             srcParts[#srcParts + 1] = altName .. " x" .. count
    --                         end
    --                         table_sort(srcParts)
    --                     end
    --                     lines[#lines + 1] = string_format("%s | total: %d | %s | %s", name, item.itemCount, item.itemString or "",
    --                                                       table_concat(srcParts, ", "))
    --                 end
    --                 index = endIndex + 1
    --                 if index <= #list then
    --                     After(0, processBatch)
    --                 else
    --                     exportBox:SetText(table_concat(lines, "\n"))
    --                 end
    --             end

    --             After(0, processBatch)
    --         end

    --         if needsBuild then
    --             exportBox:SetText("Building item list, please wait...")
    --             updateItemsList(UI_Inventory, function()
    --                 getItems(UI_Inventory, UI_Inventory.itemsList, function()
    --                     runByItemExport()
    --                 end)
    --             end)
    --         elseif needsHydrate then
    --             exportBox:SetText("Resolving item names, please wait...")
    --             getItems(UI_Inventory, UI_Inventory.itemsList, function()
    --                 runByItemExport()
    --             end)
    --         else
    --             runByItemExport()
    --         end
    --     else
    --         local sv = GBCR.Database.savedVariables
    --         local roster = GBCR.Database:GetRosterGuildBankAlts() or {}
    --         exportBox:SetText("Building export, please wait...")
    --         local lines = {metadataHeader(meta, "By Bank")}
    --         local altIndex = 1
    --         local currentItems = nil
    --         local currentAltLines = nil
    --         local itemIndex = 1
    --         local ITEM_BATCH = 200

    --         local function processNext()
    --             if not currentItems then
    --                 if altIndex > #roster then
    --                     exportBox:SetText(table_concat(lines, "\n"))

    --                     return
    --                 end

    --                 local altName = roster[altIndex]
    --                 local altData = sv and sv.alts and sv.alts[altName]
    --                 lines[#lines + 1] = "=== " .. altName .. " ==="
    --                 if altData then
    --                     local ver = altData.version
    --                     lines[#lines + 1] = "Last updated : " .. (ver and ver > 0 and date("%Y-%m-%d %H:%M", ver) or "Never")
    --                     local money = altData.money or 0
    --                     lines[#lines + 1] = string_format("Money        : %dg %ds %dc", math_floor(money / 10000),
    --                                                       math_floor((money % 10000) / 100), money % 100)
    --                     local items = altData.items
    --                     if items and #items > 0 then
    --                         currentItems = items
    --                         currentAltLines = {}
    --                         itemIndex = 1
    --                     else
    --                         lines[#lines + 1] = "  (no items)"
    --                         lines[#lines + 1] = ""
    --                         altIndex = altIndex + 1
    --                         After(0, processNext)

    --                         return
    --                     end
    --                 else
    --                     lines[#lines + 1] = "  (no data)"
    --                     lines[#lines + 1] = ""
    --                     altIndex = altIndex + 1
    --                     After(0, processNext)

    --                     return
    --                 end
    --             end

    --             local endIndex = math_min(itemIndex + ITEM_BATCH - 1, #currentItems)
    --             for i = itemIndex, endIndex do
    --                 local it = currentItems[i]
    --                 local info = UI_Inventory.itemInfoCache[it.itemString]
    --                 currentAltLines[#currentAltLines + 1] = {
    --                     name = (info and not info.isFallback and info.name) or ("item:" .. (it.itemString or "?")),
    --                     count = it.itemCount or 1,
    --                     itemString = it.itemString or ""
    --                 }
    --             end
    --             itemIndex = endIndex + 1

    --             if itemIndex > #currentItems then
    --                 table_sort(currentAltLines, function(a, b)
    --                     return a.name < b.name
    --                 end)
    --                 for _, entry in ipairs(currentAltLines) do
    --                     lines[#lines + 1] = string_format("  %s x%d  (%s)", entry.name, entry.count, entry.itemString)
    --                 end
    --                 lines[#lines + 1] = ""
    --                 currentItems = nil
    --                 currentAltLines = nil
    --                 altIndex = altIndex + 1
    --             end

    --             After(0, processNext)
    --         end

    --         After(0, processNext)
    --     end
    -- end)
end

-- Derive money total and newest version timestamp for the current view
local function getViewStats(self)
    local sv = GBCR.Database and GBCR.Database.savedVariables
    if not sv or not sv.alts then
        return 0, 0
    end

    local totalMoney = 0
    local newestVersion = 0
    local view = self.currentView

    if view == "Show all guild banks" then
        for _, altData in pairs(sv.alts) do
            totalMoney = totalMoney + (altData.money or 0)
            if (altData.version or 0) > newestVersion then
                newestVersion = altData.version
            end
        end
    else
        local altData = sv.alts[view]
        if altData then
            totalMoney = altData.money or 0
            newestVersion = altData.version or 0
        end
    end

    return totalMoney, newestVersion
end

-- Update the window status bar with filtered-item count, gold, and sync state
local function updateStatusText(self)
    if not self.window or self.currentTab ~= "browse" then
        return
    end

    local filtered = self.filteredCount or 0
    local total = self.itemsList and #self.itemsList or 0
    local gold, ver = getViewStats(self)

    local lockout = GBCR.Protocol.isLockedOut and ("  •  " .. Globals.ColorizeText(Constants.COLORS.RED, "Sync paused")) or ""

    local status
    if (filtered < total and total > 0) or self.filterStatus ~= "" then
        status = string_format("showing %d of %d items  •  %s", filtered, total, self.filterStatus)
    elseif ver and ver > 0 then
        status = string_format("%s  •  as of %s", Globals.GetCoinTextureString(gold), date("%b %d  %H:%M", ver))
    else
        status = "no available data"
    end

    self.window:SetStatusText(status .. lockout)
end

local function updateFilterStatus(self)
    -- print("updateFilterStatus is called")
    if self.currentTab ~= "browse" or not self.filters then
        return
    end

    local active = 0
    local parts = {}

    if self.searchText and self.searchText ~= "" then
        active = active + 1
        parts[#parts + 1] = "search"
    end
    if self.activeRarity and self.activeRarity ~= "any" then
        active = active + 1
        parts[#parts + 1] = "rarity"
    end
    if self.activeTreeFilter and self.activeTreeFilter.classID ~= -1 then
        active = active + 1
        parts[#parts + 1] = "type"
    end
    if self.currentView and self.currentView ~= "Show all guild banks" then
        active = active + 1
        parts[#parts + 1] = "guild bank"
    end

    if active > 0 then
        self.filterStatus = string_format("%d filter%s: %s", active, active ~= 1 and "s" or "", table_concat(parts, ", "))
    else
        self.filterStatus = ""
    end

    updateStatusText(self)

    if self.filters.resetBtn then
        if active > 0 then
            self.filters.resetBtn:SetDisabled(false)
        else
            self.filters.resetBtn:SetDisabled(true)
        end
    end
end

-- Build the search index with object pooling using the pre-aggregated itemsList
local function buildSearchData(self, callback)
    self.buildSearchGeneration = (self.buildSearchGeneration or 0) + 1
    local myGen = self.buildSearchGeneration

    local debugEnabled = GBCR.Options:IsDebugEnabled() and GBCR.Options:IsCategoryEnabled("SEARCH")

    if not self.itemsList or #self.itemsList == 0 then
        if debugEnabled then
            GBCR.Output:Debug("SEARCH", "BuildSearchData: early exit due to missing data")
        end
        wipe(self.dirtyAlts)
        self.needsFullRebuild = false
        if callback then
            callback()
        end

        return
    end

    if debugEnabled then
        GBCR.Output:Debug("SEARCH", "BuildSearchData called")
    end

    local corpus = self.corpus
    local corpusNamesSeen = self.corpusNamesSeen
    local corpusPool = self.corpusPool
    local corpusCount = 0
    local total = #self.itemsList
    local index = 1

    wipe(corpus)
    wipe(corpusNamesSeen)

    local function Resume()
        if myGen ~= self.buildSearchGeneration then
            GBCR.Output:Debug("SEARCH", "buildSearchData aborted (stale generation %d)", myGen)

            return
        end

        local frameStart = debugprofilestop()
        local processedThisFrame = 0

        while index <= total do
            local aggItem = self.itemsList[index]

            if aggItem and aggItem.itemInfo and aggItem.itemInfo.name then
                local name = aggItem.itemInfo.name
                if not corpusNamesSeen[name] then
                    corpusNamesSeen[name] = true
                    corpusCount = corpusCount + 1
                    local entry = corpusPool[corpusCount] or {}
                    corpusPool[corpusCount] = entry
                    entry.name = name
                    entry.lower = aggItem.lowerName or string_lower(name)
                    corpus[corpusCount] = entry
                end
            end

            index = index + 1
            processedThisFrame = processedThisFrame + 1

            if shouldYield(frameStart, processedThisFrame, 50, 300) then
                After(0, Resume)

                return
            end
        end

        for i = corpusCount + 1, #corpusPool do
            corpusPool[i] = nil
        end

        wipe(self.dirtyAlts)
        self.needsFullRebuild = false

        GBCR.Output:Debug("SEARCH", "buildSearchData: corpus built with %d unique names", corpusCount)

        if myGen ~= self.buildSearchGeneration then
            return
        end

        if callback then
            callback()
        end
    end

    After(0, Resume)
end

local function buildFilteredList(self, callback)
    -- print("buildFilteredList is called", self.itemsList and #self.itemsList, self.isDataPending, self.isReady)

    if not self.itemsList or #self.itemsList == 0 then
        wipe(self.cachedFilteredList)
        self.filteredCount = 0
        if not self.isDataPending then
            if updateVirtualGrid then
                updateVirtualGrid(self)
            end
        end
        if self.emptyLabel and self.isReady then
            self.emptyLabel:SetText("No items found")
            self.emptyLabel:Show()
        end

        -- local itemCount = self.cachedFilteredList and #self.cachedFilteredList or 0
        -- local browseTabText = itemCount > 0 and string_format("Browse (%d)", itemCount) or "Browse"
        -- -- Update the tab button text
        -- if self.tabs and self.tabs.tabs then
        --     for _, tab in pairs(self.tabs.tabs) do
        --         if tab.value == "browse" then
        --             tab:SetText(browseTabText)

        --             break
        --         end
        --     end
        -- end
        local browseTabText = "Browse"
        if self.tabs and self.tabs.tabs then
            for _, tab in pairs(self.tabs.tabs) do
                if tab.value == "browse" then
                    tab:SetText(browseTabText)

                    break
                end
            end
        end

        updateFilterStatus(self)

        if callback then
            callback()
        end

        return
    end

    self.renderGeneration = (self.renderGeneration or 0) + 1
    local currentGen = self.renderGeneration

    local searchText = string_lower(self.searchText or "")
    local searchTokens = parseSearchQuery(searchText)

    -- Corpus fast-reject: for plain text searches with no operator tokens, scan unique names (~5k) instead of all items (~142k)
    -- Operator tokens (q:, t:, s:, lvl>, ilvl<=) search dimensions other than name, so the corpus cannot reject them
    if searchText ~= "" and #self.corpus > 0 then
        local hasOperator = false
        for _, token in ipairs(searchTokens) do
            if string_match(token, "^%a+[<>=]") or string_match(token, "^%a+:") then
                hasOperator = true

                break
            end
        end

        if not hasOperator then
            -- Pure name search: corpus can definitively answer "zero results possible"
            local corpusMatch = false
            for ci = 1, #self.corpus do
                if string_find(self.corpus[ci].lower, searchText, 1, true) then
                    corpusMatch = true

                    break
                end
            end
            if not corpusMatch then
                if currentGen ~= self.renderGeneration then
                    return
                end

                wipe(self.cachedFilteredList)
                self.filteredCount = 0
                if updateVirtualGrid then
                    updateVirtualGrid(self)
                end
                if self.emptyLabel and self.isReady then
                    self.emptyLabel:SetText("No items found")
                    self.emptyLabel:Show()
                end
                updateFilterStatus(self)
                if callback then
                    callback()
                end

                -- print("buildFilteredList exit 1")
                return
            end
        end
    end

    ---
    local function continueAfterHydration(list)
        if currentGen ~= self.renderGeneration then
            -- print("buildFilteredList exit 2")

            return
        end

        local function startFilterBatch()
            if currentGen ~= self.renderGeneration then
                -- print("buildFilteredList exit 3")

                return
            end

            wipe(self.cachedFilteredList)
            self.filteredCount = 0

            local rarityVal = self.filters and self.filters.rarity and self.filters.rarity:GetValue() or "any"
            local targetRarity = Constants.FILTER.RARITY_MAP[rarityVal]
            local totalItems = #list
            local currentIndex = 1

            local function processFilterBatch()
                if currentGen ~= self.renderGeneration then
                    -- print("buildFilteredList exit 4")

                    return
                end

                local startTime = debugprofilestop()
                local processedThisFrame = 0

                while currentIndex <= totalItems do
                    local item = list[currentIndex]
                    local info = item and item.itemInfo
                    local pass = true

                    if info then
                        if self.activeTreeFilter and self.activeTreeFilter.classID ~= -1 then
                            if (info.class or 0) ~= self.activeTreeFilter.classID then
                                pass = false
                            elseif self.activeTreeFilter.subClassID and self.activeTreeFilter.subClassID ~= -1 and
                                (info.subClass or 0) ~= self.activeTreeFilter.subClassID then
                                pass = false
                            elseif self.activeTreeFilter.invSlotID and self.activeTreeFilter.invSlotID ~= (info.equipId or 0) then
                                pass = false
                            end
                        end
                        if pass and rarityVal ~= "any" and targetRarity then
                            if (info.rarity or 1) ~= targetRarity then
                                pass = false
                            end
                        end
                    elseif self.activeTreeFilter and self.activeTreeFilter.classID ~= -1 then
                        pass = false
                    end

                    if pass and searchText ~= "" then
                        pass = #searchTokens > 0 and advancedSearchMatch(item, searchTokens) or
                                   (string_find(item.lowerName or "", searchText, 1, true) ~= nil)
                    end

                    if pass then
                        self.filteredCount = self.filteredCount + 1
                        self.cachedFilteredList[self.filteredCount] = item
                    end

                    currentIndex = currentIndex + 1
                    processedThisFrame = processedThisFrame + 1

                    if shouldYield(startTime, processedThisFrame, 50, 300) then
                        After(0, processFilterBatch)

                        -- print("buildFilteredList exit 5")

                        return
                    end
                end

                sort(self, self.cachedFilteredList, GBCR.Options:GetSortMode())
                if updateVirtualGrid then
                    updateVirtualGrid(self)
                end

                do
                    local _cnt = self.filteredCount or 0
                    local _text = _cnt > 0 and string_format("Browse (%d)", _cnt) or "Browse"
                    if self.tabs and self.tabs.tabs then
                        for _, _tb in pairs(self.tabs.tabs) do
                            if _tb.value == "browse" then
                                _tb:SetText(_text)

                                break
                            end
                        end
                    end
                end

                if self.emptyLabel then
                    if self.filteredCount == 0 and self.isReady then
                        self.emptyLabel:SetText("No items found")
                        self.emptyLabel:Show()
                    else
                        self.emptyLabel:Hide()
                    end
                end
                updateFilterStatus(self)
                if callback then
                    callback()
                end
            end
            processFilterBatch()
        end

        if self.pendingCorpusBuild then
            self.pendingCorpusBuild = false
            local isFullRebuild = self.needsFullRebuild
            local capturedDirty = nil
            if not isFullRebuild and next(self.dirtyAlts) then
                capturedDirty = {}
                for k in pairs(self.dirtyAlts) do
                    capturedDirty[k] = true
                end
            end
            local genAtBuild = currentGen
            buildSearchData(self, function()
                if genAtBuild ~= self.renderGeneration then
                    return
                end

                GBCR.Inventory:BuildGlobalItemSourcesIndex(capturedDirty, function()
                    if genAtBuild ~= self.renderGeneration then
                        return
                    end

                    startFilterBatch()
                end)
            end)
        else
            startFilterBatch()
        end
    end

    if not self.itemsHydrated then
        getItems(self, self.itemsList, function(list)
            if currentGen ~= self.renderGeneration then
                return
            end

            self.itemsHydrated = true
            continueAfterHydration(list)
        end)
    else
        continueAfterHydration(self.itemsList)
    end
    ---
end

-- Helper callback
local function onSortDropdownChanged(widget, event, value)
    local self = widget:GetUserData("self")
    GBCR.Options:SetSortMode(value)
    if self.cachedFilteredList and #self.cachedFilteredList > 0 then
        sort(self, self.cachedFilteredList, value)
        if updateVirtualGrid then
            updateVirtualGrid(self)
        end
    end
end

-- Helper callback for Rarity Dropdown
local function onRarityDropdownChanged(widget, event, key)
    local self = widget:GetUserData("self")
    self.activeRarity = key
    self:Refresh()
end

local function onGuildBankDropdownChanged(widget, event, value)
    local self = widget:GetUserData("self")
    self.currentView = value
    self:Refresh()
end

local function handleSearchDrop()
    local cursorType, _, info = GetCursorInfo()
    if cursorType == "item" and info then
        local itemName = string_match(info, "%[(.+)%]")
        if itemName then
            local searchInput = _G["GBankClassicSearch"]
            UI_Inventory.searchText = itemName
            searchInput:SetText(itemName)
            ClearCursor()
            searchInput:ClearFocus()

            return true
        end
    end

    return false
end

-- Helper to populate the list of guild bank alts
local function updateBankDropdown(self)
    -- print("!!!", self.filters, self.filters and self.filters.bankDropdown, self.currentTab)
    if not self.filters or not self.filters.bankDropdown or self.currentTab ~= "browse" then
        -- print("!!! exit")
        return
    end

    local savedVars = GBCR.Database and GBCR.Database.savedVariables
    local alts = savedVars and savedVars.alts

    local sortedNames = {}
    local n = 0
    if alts then
        for altName in pairs(alts) do
            n = n + 1
            sortedNames[n] = altName
        end
    end
    table_sort(sortedNames)

    local currentHash = table_concat(sortedNames, "\0")
    if currentHash == self.lastBankDropdownHash then
        return
    end

    self.lastBankDropdownHash = currentHash

    local list = {["Show all guild banks"] = "Show all guild banks"}
    local order = {"Show all guild banks"}

    for i = 1, n do
        local altName = sortedNames[i]
        list[altName] = altName
        order[#order + 1] = altName
    end

    self.filters.bankDropdown:SetList(list, order)
    self.filters.bankDropdown:SetValue(self.currentView or "Show all guild banks")
end

-- Helper callback for Grid Resizing
local function onVirtualGridResize(frame)
    local self = UI_Inventory
    if self.resizeTimer then
        return
    end

    self.resizeTimer = NewTimer(0.05, function()
        self.resizeTimer = nil
        if self.currentTab == "browse" and self.grid and self.grid.scroll then
            self.grid.scroll:FixScroll()
            updateVirtualGrid(self)
            populateCustomTooltip()
        end
    end)
end

-- Helper to draw the right panel for the browse tab
local function drawBrowsePanel(self, container, group)
    -- print("GBCR.UI.Inventory drawBrowsePanel")

    container:ReleaseChildren()
    container:SetLayout("GBCR_ThreePane")

    -- SEARCH + FILTERS
    local filters = aceGUI:Create("SimpleGroup")
    filters:SetLayout("Flow")
    container:AddChild(filters)
    self.filters = filters

    local searchWrapper = aceGUI:Create("SimpleGroup")
    searchWrapper:SetWidth(250)
    searchWrapper:SetHeight(44)
    searchWrapper:SetLayout("Fill")
    searchWrapper.frame:EnableMouse(true)
    searchWrapper.frame:SetScript("OnReceiveDrag", handleSearchDrop)
    searchWrapper.frame:SetScript("OnMouseUp", handleSearchDrop)

    local searchLabel = self.searchLabel
    if not searchLabel then
        searchLabel = searchWrapper.frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        self.searchLabel = searchLabel
    end
    searchLabel:SetParent(searchWrapper.frame)
    searchLabel:ClearAllPoints()
    searchLabel:SetPoint("TOPLEFT", searchWrapper.frame, "TOPLEFT", 0, 16)
    searchLabel:SetHeight(44)
    searchLabel:SetFontObject(GameFontNormal)
    searchLabel:SetText("Search")
    searchLabel:Show()

    local instructions = "Type to search or drag an item here"
    local searchInput = self.searchField or CreateFrame("EditBox", "GBankClassicSearch", searchWrapper.frame, "SearchBoxTemplate")
    self.searchField = searchInput
    searchInput:SetParent(searchWrapper.frame)
    searchInput:ClearAllPoints()
    searchInput:SetPoint("BOTTOMLEFT", searchWrapper.frame, "BOTTOMLEFT", 8, 10)
    searchInput:SetSize(242, 20)
    searchInput:Show()
    searchInput.Instructions:SetText(instructions)
    searchInput:SetScript("OnEnter", function()
        GameTooltip:SetOwner(searchInput, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Search all guild banks")
        GameTooltip:AddLine("Find items across all bank characters.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Or drag an item here.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Globals.ColorizeText(colorYellow, "Advanced search tips:"), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("q:[quality]", "q:rare", 1, 1, 1, 0.5, 0.5, 0.5)
        GameTooltip:AddDoubleLine("lvl:[op][num]", "lvl>40", 1, 1, 1, 0.5, 0.5, 0.5)
        GameTooltip:AddDoubleLine("t:[type]", "t:armor", 1, 1, 1, 0.5, 0.5, 0.5)
        GameTooltip:AddDoubleLine("s:[slot]", "s:head", 1, 1, 1, 0.5, 0.5, 0.5)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Accepted operators: " .. Globals.ColorizeText(colorYellow, ">") .. ", " ..
                                Globals.ColorizeText(colorYellow, "<") .. ", " .. Globals.ColorizeText(colorYellow, ">=") .. ", " ..
                                Globals.ColorizeText(colorYellow, "<=") .. ", " .. Globals.ColorizeText(colorYellow, "=") .. "",
                            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    searchInput:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    searchInput:SetScript("OnTextChanged", function(input)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(input)
        end
        local text = input:GetText()
        UI_Inventory.searchText = text
        UI_Inventory.searchTokens = parseSearchQuery(text)

        if self.searchTimer then
            self.searchTimer:Cancel()
        end
        self.searchTimer = NewTimer(Constants.TIMER_INTERVALS.SEARCH_DEBOUNCE, function()
            UI_Inventory:Refresh()
        end)
    end)
    searchInput:SetScript("OnEnterPressed", function(input)
        UI_Inventory.searchText = input:GetText()
        input:ClearFocus()
    end)
    searchInput:SetScript("OnReceiveDrag", handleSearchDrop)
    searchInput:HookScript("OnMouseDown", handleSearchDrop)
    searchWrapper:SetCallback("OnRelease", function()
        if self.searchField then
            self.searchField:Hide()
            self.searchField:SetParent(UIParent)
            self.searchLabel:Hide()
            self.searchLabel:SetParent(UIParent)
        end
    end)
    self.searchWrapper = searchWrapper
    filters:AddChild(searchWrapper)

    local sortDropdown = aceGUI:Create("Dropdown")
    sortDropdown:SetLabel("Sort")
    sortDropdown:SetList(Constants.SORT_LIST, Constants.SORT_ORDER)
    sortDropdown:SetWidth(150)
    sortDropdown.label:SetFontObject(GameFontNormal)
    sortDropdown:SetValue(GBCR.Options:GetSortMode())
    sortDropdown:SetUserData("self", self)
    sortDropdown:SetCallback("OnValueChanged", onSortDropdownChanged)
    filters:AddChild(sortDropdown)
    self.filters.sortDropdown = sortDropdown

    self.lastBankDropdownHash = nil
    local guildBankAltDropdown = aceGUI:Create("Dropdown")
    guildBankAltDropdown:SetLabel("Filter on guild bank")
    guildBankAltDropdown:SetWidth(250)
    guildBankAltDropdown.label:SetFontObject(GameFontNormal)
    guildBankAltDropdown:SetUserData("self", self)
    guildBankAltDropdown:SetCallback("OnValueChanged", onGuildBankDropdownChanged)
    self.filters.bankDropdown = guildBankAltDropdown
    updateBankDropdown(self)
    filters:AddChild(guildBankAltDropdown)

    local rarity = aceGUI:Create("Dropdown")
    rarity:SetLabel("Filter on rarity")
    rarity:SetList(Constants.FILTER.RARITY_LIST, Constants.FILTER.RARITY_ORDER)
    rarity:SetValue(self.activeRarity or "any")
    rarity:SetWidth(150)
    rarity.label:SetFontObject(GameFontNormal)
    rarity:SetUserData("self", self)
    rarity:SetCallback("OnValueChanged", onRarityDropdownChanged)
    filters:AddChild(rarity)
    self.filters.rarity = rarity

    local resetFiltersBtn = aceGUI:Create("Button")
    resetFiltersBtn:SetText("Reset filters")
    resetFiltersBtn:SetWidth(100)
    resetFiltersBtn:SetDisabled(true)
    resetFiltersBtn:SetCallback("OnClick", function()
        UI_Inventory.searchText = ""
        if _G["GBankClassicSearch"] then
            _G["GBankClassicSearch"]:SetText("")
        end
        self.activeRarity = "any"
        self.filters.rarity:SetValue("any")
        self.activeTreeFilter = self.filterCategories["any"]
        self.activeTreeGroup = "any"
        self.tree:SelectByValue("any")
        self.currentView = "Show all guild banks"
        self:Refresh()
    end)
    filters:AddChild(resetFiltersBtn)
    self.filters.resetBtn = resetFiltersBtn

    -- local filterStatusLabel = aceGUI:Create("Label")
    -- filterStatusLabel:SetWidth(40)
    -- filterStatusLabel.label:SetFontObject(GameFontNormal)
    -- filters:AddChild(filterStatusLabel)
    -- self.filters.statusLabel = filterStatusLabel

    -- ITEM GRID
    local gridContainer = aceGUI:Create("InlineGroup")
    gridContainer:SetTitle("")
    gridContainer:SetLayout("Fill")
    container:AddChild(gridContainer)
    self.grid = gridContainer

    local scroll = aceGUI:Create("ScrollFrame")
    -- scroll:SetLayout("Flow")
    scroll:SetLayout(nil)
    gridContainer:AddChild(scroll)
    self.grid.scroll = scroll

    local emptyLabel = scroll.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyLabel:SetPoint("CENTER", scroll.frame, "CENTER", 0, 0)
    emptyLabel:SetText("No items found")
    emptyLabel:Hide()
    self.emptyLabel = emptyLabel

    -- SELECTED ITEM PREVIEW
    local preview = aceGUI:Create("InlineGroup")
    preview:SetTitle("")
    preview:SetLayout("Flow")
    container:AddChild(preview)
    self.preview = preview
    self.preview.isScrollAttached = false
    self.preview.selectedItem = nil

    local label = aceGUI:Create("Label")
    label:SetText("")
    label:SetFullWidth(true)
    label:SetFontObject(GameFontHighlight)
    preview:AddChild(label)
    self.preview.label = label

    local qty = aceGUI:Create("Slider")
    qty:SetLabel("Quantity")
    qty:SetSliderValues(1, 1, 1)
    qty:SetFullWidth(true)
    qty:SetDisabled(true)
    preview:AddChild(qty)
    self.preview.slider = qty

    local request = aceGUI:Create("Button")
    request:SetText("Add to request list")
    request:SetFullWidth(true)
    request:SetDisabled(true)
    request:SetCallback("OnClick", onRequestAddToCart)
    preview:AddChild(request)
    self.preview.button = request

    local tooltipScroll = aceGUI:Create("ScrollFrame")
    tooltipScroll:SetLayout("Fill")
    tooltipScroll:SetFullWidth(true)
    tooltipScroll:SetFullHeight(true)
    tooltipScroll:SetCallback("OnRelease", function()
        if self.customTooltip then
            self.customTooltip:Hide()
            self.customTooltip:ClearAllPoints()
            self.customTooltip:SetParent(UIParent)
        end
    end)
    if not tooltipScroll.frame.gbcrSizeHooked then
        tooltipScroll.frame:HookScript("OnSizeChanged", onVirtualGridResize)
        tooltipScroll.frame.gbcrSizeHooked = true
    end
    self.preview.scroll = tooltipScroll

    self.customTooltip = self.customTooltip or CreateCustomTooltip(tooltipScroll.content)
    if self.customTooltip:GetParent() ~= tooltipScroll.content then
        self.customTooltip:SetParent(tooltipScroll.content)
        self.customTooltip:ClearAllPoints()
    end
    self.customTooltip:Hide()
    self.customTooltip:SetPoint("TOPLEFT", tooltipScroll.content, "TOPLEFT", 5, -5)

    scroll.content:SetHeight(1)
    scroll:SetLayout("GBCR_VirtualGrid")
    if not scroll.scrollbar.gbcrValueHooked then
        scroll.scrollbar:HookScript("OnValueChanged", function(slider, value)
            if self.currentTab == "browse" and not self.isUpdatingScroll then
                updateVirtualGrid(self)
            end
        end)
        scroll.scrollbar.gbcrValueHooked = true
    end

    if not scroll.frame.gbcrSizeHooked then
        scroll.frame:HookScript("OnSizeChanged", onVirtualGridResize)
        scroll.frame.gbcrSizeHooked = true
    end
end

-- Add this near the other helper functions in UI/Inventory.lua:
local function getTabTopBarMessage(tab)
    if tab == "browse" then
        return "Type or drag an item into the search box  •  Shift-click to link  •  Ctrl-click to preview"
    elseif tab == "cart" then
        return "Review quantities, then share the import code with a guild bank"
    elseif tab == "ledger" then
        return "Recent guild bank transactions from mail, trade, vendor, AH, and destroy operations"
    elseif tab == "export" then
        return "Export inventory data for use outside the game"
    elseif tab == "network" then
        local meta = GBCR.Database.savedVariables and GBCR.Database.savedVariables.networkMeta
        local seedCount = meta and meta.seedCount or 0
        local isGBA = GBCR.Guild and GBCR.Guild.weAreGuildBankAlt
        if isGBA then
            if seedCount > 0 then
                return Globals.ColorizeText(Constants.COLORS.GREEN,
                                            "Ok  •  Your data has been shared this session, safe to log off")
            else
                return Globals.ColorizeText(Constants.COLORS.ORANGE,
                                            "Please wait  •  Your data has not yet been shared with online members, stay online")
            end
        end

        return "Real-time guild bank sync status with online guild members"
    elseif tab == "fulfillment" then
        return "Pull items from bank or bags first, then use the pre-fill mail button"
    elseif tab == "configuration" then
        return "Configuration settings apply immediately"
    end

    return ""
end

local function getTabStatusText(self)
    local tab = self.currentTab
    local sv = GBCR.Database and GBCR.Database.savedVariables

    if tab == "browse" then
        -- Already handled by updateStatusText (Patch L)
        return nil -- let updateStatusText manage it
    elseif tab == "cart" then
        local uniqueCount = self.cartCount or 0
        local totalQty = 0
        for _, d in pairs(self.cartData or {}) do
            totalQty = totalQty + (d.qty or 0)
        end

        return string_format("%d item%s  •  %d total quantity", uniqueCount, uniqueCount ~= 1 and "s" or "", totalQty)
    elseif tab == "ledger" then
        if not sv or not sv.alts then
            return "No data"
        end

        local entries = 0
        local newest = 0
        for _, alt in pairs(sv.alts) do
            if alt.ledger then
                entries = entries + #alt.ledger
            end
            if (alt.version or 0) > newest then
                newest = alt.version
            end
        end

        local age = newest > 0 and formatTimeAgo(newest) or "never"
        if age == "never" then
            age = Globals.ColorizeText(colorGray, age)
        end

        return string_format("%d ledger entries  •  last guild bank update %s", entries, age)
    elseif tab == "export" then
        local items = self.itemsList and #self.itemsList or 0
        local alts = sv and sv.alts and Globals.Count(sv.alts) or 0

        return string_format("%d unique items across %d alts", items, alts)
    elseif tab == "network" then
        local roster = GBCR.Database:GetRosterGuildBankAlts() or {}
        local synced = 0
        if sv and sv.alts then
            for _, name in ipairs(roster) do
                local a = sv.alts[name]
                if a and (a.version or 0) > 0 then
                    synced = synced + 1
                end
            end
        end
        local users = Globals.Count(GBCR.Guild.cachedAddonUsers or {}) or 0
        local members = GBCR.Guild.cachedOnlineGuildMemberCount or 0

        return string_format("%d/%d alts synced  •  %d other addon user%s online  •  %d guild member%s online", synced,
                             #roster, users, users ~= 1 and "s" or "", members, members ~= 1 and "s" or "")
    elseif tab == "configuration" or tab == "fulfillment" then
        local guildName = sv and sv.guildName or "no guild"

        return GBCR.Guild:GetNormalizedPlayerName() .. "  •  " .. guildName
    end

    return ""
end

function UI_Inventory:NotifyStateChanged()
    if self and self.isOpen then
        -- Status bar: browse tab has its own richer updateStatusText; all others use getTabStatusText.
        if self.currentTab == "browse" then
            updateStatusText(self)
        else
            local statusTxt = getTabStatusText(self)
            if statusTxt and self.window then
                self.window:SetStatusText(statusTxt)
            end
        end

        -- Top-bar text: re-evaluate for tabs whose message depends on runtime state
        -- (notably "network" which shows "Please wait" vs "Ok" based on seedCount).
        if self.topBar and self.topBar.topBarText then
            local newMsg = getTabTopBarMessage(self.currentTab)
            if newMsg ~= self.topBarBaseText then
                self.topBarBaseText = newMsg
                if not self.isSyncing then
                    self.topBar.topBarText:SetText(newMsg)
                else
                    local syncing = Globals.ColorizeText(Constants.COLORS.GREEN, "SYNCING")
                    self.topBar.topBarText:SetText(syncing .. "  •  " .. newMsg)
                end
            end
        end
    end

    GBCR.UI.Network:RefreshIfOpen()
end

-- Helper callback for Tree Group Selection
local function onTreeGroupSelected(widget, event, selectedGroup)
    local self = UI_Inventory
    -- print("GBCR.UI.Inventory tree OnGroupSelected", selectedGroup)

    if self.preview then
        self.preview.selectedItem = nil
        self.preview.label:SetText("")
        self.preview.slider:SetDisabled(true)
        self.preview.slider:SetSliderValues(1, 1, 1)
        self.preview.slider:SetValue(0)
        self.preview.button:SetDisabled(true)
        self.customTooltip:Hide()
    end

    local selectedValue = string_match(selectedGroup, "[^%c]+$") or selectedGroup

    -- If the tree filter hasn't actually changed and the panel is already drawn,
    -- avoid a full rebuild triggered by SelectByValue re-firing the callback.
    if self.browsePanelDrawn and self.activeTreeGroup == selectedGroup and self.activeTreeFilter ==
        self.filterCategories[selectedValue] then
        return
    end

    self.activeTreeFilter = self.filterCategories[selectedValue]
    self.activeTreeGroup = selectedGroup

    if not self.browsePanelDrawn then
        drawBrowsePanel(self, widget, selectedGroup)
        self.browsePanelDrawn = true
    end

    self:Refresh()
end

-- Helper to draw the browse tab with the tree and the right panel
local function drawBrowseTab(self, container)
    -- print("GBCR.UI.Inventory drawBrowseTab")

    if not self.tree then
        local tree = aceGUI:Create("TreeGroup")
        tree:SetLayout("Fill")
        tree:SetTree(self.filterTree)
        tree:SetStatusTable(self.treeStatusTable)
        tree:SetCallback("OnGroupSelected", onTreeGroupSelected)
        self.tree = tree
    end

    container:AddChild(self.tree)

    self.tree:SelectByValue(self.activeTreeGroup or "any")
end

local function updateDynamicTabs(self)
    if not self.tabs then
        return
    end

    GBCR.Guild.weCanEditOfficerNotes = Globals.CanEditOfficerNote()

    local isBankAlt = (GBCR.Guild.weAreGuildBankAlt ~= nil) and GBCR.Guild.weAreGuildBankAlt
    local isOfficer = GBCR.Guild.weCanEditOfficerNotes == true

    if self.lastKnownBankAltState == isBankAlt and self.lastKnownOfficerState == isOfficer then
        return
    end
    self.lastKnownBankAltState = isBankAlt
    self.lastKnownOfficerState = isOfficer

    local dynamicTabs = {}
    for _, t in ipairs(Constants.UI.TABS) do
        dynamicTabs[#dynamicTabs + 1] = {text = t.text, value = t.value}
    end
    if isBankAlt then
        for _, t in ipairs(Constants.UI.TABS_BANK) do
            dynamicTabs[#dynamicTabs + 1] = {text = t.text, value = t.value}
        end
    end
    self.tabs:SetTabs(dynamicTabs)

    GBCR.Libs.AceConfigRegistry:NotifyChange(addonName)

    -- Apply consistent font objects to all tab buttons
    -- HookScript on Enable/Disable bypasses TSM + Auctioneer font-object overrides which both reset tab text to white when run together
    if self.tabs.tabs then
        for _, tabButton in pairs(self.tabs.tabs) do
            tabButton:SetNormalFontObject(GameFontNormal)
            tabButton:SetHighlightFontObject(GameFontHighlight)
            if not tabButton.origSetDisabledFontObject then
                tabButton.origSetDisabledFontObject = tabButton.SetDisabledFontObject
                tabButton.SetDisabledFontObject = function(s, fontObj)
                    return s:origSetDisabledFontObject(GameFontHighlight)
                end
            end
            tabButton:SetDisabledFontObject(GameFontHighlight)
            if not tabButton._gbcrColorHooked then
                tabButton._gbcrColorHooked = true
                tabButton:HookScript("OnEnable", function(btn)
                    local fs = btn:GetFontString()
                    if fs then
                        fs:SetTextColor(1, 0.82, 0)
                    end -- gold = unselected
                end)
                tabButton:HookScript("OnDisable", function(btn)
                    local fs = btn:GetFontString()
                    if fs then
                        fs:SetTextColor(1, 1, 1)
                    end -- white = selected/active
                end)
            end
            local fs = tabButton:GetFontString()
            if fs then
                if tabButton:IsEnabled() then
                    fs:SetTextColor(1, 0.82, 0)
                else
                    fs:SetTextColor(1, 1, 1)
                end
            end
        end
    end
end

local function exitNonDataTab(self)
    self.isDataPending = false
    if self.loadingOverlay then
        self.loadingOverlay:Hide()
    end
    -- if self.window and self.currentTab ~= "browse" then
    --     self.window:SetStatusText("")
    -- end
    local statusTxt = getTabStatusText(self)
    if statusTxt and self.window then
        self.window:SetStatusText(statusTxt)
    end
end

local function refresh(self)
    -- print("GBCR.UI.Inventory refresh is called")

    if not self.window or not self.window:IsShown() then
        -- print("GBCR.UI.Inventory refresh: exit 1")

        return
    end

    -- self.clockLabel:ClearAllPoints()
    -- self.clockLabel:SetPoint("TOPLEFT", self.topBar.content, "TOPLEFT", 20, 0)
    -- self.topBar.topBarText:ClearAllPoints()
    -- self.topBar.topBarText:SetPoint("TOPLEFT", self.topBar.content, "TOPLEFT", 60, 0)
    -- self.topBar.topBarText:SetWidth(750)
    -- self.syncDot:ClearAllPoints()
    -- self.syncDot:SetPoint("LEFT", self.topBar.content, "LEFT", 0, 0)

    if self.currentTab == "browse" then
        updateStatusText(self)
    end

    updateDynamicTabs(self)

    local tab = self.currentTab
    if tab == "configuration" then
        exitNonDataTab(self)

        return
    end

    if not IsInGuild() then
        if self.emptyLabel then
            self.emptyLabel:SetText("Join a guild to use this addon")
            self.emptyLabel:Show()
        end
        exitNonDataTab(self)

        return
    end

    -- Guard: data prerequisites not yet available
    -- Hide the overlay rather than leaving it stuck, and mark as ready so the next QueueUIRefresh (fired by guild/db events) will proceed
    if not GBCR.Database.savedVariables then
        -- print("GBCR.UI.Inventory refresh: exit 2")

        return
    end

    -- Non-browse tabs have their own data paths; skip the expensive pipeline
    -- The browse tab drives the item corpus, keep dirty flags for when it opens
    -- local isDataTab = (self.currentTab == "browse" or self.currentTab == "cart" or self.currentTab == "export" or not self.--    --     -- currenexitNonDataTab(self)
    --     -- print("GBCR.UI.Inventory refresh: exit 4")

    --     return
    -- end

    -- Ledger: repopulate the virtual scroll with current data, no item pipeline needed.
    if tab == "ledger" then
        if self.refreshLedger then
            self.refreshLedger()
        end
        exitNonDataTab(self)

        return
    end

    -- Network: repopulate rows and labels.
    if tab == "network" then
        if GBCR.UI.Network.isOpen then
            GBCR.UI.Network:Populate()
        end
        exitNonDataTab(self)

        return
    end

    if tab == "cart" or tab == "fulfillment" then
        exitNonDataTab(self)

        return
    end

    if tab == "export" then
        exitNonDataTab(self)

        return
    end

    if not GBCR.Database:GetRosterGuildBankAlts() then
        -- print("GBCR.UI.Inventory refresh: exit 3")

        if self.window and self.window.frame then
            if not self.loadingOverlay then
                setUILoading(self, true)
            else
                self.loadingOverlay:Show()
            end
            if self.loadingOverlayText then
                self.loadingOverlayText:SetText("Waiting for guild roster...")
            end
        end

        return
    end

    -- Browse and Export tabs require the full aggregation + filter pipeline.
    -- print("GBCR.UI.Inventory refresh: continue", self.lastAggregatedView, self.currentView)

    -- self.isDataPending = true
    -- setUILoading(self, true)
    local inventoryChanged = self.needsFullRebuild or next(self.dirtyAlts) or self.lastAggregatedView ~= self.currentView
    if inventoryChanged then
        self.isDataPending = true
        setUILoading(self, true)
    end

    updateBankDropdown(self)

    local function proceedToRender()
        buildFilteredList(self, function()
            self.isDataPending = false
            if updateVirtualGrid then
                updateVirtualGrid(self)
            end
            self.isReady = true
            setUILoading(self, false)
            GBCR.Output:Debug("UI", "UI refresh complete and data hydrated")
        end)
    end

    if inventoryChanged then
        -- Raw data changed: rebuild aggregation AND the search corpus, then render (buildSearchData is only ever called from this branch)
        updateItemsList(self, function()
            self.lastAggregatedView = self.currentView
            self.pendingCorpusBuild = true
            proceedToRender()
        end)
    else
        -- Nothing in the inventory changed (user changed sort/rarity/search text)
        -- Skip aggregation and corpus rebuild entirely
        proceedToRender()
    end
end

local function onClose()
    local self = UI_Inventory

    self.isOpen = false
    self.renderGeneration = (self.renderGeneration or 0) + 1

    if self.window then
        self.window:Hide()
    end
end

local function closeWindow(self)
    if not self.isOpen or not self.window then
        return
    end

    onClose()
end

function UI_Inventory:UpdateTransparency()
    if not self.window then
        return
    end

    local frame = self.window.frame
    local isTransparent = GBCR.Options:GetUiTransparency()

    if not isTransparent then
        -- Apply the custom Solid Backdrop
        local solidBackdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4}
        }
        frame:SetBackdrop(solidBackdrop)
        frame:SetBackdropColor(0.05, 0.05, 0.05, 1)
        frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

        if self.window.titlebg_l then
            self.window.titlebg:SetDesaturated(true)
            self.window.titlebg:SetVertexColor(0.6, 0.6, 0.6, 1)
            self.window.titlebg_l:SetDesaturated(true)
            self.window.titlebg_l:SetVertexColor(0.6, 0.6, 0.6, 1)
            self.window.titlebg_r:SetDesaturated(true)
            self.window.titlebg_r:SetVertexColor(0.6, 0.6, 0.6, 1)
        end
    else
        -- Revert to the cached original AceGUI Backdrop
        if self.originalBackdrop then
            frame:SetBackdrop(self.originalBackdrop)
            frame:SetBackdropColor(table_unpack(self.originalBackdropColor))
            frame:SetBackdropBorderColor(table_unpack(self.originalBackdropBorderColor))
        end

        -- Revert Title textures to default
        if self.window.titlebg_l then
            self.window.titlebg:SetDesaturated(false)
            self.window.titlebg:SetVertexColor(1, 1, 1, 1)
            self.window.titlebg_l:SetDesaturated(false)
            self.window.titlebg_l:SetVertexColor(1, 1, 1, 1)
            self.window.titlebg_r:SetDesaturated(false)
            self.window.titlebg_r:SetVertexColor(1, 1, 1, 1)
        end
    end
end

function UI_Inventory:SetSyncing(active)
    if not self.syncDot then
        return
    end

    if GBCR.Guild.cachedOnlineGuildMemberCount <= 1 then
        return
    end

    self.isSyncing = active

    local label = self.topBar.topBarText.label
    if active then
        local syncing = Globals.ColorizeText(Constants.COLORS.GREEN, "SYNCING")
        label:SetText(syncing .. "  •  " .. (self.topBarBaseText or ""))
        self.syncDot:SetAlpha(1)
        self.syncDot:Show()
        if not self.syncPulseTicker then
            local _pulseHigh = true
            self.syncPulseTicker = NewTicker(0.45, function()
                if not self.syncDot or not self.syncDot:IsShown() then

                    return
                end

                _pulseHigh = not _pulseHigh
                self.syncDot:SetAlpha(_pulseHigh and 1 or 0.15)
            end)
        end
    else
        label:SetText(self.topBarBaseText or "")
        if self.syncPulseTicker then
            self.syncPulseTicker:Cancel()
            self.syncPulseTicker = nil
        end
        self.syncDot:SetAlpha(1)
        self.syncDot:Hide()
    end
end

-- Helper to draw the main user interface window with top bar, tabs, and bottom bar
local function drawWindow(self)
    local window = aceGUI:Create("Frame")
    window:SetTitle(GBCR.Core.addonHeader)
    window:SetLayout("GBCR_AppLayout")
    window:SetWidth(850)
    window:SetHeight(485)
    window:SetCallback("OnClose", onClose)
    window:Hide()
    window.frame:SetResizeBounds(850, 485)
    window.frame:SetClampedToScreen(true)
    window.frame:EnableKeyboard(true)
    window.frame:SetPropagateKeyboardInput(true)
    window.frame:SetScript("OnKeyDown", eventHandler)
    window.frame:SetFrameStrata("HIGH")
    local globalFrameName = "GBCR_UI"
    _G[globalFrameName] = window.frame
    UISpecialFrames[#UISpecialFrames + 1] = globalFrameName
    self.window = window

    self.originalBackdrop = window.frame:GetBackdrop()
    local r, g, b, a = window.frame:GetBackdropColor()
    self.originalBackdropColor = {r or 0, g or 0, b or 0, a or 0}
    r, g, b, a = window.frame:GetBackdropBorderColor()
    self.originalBackdropBorderColor = {r or 1, g or 1, b or 1, a or 1}
    self:UpdateTransparency()

    -- Top bar
    local topBar = aceGUI:Create("SimpleGroup")
    topBar:SetFullWidth(true)
    topBar:SetLayout("GBCR_NoLayout")
    topBar.noAutoHeight = true
    window:AddChild(topBar)
    self.topBar = topBar

    -- Server clock
    local clockLabel = aceGUI:Create("Label")
    clockLabel:SetFontObject(GameFontNormal)
    topBar:AddChild(clockLabel)
    self.clockLabel = clockLabel

    if self.clockTicker then
        self.clockTicker:Cancel()
    end

    self.clockTicker = NewTicker(1, function()
        if not self.isOpen or not self.clockLabel then
            return
        end

        local useLocal = GBCR.db and GBCR.db.profile.clockTime == "local"
        local timeStr

        if useLocal then
            timeStr = date("%H:%M")
        else
            local h, m = GetGameTime()
            timeStr = string.format("%02d:%02d", h, m)
        end

        self.clockLabel:SetText(Globals.ColorizeText(Constants.COLORS.WHITE, timeStr))
    end)

    -- Sync dot: parented to topBar.frame (topBar.content = topBar.frame in SimpleGroup).
    -- Position is enforced by GBCR_AppLayout after every layout pass.
    local syncDot = topBar.frame:CreateTexture(nil, "OVERLAY")
    syncDot:SetSize(8, 8)
    syncDot:SetColorTexture(0, 1, 0.4, 1)
    syncDot:SetPoint("LEFT", topBar.frame, "LEFT", 2, 0)
    syncDot:Hide()
    self.syncDot = syncDot

    -- Notice text
    local topBarText = aceGUI:Create("Label")
    topBarText:SetText("")
    topBarText:SetFontObject(GameFontHighlight)
    topBarText.label:SetWordWrap(false)
    topBar:AddChild(topBarText)
    self.topBar.topBarText = topBarText
    self.topBarBaseText = ""

    -- Middle: tabs
    local tabs = aceGUI:Create("TabGroup")
    tabs:SetLayout("Fill")
    self.tabs = tabs
    updateDynamicTabs(self)
    tabs:SetCallback("OnGroupSelected", function(container, event, group)
        self.container = container
        -- print("<> GBCR.UI.Inventory tabs OnGroupSelected", group)

        if GBCR.Libs.AceConfigDialog.OpenFrames[addonName] then
            GBCR.Libs.AceConfigDialog:Close(addonName)
        end

        if self.itemPool then
            for i = 1, #self.itemPool do
                local btn = self.itemPool[i]
                if btn then
                    aceGUI:Release(btn)
                end
            end
            wipe(self.itemPool)
        end

        if self.emptyLabel then
            self.emptyLabel:Hide()
        end

        self.currentTab = group
        if self.topBar and self.topBar.topBarText then
            local msg = getTabTopBarMessage(group)
            self.topBarBaseText = msg
            self.topBar.topBarText:SetText(msg)
            if self.isSyncing then
                self:SetSyncing(true)
            end
        end

        setUILoading(self, self.isDataPending)

        self.browsePanelDrawn = false
        self.requestsTabGeneration = (self.requestsTabGeneration or 0) + 1

        self.tree = nil
        self.filters = nil
        self.grid = nil
        self.preview = nil
        -- self.searchField = nil
        self.searchWrapper = nil
        -- self.searchLabel = nil
        self.emptyLabel = nil

        -- -- Unglue native WoW frames from their AceGUI parents before recycling
        -- if self.searchField then
        --     self.searchField:Hide()
        --     self.searchField:ClearAllPoints()
        --     self.searchField:SetParent(UIParent)
        -- end
        -- if self.searchLabel then
        --     self.searchLabel:Hide()
        --     self.searchLabel:ClearAllPoints()
        --     self.searchLabel:SetParent(UIParent)
        -- end
        -- if self.customTooltip then
        --     self.customTooltip:Hide()
        --     self.customTooltip:ClearAllPoints()
        --     self.customTooltip:SetParent(UIParent)
        -- end

        container:ReleaseChildren()

        container:SetLayout("Fill")

        if group == "browse" then
            drawBrowseTab(self, container)
        elseif group == "cart" then
            drawCartTab(self, container)
        elseif group == "fulfillment" then
            drawFulfillmentTab(self, container)
        elseif group == "ledger" then
            drawLedgerTab(self, container)
        elseif group == "export" then
            drawExportTab(self, container)
        elseif group == "configuration" then
            drawConfigurationTab(self, container)
        elseif group == "bank_configuration" then
            drawBankConfigurationTab(self, container)
        elseif group == "officer_configuration" then
            drawOfficerConfigurationTab(self, container)
        elseif group == "network" then
            GBCR.UI.Network:DrawNetworkTab(container)
        end

        updateBottomBar(self)

        if group ~= "browse" then
            -- print("<> GBCR.UI.Inventory tabs OnGroupSelected: refresh for non browse tabs")
            self:Refresh()
        end
    end)
    window:AddChild(tabs)

    -- Bottom bar
    local bottomBar = aceGUI:Create("SimpleGroup")
    bottomBar:SetFullWidth(true)
    bottomBar:SetLayout("Flow")
    bottomBar:SetHeight(25)
    window:AddChild(bottomBar)
    self.bottomBar = bottomBar

    local bottomBarText = aceGUI:Create("Label")
    bottomBarText:SetText("Your request list is empty")
    bottomBarText:SetRelativeWidth(0.75)
    bottomBarText:SetFontObject(GameFontHighlight)
    bottomBarText:SetJustifyV("MIDDLE")
    bottomBar:AddChild(bottomBarText)
    self.bottomBar.bottomBarText = bottomBarText

    local bottomBarButton = aceGUI:Create("Button")
    bottomBarButton:SetText("Prepare request export")
    bottomBarButton:SetDisabled(true)
    bottomBarButton:SetRelativeWidth(0.24)
    bottomBarButton:SetCallback("OnClick", function() -- TODO
        -- if getCartUniqueCount(self) == 0 then
        --     return
        -- end
        -- print("Submitting request...")
        -- wipe(self.cartData)
        -- self.bottomBar.bottomBarText:SetText("Your request list is empty. Browse to add items.")
        tabs:SelectTab("cart")
    end)
    bottomBar:AddChild(bottomBarButton)
    self.bottomBar.button = bottomBarButton

    -- Status bar
    local statusbg = window.statustext:GetParent()
    statusbg:ClearAllPoints()
    statusbg:SetPoint("BOTTOMLEFT", window.frame, "BOTTOMLEFT", 15, 15)
    statusbg:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -163, 15)

    local helpIcon = CreateFrame("Frame", nil, window.frame)
    helpIcon:SetSize(24, 24)
    helpIcon:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -133, 15)
    helpIcon:EnableMouse(true)

    local helpText = helpIcon:CreateTexture(nil, "OVERLAY")
    helpText:SetAllPoints(helpIcon)
    helpText:SetTexture("Interface\\Common\\help-i")
    helpIcon:SetScript("OnEnter", function(self) -- TODO: review
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(GBCR.Core.addonHeader)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Globals.ColorizeText(colorYellow, "Browse:"), 1, 1, 1, false)
        GameTooltip:AddLine("Browse for items across all guild banks.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Use sort and filters to find items faster.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Reset filters when done.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Globals.ColorizeText(colorYellow, "My request list:"), 1, 1, 1, false)
        GameTooltip:AddLine("Review your request list and prepare an export.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Share your exported request on Discord.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Globals.ColorizeText(colorYellow, "Ledger:"), 1, 1, 1, false)
        GameTooltip:AddLine("Recent guild bank transactions are recorded and synced.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Globals.ColorizeText(colorYellow, "Export:"), 1, 1, 1, false)
        GameTooltip:AddLine("Export guild bank data for out-of-game display.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Globals.ColorizeText(colorYellow, "Network:"), 1, 1, 1, false)
        GameTooltip:AddLine("View the synchronization progress and health of your data.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    helpIcon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function openWindow(self, tabName)
    -- Always invalidate so a re-open after a status change during window-closed forces updateDynamicTabs to re-evaluate rather than serve stale state
    self.lastKnownBankAltState = nil
    self.lastKnownOfficerState = nil

    -- If already open, just switch tabs
    if self.isOpen then
        if tabName and self.tabs then
            updateDynamicTabs(self)
            self.tabs:SelectTab(tabName)
        end

        return
    end

    self.isOpen = true

    if not self.window then
        drawWindow(self)
    end

    self.window:Show()

    updateDynamicTabs(self)

    if self.tabs then
        self.tabs:SelectTab(tabName or "browse")
    end

    self:Refresh()

    GBCR.Protocol:PerformSync()
end

local function toggleWindow(self)
    if self.isOpen then
        closeWindow(self)
    else
        openWindow(self)
    end
end

local function toggleTab(self, tabName)
    if self.isOpen and self.currentTab == tabName then
        closeWindow(self)
    else
        openWindow(self, tabName)
    end
end

local function init(self)
    self.isReady = false

    self.pendingCorpusBuild = false
    self.needsFullRebuild = true
    self.dirtyAlts = {}

    self.itemButtonWidgetType = "GBCR_ItemButtonWidget"
    self.itemButtonWidgetVersion = 1

    self.filterTree = {}
    self.filterCategories = {}
    self.cachedFilteredList = {}
    self.cartData = {}

    local savedPanes = GBCR.db and GBCR.db.profile.framePositions.panes or {}
    self.activeCartLeftPaneWidth = savedPanes.cartLeft or 550
    self.activePreviewRightPaneWidth = savedPanes.previewRight or 284

    self.currentView = "Show all guild banks"

    self.itemsList = {}
    self.aggItemPool = {}
    self.aggregatedMap = {}
    self.aggItemPoolCount = 0
    self.cartCount = 0

    self.corpus = {}
    self.corpusPool = {}
    self.corpusNamesSeen = {}

    self.itemInfoCache = {}

    self.aggregationGeneration = 0
    self.buildSearchGeneration = 0
    self.lastBankDropdownHash = nil

    self.filterTree = drawBrowseFilterTree(self)
    self.treeStatusTable = {treewidth = 175}

    self.itemsHydrated = false
    self.filterStatus = ""

    registerCustomUI(self)

    local tooltipScanner = CreateFrame("GameTooltip", "GBCR_TooltipScanner", nil, "GameTooltipTemplate")
    tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
    self.tooltipScanner = tooltipScanner

    drawWindow(self)
end

-- Export functions for other modules
UI_Inventory.MarkAltDirty = markAltDirty
UI_Inventory.MarkAllDirty = markAllDirty
UI_Inventory.FormatTimeAgo = formatTimeAgo
UI_Inventory.Refresh = refresh
UI_Inventory.Close = closeWindow
UI_Inventory.Open = openWindow
UI_Inventory.Toggle = toggleWindow
UI_Inventory.ToggleTab = toggleTab
UI_Inventory.Init = init
