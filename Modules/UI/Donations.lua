GBankClassic_UI_Donations = {}

function GBankClassic_UI_Donations:Init()
    self:DrawWindow()
end

local function OnClose(_)
    GBankClassic_UI_Donations.isOpen = false
    GBankClassic_UI_Donations.Window:Hide()
end

function GBankClassic_UI_Donations:Toggle()
    if self.isOpen then
        self:Close()
    else
        self:Open()
    end
end

function GBankClassic_UI_Donations:Open()
    if self.isOpen then return end
    self.isOpen = true

    if not self.Window then
        self:DrawWindow()
    end

    self.Window:Show()
    if GBankClassic_UI_Inventory.isOpen and GBankClassic_UI_Inventory.Window then
        self.Window:ClearAllPoints()
        self.Window:SetPoint("TOPLEFT", GBankClassic_UI_Inventory.Window.frame, "TOPRIGHT", 0, 0)
    end

    self:DrawContent()

    if _G["GBankClassic"] then
        _G["GBankClassic"]:Show()
    else
        GBankClassic_UI:Controller()
    end
end

function GBankClassic_UI_Donations:Close()
    if not self.isOpen then return end
    if not self.Window then return end

    OnClose(self.Window)

    if GBankClassic_UI_Inventory.isOpen == false then
        _G["GBankClassic"]:Hide()
    end
end

function GBankClassic_UI_Donations:DrawWindow()
    local donations = GBankClassic_UI:Create("Frame")
    donations:Hide()
    donations:SetCallback("OnClose", OnClose)
    donations:SetTitle("Donations")
    donations:SetLayout("Flow")
    ---START CHANGES
    donations:SetWidth(350)
    ---END CHANGES
    donations:EnableResize(false)
    --handle keyboard events
    donations.frame:EnableKeyboard(true)
    donations.frame:SetPropagateKeyboardInput(true)
    donations.frame:SetScript("OnKeyDown", function (self, event)
        GBankClassic_UI:EventHandler(self, event)
    end)

    self.Window = donations

    local content = GBankClassic_UI:Create("SimpleGroup")
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
                alignV = "middle"
            },
            {
                width = 0.2,
                alignH = "end",
                alignV = "middle"
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

function GBankClassic_UI_Donations:DrawContent()
    self.Window:SetStatusText("")
    self.Content:ReleaseChildren()

    local info = GBankClassic_Guild.Info
    if not info or not info.roster.version then
        return
    end

    local players = {}
    local alts = info.alts
    for _, v in pairs(info.roster.alts) do
        if alts[v] then
            local alt = alts[v]
            if alt.ledger then
                for p, s in pairs(alt.ledger) do
                    if not players[p] then
                        players[p] = s
                    else
                        players[p] = players[p] + s
                    end
                end
            end
        end
    end

    local scoreboard = {}
    for k, v in pairs(players) do
        table.insert(scoreboard, {player = k, score = v})
    end

    table.sort(scoreboard, function (a, b) return a.score > b.score end)

    local header = GBankClassic_UI:Create("Label")
    header:SetText("")
    self.Content:AddChild(header)

    header = GBankClassic_UI:Create("Label")
    header:SetText("Name")
    self.Content:AddChild(header)

    header = GBankClassic_UI:Create("Label")
    header:SetText("Score")
    self.Content:AddChild(header)

    local count = 0
    for _, v in pairs(scoreboard) do
        count = count + 1

        if count <= 25 then
            local rank = GBankClassic_UI:Create("Label")
            local formatString = " %d)"
            if count < 10 then
                formatString = "  " .. formatString
            end
            rank:SetText(string.format(formatString, count))
            self.Content:AddChild(rank)

            local color = "ff888888"
            local class = GBankClassic_Guild:GetPlayerInfo(v.player)
            if class then
                _, _, _, color = GetClassColor(class)
            end
            local contributor = GBankClassic_UI:Create("Label")
            contributor:SetText(string.format("|c%s%s|r", color, v.player))
            self.Content:AddChild(contributor)

            local score = GBankClassic_UI:Create("Label")
            score:SetText(string.format("|c%s%d|r", color, math.ceil(v.score)))
            self.Content:AddChild(score)
        end
    end

    self.Window:SetStatusText(count .. " Total")
end