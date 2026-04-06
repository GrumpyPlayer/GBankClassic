local addonName, GBCR = ...

GBCR.UI.Donations = {}
local UI_Donations = GBCR.UI.Donations

local Globals = GBCR.Globals
local ipairs = Globals.ipairs
local math_floor = Globals.math_floor
local select = Globals.select
local string_format = Globals.string_format

local GameTooltip = Globals.GameTooltip
local GetClassColor = Globals.GetClassColor
local GetCoinTextureString = Globals.GetCoinTextureString

local Constants = GBCR.Constants
local colorGray = Constants.COLORS.GRAY

local function onClose(self)
    self.isOpen = false

    if self.window then
        self.window:Hide()
    end
end

local function drawContent(self)
    GBCR.Output:Debug("UI", "UI_Donations:DrawContent called")

    if not self.window or not self.window:IsVisible() then
		GBCR.Output:Debug("UI", "UI_Donations:DrawContent: early exit since window is not visible")

        return
    end

    if self.needsDonationRebuild or not self.cachedDonations then
        GBCR.Donations:BuildDonationCache()

        if not self.cachedDonations then
    		GBCR.Output:Debug("UI", "UI_Donations:DrawContent: early exit because of missing data")

            return
        end
    end

    self.window:SetStatusText("")
    self.content:ReleaseChildren()

    local aceGUI = GBCR.Libs.AceGUI

    local header = aceGUI:Create("Label")
    header:SetText("")
    self.content:AddChild(header)

    header = aceGUI:Create("Label")
    header:SetText("Top 30 donors")
    self.content:AddChild(header)

    header = aceGUI:Create("Label")
    header:SetText("Vendor value")
    self.content:AddChild(header)
    header.frame:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:SetText("Total value to sell to a vendor", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Items with no sell price are valued at 1 copper for the donation ledger", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local count = #self.cachedDonations
    local guild = GBCR.Guild

    for index, ledgerEntry in ipairs(self.cachedDonations) do
        if index <= 30 then
            local rank = aceGUI:Create("Label")
            local formatString = (index < 10) and "  %d)" or " %d)"
            rank:SetText(string_format(formatString, index))
            self.content:AddChild(rank)

            local color = colorGray
            local playerClass = guild:GetGuildMemberInfo(ledgerEntry.donatedBy)
            if playerClass then
                color = select(4, GetClassColor(playerClass))
            end

            local donatedBy = aceGUI:Create("Label")
            donatedBy:SetText(Globals:Colorize(color, ledgerEntry.donatedBy))
            self.content:AddChild(donatedBy)

            local donationValue = aceGUI:Create("Label")
            donationValue:SetText(Globals:Colorize(color, GetCoinTextureString(math_floor(ledgerEntry.donationValue * 10000 + 0.5))))
            self.content:AddChild(donationValue)
        end
    end

    local plural = (count ~= 1 and "s" or "")
    self.window:SetStatusText(count .. " total donor" .. plural)
end

local function drawWindow(self)
    local aceGUI = GBCR.Libs.AceGUI

    local donations = aceGUI:Create("Frame")
    donations:Hide()
    donations:SetCallback("OnClose", function()
        onClose(UI_Donations)
    end)
    donations:SetTitle("Donations")
    donations:SetLayout("Flow")
    donations:EnableResize(false)
    donations.frame:SetSize(350, 500)
    donations.frame:EnableKeyboard(true)
    donations.frame:SetPropagateKeyboardInput(true)
    self.window = donations

    local content = aceGUI:Create("SimpleGroup")
    content:SetLayout("Table")
    content:SetUserData("table", {
        columns = {
            {
                width = 15,
                align = "CENTERRIGHT",
            },
            {
                width = 0.6,
                alignH = "start",
                alignV = "middle",
            },
            {
                width = 0.2,
                alignH = "end",
                alignV = "middle",
            },
        },
        spaceH = 5,
        spaceV = 1,
    })
    content:SetFullWidth(true)
    content:SetFullHeight(true)
    content.content:ClearAllPoints()
    content.content:SetPoint("TOPLEFT", content.frame, "TOPLEFT", 5, -10)
    donations:AddChild(content)
    self.content = content
end

local function openWindow(self)
	if self.isOpen then
		return
	end

    self.isOpen = true

    if not self.window then
        drawWindow(self)
    end

    self.window:Show()

    if GBCR.UI.Inventory.isOpen and GBCR.UI.Inventory.window then
        self.window:ClearAllPoints()
        self.window:SetPoint("TOPLEFT", GBCR.UI.Inventory.window.frame, "TOPRIGHT", 0, 0)
    end

	GBCR.UI:ClampFrameToScreen(self.window)

    GBCR.UI:ForceDraw()
end

local function closeWindow(self)
	if not self.isOpen or not self.window then
		return
	end

    onClose(self)
end

local function toggleWindow(self)
    if self.isOpen then
        closeWindow(self)
    else
        openWindow(self)
    end
end

local function init(self)
    self.donationTimer = nil
    self.cachedDonations = nil
    self.needsDonationRebuild = true

    drawWindow(self)
end

-- Export functions for other modules
UI_Donations.DrawContent = drawContent
UI_Donations.Close = closeWindow
UI_Donations.Toggle = toggleWindow
UI_Donations.Init = init