local addonName, GBCR = ...

GBCR.UI.Donations = {}
local UI_Donations = GBCR.UI.Donations

local Globals = GBCR.Globals
local GetClassColor = Globals.GetClassColor
local GetCoinTextureString = Globals.GetCoinTextureString
local GameTooltip = Globals.GameTooltip

local Constants = GBCR.Constants
local colorGray = Constants.COLORS.GRAY

function UI_Donations:Init()
    self:DrawWindow()
end

function UI_Donations:Toggle()
    if self.isOpen then
        self:Close()
    else
        self:Open()
    end
end

function UI_Donations:Open()
	if self.isOpen then
		return
	end

    self.isOpen = true

    if not self.Window then
        self:DrawWindow()
    end

    self.Window:Show()
    if GBCR.UI.Inventory.isOpen and GBCR.UI.Inventory.Window then
        self.Window:ClearAllPoints()
        self.Window:SetPoint("TOPLEFT", GBCR.UI.Inventory.Window.frame, "TOPRIGHT", 0, 0)
    end

	GBCR.UI:ClampFrameToScreen(self.Window)

    self:DrawContent()
end

function UI_Donations:Close()
	if not self.isOpen then
		return
	end
	if not self.Window then
		return
	end

    self:OnClose()
end

function UI_Donations:OnClose()
    self.isOpen = false
    if self.Window then
        self.Window:Hide()
    end
end

function UI_Donations:DrawWindow()
    local donations = GBCR.Libs.AceGUI:Create("Frame")
    donations:Hide()
    donations:SetCallback("OnClose", function()
        self:OnClose()
    end)
    donations:SetTitle("Donations")
    donations:SetLayout("Flow")
    donations:EnableResize(false)
    donations.frame:SetSize(350, 500)
    donations.frame:EnableKeyboard(true)
    donations.frame:SetPropagateKeyboardInput(true)

    self.Window = donations

    local content = GBCR.Libs.AceGUI:Create("SimpleGroup")
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

    self.Content = content
end

function UI_Donations:DrawContent()
    GBCR.Output:Debug("UI", "UI_Donations:DrawContent called")
    self.Window:SetStatusText("")
    self.Content:ReleaseChildren()

    local info = GBCR.Database.savedVariables
	local roster_alts = GBCR.Guild:GetRosterGuildBankAlts()
	if not info or not roster_alts then
		return
	end

    local players = {}
    local alts = info.alts
    for i = 1, #roster_alts do
        local guildBankAltName = roster_alts[i]
		local norm = GBCR.Guild:NormalizeName(guildBankAltName) or guildBankAltName
		local alt = alts[norm]
		if alt and alt.ledger then
            for donatedBy, donationValue in pairs(alt.ledger) do
                if not players[donatedBy] then
                    players[donatedBy] = donationValue
                else
                    players[donatedBy] = players[donatedBy] + donationValue
                end
            end
        end
    end

    local donations = {}
    for donatedBy, donationValue in pairs(players) do
        table.insert(donations, { donatedBy = donatedBy, donationValue = donationValue })
    end
    table.sort(donations, function(a, b)
        return a.donationValue > b.donationValue
    end)

    local header = GBCR.Libs.AceGUI:Create("Label")
    header:SetText("")
    self.Content:AddChild(header)

    header = GBCR.Libs.AceGUI:Create("Label")
    header:SetText("Top 30 donors")
    self.Content:AddChild(header)

    header = GBCR.Libs.AceGUI:Create("Label")
    header:SetText("Vendor value")
    self.Content:AddChild(header)
    header.frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Total value to sell to a vendor", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Items with no sell price are valued at 1 copper for the donation ledger", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header.frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local count = #donations
    for index, ledgerEntry in ipairs(donations) do
        if count <= 30 then
            local rank = GBCR.Libs.AceGUI:Create("Label")
            local formatString = " %d)"
            if count < 10 then
                formatString = "  " .. formatString
            end
            rank:SetText(string.format(formatString, index))
            self.Content:AddChild(rank)

            local color = colorGray
            local playerClass = GBCR.Guild:GetGuildMemberInfo(ledgerEntry.donatedBy)
            if playerClass then
                color = select(4, GetClassColor(playerClass))
            end
            local donatedBy = GBCR.Libs.AceGUI:Create("Label")
            donatedBy:SetText(GBCR.Globals:Colorize(color, ledgerEntry.donatedBy))
            self.Content:AddChild(donatedBy)

            local donationValue = GBCR.Libs.AceGUI:Create("Label")
            local totalCopper = math.floor(ledgerEntry.donationValue * 10000 + 0.5)
            donationValue:SetText(GBCR.Globals:Colorize(color, GetCoinTextureString(totalCopper)))
            self.Content:AddChild(donationValue)
        end
    end

    local plural = (count ~= 1 and "s" or "")
    self.Window:SetStatusText(count .. " total donor" .. plural)
end