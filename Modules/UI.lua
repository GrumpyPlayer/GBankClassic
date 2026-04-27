local addonName, GBCR = ...

GBCR.UI = {}
local UI = GBCR.UI

local Globals = GBCR.Globals
local wipe = Globals.wipe

local After = Globals.After
local GameFontDisable = Globals.GameFontDisable
local GameFontHighlight = Globals.GameFontHighlight
local GameFontHighlightSmall = Globals.GameFontHighlightSmall
local GameFontNormal = Globals.GameFontNormal
local GameTooltip = Globals.GameTooltip
local GameTooltip_SetDefaultAnchor = Globals.GameTooltip_SetDefaultAnchor
local GetServerTime = Globals.GetServerTime
local UIParent = Globals.UIParent
local WorldFrame = Globals.WorldFrame

local Constants = GBCR.Constants

-- Clears the contents of the debug output (with /bank debugclear) as seen in the seperate debug output window (/bank debuglog); called by GBCR.Constants
local function clearDebugContent(self)
    wipe(GBCR.Output.debugMessageBuffer)

    if GBCR.UI.Debug.content then
        GBCR.UI.Debug.content:SetText("")
    end

    GBCR.Output:Response("Debug output cleared.")
end

-- Called each time a new debug message needs to be logged to refresh the output window only once every x seconds (fixed delay); called by GBCR.Output
local function queueDebugLogRefresh(self)
    if GBCR.UI.Debug.isRefreshPending then
        return
    end

    GBCR.UI.Debug.isRefreshPending = true

    After(Constants.TIMER_INTERVALS.DEBUG_LOG_REFRESH, function()
        GBCR.UI.Debug.isRefreshPending = false

        if GBCR.UI.Debug.isOpen then
            GBCR.UI.Debug:DrawContent()
        end
    end)
end

-- Immediately draws all open UI windows and cancels any pending delayed refreshes; called when opening windows
local function forceDraw(self)
    GBCR.Output:Debug("UI", "UI:ForceDraw called")

    self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1

    GBCR.UI.Inventory:Refresh()
end

-- Called each time data changes to queue a UI refresh with native debouncing total prevent double-refreshes; called by GBCR.Events, GBCR.Protocol, GBCR.Guild, and GBCR.Inventory
local function queueUIRefresh(self)
    GBCR.Output:Debug("UI", "UI:QueueUIRefresh called")

    -- Hard cap: if we haven't rendered in 3 seconds, force one now regardless of how many events are still arriving
    -- Prevents stale UI during high-traffic syncs
    local now = GetServerTime()
    self._lastForcedRefresh = self._lastForcedRefresh or 0

    if now - self._lastForcedRefresh >= Constants.TIMER_INTERVALS.UI_REFRESH_FORCE_AGE then
        self._lastForcedRefresh = now
        self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1
        forceDraw(self)

        return
    end

    -- Trailing debounce: collapse rapid calls, wait 0.5s after the last one
    -- 0.5s is imperceptible to users but batches bursts of protocol events
    self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1
    local currentGen = self.uiRefreshGeneration

    After(Constants.TIMER_INTERVALS.UI_REFRESH_DEBOUNCE, function()
        if self.uiRefreshGeneration ~= currentGen then
            return -- A newer call superseded this one
        end
        self._lastForcedRefresh = GetServerTime()
        forceDraw(self)
    end)
end

-- Restores the UI to their default sizes and positions; called by GBCR.Core, GBCR.Constants, and GBCR.UI.Minimap
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

    resetWindow(GBCR.UI.Inventory, "inventory")
    resetWindow(GBCR.UI.Debug, "debug")

    -- Reset pane widths to defaults
    local paneDefaults = optionsDB.defaults.profile.framePositions.panes
    if paneDefaults then
        optionsDB.profile.framePositions.panes = {
            cartLeft = paneDefaults.cartLeft or 550,
            previewRight = paneDefaults.previewRight or 284
        }
        GBCR.UI.Inventory.activeCartLeftPaneWidth = optionsDB.profile.framePositions.panes.cartLeft
        GBCR.UI.Inventory.activePreviewRightPaneWidth = optionsDB.profile.framePositions.panes.previewRight
    end

    if GBCR.UI.Inventory.tabs and GBCR.UI.Inventory.currentTab then
        GBCR.UI.Inventory.tabs:SelectTab(GBCR.UI.Inventory.currentTab)
    end

    forceDraw(self)

    GBCR.Output:Response("The user interface window size and position have been reset to their defaults.")
end

-- Show the item tooltip in the main UI but throttle these frequency; called by GBCR.UI.Inventory
local function showItemTooltip(self, itemLink, sources)
    if not itemLink then
        return
    end

    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip.pendingSourcesForGBCR = sources
    GameTooltip:SetHyperlink(itemLink)
    GameTooltip:Show()
end

-- Hide the item tooltips and reset the throttle frquencye; called by GBCR.UI.Inventory
local function hideTooltip(self)
    GameTooltip.pendingSourcesForGBCR = nil
    GameTooltip:Hide()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
end

-- Helper to undo the mess that Auctioneer + TSM create with label fonts
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

-- Initialize; called by GBCR.Core
local function init(self)
    GBCR.UI.Minimap.Init()
    GBCR.UI.Inventory:Init()

    patchAceGUIFonts()
end

-- Export functions for other modules
UI.ClearDebugContent = clearDebugContent
UI.QueueDebugLogRefresh = queueDebugLogRefresh
UI.ForceDraw = forceDraw
UI.QueueUIRefresh = queueUIRefresh
UI.RestoreUI = restoreUI
UI.ShowItemTooltip = showItemTooltip
UI.HideTooltip = hideTooltip
UI.Init = init
