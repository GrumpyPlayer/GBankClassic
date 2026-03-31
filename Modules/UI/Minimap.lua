local addonName, GBCR = ...

GBCR.UI.Minimap = {}
local UI_Minimap = GBCR.UI.Minimap

local Globals = GBCR.Globals
local IsShiftKeyDown = Globals.IsShiftKeyDown
local IsControlKeyDown = Globals.IsControlKeyDown
local GameTooltip = Globals.GameTooltip
local WorldFrame = Globals.WorldFrame

function UI_Minimap:Init()
    local iconDB = GBCR.Libs.LibDataBroker:NewDataObject("GBankClassicIcon", {
        type = "data source",
        text = GBCR.Core.addonHeader,
        icon = "Interface/ICONS/INV_Box_04",
        OnEnter = function()
            UI_Minimap:ShowTooltip()
        end,
        OnLeave = function()
            GBCR.UI:HideTooltip()
        end,
        OnClick = function(_, b)
            if IsShiftKeyDown() then
                GBCR.Options:Open()
            elseif IsControlKeyDown() then
                GBCR.Chat:RestoreUI()
            else
                GBCR.UI.Inventory:Toggle()
            end
        end,
    })
    GBCR.Libs.LibDBIcon:Register("GBankClassic", iconDB, GBCR.Options.db.profile.minimap)
end

function UI_Minimap:Toggle()
    if not GBCR.Options:GetMinimapEnabled() then
        GBCR.Libs.LibDBIcon:Hide("GBankClassic")
    else
        GBCR.Libs.LibDBIcon:Show("GBankClassic")
    end
end

function UI_Minimap:ShowTooltip()
    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip:AddLine(GBCR.Core.addonHeader)
    GameTooltip:AddDoubleLine("Click", "Show guild bank items", 1, 1, 1)
    GameTooltip:AddDoubleLine("Shift-Click", "Configure options", 1, 1, 1)
    GameTooltip:AddDoubleLine("Ctrl-Click", "Restore default UI", 1, 1, 1)
    GameTooltip:Show()
end