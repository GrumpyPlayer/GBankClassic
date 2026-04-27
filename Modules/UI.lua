local addonName, GBCR = ...

GBCR.UI = {}
local UI = GBCR.UI

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

local After = Globals.After
local ChatEdit_InsertLink = Globals.ChatEdit_InsertLink
local ClearCursor = Globals.ClearCursor
local ClickSendMailItemButton = Globals.ClickSendMailItemButton
local CreateFrame = Globals.CreateFrame
local DressUpItemLink = Globals.DressUpItemLink
local Enum = Globals.Enum
local GameFontDisable = Globals.GameFontDisable
local GameFontHighlight = Globals.GameFontHighlight
local GameFontHighlightSmall = Globals.GameFontHighlightSmall
local GameFontNormal = Globals.GameFontNormal
local GameTooltip = Globals.GameTooltip
local GameTooltip_SetDefaultAnchor = Globals.GameTooltip_SetDefaultAnchor
local GetContainerItemInfo = Globals.GetContainerItemInfo
local GetContainerNumSlots = Globals.GetContainerNumSlots
local GetCursorInfo = Globals.GetCursorInfo
local GetCursorPosition = Globals.GetCursorPosition
local GetGameTime = Globals.GetGameTime
local GetItemClassInfo = Globals.GetItemClassInfo
local GetItemInfo = Globals.GetItemInfo
local GetItemInventoryTypeByID = Globals.GetItemInventoryTypeByID
local GetItemQualityColor = Globals.GetItemQualityColor
local GetItemSubClassInfo = Globals.GetItemSubClassInfo
local GetRealmName = Globals.GetRealmName
local GetServerTime = Globals.GetServerTime
local IsControlKeyDown = Globals.IsControlKeyDown
local IsInGuild = Globals.IsInGuild
local IsShiftKeyDown = Globals.IsShiftKeyDown
local NewTicker = Globals.NewTicker
local NewTimer = Globals.NewTimer
local PickupContainerItem = Globals.PickupContainerItem
local PickupItem = Globals.PickupItem
local SearchBoxTemplate_OnTextChanged = Globals.SearchBoxTemplate_OnTextChanged
local shouldYield = Globals.ShouldYield
local SplitContainerItem = Globals.SplitContainerItem
local UIParent = Globals.UIParent
local UISpecialFrames = Globals.UISpecialFrames
local WorldFrame = Globals.WorldFrame

local formatTimeAgo = Globals.FormatTimeAgo

local Constants = GBCR.Constants
local colorGreen = Constants.COLORS.GREEN
local colorYellow = Constants.COLORS.YELLOW
local colorRed = Constants.COLORS.RED
local colorBlue = Constants.COLORS.BLUE
local colorGray = Constants.COLORS.GRAY

local importPrefix = Constants.IMPORT_PREFIX
local discordMaxChar = Constants.LIMITS.DISCORD_MAX

local aceGUI = GBCR.Libs.AceGUI

local callbacks = {}

-- ================================================================================================ -- export metadata

-- Helper to populate the metadata for export
local function buildExportMetadata()
    local sv = GBCR.Database and GBCR.Database.savedVariables
    local guild = (sv and sv.guildName) or "Unknown Guild"
    local realm = (sv and sv.realm) or GetRealmName() or "Unknown Realm"
    local player = GBCR.Guild:GetNormalizedPlayerName()
    local version = GBCR.Core.addonVersion or "?"
    local now = GetServerTime()

    return {exportTime = date("%Y-%m-%d %H:%M:%S", now), guild = guild, realm = realm, character = player, version = version}
end

-- Helper to generate export metadata on top
local function metadataHeader(meta, formatLabel)
    return table_concat({
        "-- GBankClassic Revived export (" .. formatLabel .. ") --",
        "Generated : " .. meta.exportTime,
        "Guild     : " .. meta.guild .. " @ " .. meta.realm,
        "Character : " .. meta.character,
        "AddOn     : " .. meta.version,
        ""
    }, "\n")
end

-- ================================================================================================ -- debug output window

-- Clears the contents of the debug output (with /bank debugclear) as seen in the seperate debug output window (/bank debuglog)
local function clearDebugContent()
    wipe(GBCR.Output.debugMessageBuffer)

    if UI.Debug.content then
        UI.Debug.content:SetText("")
    end

    GBCR.Output:Response("Debug output cleared.")
end

-- Called each time a new debug message needs to be logged to refresh the output window only once every x seconds (fixed delay)
local function queueDebugLogRefresh()
    if UI.Debug.isRefreshPending then
        return
    end

    UI.Debug.isRefreshPending = true

    After(Constants.TIMER_INTERVALS.DEBUG_LOG_REFRESH, function()
        UI.Debug.isRefreshPending = false

        if UI.Debug.isOpen then
            UI.Debug:DrawContent()
        end
    end)
end

-- ================================================================================================ -- UI components

-- Helper to show the item tooltips with sources
local function showItemTooltip(itemLink, sources)
    if not itemLink then
        return
    end

    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip.pendingSourcesForGBCR = sources
    GameTooltip:SetHyperlink(itemLink)
    GameTooltip:Show()
end

-- Helper to hide the item tooltips with sources
local function hideTooltip()
    GameTooltip.pendingSourcesForGBCR = nil
    GameTooltip:Hide()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
end

-- Helper to handle UI events
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

-- Helper to populate a fixed item tooltip preview after selecting an item in the browse tab
local function populateCustomTooltip()
    local frame = UI.customTooltip
    local itemLink = UI.preview.selectedItem and
                         ((UI.preview.selectedItem.itemInfo and UI.preview.selectedItem.itemInfo.realLink) or
                             UI.preview.selectedItem.itemLink) or nil
    local targetWidth = UI.preview.scroll.frame:GetWidth() - 40

    for _, line in ipairs(frame.lines) do
        line.left:Hide()
        if line.right then
            line.right:Hide()
        end
    end

    if not itemLink then
        return
    end

    UI.tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")
    UI.tooltipScanner:ClearLines()
    UI.tooltipScanner:SetHyperlink(itemLink)

    local yOffset = -10
    local padding = 10
    local textWidth = targetWidth - (padding * 2)
    local numLines = UI.tooltipScanner:NumLines()

    for i = 1, numLines do
        local leftTextObj = _G["GBCR_TooltipScannerTextLeft" .. i]
        local rightTextObj = _G["GBCR_TooltipScannerTextRight" .. i]
        if not leftTextObj then
            break
        end

        if not frame.lines[i] then
            frame.lines[i] = {
                left = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
                right = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            }
        end

        local line = frame.lines[i]
        local text = leftTextObj:GetText()

        if text and text ~= "" then
            line.left:SetWidth(textWidth)
            line.left:SetJustifyH("LEFT")
            line.left:SetWordWrap(true)
            line.left:ClearAllPoints()
            line.left:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, yOffset)
            line.left:SetTextColor(leftTextObj:GetTextColor())
            line.left:SetText(text)
            line.left:Show()

            local rightText = rightTextObj:GetText()
            if rightText and rightText ~= "" and rightTextObj:IsShown() then
                line.right:ClearAllPoints()
                line.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padding, yOffset)
                line.right:SetTextColor(rightTextObj:GetTextColor())
                line.right:SetText(rightText)
                line.right:Show()

                local rightWidth = line.right:GetStringWidth()
                line.left:SetWidth(math_max(1, textWidth - rightWidth - 5))
            end

            yOffset = yOffset - (line.left:GetStringHeight() + 2)
        end
    end

    local totalHeight = math_abs(yOffset) + 8
    frame:SetHeight(totalHeight)
    frame:SetWidth(targetWidth)
    frame:Show()

    local content = frame:GetParent()
    content:SetHeight(totalHeight + 4)
    if content.obj and content.obj.FixScroll then
        content.obj:FixScroll()
    end
end

-- Helper to create the fixed item tooltip frame for item previews
local function createCustomTooltip(parent)
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

-- Helper to contain the grid logic to avoid creating an anonymous closure on every frame/scroll update
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
            btn:SetCallback("OnClick", callbacks.onClickBrowseItem)
            btn:SetCallback("OnDragStart", callbacks.onDragStartBrowseItem)
            btn:SetCallback("OnEnter", callbacks.onEnterBrowseItem)
            btn:SetCallback("OnLeave", callbacks.onLeaveBrowseItem)
            btn.parentedToGrid = true
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

    offset = math_min(math_max(0, offset), maxScroll)

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
                if not slot.parentedToGrid then
                    slot.frame:SetParent(scroll.content)
                    slot.frame:SetFrameLevel(baseLevel)
                    slot.parentedToGrid = true
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

-- Helper to update the virtual grid
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

    local ok, errorMessage = pcall(doUpdateGridLogic, self, scroll, availableWidth, frameHeight)

    self.isUpdatingScroll = false

    if not ok then
        GBCR.Output:Error("updateVirtualGrid error: %s", tostring(errorMessage))
    end
end

-- Helper to create our own custom resizer akin to what the AceGUI tree group container uses
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

            if originalOnRelease then
                originalOnRelease(widget)
            end
        end
    end

    content.paneResizer.UpdateMath = onUpdateMath

    return content.paneResizer
end

-- Helper to define item button methods once
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
        type = UI.itemButtonWidgetType,
        width = 40,
        height = 40
    }

    for methodName, methodFunction in pairs(widgetMethods) do
        widget[methodName] = methodFunction
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

-- Helper to register our custom widget and custom layouts with AceGUI
local function registerCustomUI(self)
    aceGUI:RegisterWidgetType(self.itemButtonWidgetType, itemButtonWidget, self.itemButtonWidgetVersion)

    aceGUI:RegisterLayout("GBCR_AppLayout", function(content, children)
        local topBar = children[1]
        local tabs = children[2]
        local bottomBar = children[3]

        local topHeight, bottomHeight = 0, 0
        local contentWidth = content:GetWidth() or 0

        if topBar then
            topBar.frame:ClearAllPoints()
            topBar.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            topBar.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            topBar:SetWidth(contentWidth)
            topBar.frame:SetHeight(16)
            topBar.frame:Show()
            topHeight = 16

            if UI.clockLabel then
                UI.clockLabel.frame:ClearAllPoints()
                UI.clockLabel.frame:SetPoint("LEFT", topBar.content, "LEFT", 14, 0)
                UI.clockLabel.frame:SetWidth(32)
                UI.clockLabel.frame:SetHeight(16)
                if UI.clockLabel.label then
                    UI.clockLabel.label:SetJustifyV("MIDDLE")
                end
            end

            if UI.topBar and UI.topBar.topBarText then
                local topBarText = UI.topBar.topBarText
                topBarText.frame:ClearAllPoints()
                topBarText.frame:SetPoint("LEFT", topBar.content, "LEFT", 60, 0)
                topBarText.frame:SetPoint("RIGHT", topBar.content, "RIGHT", -8, 0)
                topBarText.frame:SetHeight(16)
                topBarText:SetWidth(700)
                if topBarText.label then
                    topBarText.label:SetJustifyV("MIDDLE")
                end
            end

            if UI.syncDot then
                UI.syncDot:ClearAllPoints()
                UI.syncDot:SetPoint("LEFT", topBar.frame, "LEFT", 2, 0)
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

            bottomHeight = math_max(bottomBar.frame:GetHeight(), 26)
            bottomBar.frame:SetHeight(bottomHeight)
        end

        if tabs then
            tabs.frame:ClearAllPoints()
            tabs.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -topHeight)
            tabs.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, bottomHeight)
            tabs.frame:Show()
            tabs:SetWidth(content:GetWidth())
            tabs:SetHeight(content:GetHeight() - topHeight - bottomHeight)

            if tabs.PerformLayout then
                tabs:PerformLayout()
            end
        end
    end)

    aceGUI:RegisterLayout("GBCR_TopBottom", function(content, children)
        local topWidget = children[1]
        local bottomWidget = children[2]

        local width = content:GetWidth() or 0
        local height = content:GetHeight() or 0
        local topHeight = 0

        if topWidget then
            topWidget.frame:ClearAllPoints()
            topWidget.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            topWidget.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            topWidget:SetWidth(width)
            topWidget.frame:Show()

            if topWidget.PerformLayout then
                topWidget:PerformLayout()
            end

            topHeight = topWidget.frame:GetHeight()
        end

        if bottomWidget then
            bottomWidget.frame:ClearAllPoints()
            bottomWidget.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -topHeight)
            bottomWidget.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
            bottomWidget.frame:Show()
            bottomWidget:SetHeight(height - topHeight)
            bottomWidget:SetWidth(width)

            if bottomWidget.PerformLayout then
                bottomWidget:PerformLayout()
            end
        end
    end)

    aceGUI:RegisterLayout("GBCR_TwoPane", function(content, children)
        local leftPane = children[1]
        local rightPane = children[2]

        local width = content:GetWidth() or 0
        local height = content:GetHeight() or 0

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

            UI.activeCartLeftPaneWidth = newWidth

            if GBCR.db then
                GBCR.db.profile.framePositions.panes = GBCR.db.profile.framePositions.panes or {}
                GBCR.db.profile.framePositions.panes.cartLeft = newWidth
            end

            content.obj:PerformLayout()
        end)

        local maxAllowedLeft = width - 300 - resizer:GetWidth()
        local effectiveLeftWidth = UI.activeCartLeftPaneWidth

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
            leftPane.frame:SetHeight(height)
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
            rightPane.frame:SetWidth(width - effectiveLeftWidth - resizer:GetWidth())
            rightPane.frame:SetHeight(height)
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

            UI.activePreviewRightPaneWidth = newWidth

            if GBCR.db then
                GBCR.db.profile.framePositions.panes = GBCR.db.profile.framePositions.panes or {}
                GBCR.db.profile.framePositions.panes.previewRight = newWidth
            end

            content.obj:PerformLayout()
        end)

        local maxAllowedPreview = contentWidth - 218 - resizer:GetWidth()
        local effectivePreviewWidth = UI.activePreviewRightPaneWidth

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
        local width = content:GetWidth() or 0
        local height = content:GetHeight() or 0
        local half = math_max(1, math_floor((width - 6) / 2))

        if left then
            left.frame:ClearAllPoints()
            left.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            left.frame:SetWidth(half)
            left.frame:SetHeight(height)
            left.frame:Show()
            left:SetWidth(half)
            left:SetHeight(height)
            if left.PerformLayout then
                left:PerformLayout()
            end
        end
        if right then
            right.frame:ClearAllPoints()
            right.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
            right.frame:SetWidth(half)
            right.frame:SetHeight(height)
            right.frame:Show()
            right:SetWidth(half)
            right:SetHeight(height)
            if right.PerformLayout then
                right:PerformLayout()
            end
        end
    end)
end

-- Helper to display a dialog with pre-highlighted text for the user to copy with Ctrl + C
local function showCopyDialog(title, text)
    local frame = aceGUI:Create("Frame")
    frame:SetTitle(title or "Copy")
    frame:SetWidth(520)
    frame:SetHeight(380)
    frame:SetLayout("Fill")
    frame:SetCallback("OnClose", callbacks.onCloseCopyDialog)
    frame.frame:SetClampedToScreen(true)
    frame.frame:SetPoint("CENTER", Globals.UIParent, "CENTER")
    frame:SetStatusText("Select text and press Ctrl + C to copy")

    local box = aceGUI:Create("MultiLineEditBox")
    box:SetLabel("")
    box:DisableButton(true)
    box:SetFullWidth(true)
    box:SetFullHeight(true)
    box:SetText(text)
    frame:AddChild(box)

    frame:Show()
    if box.editBox then
        box.editBox:SetFocus()
        box.editBox:HighlightText()
    end
end

-- Helper to create an efficient virtual scroll
local function createVirtualScroll(aceParent, rowHeight, renderFn)
    local virtualScroll = {rowHeight = rowHeight or 20, renderFn = renderFn, data = {}, pool = {}}
    local scrollBarWidth = 16

    local scrollFrame = CreateFrame("ScrollFrame", nil, aceParent.content)
    scrollFrame:SetPoint("TOPLEFT", aceParent.content, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", aceParent.content, "BOTTOMRIGHT", -scrollBarWidth, 0)
    scrollFrame:EnableMouse(true)
    virtualScroll.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    virtualScroll.content = content

    local scrollbar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
    scrollbar:SetPoint("TOPRIGHT", aceParent.content, "TOPRIGHT", 0, -16)
    scrollbar:SetPoint("BOTTOMRIGHT", aceParent.content, "BOTTOMRIGHT", 0, 16)
    scrollbar:SetWidth(scrollBarWidth)
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValue(0)
    scrollbar:SetValueStep(virtualScroll.rowHeight)
    scrollbar:SetObeyStepOnDrag(true)
    scrollbar:Hide()
    virtualScroll.scrollbar = scrollbar

    local function ensurePool(needed)
        while #virtualScroll.pool < needed do
            local frame = CreateFrame("Frame", nil, virtualScroll.content)
            frame:SetHeight(virtualScroll.rowHeight)
            frame:Hide()
            virtualScroll.pool[#virtualScroll.pool + 1] = frame
        end
    end

    local function repaint()
        local data = virtualScroll.data
        local total = #data
        local scrollRowHeight = virtualScroll.rowHeight
        local scroll = virtualScroll.scrollFrame:GetVerticalScroll()
        local scrollFrameHeight = virtualScroll.scrollFrame:GetHeight()

        local firstRow = math_floor(scroll / scrollRowHeight)
        local lastRow = math_floor((scroll + scrollFrameHeight) / scrollRowHeight)
        firstRow = math_max(0, firstRow - 1)
        lastRow = math_min(total - 1, lastRow + 1)

        for _, frame in ipairs(virtualScroll.pool) do
            frame:Hide()
        end

        local poolIndex = 1

        for rowIndex = firstRow, lastRow do
            local dataIndex = rowIndex + 1
            if dataIndex > total then
                break
            end

            local frame = virtualScroll.pool[poolIndex]
            if not frame then
                break
            end

            poolIndex = poolIndex + 1

            frame:SetPoint("TOPLEFT", virtualScroll.content, "TOPLEFT", 0, -rowIndex * scrollRowHeight)
            frame:SetWidth(virtualScroll.content:GetWidth())
            frame:Show()
            virtualScroll.renderFn(frame, data[dataIndex], dataIndex)
        end
    end

    local function refresh()
        local scrollFrameHeight = virtualScroll and virtualScroll.scrollFrame and virtualScroll.scrollFrame:GetHeight() or 0
        if scrollFrameHeight < 1 then
            return
        end

        local total = #virtualScroll.data
        local scrollRowHeight = virtualScroll.rowHeight
        local totalRowHeight = math_max(1, total * scrollRowHeight)

        virtualScroll.content:SetHeight(totalRowHeight)

        if virtualScroll.scrollbar then
            local maxScrollValue = math_max(0, totalRowHeight - scrollFrameHeight)
            if maxScrollValue > 0 then
                virtualScroll.scrollbar:SetMinMaxValues(0, maxScrollValue)
                local currentScrollValue = math_min(virtualScroll.scrollFrame:GetVerticalScroll(), maxScrollValue)
                virtualScroll.scrollFrame:SetVerticalScroll(currentScrollValue)
                virtualScroll.scrollbar:SetValue(currentScrollValue)
                virtualScroll.scrollbar:Show()
            else
                virtualScroll.scrollbar:SetMinMaxValues(0, 0)
                virtualScroll.scrollbar:SetValue(0)
                virtualScroll.scrollbar:Hide()
                virtualScroll.scrollFrame:SetVerticalScroll(0)
            end
        end

        local visible = math_ceil(scrollFrameHeight / scrollRowHeight) + 2
        ensurePool(visible)
        repaint()
    end

    local function setData(dataArray)
        virtualScroll.data = dataArray or {}
        refresh()
    end

    local function destroy()
        if virtualScroll.scrollFrame then
            virtualScroll.scrollFrame:SetScript("OnMouseWheel", nil)
            virtualScroll.scrollFrame:SetScript("OnVerticalScroll", nil)
            virtualScroll.scrollFrame:SetScript("OnSizeChanged", nil)
            virtualScroll.scrollFrame:Hide()
            virtualScroll.scrollFrame:SetParent(nil)
        end

        if virtualScroll.scrollbar then
            virtualScroll.scrollbar:SetScript("OnValueChanged", nil)
            virtualScroll.scrollbar:Hide()
            virtualScroll.scrollbar:SetParent(nil)
        end

        if virtualScroll.content then
            virtualScroll.content:Hide()
            virtualScroll.content:SetParent(nil)
        end

        for _, frame in ipairs(virtualScroll.pool) do
            frame:Hide()
            frame:SetParent(nil)
        end

        virtualScroll.pool = {}
        virtualScroll.data = {}
        virtualScroll.renderFn = nil
        virtualScroll.scrollFrame = nil
        virtualScroll.content = nil
        virtualScroll.scrollbar = nil
    end

    scrollbar:SetScript("OnValueChanged", function(_, value, isUser)
        if isUser then
            scrollFrame:SetVerticalScroll(value)
            repaint()
        end
    end)

    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local currentScrollValue = scrollFrame:GetVerticalScroll()
        local maxScrollValue = math_max(0, virtualScroll.content:GetHeight() - scrollFrame:GetHeight())
        local newScrollValue = math_max(0, math_min(maxScrollValue, currentScrollValue - delta * virtualScroll.rowHeight * 3))

        scrollFrame:SetVerticalScroll(newScrollValue)
        if scrollbar:IsShown() then
            scrollbar:SetValue(newScrollValue)
        end
        repaint()
    end)

    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
        refresh()
    end)

    virtualScroll.SetData = setData
    virtualScroll.Destroy = destroy

    return virtualScroll
end

-- Helper that streams lines from an iterator function into a VirtualScroll viewer
local function renderStreamingTextArea(container, lineIteratorFn, onDone)
    local wrapper = aceGUI:Create("SimpleGroup")
    wrapper:SetFullWidth(true)
    wrapper:SetFullHeight(true)
    wrapper:SetLayout("GBCR_TopBottom")
    container:AddChild(wrapper)

    local controlRow = aceGUI:Create("SimpleGroup")
    controlRow:SetFullWidth(true)
    controlRow:SetLayout("Flow")
    wrapper:AddChild(controlRow)

    local progressLabel = aceGUI:Create("Label")
    progressLabel:SetText("Building export...")
    progressLabel:SetWidth(220)
    controlRow:AddChild(progressLabel)

    local copyExportbtn = aceGUI:Create("Button")
    copyExportbtn:SetText("Copy all")
    copyExportbtn:SetWidth(90)
    copyExportbtn:SetDisabled(true)
    controlRow:AddChild(copyExportbtn)

    local vsGroup = aceGUI:Create("SimpleGroup")
    vsGroup:SetFullWidth(true)
    vsGroup:SetFullHeight(true)
    vsGroup:SetLayout("Fill")
    wrapper:AddChild(vsGroup)

    local virtualScroll = createVirtualScroll(vsGroup, 18, function(frame, row)
        if not frame.frameFontString then
            frame.frameFontString = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            frame.frameFontString:SetPoint("LEFT", frame, "LEFT", 4, 0)
            frame.frameFontString:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
            frame.frameFontString:SetJustifyH("LEFT")
            frame.frameFontString:SetWordWrap(false)
        end
        frame.frameFontString:SetText(row.text or "")
        frame.frameFontString:Show()
    end)

    UI.streamGeneration = (UI.streamGeneration or 0) + 1
    vsGroup:SetUserData("module", UI)
    vsGroup:SetUserData("virtualScroll", virtualScroll)
    vsGroup:SetCallback("OnRelease", callbacks.onReleaseVirtualScrollGroup)

    local BATCH = 300 -- TODO

    local allLines = {}
    local allStrings = {}
    local myGeneration = UI.streamGeneration

    local function collect()
        if myGeneration ~= UI.streamGeneration then
            return
        end

        local count = 0
        while count < BATCH do
            local line = lineIteratorFn()

            if line == nil then
                virtualScroll.SetData(allLines)
                progressLabel:SetText(string_format("Lines: %d", #allStrings))
                copyExportbtn:SetDisabled(false)
                copyExportbtn:SetUserData("allStrings", allStrings)
                copyExportbtn:SetCallback("OnClick", callbacks.onClickCopyExportbtn)

                if onDone then
                    onDone(allStrings)
                end

                return
            end

            allLines[#allLines + 1] = {text = line}
            allStrings[#allStrings + 1] = line
            count = count + 1
        end

        virtualScroll.SetData(allLines)
        progressLabel:SetText(string_format("Loading... %d lines", #allStrings))

        After(0, collect)
    end

    After(0, collect)

    return virtualScroll
end

-- Helper callback for the browse tab: item click populates preview
function callbacks.onClickBrowseItem(_, _, item)
    if eventHandler(item, "OnClick") then
        return
    end

    UI.preview.selectedItem = item

    local itemKey = item.itemString or tostring(item.itemId or 0)
    local alreadyInCart = UI.cartData[itemKey] and UI.cartData[itemKey].qty or 0
    local availableToRequest = item.itemCount - alreadyInCart

    if availableToRequest > 0 then
        UI.preview.slider:SetDisabled(false)
        UI.preview.slider:SetSliderValues(1, availableToRequest, 1)
        UI.preview.slider:SetValue(1)
        UI.preview.button:SetDisabled(false)
    else
        UI.preview.slider:SetDisabled(true)
        UI.preview.slider:SetValue(0)
        UI.preview.button:SetDisabled(true)
    end

    if not UI.preview.isScrollAttached then
        UI.preview:AddChild(UI.preview.scroll)
        UI.preview.isScrollAttached = true
        UI.preview:PerformLayout()
    end

    populateCustomTooltip()
end

-- Helper callback for the browse tab: dragging an item to search
function callbacks.onDragStartBrowseItem(_, _, item)
    eventHandler(item, "OnDragStart")
end

-- Helper callback for the browse tab: mouse over an item
function callbacks.onEnterBrowseItem(_, _, item)
    local link = (item.itemInfo and item.itemInfo.realLink) or item.itemLink
    showItemTooltip(link, item.sources)
end

-- Helper callback for the browse tab: mouse leave an item
function callbacks.onLeaveBrowseItem()
    hideTooltip()
end

-- Helper callback for the copy dialog closing
function callbacks.onCloseCopyDialog(widget)
    aceGUI:Release(widget)
end

-- Helper callback for the exports: open copy dialog
function callbacks.onClickCopyExportbtn(widget)
    local allStrings = widget:GetUserData("allStrings")

    showCopyDialog("Export", table_concat(allStrings, "\n"))
end

-- Helper callback for the my request list tab: copy import code
function callbacks.onClickCopyImportCartBtn()
    local code = UI.cart and UI.cart.importBox and UI.cart.importBox:GetText()
    if code and string_match(code, "^" .. importPrefix) then
        showCopyDialog("Import code", code)
    end
end

-- Helper callback for the streaming of export data
function callbacks.onReleaseVirtualScrollGroup(widget)
    local module = widget:GetUserData("module")
    local virtualScroll = widget:GetUserData("virtualScroll")

    module.streamGeneration = (module.streamGeneration or 0) + 1

    if virtualScroll then
        virtualScroll.Destroy()
    end
end

-- ================================================================================================ -- browse tab

-- Helper to sort items based on the selected sort mode
local function sortItems(items, mode)
    if not items then
        return
    end

    table_sort(items, Constants.SORT_COMPARATORS[mode] or Constants.SORT_COMPARATORS.default)
end

-- Helper to parse a search query into tokens (splitting "q:rare lvl>40 sword" into {"q:rare", "lvl>40", "sword"})
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

-- Helper to evaluate a single item against a list of parsed tokens
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

-- Helper to build the search index
local function buildSearchData(self, callback)
    self.buildSearchGeneration = (self.buildSearchGeneration or 0) + 1
    local myGeneration = self.buildSearchGeneration

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
        if myGeneration ~= self.buildSearchGeneration then
            GBCR.Output:Debug("SEARCH", "buildSearchData aborted (stale generation %d)", myGeneration)

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

        if myGeneration ~= self.buildSearchGeneration then
            return
        end

        if callback then
            callback()
        end
    end

    After(0, Resume)
end

-- Helper to populate the list of guild bank alts
local function updateBankDropdown(self)
    if not self.filters or not self.filters.bankDropdown or self.currentTab ~= "browse" then
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

-- Helper to draw the right panel for the browse tab
local function drawBrowsePanel(self, container)
    container:ReleaseChildren()
    container:SetLayout("GBCR_ThreePane")

    -- Search and filters
    local filters = aceGUI:Create("SimpleGroup")
    filters:SetLayout("Flow")
    container:AddChild(filters)
    self.filters = filters

    local searchWrapper = aceGUI:Create("SimpleGroup")
    searchWrapper:SetWidth(250)
    searchWrapper:SetHeight(44)
    searchWrapper:SetLayout("Fill")
    searchWrapper.frame:EnableMouse(true)
    searchWrapper.frame:SetScript("OnReceiveDrag", callbacks.onSearchDrop)
    searchWrapper.frame:SetScript("OnMouseUp", callbacks.onSearchDrop)

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
        UI.searchText = text
        UI.searchTokens = parseSearchQuery(text)

        if self.searchTimer then
            self.searchTimer:Cancel()
        end
        self.searchTimer = NewTimer(Constants.TIMER_INTERVALS.SEARCH_DEBOUNCE, function()
            UI:RefreshUI()
        end)
    end)
    searchInput:SetScript("OnEnterPressed", function(input)
        UI.searchText = input:GetText()
        input:ClearFocus()
    end)
    searchInput:SetScript("OnReceiveDrag", callbacks.onSearchDrop)
    searchInput:SetScript("OnMouseDown", callbacks.onSearchDrop)
    searchWrapper:SetUserData("module", self)
    searchWrapper:SetCallback("OnRelease", callbacks.onReleaseSearchWrapper)
    self.searchWrapper = searchWrapper
    filters:AddChild(searchWrapper)

    local sortDropdown = aceGUI:Create("Dropdown")
    sortDropdown:SetLabel("Sort")
    sortDropdown:SetList(Constants.SORT_LIST, Constants.SORT_ORDER)
    sortDropdown:SetWidth(150)
    sortDropdown.label:SetFontObject(GameFontNormal)
    sortDropdown:SetValue(GBCR.Options:GetSortMode())
    sortDropdown:SetUserData("module", self)
    sortDropdown:SetCallback("OnValueChanged", callbacks.onValueChangedSortDropdown)
    filters:AddChild(sortDropdown)
    self.filters.sortDropdown = sortDropdown

    self.lastBankDropdownHash = nil
    local guildBankAltDropdown = aceGUI:Create("Dropdown")
    guildBankAltDropdown:SetLabel("Filter on guild bank")
    guildBankAltDropdown:SetWidth(250)
    guildBankAltDropdown.label:SetFontObject(GameFontNormal)
    guildBankAltDropdown:SetUserData("module", self)
    guildBankAltDropdown:SetCallback("OnValueChanged", callbacks.onValueChangedGuildBankAltDropdown)
    self.filters.bankDropdown = guildBankAltDropdown
    updateBankDropdown(self)
    filters:AddChild(guildBankAltDropdown)

    local rarity = aceGUI:Create("Dropdown")
    rarity:SetLabel("Filter on rarity")
    rarity:SetList(Constants.FILTER.RARITY_LIST, Constants.FILTER.RARITY_ORDER)
    rarity:SetValue(self.activeRarity or "any")
    rarity:SetWidth(150)
    rarity.label:SetFontObject(GameFontNormal)
    rarity:SetUserData("module", self)
    rarity:SetCallback("OnValueChanged", callbacks.onValueChangedRarityDropdown)
    filters:AddChild(rarity)
    self.filters.rarity = rarity

    local resetFiltersBtn = aceGUI:Create("Button")
    resetFiltersBtn:SetText("Reset filters")
    resetFiltersBtn:SetWidth(100)
    resetFiltersBtn:SetDisabled(true)
    resetFiltersBtn:SetUserData("module", self)
    resetFiltersBtn:SetCallback("OnClick", callbacks.onClickResetFiltersBtn)
    filters:AddChild(resetFiltersBtn)
    self.filters.resetBtn = resetFiltersBtn

    -- Item grid
    local gridContainer = aceGUI:Create("InlineGroup")
    gridContainer:SetTitle("")
    gridContainer:SetLayout("Fill")
    container:AddChild(gridContainer)
    self.grid = gridContainer

    local scroll = aceGUI:Create("ScrollFrame")
    scroll:SetLayout(nil)
    gridContainer:AddChild(scroll)
    self.grid.scroll = scroll

    local emptyLabel = scroll.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyLabel:SetPoint("CENTER", scroll.frame, "CENTER", 0, 0)
    emptyLabel:SetText("No items found")
    emptyLabel:Hide()
    self.emptyLabel = emptyLabel

    -- Item preview
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

    local addToRequestListBtn = aceGUI:Create("Button")
    addToRequestListBtn:SetText("Add to request list")
    addToRequestListBtn:SetFullWidth(true)
    addToRequestListBtn:SetDisabled(true)
    addToRequestListBtn:SetCallback("OnClick", callbacks.onClickAddToRequestListBtn)
    preview:AddChild(addToRequestListBtn)
    self.preview.button = addToRequestListBtn

    local tooltipScroll = aceGUI:Create("ScrollFrame")
    tooltipScroll:SetLayout("Fill")
    tooltipScroll:SetFullWidth(true)
    tooltipScroll:SetFullHeight(true)
    tooltipScroll:SetUserData("module", self)
    tooltipScroll:SetCallback("OnRelease", callbacks.onReleaseTooltipScroll)
    if not tooltipScroll.frame.gbcrSizeHooked then
        tooltipScroll.frame:HookScript("OnSizeChanged", callbacks.onSizeChangedResizeVirtualGrid)
        tooltipScroll.frame.gbcrSizeHooked = true
    end
    self.preview.scroll = tooltipScroll

    self.customTooltip = self.customTooltip or createCustomTooltip(tooltipScroll.content)
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
        scroll.frame:HookScript("OnSizeChanged", callbacks.onSizeChangedResizeVirtualGrid)
        scroll.frame.gbcrSizeHooked = true
    end
end

-- Helper to draw the browse tab with the tree and the right panel
local function drawBrowseTab(self, container)
    if not self.tree then
        local tree = aceGUI:Create("TreeGroup")
        tree:SetLayout("Fill")
        tree:SetTree(self.filterTree)
        tree:SetStatusTable(self.treeStatusTable)
        tree:SetCallback("OnGroupSelected", callbacks.onGroupSelectedTree)
        self.tree = tree
    end

    container:AddChild(self.tree)

    self.tree:SelectByValue(self.activeTreeGroup or "any")
end

-- Callback for dragging an item directly into the search box
function callbacks.onChatEdit_InsertLink(self, itemLink)
    if not self.searchField or not self.searchField:HasFocus() then
        return
    end

    local plainName = string_match(itemLink, "%[(.+)%]") or itemLink
    self.searchField:SetText(plainName)
    UI.searchText = string_lower(plainName)

    if self.searchTimer then
        self.searchTimer:Cancel()
    end
    self.searchTimer = NewTimer(Constants.TIMER_INTERVALS.SEARCH_DEBOUNCE, function()
        UI:RefreshUI()
    end)
    self.searchField:ClearFocus()
end

-- Helper callback for the browse tab: release
function callbacks.onReleaseSearchWrapper(widget)
    local module = widget:GetUserData("module")

    if module.searchField then
        module.searchField:Hide()
        module.searchField:SetParent(UIParent)
        module.searchLabel:Hide()
        module.searchLabel:SetParent(UIParent)
    end
end

-- Helper callback for the browse tab: release
function callbacks.onReleaseTooltipScroll(widget)
    local module = widget:GetUserData("module")

    if module.customTooltip then
        module.customTooltip:Hide()
        module.customTooltip:ClearAllPoints()
        module.customTooltip:SetParent(UIParent)
    end
end

-- Helper callback for the browse tab: reset filters
function callbacks.onClickResetFiltersBtn(widget)
    local module = widget:GetUserData("module")

    UI.searchText = ""
    if _G["GBankClassicSearch"] then
        _G["GBankClassicSearch"]:SetText("")
    end
    module.activeRarity = "any"
    module.filters.rarity:SetValue("any")
    module.activeTreeFilter = module.filterCategories["any"]
    module.activeTreeGroup = "any"
    module.tree:SelectByValue("any")
    module.currentView = "Show all guild banks"
    module.filters.bankDropdown:SetValue("Show all guild banks")
    UI:RefreshUI()
end

-- Helper callback for the browse tab: changing sort
function callbacks.onValueChangedSortDropdown(widget, _, value)
    local module = widget:GetUserData("module")

    GBCR.Options:SetSortMode(value)
    if module.cachedFilteredList and #module.cachedFilteredList > 0 then
        sortItems(module.cachedFilteredList, value)
        if updateVirtualGrid then
            updateVirtualGrid(module)
        end
    end
end

-- Helper callback for the browse tab: changing guild bank
function callbacks.onValueChangedGuildBankAltDropdown(widget, _, value)
    local module = widget:GetUserData("module")

    module.currentView = value
    module:RefreshUI()
end

-- Helper callback for the browse tab: changing rarity
function callbacks.onValueChangedRarityDropdown(widget, _, key)
    local module = widget:GetUserData("module")

    module.activeRarity = key
    module:RefreshUI()
end

-- Helper callback for the browse tab: dropping an item into search
function callbacks.onSearchDrop()
    local cursorType, _, info = GetCursorInfo()
    if cursorType == "item" and info then
        local itemName = string_match(info, "%[(.+)%]")
        if itemName then
            local searchInput = _G["GBankClassicSearch"]
            UI.searchText = itemName
            searchInput:SetText(itemName)
            ClearCursor()
            searchInput:ClearFocus()

            return true
        end
    end

    return false
end

-- Helper callback for the browse tab: resizing the virtual grid
function callbacks.onSizeChangedResizeVirtualGrid()
    local module = UI
    if module.resizeTimer then
        return
    end

    module.resizeTimer = NewTimer(0.05, function()
        module.resizeTimer = nil
        if module.currentTab == "browse" and module.grid and module.grid.scroll then
            module.grid.scroll:FixScroll()
            updateVirtualGrid(module)
            populateCustomTooltip()
        end
    end)
end

-- Helper callback for the browse tab: selecting something in the filter tree
function callbacks.onGroupSelectedTree(widget, _, selectedGroup)
    local module = UI
    if module.preview then
        module.preview.selectedItem = nil
        module.preview.label:SetText("")
        module.preview.slider:SetDisabled(true)
        module.preview.slider:SetSliderValues(1, 1, 1)
        module.preview.slider:SetValue(0)
        module.preview.button:SetDisabled(true)
        module.customTooltip:Hide()
    end

    local selectedValue = string_match(selectedGroup, "[^%c]+$") or selectedGroup

    if module.browsePanelDrawn and module.activeTreeGroup == selectedGroup and module.activeTreeFilter ==
        module.filterCategories[selectedValue] then
        return
    end

    module.activeTreeFilter = module.filterCategories[selectedValue]
    module.activeTreeGroup = selectedGroup

    if not module.browsePanelDrawn then
        drawBrowsePanel(module, widget)
        module.browsePanelDrawn = true
    end

    UI:RefreshUI()
end

-- ================================================================================================ -- my request list ("cart") tab

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

-- Helper to generate a small encoded import string to paste on Discord for request fulfillment
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

    return importPrefix .. GBCR.Libs.LibDeflate:EncodeForPrint(compressed)
end

-- Helper to parse the encoded import string for request fulfillment
local function parseImportString(str)
    if not str then
        return nil, "empty input"
    end

    local encoded = string_match(str, "^" .. importPrefix .. "(.+)$")
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

-- Helper to retrieve the item name for items in the request list
local function getCartItemName(data, key)
    if data.itemInfo and not data.itemInfo.isFallback and data.itemInfo.name then
        return data.itemInfo.name
    end

    if data.itemLink then
        local n = string_match(data.itemLink, "%[(.-)%]")
        if n and not string_match(n, "^item:%d") then
            return n
        end
    end

    return "Item #" .. tostring(key)
end

-- Helper to draw the my request list tab with a left pane for cart review and a right pane for copying text
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
    emptyCartBtn:SetCallback("OnClick", callbacks.onClickEmptyCartBtn)
    cartActions:AddChild(emptyCartBtn)
    self.cart.actions.emptyCart = emptyCartBtn

    local refreshCartExportBtn = aceGUI:Create("Button")
    refreshCartExportBtn:SetText("Prepare export")
    refreshCartExportBtn:SetRelativeWidth(0.48)
    refreshCartExportBtn:SetCallback("OnClick", callbacks.onClickRefreshCartExportBtn)
    cartActions:AddChild(refreshCartExportBtn)
    self.cart.actions.refreshExport = refreshCartExportBtn

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

    local rightWrapper = aceGUI:Create("SimpleGroup")
    rightWrapper:SetLayout("GBCR_TopBottom")
    split:AddChild(rightWrapper)
    self.cart.rightPane = rightWrapper

    -- Top import code
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

    local copyImportCartBtn = aceGUI:Create("Button")
    copyImportCartBtn:SetText("Copy import code")
    copyImportCartBtn:SetFullWidth(true)
    copyImportCartBtn:SetDisabled(true)
    copyImportCartBtn:SetCallback("OnClick", callbacks.onClickCopyImportCartBtn)
    importGroup:AddChild(copyImportCartBtn)
    self.cart.copyImportCartBtn = copyImportCartBtn

    -- Bottom Discord export
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

    if self.cartCount == 0 then
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
            row:SetUserData("table", {columns = {50, 1, 110}})

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
            btn:SetCallback("OnEnter", callbacks.onEnterCartIcon)
            btn:SetCallback("OnClick", callbacks.onClickCartIcon)
            btn:SetCallback("OnDragStart", callbacks.onDragStartCartIcon)
            btn:SetCallback("OnLeave", callbacks.onLeaveCartIcon)
            row:AddChild(btn)

            local cartQuantitySlider = aceGUI:Create("Slider")
            cartQuantitySlider:SetFullWidth(true)
            cartQuantitySlider:SetLabel(plainName)
            cartQuantitySlider:SetSliderValues(1, data.itemCount, 1)
            cartQuantitySlider:SetValue(data.qty)
            cartQuantitySlider:SetUserData("itemKey", itemKey)
            cartQuantitySlider:SetCallback("OnValueChanged", callbacks.onValueChangedCartQuantitySlider)
            row:AddChild(cartQuantitySlider)

            local cartRemoveBtn = aceGUI:Create("Button")
            cartRemoveBtn:SetText("Remove")
            cartRemoveBtn:SetWidth(100)
            cartRemoveBtn:SetUserData("itemKey", itemKey)
            cartRemoveBtn:SetCallback("OnClick", callbacks.onClickCartRemoveBtn)
            row:AddChild(cartRemoveBtn)

            cartScroll:AddChild(row)
        end
    end
end

-- Helper callback for the my request list tab: button to open my request list
function callbacks.onClickViewRequestList()
    UI.tabs:SelectTab("cart")
end

-- Helper callback for the my request list tab: generate an export for Discord to manually request the contents of the cart
function callbacks.onClickRefreshCartExportBtn()
    local module = UI
    if module.cartCount == 0 then
        if module.cart and module.cart.exportArea then
            module.cart.exportArea:ReleaseChildren()
            local lbl = aceGUI:Create("Label")
            lbl:SetFullWidth(true)
            lbl:SetText("Your request list is empty, browse to add items")
            module.cart.exportArea:AddChild(lbl)
            module.cart.exportArea:DoLayout()
        end

        return
    end

    -- Build allocations
    local allocationsByBank = {}
    local unassignedItems = {}

    for _, sortedItem in ipairs(module.sortedCartItems) do
        local plainName = sortedItem.name
        local data = sortedItem.data
        local remaining = data.qty
        local enchant = data.enchantText

        if not enchant and data.itemLink then
            enchant = getEnchantTextFromTooltip(module, data.itemLink)
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

    -- Populate import code box
    local importStr = generateImportString(module.sortedCartItems)
    if module.cart and module.cart.importBox then
        module.cart.importBox:SetText(importStr or "nothing to do")
        module.cart.importBox:SetDisabled(false)
        if module.cart.copyImportCartBtn then
            module.cart.copyImportCartBtn:SetDisabled(importStr == nil)
        end
    end

    -- Measure Discord chunk info
    local totalChars = 0
    for _, ln in ipairs(lines) do
        totalChars = totalChars + string_len(ln) + 1
    end
    local numChunks = math_ceil(totalChars / discordMaxChar)

    local chunkNote = numChunks > 1 and Globals.ColorizeText(Constants.COLORS.ORANGE,
                                                             string_format(
                                                                 "Note: %d characters, split into %d Discord messages (maximum %d characters each)",
                                                                 totalChars, numChunks, discordMaxChar)) or
                          Globals.ColorizeText(colorGray, string_format("%d characters, fits in one Discord message", totalChars))

    -- Stream Discord text into exportArea
    if not (module.cart and module.cart.exportArea) then
        return
    end
    module.cart.exportArea:ReleaseChildren()

    local position = 1
    local function nextLine()
        if position > #lines then
            return nil
        end

        local ln = lines[position]
        position = position + 1

        return ln
    end

    -- Info label above the stream (shows chunk count)
    local infoWrapper = aceGUI:Create("SimpleGroup")
    infoWrapper:SetFullWidth(true)
    infoWrapper:SetLayout("GBCR_TopBottom")
    module.cart.exportArea:AddChild(infoWrapper)

    local infoLabel = aceGUI:Create("Label")
    infoLabel:SetFullWidth(true)
    infoLabel:SetText(chunkNote)
    infoWrapper:AddChild(infoLabel)

    local streamGroup = aceGUI:Create("SimpleGroup")
    streamGroup:SetFullWidth(true)
    streamGroup:SetFullHeight(true)
    streamGroup:SetLayout("Fill")
    infoWrapper:AddChild(streamGroup)

    renderStreamingTextArea(streamGroup, nextLine)
end

-- Helper callback for the my request list tab: mouse over an item
function callbacks.onEnterCartIcon(widget)
    local data = widget:GetUserData("itemData")

    showItemTooltip(data.itemLink, data.sources)
end

-- Helper callback for the my request list tab: mouse leave an item
function callbacks.onLeaveCartIcon()
    hideTooltip()
end

-- Helper callback for the my request list tab: click an item
function callbacks.onClickCartIcon(widget)
    local data = widget:GetUserData("itemData")

    eventHandler(data, "OnClick")
end

-- Helper callback for the my request list tab: drag an item
function callbacks.onDragStartCartIcon(widget)
    local data = widget:GetUserData("itemData")

    eventHandler(data, "OnDragStart")
end

-- ================================================================================================ -- ledger tab

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

    local ledgerAltDropdown = aceGUI:Create("Dropdown")
    ledgerAltDropdown:SetLabel("Filter on guild bank")
    ledgerAltDropdown:SetWidth(250)
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
    ledgerAltDropdown:SetList(altList, altOrder)
    ledgerAltDropdown:SetValue("Show all guild banks")
    controlGroup:AddChild(ledgerAltDropdown)

    local ledgerBtn = aceGUI:Create("Button")
    ledgerBtn:SetText("Show ledger")
    ledgerBtn:SetWidth(140)
    controlGroup:AddChild(ledgerBtn)

    local ledgerDonorsBtn = aceGUI:Create("Button")
    ledgerDonorsBtn:SetText("Show donors")
    ledgerDonorsBtn:SetWidth(140)
    controlGroup:AddChild(ledgerDonorsBtn)

    local exportLedgerBtn = aceGUI:Create("Button")
    exportLedgerBtn:SetText("Prepare export")
    exportLedgerBtn:SetWidth(140)
    controlGroup:AddChild(exportLedgerBtn)

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

    local function startBuildLedgerRows(entries, getVS, myGeneration, getGen)
        GBCR.Output:Debug("LEDGER", "startBuildLedgerRows called with %d entries (myGeneration=%d)", #entries, myGeneration)

        local rows = {}
        local currentDate = ""
        local index = 1

        local ROW_BATCH = 30 -- TODO

        local function buildRows()
            if getGen() ~= myGeneration then
                return
            end

            local endIndex = math_min(index + ROW_BATCH - 1, #entries)
            for i = index, endIndex do
                local width = entries[i]

                local entryDate = date("%b %d, %Y", width.entry[1])
                if entryDate ~= currentDate then
                    currentDate = entryDate
                    rows[#rows + 1] = {isHeader = true, text = entryDate}
                end

                local timeStr, iconPath, desc = GBCR.Ledger:FormatEntry(width.entry, width.altName)
                if timeStr and desc then
                    rows[#rows + 1] = {timeStr = timeStr, iconPath = iconPath, desc = desc}
                end
            end

            index = endIndex + 1

            local virtualScroll = getVS()

            if index <= #entries then
                if virtualScroll then
                    virtualScroll.SetData(rows)

                    local parent = virtualScroll.scrollFrame:GetParent()
                    if parent and parent.obj and parent.obj.PerformLayout then
                        parent.obj:PerformLayout()
                    end
                end

                After(0, buildRows)
            else
                if #rows == 0 then
                    rows[1] = {isHeader = true, text = "No ledger entries yet"}
                end

                if virtualScroll then
                    virtualScroll.SetData(rows)
                end
            end
        end
        After(0, buildRows)
    end

    local populateLedgerGen = 0
    local donorsViewGen = 0

    local function populateLedger(selectedAlt)
        populateLedgerGen = populateLedgerGen + 1
        local myGeneration = populateLedgerGen

        local MAX_ENTRIES = Constants.LEDGER.MAX_ENTRIES -- cap before sort to keep sort < 5ms
        local COLLECT_BATCH = 1000 -- TODO

        if selectedAlt ~= "Show all guild banks" then
            -- Single alt: small ledger, can collect synchronously
            local altData = sv and sv.alts and sv.alts[selectedAlt]
            local entries = {}

            if altData and altData.ledger then
                for _, e in ipairs(altData.ledger) do
                    entries[#entries + 1] = {entry = e, altName = selectedAlt}
                end
            end
            table_sort(entries, function(a, b)
                return a.entry[1] > b.entry[1]
            end)

            startBuildLedgerRows(entries, function()
                return ledgerVS
            end, myGeneration, function()
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

        table_sort(altPairs, function(a, b)
            local la = math_max((a.ledger[1] and a.ledger[1][1]) or 0, (a.ledger[#a.ledger] and a.ledger[#a.ledger][1]) or 0)
            local lb = math_max((b.ledger[1] and b.ledger[1][1]) or 0, (b.ledger[#b.ledger] and b.ledger[#b.ledger][1]) or 0)

            return la > lb
        end)

        local function collectBatch()
            if myGeneration ~= populateLedgerGen then
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

            table_sort(entries, function(a, b)
                return a.entry[1] > b.entry[1]
            end)

            startBuildLedgerRows(entries, function()
                return ledgerVS
            end, myGeneration, function()
                return populateLedgerGen
            end)
        end

        After(0, collectBatch)
    end

    local function clearLedgerBottomArea()
        populateLedgerGen = populateLedgerGen + 1
        donorsViewGen = donorsViewGen + 1

        if ledgerVS then
            ledgerVS.Destroy()
            ledgerVS = nil
        end
        bottomArea:ReleaseChildren()
    end

    local function showLedgerView()
        currentView = "ledger"
        clearLedgerBottomArea()

        local vsGroup = aceGUI:Create("SimpleGroup")
        vsGroup:SetFullWidth(true)
        vsGroup:SetFullHeight(true)
        vsGroup:SetLayout("Fill")
        vsGroup:SetCallback("OnRelease", callbacks.onReleaseLedgerVirtualScrollGroup)

        bottomArea:AddChild(vsGroup)
        ledgerVS = createVirtualScroll(vsGroup, 26, renderLedgerRow)
        UI.ledgerVS = ledgerVS
        UI.ledgerDataDirty = false
        populateLedger(ledgerAltDropdown:GetValue())
    end

    local function showExportView(headerText, altName)
        currentView = "export"
        clearLedgerBottomArea()

        bottomArea:SetLayout("Fill")

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
        local curLed = nil

        local function nextLine()
            if hIndex <= #headerLines then
                local l = headerLines[hIndex]
                hIndex = hIndex + 1

                return l
            end

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

                curLed = nil
                aIndex = aIndex + 1
            end

            return nil
        end

        renderStreamingTextArea(bottomArea, nextLine)
    end

    local function showDonorsView()
        currentView = "donors"
        clearLedgerBottomArea()

        donorsViewGen = donorsViewGen + 1
        local myDonorsGen = donorsViewGen

        local priceCache = {}
        local donations = {}

        local selectedAlt = ledgerAltDropdown:GetValue()

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

        local BATCH = 500 -- TODO

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

            bottomArea:ReleaseChildren()
            bottomArea:SetLayout("Fill")

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

            local function createHeaderLabel(text)
                local label = aceGUI:Create("Label")
                label:SetText(text)
                scroll:AddChild(label)
            end

            createHeaderLabel("")
            createHeaderLabel("Top 30 donors")
            createHeaderLabel("Vendor value")

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

    ledgerBtn:SetUserData("showLedgerView", showLedgerView)
    ledgerBtn:SetCallback("OnClick", callbacks.onClickLedgerBtn)

    ledgerDonorsBtn:SetUserData("showDonorsView", showDonorsView)
    ledgerDonorsBtn:SetCallback("OnClick", callbacks.onClickLedgerDonorsBtn)

    exportLedgerBtn:SetUserData("showExportView", showExportView)
    exportLedgerBtn:SetUserData("ledgerAltDropdown", ledgerAltDropdown)
    exportLedgerBtn:SetCallback("OnClick", callbacks.onClickExportLedgerBtn)

    ledgerAltDropdown:SetUserData("currentView", currentView)
    ledgerAltDropdown:SetUserData("populateLedger", populateLedger)
    ledgerAltDropdown:SetUserData("showDonorsView", showDonorsView)
    ledgerAltDropdown:SetUserData("showLedgerView", showLedgerView)
    ledgerAltDropdown:SetCallback("OnValueChanged", callbacks.onValueChangedLedgerAltDropdown)

    self.refreshLedger = function()
        if currentView == "ledger" and ledgerVS then
            populateLedger(ledgerAltDropdown:GetValue())
        elseif currentView == "donors" then
            showDonorsView()
        end
    end

    showLedgerView()
end

-- Helper callback for the ledger tab: release
function callbacks.onReleaseLedgerVirtualScrollGroup()
    if UI.ledgerVS then
        UI.ledgerVS.Destroy()
        UI.ledgerVS = nil
    end
end

-- Helper callback for the ledger tab: show ledger
function callbacks.onClickLedgerBtn(widget)
    local showLedgerView = widget:GetUserData("showLedgerView")

    showLedgerView()
end

-- Helper callback for the ledger tab: show donors
function callbacks.onClickLedgerDonorsBtn(widget)
    local showDonorsView = widget:GetUserData("showDonorsView")

    showDonorsView()
end

-- Helper callback for the ledger tab: change build bank alt
function callbacks.onValueChangedLedgerAltDropdown(widget, _, value)
    local currentView = widget:GetUserData("currentView")
    local populateLedger = widget:GetUserData("populateLedger")
    local showDonorsView = widget:GetUserData("showDonorsView")
    local showLedgerView = widget:GetUserData("showLedgerView")

    if currentView == "ledger" then
        if UI.ledgerVS then
            UI.ledgerDataDirty = false
            populateLedger(value)
        else
            showLedgerView()
        end
    elseif currentView == "donors" then
        showDonorsView()
    else
        showLedgerView()
    end
end

-- Helper callback for the ledger tab: export
function callbacks.onClickExportLedgerBtn(widget)
    local showExportView = widget:GetUserData("showExportView")
    local ledgerAltDropdown = widget:GetUserData("ledgerAltDropdown")

    local meta = buildExportMetadata()
    local selected = ledgerAltDropdown:GetValue()
    showExportView(metadataHeader(meta, "Ledger"), selected)
end

-- ================================================================================================ -- export tab

-- Helper to draw the export tab
local function drawExportTab(_, container)
    container:SetLayout("GBCR_TopBottom")

    -- Top controls
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

    -- Bottom box
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

    exportBtn:SetUserData("formatDropdown", formatDropdown)
    exportBtn:SetUserData("boxContainer", boxContainer)
    exportBtn:SetCallback("OnClick", callbacks.onClickExportBtn)
end

-- ================================================================================================ -- network tab

-- Sets the syncing state for the pulsing dot
local function setSyncing(self, active)
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

-- Helper to retrieve the network sync status metadata
local function getSyncMeta()
    local sv = GBCR.Database.savedVariables
    if not sv then
        return {}
    end

    sv.networkMeta = sv.networkMeta or {}

    return sv.networkMeta
end

-- Record a successful data transmittion to another player
local function recordSuccessfulSeed(toPlayer)
    local meta = getSyncMeta()
    meta.lastSeedTime = GetServerTime()
    meta.lastSeedTarget = toPlayer
    meta.seedCount = (meta.seedCount or 0) + 1

    local myName = GBCR.Guild:GetNormalizedPlayerName()
    local sv = GBCR.Database.savedVariables
    if sv and sv.alts and sv.alts[myName] then
        meta.lastSharedVersion = sv.alts[myName].version or 0
    end

    setSyncing(UI, false)
    UI:NotifyStateChanged()
end

-- Record a successful data receipt from another player
local function recordReceived(altName, fromPlayer)
    local meta = getSyncMeta()
    meta.lastReceiveTime = GetServerTime()
    meta.lastReceiveAlt = altName
    meta.lastReceiveSource = fromPlayer

    setSyncing(UI, false)
    UI:NotifyStateChanged()
end

-- Helper to display a summary status on top
local function getGlobalStatusText(s)
    local pluralUsers = (s.addonUserCount ~= 1 and "s" or "")

    if not s.isInGuild then
        return "NEUTRAL", "Join a guild to use this addon"
    end

    if s.isLoading then
        return "NEUTRAL", "Loading guild data..."
    end

    if s.isLockedOut then
        return "WARN", "Sync paused (combat, instance, or raid)"
    end

    if s.addonUserCount == 0 then
        return "WARN", "No other addon users detected (data syncs automatically)"
    end

    local req, recv, out = 0, 0, 0
    for _, state in pairs(GBCR.Protocol.protocolStates or {}) do
        if state == Constants.STATE.REQUESTING then
            req = req + 1
        elseif state == Constants.STATE.RECEIVING then
            recv = recv + 1
        elseif state == Constants.STATE.OUTDATED then
            out = out + 1
        end
    end

    local activity = (req + recv + out > 0) and string_format(" [%d requesting, %d downloading, %d pending]", req, recv, out) or
                         ""

    if s.syncing then
        return "INFO", string_format("Syncing with %d other addon user%s online%s", s.addonUserCount, pluralUsers, activity)
    end

    return "OK", string_format("Up to date, %d other addon user%s online%s", s.addonUserCount, pluralUsers, activity)
end

-- Helper to return the status for the currently logged in guild bank alt
local function getGuildBankStatusText(s)
    local meta = s.meta
    if not s.isGuildBankAlt then
        return nil
    end

    local myData = s.savedAlts[s.myName]
    local hasScanned = myData and myData.items and #myData.items > 0
    if not hasScanned then
        return "WARN",
               "You are a guild bank alt but have no scan data yet. Open your bank and mailbox to record your inventory, then wait for the data to sync."
    end

    local myVersion = myData.version or 0
    local lastSharedVer = meta.lastSharedVersion or 0
    local hasUnsharedChanges = myVersion > lastSharedVer

    if hasUnsharedChanges then
        if s.addonUserCount == 0 then
            return "WARN", "You have unshared changes, but no other addon users are online to receive the update."
        end

        return "INFO", "Data updated locally. Waiting to share with online members."
    end

    local seedCount = meta.seedCount or 0
    local lastSeed = meta.lastSeedTime

    if seedCount > 0 and lastSeed then
        local pluralSeed = (seedCount ~= 1 and "s" or "")
        return "OK",
               string_format(
                   "Your data is up to date and has been shared with %d peer%s this session. Last share: %s to %s.\n" ..
                       "Safe to log off.", seedCount, pluralSeed, meta.lastSeedTarget or "unknown", formatTimeAgo(lastSeed))
    end

    if s.addonUserCount == 0 then
        return "WARN", "Your data is up to date and was previously shared. No other addon users are currently online."
    end

    return "OK", "Your data is up to date and has been shared. Ready for new changes."
end

-- Helper to return the correct state status per guild bank alt
local function getAltRowState(altName, altData, s)
    if GBCR.Protocol.isLockedOut then
        return Globals.ColorizeText(colorRed, "Paused")
    end

    if altName == s.myName and s.isGuildBankAlt then
        return Globals.ColorizeText(colorGreen, "This character")
    end

    local altState = GBCR.Protocol.protocolStates and GBCR.Protocol.protocolStates[altName]

    if altState == Constants.STATE.REQUESTING then
        return Globals.ColorizeText(colorBlue, "Requesting")
    end

    if altState == Constants.STATE.RECEIVING then
        return Globals.ColorizeText(colorBlue, "Receiving...")
    end

    if altState == Constants.STATE.OUTDATED then
        return Globals.ColorizeText(colorYellow, "Outdated")
    end

    if altState == Constants.STATE.DISCOVERING then
        return Globals.ColorizeText(colorYellow, "Discovering")
    end

    if altState == Constants.STATE.UPDATED then
        return Globals.ColorizeText(colorGreen, "Just updated")
    end

    local version = altData and altData.version or 0

    if not altData or version == 0 then
        local isOnline = s.cachedAddonUsers[altName]
        if isOnline then
            return Globals.ColorizeText(colorYellow, "Online, waiting...")
        end

        return Globals.ColorizeText(colorRed, "Awaiting scan")
    end

    return Globals.ColorizeText(colorGreen, "Synced")
end

-- Helper to understand the network state
local function deriveNetworkState()
    local state = {
        isLockedOut = GBCR.Protocol.isLockedOut,
        isLoading = not GBCR.Database.savedVariables,
        isInGuild = IsInGuild(),
        isGuildBankAlt = false,
        myName = GBCR.Guild:GetNormalizedPlayerName(),
        rosterAlts = GBCR.Database:GetRosterGuildBankAlts() or {},
        savedAlts = (GBCR.Database.savedVariables and GBCR.Database.savedVariables.alts) or {},
        cachedAddonUsers = GBCR.Guild.cachedAddonUsers or {},
        addonUserCount = 0,
        syncing = false,
        meta = getSyncMeta()
    }

    for name in pairs(state.cachedAddonUsers) do
        if name ~= state.myName then
            state.addonUserCount = state.addonUserCount + 1
        end
    end

    state.isGuildBankAlt = GBCR.Guild.weAreGuildBankAlt

    for _, s in pairs(GBCR.Protocol.protocolStates or {}) do
        if s ~= GBCR.Constants.STATE.IDLE and s ~= GBCR.Constants.STATE.UPDATED then
            state.syncing = true

            break
        end
    end

    return state
end

-- Helper to handle drawing all guild bank alts on the roster
local function ensureRosterPool(self, needed)
    local pool = self.rosterPool
    local parentContent = self.rowsContainer.content

    for i = 1, #pool do
        if pool[i].frame:GetParent() ~= parentContent then
            pool[i].frame:SetParent(parentContent)
        end
    end

    for i = #pool + 1, needed do
        local frame = CreateFrame("Frame", nil, parentContent)
        frame:SetHeight(self.rowHeight)

        local nameFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("LEFT", frame, "LEFT", 4, 0)
        nameFS:SetWidth(216)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")

        local ageFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ageFS:SetPoint("LEFT", frame, "LEFT", 224, 0)
        ageFS:SetWidth(116)
        ageFS:SetJustifyH("LEFT")
        ageFS:SetJustifyV("MIDDLE")

        local stateFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        stateFS:SetPoint("LEFT", frame, "LEFT", 344, 0)
        stateFS:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        stateFS:SetJustifyH("LEFT")
        stateFS:SetJustifyV("MIDDLE")

        pool[i] = {frame = frame, name = nameFS, age = ageFS, state = stateFS}
    end

    for i = 1, #pool do
        local row = pool[i]
        row.frame:ClearAllPoints()
        if i <= needed then
            row.frame:SetPoint("TOPLEFT", parentContent, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
            row.frame:SetPoint("TOPRIGHT", parentContent, "TOPRIGHT", 0, -(i - 1) * self.rowHeight)
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end

    local newH = math_max(needed * self.rowHeight, 1)
    parentContent:SetHeight(newH)
    self.rowsContainer.frame:SetHeight(newH)
    self.rowsContainer:SetHeight(newH)
    if self.scrollFrame then
        self.scrollFrame:DoLayout()
        self.scrollFrame:FixScroll()
    end
end

-- Helper to update the network labels as state changes
local function updateDynamicNetworkLabels(self)
    if not self.isNetworkTabOpen or not self.rosterPool then
        return
    end

    local s = deriveNetworkState()
    local alts = s.rosterAlts
    local pool = self.rosterPool

    for index = 1, #alts do
        local row = pool[index]
        if row then
            local altName = alts[index]
            local altData = s.savedAlts[altName]
            local version = altData and altData.version or 0

            row.state:SetText(getAltRowState(altName, altData, s))

            local ageText = formatTimeAgo(version)
            local ageColor = version > 0 and colorGray or colorRed
            row.age:SetText(Globals.ColorizeText(ageColor, ageText))
        end
    end
end

-- Helper to populate the network tab
local function populateNetworkTab()
    local module = UI
    if not module.isNetworkTabOpen or not module.statusLabel then
        return
    end

    local s = deriveNetworkState()

    local statusKind, statusText = getGlobalStatusText(s)
    local statusColor = ({OK = colorGreen, WARN = colorYellow, INFO = colorBlue, NEUTRAL = colorGray})[statusKind]
    module.statusLabel:SetText(Globals.ColorizeText(statusColor, statusText))

    local kind, text = getGuildBankStatusText(s)
    if text then
        module.guildBankGroup.frame:Show()
        module.guildBankGroup.frame:SetHeight(80)
        module.guildBankGroup:SetHeight(80)
        local color = ({OK = colorGreen, WARN = colorYellow, INFO = colorBlue})[kind]
        module.guildBankLabel:SetText(Globals.ColorizeText(color, text))
    else
        module.guildBankGroup.frame:SetHeight(0)
        module.guildBankGroup:SetHeight(0)
        if module.guildBankGroup.content then
            module.guildBankGroup.content:SetHeight(0)
        end
        module.guildBankGroup.frame:Hide()
        if module.scrollFrame then
            module.scrollFrame:DoLayout()
        end
    end

    local numAlts = #s.rosterAlts
    ensureRosterPool(module, numAlts)

    local pool = module.rosterPool

    for index = 1, numAlts do
        local altName = s.rosterAlts[index]
        local altData = s.savedAlts[altName]
        local version = altData and altData.version or 0
        local row = pool[index]

        row.name:SetText(GBCR.Guild:ColorPlayerName(altName))

        local ageText = formatTimeAgo(version)
        local ageColor = version > 0 and colorGray or colorRed
        row.age:SetText(Globals.ColorizeText(ageColor, ageText))

        row.state:SetText(getAltRowState(altName, altData, s))
    end

    local meta = s.meta
    local activeDl = 0

    for _, st in pairs(GBCR.Protocol.protocolStates or {}) do
        if st == Constants.STATE.RECEIVING then
            activeDl = activeDl + 1
        end
    end

    if activeDl > 0 then
        module.footer:SetText(string_format("Downloading data for %d alt(s)…", activeDl))
    elseif meta.lastReceiveTime then
        local ageText = formatTimeAgo(meta.lastReceiveTime)
        module.footer:SetText(string_format("Last received: %s for %s from %s", Globals.ColorizeText(colorGray, ageText),
                                            meta.lastReceiveAlt or "?", meta.lastReceiveSource or "?"))
    else
        module.footer:SetText("")
    end
end

-- Helper update the network tab on a timer
local function startTicker(self)
    if self.networkTicker then
        return
    end

    self.networkTickCount = 0
    self.networkTicker = NewTicker(10, function()
        if not self.isNetworkTabOpen then
            if self.networkTicker then
                self.networkTicker:Cancel()
                self.networkTicker = nil
            end

            return
        end

        self.networkTickCount = self.networkTickCount + 1
        if self.networkTickCount % 3 == 0 then
            populateNetworkTab()
        else
            updateDynamicNetworkLabels(self)
        end
    end)
end

-- Disables the network ticker when disabling the addon
local function stopNetworkTicker(self)
    if self.networkTicker then
        self.networkTicker:Cancel()
        self.networkTicker = nil
    end
    self.networkTickCount = 0
    self.isNetworkTabOpen = false
end

-- Helper to draw the network tab
local function drawNetworkTab(self, container)
    self.isNetworkTabOpen = true

    container:SetLayout("Fill")

    local networkScrollFrame = aceGUI:Create("ScrollFrame")
    networkScrollFrame:SetLayout("List")
    networkScrollFrame:SetFullWidth(true)
    networkScrollFrame:SetFullHeight(true)
    container:AddChild(networkScrollFrame)
    self.scrollFrame = networkScrollFrame

    networkScrollFrame:SetUserData("module", self)
    networkScrollFrame:SetCallback("OnRelease", callbacks.onReleaseNetworkScrollFrame)

    startTicker(self)

    local statusLabel = aceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    statusLabel:SetFontObject(GameFontNormal)
    networkScrollFrame:AddChild(statusLabel)
    self.statusLabel = statusLabel

    local spacer1 = aceGUI:Create("Label")
    spacer1:SetText(" ")
    networkScrollFrame:AddChild(spacer1)

    local guildBankGroup = aceGUI:Create("InlineGroup")
    guildBankGroup:SetTitle("This character")
    guildBankGroup:SetFullWidth(true)
    guildBankGroup:SetLayout("List")
    guildBankGroup.titletext:ClearAllPoints()
    guildBankGroup.titletext:SetPoint("TOPLEFT", guildBankGroup.frame, "TOPLEFT", 0, 0)
    self.guildBankGroup = guildBankGroup

    local guildBankLabel = aceGUI:Create("Label")
    guildBankLabel:SetFullWidth(true)
    guildBankGroup:AddChild(guildBankLabel)
    networkScrollFrame:AddChild(guildBankGroup)
    self.guildBankLabel = guildBankLabel

    local spacer2 = aceGUI:Create("Label")
    spacer2:SetText(" ")
    networkScrollFrame:AddChild(spacer2)

    local gridGroup = aceGUI:Create("InlineGroup")
    gridGroup:SetTitle("Guild bank data status")
    gridGroup:SetFullWidth(true)
    gridGroup:SetLayout("List")
    gridGroup.titletext:ClearAllPoints()
    gridGroup.titletext:SetPoint("TOPLEFT", gridGroup.frame, "TOPLEFT", 0, 0)
    networkScrollFrame:AddChild(gridGroup)

    local headerRow = aceGUI:Create("SimpleGroup")
    headerRow:SetFullWidth(true)
    headerRow:SetLayout("Table")
    headerRow:SetUserData("table", {columns = {220, 120, 180}})
    local hName = aceGUI:Create("Label")
    hName:SetText(Globals.ColorizeText(colorYellow, "Guild bank"))
    local hAge = aceGUI:Create("Label")
    hAge:SetText(Globals.ColorizeText(colorYellow, "Data age"))
    local hState = aceGUI:Create("Label")
    hState:SetText(Globals.ColorizeText(colorYellow, "Status"))
    headerRow:AddChild(hName)
    headerRow:AddChild(hAge)
    headerRow:AddChild(hState)
    gridGroup:AddChild(headerRow)

    local rowsContainer = aceGUI:Create("SimpleGroup")
    rowsContainer:SetFullWidth(true)
    rowsContainer:SetLayout("GBCR_RosterRows")
    gridGroup:AddChild(rowsContainer)
    self.rowsContainer = rowsContainer

    local spacer3 = aceGUI:Create("Label")
    spacer3:SetText(" ")
    networkScrollFrame:AddChild(spacer3)

    local footer = aceGUI:Create("Label")
    footer:SetFullWidth(true)
    networkScrollFrame:AddChild(footer)
    self.footer = footer

    populateNetworkTab()
end

-- Helper callback for the network tab: force sync
function callbacks.onClickForceSync()
    if GBCR.Protocol:PerformSync() then
        GBCR.Output:Response("Checking for missing guild bank data from online members...")
    end
end

-- Helper callback for the network tab: release
function callbacks.onReleaseNetworkScrollFrame(widget)
    local module = widget:GetUserData("module")

    module.isNetworkTabOpen = false
    module:StopNetworkTicker()

    for _, row in ipairs(module.rosterPool) do
        if row.frame then
            row.frame:Hide()
        end
    end

    module.statusLabel = nil
    module.guildBankGroup = nil
    module.guildBankLabel = nil
    module.rowsContainer = nil
    module.footer = nil
    module.scrollFrame = nil
end

-- ================================================================================================ -- configuration tab

-- Helper to draw the configuration tab
local function drawConfigurationTab(_, container)
    container:SetLayout("Fill")

    if container.SetTitle then
        container.SetTitle = function()
        end
    end

    GBCR.Libs.AceConfigDialog:Open(addonName, container)
end

-- ================================================================================================ -- request fulfillment tab

-- Helper to find the item in bags
local function scanBagsForItem(itemId)
    wipe(UI.recycledStacks)

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)

        for slot = 1, numSlots do
            local info = GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemId then
                UI.recycledStacks[#UI.recycledStacks + 1] = {bag = bag, slot = slot, count = info.stackCount or 1}
            end
        end
    end

    table_sort(UI.recycledStacks, function(a, b)
        return a.count > b.count
    end)

    return UI.recycledStacks
end

-- Helper to find an empty bag slot for stack splitting
local function findEmptyBagSlot(excludeBag, excludeSlot)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)

        for slot = 1, numSlots do
            if not (bag == excludeBag and slot == excludeSlot) then
                if not GetContainerItemInfo(bag, slot) then
                    return bag, slot
                end
            end
        end
    end

    return nil, nil
end

-- Helper to plan the fulfillment of a single item
local function planItem(stacks, qtyNeeded)
    wipe(UI.recycledDirectOps)
    local accumulated = 0
    local splitOp = {bag = nil, slot = nil, originalCount = nil, splitAmount = nil}

    for i = 1, #stacks do
        if accumulated >= qtyNeeded then
            break
        end

        local stack = stacks[i]
        local remaining = qtyNeeded - accumulated

        if stack.count <= remaining then
            UI.recycledDirectOps[#UI.recycledDirectOps + 1] = {bag = stack.bag, slot = stack.slot, count = stack.count}
            accumulated = accumulated + stack.count
        else
            splitOp = {bag = stack.bag, slot = stack.slot, originalCount = stack.count, splitAmount = remaining}
            accumulated = accumulated + remaining

            break
        end
    end

    local directOpsCopy = {}
    for i = 1, #UI.recycledDirectOps do
        directOpsCopy[i] = UI.recycledDirectOps[i]
    end

    return {directOps = directOpsCopy, splitOp = splitOp, totalMailable = accumulated}
end

-- Helper to create the request fulfillment plan
local function buildFulfillmentPlan(requestItems)
    local MAX_SLOTS = 12 -- TODO

    local allOps = {}
    local issues = {}

    for _, req in ipairs(requestItems) do
        if req.itemId and req.qty > 0 then
            local stacks = scanBagsForItem(req.itemId)
            local plan = planItem(stacks, req.qty)

            if plan.totalMailable < req.qty then
                issues[#issues + 1] = string_format("%dx %s not in bags (have %d)", req.qty - plan.totalMailable, req.name,
                                                    plan.totalMailable)
            end

            for _, op in ipairs(plan.directOps) do
                allOps[#allOps + 1] = {
                    type = "direct",
                    bag = op.bag,
                    slot = op.slot,
                    count = op.count,
                    itemId = req.itemId,
                    itemName = req.name
                }
            end

            if plan.splitOp then
                allOps[#allOps + 1] = {
                    type = "split",
                    bag = plan.splitOp.bag,
                    slot = plan.splitOp.slot,
                    originalCount = plan.splitOp.originalCount,
                    splitAmount = plan.splitOp.splitAmount,
                    itemId = req.itemId,
                    itemName = req.name
                }
            end
        end
    end

    local batches = {}
    local currentScrollValue = {directOps = {}, splitOp = nil, slotCount = 0}

    local function flushBatch()
        if currentScrollValue.slotCount > 0 then
            batches[#batches + 1] = {
                directOps = currentScrollValue.directOps,
                splitOp = currentScrollValue.splitOp,
                slotCount = currentScrollValue.slotCount
            }
            currentScrollValue = {directOps = {}, splitOp = nil, slotCount = 0}
        end
    end

    for _, op in ipairs(allOps) do
        if currentScrollValue.slotCount >= MAX_SLOTS then
            flushBatch()
        end

        if op.type == "direct" then
            currentScrollValue.directOps[#currentScrollValue.directOps + 1] = op
            currentScrollValue.slotCount = currentScrollValue.slotCount + 1
        elseif op.type == "split" then
            currentScrollValue.splitOp = op
            currentScrollValue.slotCount = currentScrollValue.slotCount + 1

            flushBatch()
        end
    end

    flushBatch()

    return {batches = batches, issues = issues}
end

-- Helper to pick up each whole-stack operation and attach to outgoing mail
local function doDirectAttach(directOps, startSlot)
    local attached = 0
    local errors = {}
    local slot = startSlot or 1

    for _, op in ipairs(directOps) do
        if slot > 12 then
            errors[#errors + 1] = "Mail full (12 attachment limit)."

            break
        end

        ClearCursor()
        PickupContainerItem(op.bag, op.slot)

        if GetCursorInfo() == "item" then
            ClickSendMailItemButton(slot)
            slot = slot + 1
            attached = attached + op.count
        else
            errors[#errors + 1] = string_format(
                                      "Pickup failed: %dx %s (bag %d slot %d). Item moved or is bind-on-pickup. Click 'Plan fulfillment' again to re-scan",
                                      op.count, op.itemName, op.bag, op.slot)
        end
    end

    ClearCursor()

    return {attached = attached, nextSlot = slot, errors = errors}
end

-- Helper to executes the fulfillment plan (requires open mail compose window): sets the recipient name, attaches synchronously or splits first and then attaches async
local function executeFulfillmentPlan(batch, recipientRaw, onDone)
    local toName = GBCR.Guild:NormalizePlayerName(recipientRaw, true)
    if Globals.SendMailNameEditBox then
        Globals.SendMailNameEditBox:SetText(toName)
    end

    -- Direct attachments
    local dr = doDirectAttach(batch.directOps, 1)

    if not batch.splitOp then
        local msg = dr.attached > 0 and
                        string_format("Attached %d item%s for %s. Click 'Send' to deliver.", dr.attached,
                                      dr.attached ~= 1 and "s" or "", toName) or
                        "No items attached. They may have moved. Re-plan fulfillment and try again."
        onDone({attached = dr.attached, errors = dr.errors, message = msg})

        return
    end

    -- Async stack split
    local sp = batch.splitOp
    local emptyBag, emptySlot = findEmptyBagSlot(sp.bag, sp.slot)

    if not emptyBag then
        local errs = dr.errors
        errs[#errs + 1] = string_format("No empty bag slot to commit split of %dx %s. Free a slot and re-plan fulfillment.",
                                        sp.splitAmount, sp.itemName)

        onDone({
            attached = dr.attached,
            errors = errs,
            message = string_format(
                "Attached %d item%s. Split of %dx %s requires an empty bag slot. Make room and re-plan fulfillment.", dr.attached,
                dr.attached ~= 1 and "s" or "", sp.splitAmount, sp.itemName)
        })

        return
    end

    if sp.bag and sp.slot and sp.splitAmount then
        ClearCursor()
        SplitContainerItem(sp.bag, sp.slot, sp.splitAmount)
    end

    local MAX_RETRIES = 15 -- TODO

    local splitRetries = 0
    local dropRetries = 0
    local attachRetries = 0

    local attemptCursorPickup, attemptBagDrop, attemptMailAttach

    -- Pick up the newly committed stack from the bag and attach it to the mail
    attemptMailAttach = function()
        ClearCursor()
        PickupContainerItem(emptyBag, emptySlot)

        local function verifyAndAttach()
            if GetCursorInfo() == "item" then
                ClickSendMailItemButton(dr.nextSlot)
                ClearCursor()

                local totalAttached = dr.attached + sp.splitAmount
                onDone({
                    attached = totalAttached,
                    errors = dr.errors,
                    message = string_format("Attached %d item%s (includes auto-split of %dx %s) for %s. Click 'Send' to deliver.",
                                            totalAttached, totalAttached ~= 1 and "s" or "", sp.splitAmount, sp.itemName, toName)
                })
            else
                attachRetries = attachRetries + 1
                if attachRetries <= MAX_RETRIES then
                    After(0.10, verifyAndAttach)
                else
                    ClearCursor()

                    local errs = dr.errors
                    errs[#errs + 1] = string_format("Pickup of split %dx %s from bag %d slot %d failed after commit.",
                                                    sp.splitAmount, sp.itemName, emptyBag, emptySlot)

                    onDone({attached = dr.attached, errors = errs, message = "Attachment failed due to server latency."})
                end
            end
        end

        After(0.10, verifyAndAttach)
    end

    -- Wait for the item to physically land in the new bag slot
    attemptBagDrop = function()
        if GetContainerItemInfo(emptyBag, emptySlot) then
            attemptMailAttach()
        else
            dropRetries = dropRetries + 1
            if dropRetries <= MAX_RETRIES then
                After(0.10, attemptBagDrop)
            else
                local errs = dr.errors
                errs[#errs + 1] = string_format("Failed to verify split item %s landed in bag (high latency).", sp.itemName)

                onDone({attached = dr.attached, errors = errs, message = "Bag commit failed."})
            end
        end
    end

    -- Wait for the initial split item to appear on the cursor
    attemptCursorPickup = function()
        if GetCursorInfo() == "item" then
            PickupContainerItem(emptyBag, emptySlot)
            After(0.10, attemptBagDrop)
        else
            splitRetries = splitRetries + 1
            if splitRetries <= MAX_RETRIES then
                After(0.10, attemptCursorPickup)
            else
                ClearCursor()

                local errs = dr.errors
                errs[#errs + 1] = string_format("Split of %dx %s failed (stack may have moved or high latency).", sp.splitAmount,
                                                sp.itemName)
                onDone({
                    attached = dr.attached,
                    errors = errs,
                    message = string_format("Attached %d item%s. Split of %dx %s failed. Split manually and re-plan fulfillment.",
                                            dr.attached, dr.attached ~= 1 and "s" or "", sp.splitAmount, sp.itemName)
                })
            end
        end
    end

    After(0.10, attemptCursorPickup)
end

-- Helper to count by item
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

-- Helper to load data based on the import code
local function doLoad(widget)
    local fulfillmentImportInput = widget:GetUserData("fulfillmentImportInput")
    local statusLabel = widget:GetUserData("statusLabel")
    local container = widget:GetUserData("container")
    local renderFulfillment = widget:GetUserData("renderFulfillment")

    local input = fulfillmentImportInput:GetText()
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

-- Helper to draw the request fulfillment tab
local function drawFulfillmentTab(self, container)
    container:SetLayout("GBCR_TopBottom")

    self.requestsTabGeneration = (self.requestsTabGeneration or 0) + 1
    local myGeneration = self.requestsTabGeneration

    -- Top controls (stacked vertically so label, input, button, status are aligned)
    local fulfillmentTopGroup = aceGUI:Create("SimpleGroup")
    fulfillmentTopGroup:SetFullWidth(true)
    fulfillmentTopGroup:SetLayout("List")
    fulfillmentTopGroup:SetUserData("module", self)
    fulfillmentTopGroup:SetCallback("OnRelease", callbacks.onReleaseFulfillmentTopGroup)
    self.fulfillmentTopGroup = fulfillmentTopGroup
    container:AddChild(fulfillmentTopGroup)

    local inputLabel = self.inputLabel
    if not inputLabel then
        inputLabel = fulfillmentTopGroup.frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        self.inputLabel = inputLabel
    end
    inputLabel:SetText("Paste import code (starts with " .. importPrefix .. ")")
    inputLabel:SetFontObject(GameFontNormal)
    inputLabel:SetParent(fulfillmentTopGroup.frame)
    inputLabel:ClearAllPoints()
    inputLabel:SetPoint("TOPLEFT", fulfillmentTopGroup.frame, "TOPLEFT", 0, 16)
    inputLabel:SetHeight(44)
    inputLabel:Show()
    self.fulfillmentInputLabel = inputLabel

    local inputLabelOriginal = aceGUI:Create("Label")
    inputLabelOriginal:SetFullWidth(true)
    inputLabelOriginal:SetText(" ")
    inputLabelOriginal.label:SetFontObject(GameFontNormal)
    self.fulfillmentInputLabelOriginal = inputLabelOriginal
    fulfillmentTopGroup:AddChild(inputLabelOriginal)

    -- Row: editbox fills width, button is fixed on the right
    local inputRow = aceGUI:Create("SimpleGroup")
    inputRow:SetFullWidth(true)
    inputRow:SetLayout("Table")
    inputRow:SetUserData("table", {columns = {0.8, 0.2}})
    self.fulfillmentInputRow = inputRow
    fulfillmentTopGroup:AddChild(inputRow)

    local fulfillmentImportInput = aceGUI:Create("EditBox")
    fulfillmentImportInput:SetLabel("") -- label text moved above
    fulfillmentImportInput:SetFullWidth(true)
    if fulfillmentImportInput.label then
        fulfillmentImportInput.label:Hide()
    end
    self.fulfillmentImportInput = fulfillmentImportInput
    inputRow:AddChild(fulfillmentImportInput)

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
    fulfillmentTopGroup:AddChild(statusLabel)

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

        -- Per-location item counts
        local myName = GBCR.Guild:GetNormalizedPlayerName()
        local sv_ = GBCR.Database.savedVariables
        local myAlt = sv_ and sv_.alts and sv_.alts[myName]
        local cache = myAlt and myAlt.cache

        local inBags = countById(cache and cache.bags)
        local inBank = countById(cache and cache.bank)
        local inMail = countById(cache and cache.mail)

        -- Column header row
        local colHdr = aceGUI:Create("SimpleGroup")
        colHdr:SetFullWidth(true)
        colHdr:SetLayout("Table")
        colHdr:SetUserData("table", {columns = {0, 55, 55, 55, 55}})

        local function createHeaderLabel(text)
            local label = aceGUI:Create("Label")
            label:SetText(Globals.ColorizeText(Constants.COLORS.GOLD, text))
            colHdr:AddChild(label)
        end

        createHeaderLabel("Item")
        createHeaderLabel("Need")
        createHeaderLabel("Bags")
        createHeaderLabel("Bank")
        createHeaderLabel("Mail")
        scroll:AddChild(colHdr)

        -- Async batch state
        local itemEntries = requestData.i or {}
        local totalEntries = #itemEntries
        local batchPosition = 1
        local canSendItems = {}
        local totalUnmet = 0

        local BATCH = 20 -- TODO

        local function addSummarySection()
            local sp2 = aceGUI:Create("Label")
            sp2:SetText(" ")
            scroll:AddChild(sp2)

            local pluralUnmet = (totalUnmet ~= 1 and "s" or "")

            if totalUnmet > 0 then
                local warn = aceGUI:Create("Label")
                warn:SetFullWidth(true)
                warn:SetText(Globals.ColorizeText(Constants.COLORS.ORANGE, string_format(
                                                      "Warning: %d item%s cannot be fully fulfilled.", totalUnmet, pluralUnmet)))
                scroll:AddChild(warn)
            end

            if #canSendItems == 0 then
                local none = aceGUI:Create("Label")
                none:SetFullWidth(true)
                none:SetText(Globals.ColorizeText(Constants.COLORS.GRAY, "Nothing sendable from bags right now."))
                scroll:AddChild(none)
                scroll:DoLayout()

                return
            end

            local infoLabel = aceGUI:Create("Label")
            infoLabel:SetFullWidth(true)
            infoLabel:SetText(string_format("%d item type%s ready to mail.\n" ..
                                                "Items in bank or mail must be moved to bags first.\n" ..
                                                "Stacks are split automatically when needed. Each mail holds up to 12 stacks.",
                                            #canSendItems, #canSendItems ~= 1 and "s" or ""))
            scroll:AddChild(infoLabel)

            local sp3 = aceGUI:Create("Label")
            sp3:SetText(" ")
            scroll:AddChild(sp3)

            local statusLabel = aceGUI:Create("Label")
            statusLabel:SetFullWidth(true)
            statusLabel:SetText(Globals.ColorizeText(Constants.COLORS.GRAY, "Open the mailbox, then click 'Plan fulfillment'."))
            scroll:AddChild(statusLabel)

            local fulfillmentPlanBtn, fulfillmentAttachBtn

            fulfillmentAttachBtn = aceGUI:Create("Button")
            fulfillmentAttachBtn:SetText("Attach items to mail")
            fulfillmentAttachBtn:SetFullWidth(true)
            fulfillmentAttachBtn:SetDisabled(true)
            scroll:AddChild(fulfillmentAttachBtn)

            fulfillmentPlanBtn = aceGUI:Create("Button")
            fulfillmentPlanBtn:SetText("Plan fulfillment")
            fulfillmentPlanBtn:SetFullWidth(true)
            fulfillmentPlanBtn:SetUserData("statusLabel", statusLabel)
            fulfillmentPlanBtn:SetUserData("fulfillmentAttachBtn", fulfillmentAttachBtn)
            fulfillmentPlanBtn:SetUserData("requestData", requestData)
            fulfillmentPlanBtn:SetUserData("canSendItems", canSendItems)
            fulfillmentPlanBtn:SetCallback("OnClick", callbacks.onClickFulfillmentPlanBtn)
            scroll:AddChild(fulfillmentPlanBtn)

            fulfillmentAttachBtn:SetUserData("statusLabel", statusLabel)
            fulfillmentAttachBtn:SetUserData("fulfillmentAttachBtn", fulfillmentAttachBtn)
            fulfillmentAttachBtn:SetUserData("fulfillmentPlanBtn", fulfillmentPlanBtn)
            fulfillmentAttachBtn:SetUserData("requestData", requestData)
            fulfillmentAttachBtn:SetCallback("OnClick", callbacks.onClickFulfillmentAttachBtn)

            scroll:DoLayout()
        end

        local function processBatch()
            if self.requestsTabGeneration ~= myGeneration then
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

                    local function createLabelForCounts(count, isNeed)
                        local label = aceGUI:Create("Label")
                        local color = isNeed and Constants.COLORS.WHITE or
                                          (count > 0 and Constants.COLORS.GREEN or Constants.COLORS.GRAY)
                        label:SetText(Globals.ColorizeText(color, tostring(count)))
                        row:AddChild(label)
                    end

                    createLabelForCounts(qty, true)
                    createLabelForCounts(bags, false)
                    createLabelForCounts(bank, false)
                    createLabelForCounts(mail, false)

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

    parseBtn:SetUserData("fulfillmentImportInput", fulfillmentImportInput)
    parseBtn:SetUserData("statusLabel", statusLabel)
    parseBtn:SetUserData("container", container)
    parseBtn:SetUserData("renderFulfillment", renderFulfillment)
    parseBtn:SetCallback("OnClick", doLoad)

    fulfillmentImportInput:SetCallback("OnEnterPressed", callbacks.onEnterPressFulfillmentImportInput)
end

-- Helper callback for the request fulfillment tab: release
function callbacks.onReleaseFulfillmentTopGroup(widget)
    local module = widget:GetUserData("module")

    if module.inputLabel then
        module.inputLabel:Hide()
        module.inputLabel:SetParent(UIParent)
    end
end

-- Helper callback for the request fulfillment tab: plan
function callbacks.onClickFulfillmentPlanBtn(widget)
    local statusLabel = widget:GetUserData("statusLabel")
    local fulfillmentAttachBtn = widget:GetUserData("fulfillmentAttachBtn")
    local requestData = widget:GetUserData("requestData")
    local canSendItems = widget:GetUserData("canSendItems")

    if not Globals.MailFrame or not Globals.MailFrame:IsShown() then
        statusLabel:SetText(
            Globals.ColorizeText(Constants.COLORS.ORANGE, "Open the mailbox first, then click 'Plan fulfillment'."))

        return
    end

    UI.fulfillmentPlan = buildFulfillmentPlan(canSendItems)
    UI.batchIndex = 0

    if not UI.fulfillmentPlan or #UI.fulfillmentPlan.batches == 0 then
        statusLabel:SetText(Globals.ColorizeText(Constants.COLORS.RED, "No items found in bags after live scan."))
        fulfillmentAttachBtn:SetDisabled(true)
        fulfillmentAttachBtn:SetText("Attach items to mail")

        return
    end

    local toName = GBCR.Guild:NormalizePlayerName(requestData.r, true)
    local lines = {
        string_format("Recipient: %s", toName),
        string_format("Requires %d mail%s to be sent:", #UI.fulfillmentPlan.batches,
                      #UI.fulfillmentPlan.batches ~= 1 and "s" or "")
    }

    for i, batch in ipairs(UI.fulfillmentPlan.batches) do
        local slots = #batch.directOps + (batch.splitOp and 1 or 0)
        local desc = string_format("  - Mail %d: %d attachment%s", i, slots, slots ~= 1 and "s" or "")

        if batch.splitOp then
            desc = desc .. string_format(" (%dx %s)", batch.splitOp.splitAmount, batch.splitOp.itemName)
        end
        lines[#lines + 1] = desc
    end

    if #UI.fulfillmentPlan.issues > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = Globals.ColorizeText(Constants.COLORS.ORANGE, "Missing:")
        for _, issue in ipairs(UI.fulfillmentPlan.issues) do
            lines[#lines + 1] = "  - " .. issue
        end
    end

    lines[#lines + 1] = " "
    lines[#lines + 1] = Globals.ColorizeText(Constants.COLORS.GOLD, "Click 'Attach items to mail' to prepare the first mail.")

    statusLabel:SetText(table_concat(lines, "\n"))
    fulfillmentAttachBtn:SetText(string_format("Attach items (mail 1 of %d)", #UI.fulfillmentPlan.batches))
    fulfillmentAttachBtn:SetDisabled(false)
end

-- Helper callback for the request fulfillment tab: attach
function callbacks.onClickFulfillmentAttachBtn(widget)
    local statusLabel = widget:GetUserData("statusLabel")
    local fulfillmentAttachBtn = widget:GetUserData("fulfillmentAttachBtn")
    local fulfillmentPlanBtn = widget:GetUserData("fulfillmentPlanBtn")
    local requestData = widget:GetUserData("requestData")

    if not UI.fulfillmentPlan or #UI.fulfillmentPlan.batches == 0 then
        statusLabel:SetText("Click 'Plan fulfillment' first.")

        return
    end

    if not Globals.MailFrame or not Globals.MailFrame:IsShown() then
        statusLabel:SetText(Globals.ColorizeText(Constants.COLORS.ORANGE, "Mailbox is not open. Open it and try again."))

        return
    end

    UI.batchIndex = UI.batchIndex + 1
    if UI.batchIndex > #UI.fulfillmentPlan.batches then
        statusLabel:SetText(Globals.ColorizeText(Constants.COLORS.GREEN, "All mails prepared, request fully fulfilled!"))
        fulfillmentAttachBtn:SetDisabled(true)

        return
    end

    local batch = UI.fulfillmentPlan.batches[UI.batchIndex]
    fulfillmentPlanBtn:SetDisabled(true)
    fulfillmentAttachBtn:SetDisabled(true)
    statusLabel:SetText("Attaching items, please wait...")

    executeFulfillmentPlan(batch, requestData.r, function(result)
        fulfillmentPlanBtn:SetDisabled(false)

        local lines = {result.message}
        for _, err in ipairs(result.errors or {}) do
            lines[#lines + 1] = Globals.ColorizeText(Constants.COLORS.ORANGE, "  - " .. err)
        end

        if UI.batchIndex < #UI.fulfillmentPlan.batches then
            lines[#lines + 1] = " "
            lines[#lines + 1] = Globals.ColorizeText(Constants.COLORS.GOLD, string_format(
                                                         "Send this mail, then click 'Attach items' for mail %d of %d.",
                                                         UI.batchIndex + 1, #UI.fulfillmentPlan.batches))
            fulfillmentAttachBtn:SetText(string_format("Attach items (mail %d of %d)", UI.batchIndex + 1,
                                                       #UI.fulfillmentPlan.batches))
            fulfillmentAttachBtn:SetDisabled(false)
        else
            lines[#lines + 1] = " "
            lines[#lines + 1] = Globals.ColorizeText(Constants.COLORS.GREEN,
                                                     "All items attached! Send this last mail to complete the request.")
            fulfillmentAttachBtn:SetText("All done!")
            fulfillmentAttachBtn:SetDisabled(true)
        end

        statusLabel:SetText(table_concat(lines, "\n"))
    end)
end

-- Helper callback for the request fulfillment tab: import
function callbacks.onEnterPressFulfillmentImportInput(widget)
    doLoad()
    widget:ClearFocus()
end

-- ================================================================================================ -- data processing

-- Helper to wipe cached UI data
local function invalidateDataCache(self, isFullRebuild)
    self.ledgerDataDirty = true
    self.itemsHydrated = false
    self.needsFullRebuild = isFullRebuild == true
    self.pendingCorpusBuild = false
    self.lastAggregatedView = nil
    self.filteredCount = 0
    self.cachedLedgerStatus = nil
    wipe(self.corpus)
    wipe(self.aggregatedMap)
    wipe(self.itemsList)
    if isFullRebuild then
        wipe(self.itemInfoCache)
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

-- Helper to derive money total and newest version timestamp for the current view for the bottom status text
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

-- Helper to update the bottom status text depending on which tab is open
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

-- Helper to update the list of applied filters
local function updateFilterStatus(self)
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

-- Helper to retrieve uncached item information for the UI via batched processing
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
    local totalFallbacks = 0
    local resolved = 0

    local function processBatch()
        local startTime = debugprofilestop()
        local processedThisFrame = 0

        while currentIndex <= totalItems do
            local item = itemsArray[currentIndex]

            if item and item.itemString then
                local key = item.itemString
                local cached = UI.itemInfoCache[key]

                local needsFetch = not cached or cached.isFallback

                if needsFetch then
                    local name, link, rarity, level, minLevel, itemType, itemSubType, _, equipLoc, icon, price, itemClassId,
                          itemSubClassId = GetItemInfo(item.itemLink or key)

                    if name then
                        local wasFallback = cached and cached.isFallback
                        local equipId = GetItemInventoryTypeByID(item.itemId) or 0

                        UI.itemInfoCache[key] = {
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

                            UI.itemInfoCache[key] = {
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
                                isFallback = true
                            }

                            if numId and numId > 0 and not GBCR.Inventory.pendingItemInfoLoads[numId] then
                                GBCR.Inventory.pendingItemInfoLoads[numId] = true
                                GetItemInfo(numId)
                            end
                        end
                        totalFallbacks = totalFallbacks + 1
                    end
                end

                item.itemInfo = UI.itemInfoCache[key]
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
            self.fallbackCount = totalFallbacks

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

-- Helper to pool aggregated items
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

-- Helper to create the full list of aggregated items
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
                        local p1, p2, p3 = strsplit(":", key)
                        local derivedId = tonumber(p1) or 0
                        aggItem.itemId = derivedId
                        local validWoWString = string_format("item:%d:%s:0:0:0:0:%s:0:0:0:0:0:0", derivedId, p2 or "0", p3 or "0")
                        aggItem.validWoWString = validWoWString
                        aggItem.itemLink = string_format("|cffffffff|H%s|height[item:%d]|height|r", validWoWString, derivedId)
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

-- Helper to apply filters on all items
local function buildFilteredList(self, callback)
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

        local itemCount = self.cachedFilteredList and #self.cachedFilteredList or 0
        local browseTabText = itemCount > 0 and string_format("Browse (%d)", itemCount) or "Browse"

        if self.tabs and self.tabs.tabs then
            for _, tab in pairs(self.tabs.tabs) do
                if tab.value == "browse" then
                    tab:SetText(browseTabText)

                    break
                end
            end
        end

        -- local browseTabText = "Browse"
        -- if self.tabs and self.tabs.tabs then
        --     for _, tab in pairs(self.tabs.tabs) do
        --         if tab.value == "browse" then
        --             tab:SetText(browseTabText)

        --             break
        --         end
        --     end
        -- end

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

                return
            end
        end
    end

    local function continueAfterHydration(list)
        if currentGen ~= self.renderGeneration then

            return
        end

        for i = 1, #list do
            local item = list[i]
            if item and item.itemString then
                item.itemInfo = UI.itemInfoCache[item.itemString] or item.itemInfo
                if item.itemInfo then
                    item.lowerName = item.itemInfo.name and string_lower(item.itemInfo.name) or ""
                    item.itemLink = item.itemInfo.realLink or item.itemLink
                end
            end
        end

        local function startFilterBatch()
            if currentGen ~= self.renderGeneration then

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

                        return
                    end
                end

                sortItems(self.cachedFilteredList, GBCR.Options:GetSortMode())

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

            wipe(self.dirtyAlts)

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
end

-- Ensure the data is ready before allowing export
local function ensureReady(callback)
    if not UI.itemsList or #UI.itemsList == 0 then
        updateItemsList(UI, function()
            getItems(UI, UI.itemsList, callback)
        end)
    elseif UI.fallbackCount and UI.fallbackCount > 50 then
        getItems(UI, UI.itemsList, callback)
    else
        callback(UI.itemsList)
    end
end

-- Helper callback for the export tab: prepare export
function callbacks.onClickExportBtn(widget)
    local formatDropdown = widget:GetUserData("formatDropdown")
    local boxContainer = widget:GetUserData("boxContainer")

    local meta = buildExportMetadata()
    local format = formatDropdown:GetValue()

    boxContainer:ReleaseChildren()
    boxContainer:SetLayout("Fill")

    if format == "byitem" then
        ensureReady(function(list)
            local header = metadataHeader(meta, "By Item")
            local phase = 1
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

            renderStreamingTextArea(boxContainer, nextLine)
        end)
    else
        local sv_ = GBCR.Database.savedVariables
        local roster = GBCR.Database:GetRosterGuildBankAlts() or {}
        local header = metadataHeader(meta, "By Bank")
        local phase = 1
        local rIndex = 1
        local curItems, iIndex, pendingMeta = nil, 1, {}

        local function nextLine()
            if phase == 1 then
                phase = 2

                return header
            end

            while true do
                if #pendingMeta > 0 then
                    return table_remove(pendingMeta, 1)
                end

                if curItems then
                    if iIndex <= #curItems then

                        local it = curItems[iIndex]

                        iIndex = iIndex + 1

                        local info = UI.itemInfoCache[it.itemString]
                        local nm = (info and not info.isFallback and info.name) or ("item:" .. (it.itemString or "?"))

                        return string_format("  %s x%d  (%s)", nm, it.itemCount or 1, it.itemString or "")
                    end

                    curItems = nil

                    return ""
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

        renderStreamingTextArea(boxContainer, nextLine)
    end
end

-- ================================================================================================ -- main window loading and refreshing

-- Immediately draws all open UI windows and cancels any pending delayed refreshes; called when opening windows
local function forceDraw(self)
    GBCR.Output:Debug("UI", "UI:ForceDraw called")

    self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1

    UI:RefreshUI()
end

-- Called each time data changes to queue a UI refresh with native debouncing total prevent double-refreshes; called by GBCR.Events, GBCR.Protocol, GBCR.Guild, and GBCR.Inventory
local function queueUIRefresh(self)
    GBCR.Output:Debug("UI", "UI:QueueUIRefresh called")

    local now = GetServerTime()
    self._lastForcedRefresh = self._lastForcedRefresh or 0

    if now - self._lastForcedRefresh >= Constants.TIMER_INTERVALS.UI_REFRESH_FORCE_AGE then
        self._lastForcedRefresh = now
        self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1
        forceDraw(self)

        return
    end

    self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1
    local currentGen = self.uiRefreshGeneration

    After(Constants.TIMER_INTERVALS.UI_REFRESH_DEBOUNCE, function()
        if self.uiRefreshGeneration ~= currentGen then
            return
        end
        self._lastForcedRefresh = GetServerTime()
        forceDraw(self)
    end)
end

-- Helper to show an overlay while the UI is loading
local function setUILoading(self, isLoading)
    if not self.window or not self.window.frame then
        return
    end

    if not self.loadingOverlay then
        self.loadingOverlay = CreateFrame("Frame", nil, self.window.frame, "BackdropTemplate")
        self.loadingOverlay:SetAllPoints(self.window.frame)
        self.loadingOverlay:SetFrameStrata("TOOLTIP")
        self.loadingOverlay:EnableMouse(true)
        self.loadingOverlay:SetScript("OnMouseWheel", function()
        end)

        local background = self.loadingOverlay:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.7)

        local text = self.loadingOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        text:SetPoint("CENTER")
        text:SetText("Loading data, please wait...")
        self.loadingOverlayText = text
    end

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
        self.loadingOverlay:Show()
        if self.emptyLabel then
            self.emptyLabel:Hide()
        end
    else
        self.loadingOverlay:Hide()
    end
end

-- Helper to show bank and officer tabs if eligible
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

    -- HookScript on Enable/Disable attempts to bypass TSM + Auctioneer font-object overrides which both reset tab text to white when run together
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

            if not tabButton.gbcrColorHooked then
                tabButton.gbcrColorHooked = true
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

-- Helper to update the top bar
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

-- Lazy: Update the bottom bar
local function updateBottomBar(self)
    if not self.bottomBar then
        return
    end

    local tab = self.currentTab
    local count = self.cartCount
    local pluralItems = count ~= 1 and "s" or ""

    self.bottomBar.bottomBarText:SetText(string_format("%d item%s in request list", count, pluralItems))

    local btn = self.bottomBar.button
    if tab == "browse" then
        btn:SetText("View request list")
        btn:SetDisabled(count == 0)
        btn:SetCallback("OnClick", callbacks.onClickViewRequestList)
    elseif tab == "cart" then
        btn:SetText("Prepare export")
        btn:SetDisabled(count == 0)
        btn:SetCallback("OnClick", callbacks.onClickRefreshCartExportBtn)
    elseif tab == "network" then
        self.bottomBar.bottomBarText:SetText("")
        btn:SetText("Force sync")
        btn:SetDisabled(false)
        btn:SetCallback("OnClick", callbacks.onClickForceSync)
    else
        btn:SetText("View request list")
        btn:SetDisabled(count == 0)
        btn:SetCallback("OnClick", callbacks.onClickViewRequestList)
    end
end

-- Helper callback for the my request list tab: empty cart
function callbacks.onClickEmptyCartBtn()
    local module = UI
    wipe(module.cartData)
    module.cartCount = 0
    updateBottomBar(module)

    if module.cart.importBox then
        module.cart.importBox:SetText("click 'Prepare export' to generate")
        module.cart.importBox:SetDisabled(true)
    end
    if module.cart.copyImportCartBtn then
        module.cart.copyImportCartBtn:SetDisabled(true)
    end

    if module.cart.exportArea then
        module.cart.exportArea:ReleaseChildren()
        local lbl = aceGUI:Create("Label")
        lbl:SetText("Your request list is empty")
        lbl:SetFullWidth(true)
        module.cart.exportArea:AddChild(lbl)
        module.cart.exportArea:DoLayout()
    end

    callbacks.onClickViewRequestList()
end

-- Helper callback for the my request list tab: add an item to the request list
function callbacks.onClickAddToRequestListBtn()
    local module = UI
    if not module.preview.selectedItem then
        return
    end

    local item = module.preview.selectedItem
    local amount = module.preview.slider:GetValue()
    local itemKey = item.itemString or tostring(item.itemId or 0)

    local enchantText = (module.cartData[itemKey] and module.cartData[itemKey].enchantText)
    if not enchantText and item.itemLink then
        enchantText = getEnchantTextFromTooltip(module, item.itemLink)
    end

    if module.cartData[itemKey] then
        local newQty = module.cartData[itemKey].qty + amount
        module.cartData[itemKey].qty = math_min(newQty, item.itemCount)
    else
        module.cartData[itemKey] = {
            itemLink = item.itemLink,
            qty = amount,
            itemCount = item.itemCount,
            sources = item.sources,
            itemInfo = item.itemInfo,
            enchantText = enchantText
        }
        module.cartCount = module.cartCount + 1
    end

    module.preview.selectedItem = item

    local alreadyInCart = module.cartData[itemKey] and module.cartData[itemKey].qty or 0
    local availableToRequest = item.itemCount - alreadyInCart

    if availableToRequest > 0 then
        module.preview.slider:SetDisabled(false)
        module.preview.slider:SetSliderValues(1, availableToRequest, 1)
        module.preview.slider:SetValue(1)
        module.preview.button:SetDisabled(false)
    else
        module.preview.slider:SetDisabled(true)
        module.preview.slider:SetValue(0)
        module.preview.button:SetDisabled(true)
    end

    if not module.preview.isScrollAttached then
        module.preview:AddChild(module.preview.scroll)
        module.preview.isScrollAttached = true
        module.preview:PerformLayout()
    end

    updateBottomBar(module)
end

-- Helper callback for the my request list tab: change the quantity slider
function callbacks.onValueChangedCartQuantitySlider(widget, _, value)
    local module = UI
    local itemKey = widget:GetUserData("itemKey")

    module.cartData[itemKey].qty = value
    updateBottomBar(module)

    if module.cart and module.cart.importBox then
        module.cart.importBox:SetText("change detected, click 'Prepare export'")
        module.cart.importBox:SetDisabled(true)
    end

    if module.cart.copyImportCartBtn then
        module.cart.copyImportCartBtn:SetDisabled(true)
    end

    if module.cart.exportArea then
        module.cart.exportArea:ReleaseChildren()
        local lbl = aceGUI:Create("Label")
        lbl:SetText("change detected, click 'Prepare export'")
        lbl:SetFullWidth(true)
        module.cart.exportArea:AddChild(lbl)
        module.cart.exportArea:DoLayout()
    end
end

-- Helper callback for the my request list tab: click the remove button
function callbacks.onClickCartRemoveBtn(widget)
    local module = UI
    local itemKey = widget:GetUserData("itemKey")

    module.cartData[itemKey] = nil
    module.cartCount = module.cartCount - 1
    updateBottomBar(module)
    callbacks.onClickViewRequestList()
end

-- Helper to determine what the bottom status text should be
local function getTabStatusText(self)
    local tab = self.currentTab
    local sv = GBCR.Database and GBCR.Database.savedVariables

    if tab == "browse" then
        -- Already handled by updateStatusText
        return nil
    elseif tab == "cart" then
        local uniqueCount = self.cartCount or 0
        local totalQty = 0

        for _, d in pairs(self.cartData or {}) do
            totalQty = totalQty + (d.qty or 0)
        end

        return string_format("%d item%s  •  %d total quantity", uniqueCount, uniqueCount ~= 1 and "s" or "", totalQty)
    elseif tab == "ledger" then
        if not self.cachedLedgerStatus then
            local entries, newest = 0, 0

            if sv and sv.alts then
                for _, alt in pairs(sv.alts) do
                    if alt.ledger then
                        entries = entries + #alt.ledger
                    end
                    if (alt.version or 0) > newest then
                        newest = alt.version
                    end
                end
            end

            self.cachedLedgerStatus = {entries = entries, newest = newest}
        end

        local s = self.cachedLedgerStatus

        local age = s.newest > 0 and formatTimeAgo(s.newest) or "never"
        if age == "never" then
            age = Globals.ColorizeText(colorGray, age)
        end

        return string_format("showing %d recent ledger entries  •  last guild bank update %s", s.entries, age)
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

-- Helper to refresh the network tab
local function refreshNetworkTabIfOpen(self)
    if self.isNetworkTabOpen then
        populateNetworkTab()
    end
end

-- Update the protocol state
local function notifyStateChanged(self)
    if self and self.isOpen then
        -- Status bar: browse tab has its own richer updateStatusText; all others use getTabStatusText
        if self.currentTab == "browse" then
            updateStatusText(self)
        else
            local statusTxt = getTabStatusText(self)
            if statusTxt and self.window then
                self.window:SetStatusText(statusTxt)
            end
        end

        -- Top-bar text: re-evaluate for tabs whose message depends on runtime state
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

    refreshNetworkTabIfOpen(self)
end

-- Helper to stop data processing for non-data tabs
local function exitNonDataTab(self)
    self.isDataPending = false
    if self.loadingOverlay then
        self.loadingOverlay:Hide()
    end

    local statusTxt = getTabStatusText(self)
    if statusTxt and self.window then
        self.window:SetStatusText(statusTxt)
    end
end

-- Lazy: Refresh the UI
local function refreshUI(self)
    if not self.window or not self.window:IsShown() then

        return
    end

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

    if not GBCR.Database.savedVariables then

        return
    end

    if tab == "ledger" then
        if self.refreshLedger and self.ledgerDataDirty then
            self.ledgerDataDirty = false
            self.refreshLedger()
        end
        exitNonDataTab(self)

        return
    end

    if tab == "network" then
        if UI.isNetworkTabOpen then
            populateNetworkTab()
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
        if self.window and self.window.frame then
            if not self.loadingOverlay then
                setUILoading(self, true)
            else
                self.loadingOverlay:Show()
            end
            if self.loadingOverlayText then
                self.loadingOverlayText:SetText("Loading data, please wait...")
            end
        end

        return
    end

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
        local dirtyCount = 0
        local singleDirtyAlt

        for k in pairs(self.dirtyAlts) do
            dirtyCount = dirtyCount + 1
            singleDirtyAlt = k

            if dirtyCount > 1 then
                break
            end
        end

        if not self.needsFullRebuild and dirtyCount == 1 and self.lastAggregatedView == self.currentView and
            next(self.aggregatedMap) then
            local sv = GBCR.Database.savedVariables
            local oldAltData = sv and sv.alts and sv.alts[singleDirtyAlt]

            for _, aggItem in pairs(self.aggregatedMap) do
                local contrib = aggItem.sources[singleDirtyAlt]
                if contrib then
                    aggItem.itemCount = aggItem.itemCount - contrib
                    aggItem.sources[singleDirtyAlt] = nil
                end
            end

            local items = oldAltData and
                              (oldAltData.items or
                                  (oldAltData.itemsCompressed and GBCR.Database.DecompressData(oldAltData.itemsCompressed)))

            local requiresFullRebuild = false

            if items then
                for i = 1, #items do
                    local item = items[i]
                    local key = item.itemString

                    if key then
                        local aggItem = self.aggregatedMap[key]
                        if not aggItem then
                            requiresFullRebuild = true

                            break
                        end

                        local cnt = item.itemCount or 1
                        aggItem.itemCount = aggItem.itemCount + cnt
                        aggItem.sources[singleDirtyAlt] = (aggItem.sources[singleDirtyAlt] or 0) + cnt
                    end
                end
            end

            -- If the fast path succeeded without finding new items, finalize and return
            if not requiresFullRebuild then
                wipe(self.itemsList)
                local n = 0
                local toDelete = nil

                for key, aggItem in pairs(self.aggregatedMap) do
                    if next(aggItem.sources) then
                        n = n + 1
                        self.itemsList[n] = aggItem
                    else
                        if not toDelete then
                            toDelete = {}
                        end
                        toDelete[#toDelete + 1] = key
                    end
                end

                for i = n + 1, #self.itemsList do
                    self.itemsList[i] = nil
                end

                if toDelete then
                    for i = 1, #toDelete do
                        self.aggregatedMap[toDelete[i]] = nil
                    end
                end

                self.pendingCorpusBuild = true
                self.needsFullRebuild = false
                proceedToRender()

                return
            end
        end

        updateItemsList(self, function()
            self.lastAggregatedView = self.currentView
            self.pendingCorpusBuild = true
            proceedToRender()
        end)
    else
        -- Nothing in the inventory changed, skip aggregation and corpus rebuild entirely
        proceedToRender()
    end
end

-- Close the main window
local function closeWindow(self)
    if not self.isOpen or not self.window then
        return
    end

    callbacks.onCloseWindow()
end

-- Change the transparency of the main window
local function updateTransparency(self)
    if not self.window then
        return
    end

    local frame = self.window.frame
    local isTransparent = GBCR.Options:GetUiTransparency()

    if not isTransparent then
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
        if self.originalBackdrop then
            frame:SetBackdrop(self.originalBackdrop)
            frame:SetBackdropColor(table_unpack(self.originalBackdropColor))
            frame:SetBackdropBorderColor(table_unpack(self.originalBackdropBorderColor))
        end

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

-- Helper to draw the main user interface window with top bar, tabs, and bottom bar
local function drawWindow(self)
    local window = aceGUI:Create("Frame")
    window:SetTitle(GBCR.Core.addonHeader)
    window:SetLayout("GBCR_AppLayout")
    window:SetWidth(850)
    window:SetHeight(485)
    window:SetCallback("OnClose", callbacks.onCloseWindow)
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
            local height, m = GetGameTime()
            timeStr = string_format("%02d:%02d", height, m)
        end

        self.clockLabel:SetText(Globals.ColorizeText(Constants.COLORS.WHITE, timeStr))
    end)

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
    tabs:SetUserData("module", self)
    tabs:SetCallback("OnGroupSelected", callbacks.onGroupSelectedTabs)
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
    bottomBarButton:SetCallback("OnClick", callbacks.onClickViewRequestList)
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
    helpIcon:SetScript("OnEnter", function(widget)
        GameTooltip:SetOwner(widget, "ANCHOR_TOP")
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
        GameTooltip:AddLine("Recent guild bank transactions (mail, trade, vendor, destroy) are recorded.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("The " .. Constants.LEDGER.SYNC_WINDOW .. " most recent entries are synced.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("View donors sorted by total value to sell to a vendor.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Items with no sell price are valued at 1 copper for the ledger.", 0.9, 0.9, 0.9, true)
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

-- Open the main window
local function openWindow(self, tabName)
    self.lastKnownBankAltState = nil
    self.lastKnownOfficerState = nil

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

    UI:RefreshUI()

    GBCR.Protocol:PerformSync()
end

-- Opem or close main window
local function toggleWindow(self)
    if self.isOpen then
        closeWindow(self)
    else
        openWindow(self)
    end
end

-- Open or close main window to a specific tab
local function toggleTab(self, tabName)
    if self.isOpen and self.currentTab == tabName then
        closeWindow(self)
    else
        openWindow(self, tabName)
    end
end

-- Restores the UI to their default sizes and positions; called by GBCR.Core, GBCR.Constants, and UI.Minimap
local function restoreUI(self)
    local optionsDB = GBCR.Options:GetOptionsDB()
    if not optionsDB then
        return
    end

    local function resetWindow(module, moduleDefaultsKey)
        if not module or not module.window then
            return
        end

        local window = module.window
        local frame = window.frame
        local defaults = optionsDB.defaults.profile.framePositions[moduleDefaultsKey]
        local newStatus = {width = defaults.width, height = defaults.height}

        if moduleDefaultsKey == "debug" then
            newStatus.left = UIParent:GetWidth() - defaults.width - 200
            newStatus.top = defaults.height + 50
        end

        optionsDB.profile.framePositions[moduleDefaultsKey] = newStatus
        window:SetStatusTable(optionsDB.profile.framePositions[moduleDefaultsKey])
        window:ApplyStatus()

        frame:ClearAllPoints()
        if moduleDefaultsKey == "inventory" then
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        else
            frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -200, 50)
        end
    end

    resetWindow(UI, "inventory")
    resetWindow(UI.Debug, "debug")

    local paneDefaults = optionsDB.defaults.profile.framePositions.panes
    if paneDefaults then
        optionsDB.profile.framePositions.panes = {
            cartLeft = paneDefaults.cartLeft or 550,
            previewRight = paneDefaults.previewRight or 284
        }
        UI.activeCartLeftPaneWidth = optionsDB.profile.framePositions.panes.cartLeft
        UI.activePreviewRightPaneWidth = optionsDB.profile.framePositions.panes.previewRight
    end

    if UI.tabs and UI.currentTab then
        UI.tabs:SelectTab(UI.currentTab)
    end

    forceDraw(self)

    GBCR.Output:Response("The user interface window size and position have been reset to their defaults.")
end

-- Helper to attempt to undo the mess that Auctioneer + TSM create with label fonts
local function patchAceGUIFonts()
    local aceGUILib = GBCR.Libs.AceGUI
    if not aceGUILib then
        return
    end

    local origCreate = aceGUILib.Create

    local function setSafeFont(obj, fontObject)
        if obj and type(obj.SetFontObject) == "function" then
            obj:SetFontObject(fontObject)
        end
    end

    aceGUILib.Create = function(self, widgetType, ...)
        local widget = origCreate(self, widgetType, ...)
        if not widget then
            return widget
        end

        if widgetType == "Label" or widgetType == "InteractiveLabel" then
            setSafeFont(widget.label, GameFontNormal)
            if widget.frame then
                setSafeFont(widget.frame.label, GameFontNormal)
            end
        elseif widgetType == "EditBox" then
            setSafeFont(widget.label, GameFontNormal)
            setSafeFont(widget.editbox, GameFontHighlight)
        elseif widgetType == "MultiLineEditBox" then
            setSafeFont(widget.label, GameFontNormal)
            setSafeFont(widget.editBox, GameFontHighlight)
            if widget.button then
                widget.button:SetNormalFontObject(GameFontNormal)
                widget.button:SetHighlightFontObject(GameFontHighlight)
            end
        elseif widgetType == "Button" then
            if widget.frame then
                widget.frame:SetNormalFontObject(GameFontNormal)
                widget.frame:SetHighlightFontObject(GameFontHighlight)
                widget.frame:SetDisabledFontObject(GameFontDisable)
            end
            setSafeFont(widget.text, GameFontNormal)
        elseif widgetType == "Dropdown" then
            setSafeFont(widget.label, GameFontNormal)
            setSafeFont(widget.text, GameFontHighlight)
        elseif widgetType == "CheckBox" then
            setSafeFont(widget.text, GameFontNormal)
        elseif widgetType == "Slider" then
            setSafeFont(widget.label, GameFontNormal)
            setSafeFont(widget.lowtext, GameFontHighlightSmall)
            setSafeFont(widget.hightext, GameFontHighlightSmall)
            setSafeFont(widget.editbox, GameFontHighlightSmall)
        end

        return widget
    end
end

-- Helper callback for the main window: closing the window
function callbacks.onCloseWindow()
    local module = UI

    module.isOpen = false
    module.renderGeneration = (module.renderGeneration or 0) + 1

    if module.window then
        module.window:Hide()
    end
end

-- Helper callback for the main window: select a tab
function callbacks.onGroupSelectedTabs(container, _, group)
    local module = container:GetUserData("module")

    module.container = container

    if GBCR.Libs.AceConfigDialog.OpenFrames[addonName] then
        GBCR.Libs.AceConfigDialog:Close(addonName)
    end

    if module.itemPool then
        for i = 1, #module.itemPool do
            if module.itemPool[i] then
                aceGUI:Release(module.itemPool[i])
            end
        end
        wipe(module.itemPool)
    end

    if module.emptyLabel then
        module.emptyLabel:Hide()
    end

    module.currentTab = group
    if module.topBar and module.topBar.topBarText then
        local msg = getTabTopBarMessage(group)
        module.topBarBaseText = msg
        module.topBar.topBarText:SetText(msg)
        if module.isSyncing then
            setSyncing(module, true)
        end
    end

    setUILoading(module, module.isDataPending)

    module.browsePanelDrawn = false
    module.requestsTabGeneration = (module.requestsTabGeneration or 0) + 1

    module.tree = nil
    module.filters = nil
    module.grid = nil
    module.preview = nil
    module.searchWrapper = nil
    module.emptyLabel = nil

    container:ReleaseChildren()
    container:SetLayout("Fill")

    if group == "browse" then
        drawBrowseTab(module, container)
    elseif group == "cart" then
        drawCartTab(module, container)
    elseif group == "fulfillment" then
        drawFulfillmentTab(module, container)
    elseif group == "ledger" then
        drawLedgerTab(module, container)
    elseif group == "export" then
        drawExportTab(module, container)
    elseif group == "configuration" then
        drawConfigurationTab(module, container)
    elseif group == "network" then
        drawNetworkTab(module, container)
    end

    updateBottomBar(module)

    if group ~= "browse" then
        UI:RefreshUI()
    end
end

-- ================================================================================================

-- Initialize
local function init(self)
    UI.Minimap.Init()

    self.isReady = false
    self.ledgerDataDirty = false

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

    self.rosterPool = {}
    self.networkTicker = nil
    self.networkTickCount = 0
    self.rowHeight = 20

    patchAceGUIFonts()

    self.fulfillmentPlan = nil
    self.batchIndex = 0

    self.recycledStacks = {}
    self.recycledDirectOps = {}
end

-- ================================================================================================

-- Export functions for other modules
UI.ClearDebugContent = clearDebugContent
UI.QueueDebugLogRefresh = queueDebugLogRefresh

UI.OnChatEdit_InsertLink = callbacks.onChatEdit_InsertLink

UI.SetSyncing = setSyncing
UI.RecordSuccessfulSeed = recordSuccessfulSeed
UI.RecordReceived = recordReceived
UI.StopNetworkTicker = stopNetworkTicker

UI.MarkAltDirty = markAltDirty
UI.MarkAllDirty = markAllDirty

UI.ForceDraw = forceDraw
UI.QueueUIRefresh = queueUIRefresh
UI.NotifyStateChanged = notifyStateChanged
UI.RefreshUI = refreshUI -- Lazy-loaded
UI.Close = closeWindow
UI.UpdateTransparency = updateTransparency
UI.Open = openWindow
UI.Toggle = toggleWindow
UI.ToggleTab = toggleTab
UI.RestoreUI = restoreUI

UI.Init = init
