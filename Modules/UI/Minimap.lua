GBankClassic_UI_Minimap = {}

function GBankClassic_UI_Minimap:Init()
    self.icon = LibStub("LibDBIcon-1.0")
    local iconDB = LibStub("LibDataBroker-1.1"):NewDataObject("GBankClassicIcon", {
        type = "data source",
        text = "GBankClassic",
        icon = "Interface/ICONS/INV_Box_04", --purplebox
        OnEnter = function ()
            self:ShowTooltip()
        end,
        OnLeave = function()
            GBankClassic_UI:HideTooltip()
        end,
        OnClick = function(_, b)
            if IsShiftKeyDown() then
                GBankClassic_Options:Open()
            else
                GBankClassic_UI_Inventory:Toggle()
            end
        end,
    })
    self.db = LibStub("AceDB-3.0"):New("GBankClassicIconDB", {
        profile = {
            minimap = {
                hide = not GBankClassic_Options.db.char.minimap["enabled"],
            },
        },
    })
    self.icon:Register("GBankClassic", iconDB, self.db.profile.minimap)
end

function GBankClassic_UI_Minimap:Toggle()
    if not GBankClassic_Options:GetMinimapEnabled() then
        self.icon:Hide("GBankClassic")
    else
        self.icon:Show("GBankClassic")
    end
end

function GBankClassic_UI_Minimap:ShowTooltip()
    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip:AddLine("GBankClassic")
    GameTooltip:AddDoubleLine("Click", "Inventory", 1, 1, 1)
    GameTooltip:AddDoubleLine("Shift-Click", "Options", 1, 1, 1)
    GameTooltip:Show()
end