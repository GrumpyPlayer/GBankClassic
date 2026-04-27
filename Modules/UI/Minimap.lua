local addonName, GBCR = ...

GBCR.UI.Minimap = {}
local UI_Minimap = GBCR.UI.Minimap

local Globals = GBCR.Globals
local GameTooltip = Globals.GameTooltip
local IsAltKeyDown = Globals.IsAltKeyDown
local IsControlKeyDown = Globals.IsControlKeyDown
local IsShiftKeyDown = Globals.IsShiftKeyDown
local WorldFrame = Globals.WorldFrame

-- Initialize
local function init()
    local iconDB = GBCR.Libs.LibDataBroker:NewDataObject("GBankClassicIcon", {
        type = "data source",
        text = GBCR.Core.addonHeader,
        icon = "Interface/ICONS/INV_Box_04",
        OnEnter = function()
            GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
            GameTooltip:AddLine(GBCR.Core.addonHeader)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Left-click:", "Browse guild bank items", 1, 1, 1)
            GameTooltip:AddDoubleLine("Right-click:", "View synchronization status", 1, 1, 1)
            GameTooltip:AddDoubleLine("Middle-click:", "Prepare data export", 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Shift-click", "Configure options", 1, 1, 1)
            GameTooltip:AddDoubleLine("Ctrl-click", "Restore default UI", 1, 1, 1)
            GameTooltip:AddDoubleLine("Alt-click", "Show debug output window", 1, 1, 1)
            GameTooltip:Show()
        end,
        OnLeave = function()
            GameTooltip:Hide()
        end,
        OnClick = function(_, button)
            if IsShiftKeyDown() then
                GBCR.UI.Inventory:ToggleTab("configuration")
            elseif IsControlKeyDown() then
                GBCR.UI:RestoreUI()
            elseif IsAltKeyDown() then
                GBCR.UI.Debug:Toggle()
            else
                if button == "LeftButton" then
                    GBCR.UI.Inventory:ToggleTab("browse")
                elseif button == "RightButton" then
                    GBCR.UI.Inventory:ToggleTab("network")
                elseif button == "MiddleButton" then
                    GBCR.UI.Inventory:ToggleTab("export")
                end
            end
        end
    })

    GBCR.Libs.LibDBIcon:Register(addonName, iconDB, GBCR.Options.db.profile.minimap)
end

-- Export functions for other modules
UI_Minimap.Init = init
