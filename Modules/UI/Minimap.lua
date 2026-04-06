local addonName, GBCR = ...

GBCR.UI.Minimap = {}
local UI_Minimap = GBCR.UI.Minimap

local Globals = GBCR.Globals
local GameTooltip = Globals.GameTooltip
local IsAltKeyDown = Globals.IsAltKeyDown
local IsControlKeyDown = Globals.IsControlKeyDown
local IsShiftKeyDown = Globals.IsShiftKeyDown
local WorldFrame = Globals.WorldFrame

local function init(self)
    local iconDB = GBCR.Libs.LibDataBroker:NewDataObject("GBankClassicIcon", {
        type = "data source",
        text = GBCR.Core.addonHeader,
        icon = "Interface/ICONS/INV_Box_04",
        OnEnter = function()
            GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
            GameTooltip:AddLine(GBCR.Core.addonHeader)
            GameTooltip:AddDoubleLine("Click", "Show guild bank items", 1, 1, 1)
            GameTooltip:AddDoubleLine("Shift-Click", "Configure options", 1, 1, 1)
            GameTooltip:AddDoubleLine("Ctrl-Click", "Restore default UI", 1, 1, 1)
            GameTooltip:AddDoubleLine("Alt-Click", "Show debug output window", 1, 1, 1)
            GameTooltip:Show()
        end,
        OnLeave = function()
            GameTooltip:Hide()
        end,
        OnClick = function(_, b)
            if IsShiftKeyDown() then
                GBCR.Options:Open()
            elseif IsControlKeyDown() then
                GBCR.UI:RestoreUI()
            elseif IsAltKeyDown() then
                GBCR.UI.Debug:Toggle()
            else
                GBCR.UI.Inventory:Toggle()
            end
        end,
    })

    GBCR.Libs.LibDBIcon:Register(addonName, iconDB, GBCR.Options.db.profile.minimap)
end

-- Export functions for other modules
UI_Minimap.Init = init