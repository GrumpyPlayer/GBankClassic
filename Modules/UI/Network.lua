local addonName, GBCR = ...

GBCR.UI.Network = {}
local UI_Network = GBCR.UI.Network

UI_Network.rosterPool = {}

local Globals = GBCR.Globals
local ipairs = Globals.ipairs
local math_max = Globals.math_max
local pairs = Globals.pairs
local string_format = Globals.string_format

local CreateFrame = Globals.CreateFrame
local GameFontNormal = Globals.GameFontNormal
local GetServerTime = Globals.GetServerTime
local NewTicker = Globals.NewTicker
local IsInGuild = Globals.IsInGuild

local Constants = GBCR.Constants
local colorGreen = Constants.COLORS.GREEN
local colorYellow = Constants.COLORS.YELLOW
local colorRed = Constants.COLORS.RED
local colorBlue = Constants.COLORS.BLUE
local colorGray = Constants.COLORS.GRAY

-- Helpers
local formatTimeAgo = GBCR.UI.Inventory.FormatTimeAgo

-- Persistent state (survives /reload)
local function getSyncMeta()
    local sv = GBCR.Database.savedVariables
    if not sv then
        return {}
    end

    sv.networkMeta = sv.networkMeta or {}

    return sv.networkMeta
end

function UI_Network:RecordSuccessfulSeed(toPlayer)
    local meta = getSyncMeta()
    meta.lastSeedTime = GetServerTime()
    meta.lastSeedTarget = toPlayer
    meta.seedCount = (meta.seedCount or 0) + 1
    local myName = GBCR.Guild:GetNormalizedPlayerName()
    local sv = GBCR.Database.savedVariables
    if sv and sv.alts and sv.alts[myName] then
        meta.lastSharedVersion = sv.alts[myName].version or 0
    end
    GBCR.UI.Inventory:SetSyncing(false)
    GBCR.UI.Inventory:NotifyStateChanged()
end

function UI_Network:RecordReceived(altName, fromPlayer)
    local meta = getSyncMeta()
    meta.lastReceiveTime = GetServerTime()
    meta.lastReceiveAlt = altName
    meta.lastReceiveSource = fromPlayer
    GBCR.UI.Inventory:SetSyncing(false)
    GBCR.UI.Inventory:NotifyStateChanged()
end

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
        return "INFO", string_format("Syncing with %d user%s online%s", s.addonUserCount, pluralUsers, activity)
    end

    return "OK", string_format("Up to date, %d user%s online%s", s.addonUserCount, pluralUsers, activity)
end

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

    if s.syncing then
        return "INFO", "Syncing guild bank data... Please stay online."
    end

    if hasUnsharedChanges then
        if s.addonUserCount == 0 then
            return "WARN", "Your have unshared changes, but no other addon users are online to receive the update."
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
        return "WARN", "Your data is up to date and was previously shared. No peers are currently online."
    end

    return "OK", "Your data is up to date and has been shared. Ready for new changes."
end

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

-- Live-update ticker
local _ticker = nil
local _tickCount = 0

local function startTicker(self)
    if _ticker then
        return
    end

    _tickCount = 0
    _ticker = NewTicker(10, function()
        if not self.isOpen then
            if _ticker then
                _ticker:Cancel()
                _ticker = nil
            end
            return
        end
        _tickCount = _tickCount + 1
        if _tickCount % 3 == 0 then
            self:Populate()
        else
            self:UpdateDynamicLabels()
        end
    end)
end

local function stopTicker()
    if _ticker then
        _ticker:Cancel()
        _ticker = nil
    end
    _tickCount = 0
end

-- Public stop: called from Core.OnDisable so the ticker doesn't outlive the addon.
function UI_Network:Stop()
    stopTicker()
    self.isOpen = false
end

-- Widget pool for the roster grid
local ROW_H = 20

local function ensureRosterPool(self, needed)
    local pool = self.rosterPool
    local parentContent = self.rowsContainer.content

    for i = 1, #pool do
        if pool[i].frame:GetParent() ~= parentContent then
            pool[i].frame:SetParent(parentContent)
        end
    end

    for i = #pool + 1, needed do
        local f = CreateFrame("Frame", nil, parentContent)
        f:SetHeight(ROW_H)

        local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("LEFT", f, "LEFT", 4, 0)
        nameFS:SetWidth(216)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")

        local ageFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ageFS:SetPoint("LEFT", f, "LEFT", 224, 0)
        ageFS:SetWidth(116)
        ageFS:SetJustifyH("LEFT")
        ageFS:SetJustifyV("MIDDLE")

        local stateFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        stateFS:SetPoint("LEFT", f, "LEFT", 344, 0)
        stateFS:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        stateFS:SetJustifyH("LEFT")
        stateFS:SetJustifyV("MIDDLE")

        pool[i] = {frame = f, name = nameFS, age = ageFS, state = stateFS}
    end

    for i = 1, #pool do
        local row = pool[i]
        row.frame:ClearAllPoints()
        if i <= needed then
            row.frame:SetPoint("TOPLEFT", parentContent, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row.frame:SetPoint("TOPRIGHT", parentContent, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end

    local newH = math_max(needed * ROW_H, 1)
    parentContent:SetHeight(newH)
    self.rowsContainer.frame:SetHeight(newH)
    self.rowsContainer:SetHeight(newH)
    if self.scrollFrame then
        self.scrollFrame:DoLayout()
        self.scrollFrame:FixScroll()
    end
end

-- Tab Builder
function UI_Network:DrawNetworkTab(container)
    local aceGUI = GBCR.Libs.AceGUI
    self.isOpen = true

    container:SetLayout("Fill")

    local scroll = aceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)
    self.scrollFrame = scroll

    scroll:SetCallback("OnRelease", function()
        self.isOpen = false
        stopTicker()
        for _, row in ipairs(self.rosterPool) do
            if row.frame then
                row.frame:Hide()
            end
        end
        self.statusLabel = nil
        self.guildBankGroup = nil
        self.guildBankLabel = nil
        self.rowsContainer = nil
        self.footer = nil
        self.scrollFrame = nil
    end)

    startTicker(self)

    local statusLabel = aceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    statusLabel:SetFontObject(GameFontNormal)
    scroll:AddChild(statusLabel)
    self.statusLabel = statusLabel

    local spacer1 = aceGUI:Create("Label")
    spacer1:SetText(" ")
    scroll:AddChild(spacer1)

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
    scroll:AddChild(guildBankGroup)
    self.guildBankLabel = guildBankLabel

    local spacer2 = aceGUI:Create("Label")
    spacer2:SetText(" ")
    scroll:AddChild(spacer2)

    local gridGroup = aceGUI:Create("InlineGroup")
    gridGroup:SetTitle("Guild bank data status")
    gridGroup:SetFullWidth(true)
    gridGroup:SetLayout("List")
    gridGroup.titletext:ClearAllPoints()
    gridGroup.titletext:SetPoint("TOPLEFT", gridGroup.frame, "TOPLEFT", 0, 0)
    scroll:AddChild(gridGroup)

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
    scroll:AddChild(spacer3)

    local footer = aceGUI:Create("Label")
    footer:SetFullWidth(true)
    scroll:AddChild(footer)
    self.footer = footer

    self:Populate()
end

-- Populate / refresh data into existing widgets
function UI_Network:Populate()
    if not self.isOpen or not self.statusLabel then
        return
    end

    local s = deriveNetworkState()

    local statusKind, statusText = getGlobalStatusText(s)
    local statusColor = ({OK = colorGreen, WARN = colorYellow, INFO = colorBlue, NEUTRAL = colorGray})[statusKind]
    self.statusLabel:SetText(Globals.ColorizeText(statusColor, statusText))

    local kind, text = getGuildBankStatusText(s)
    if text then
        self.guildBankGroup.frame:Show()
        self.guildBankGroup.frame:SetHeight(80)
        self.guildBankGroup:SetHeight(80)
        local color = ({OK = colorGreen, WARN = colorYellow, INFO = colorBlue})[kind]
        self.guildBankLabel:SetText(Globals.ColorizeText(color, text))
    else
        self.guildBankGroup.frame:SetHeight(0)
        self.guildBankGroup:SetHeight(0)
        if self.guildBankGroup.content then
            self.guildBankGroup.content:SetHeight(0)
        end
        self.guildBankGroup.frame:Hide()
        if self.scrollFrame then
            self.scrollFrame:DoLayout()
        end
    end

    local numAlts = #s.rosterAlts
    ensureRosterPool(self, numAlts)
    local pool = self.rosterPool

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
        self.footer:SetText(string_format("Downloading data for %d alt(s)…", activeDl))
    elseif meta.lastReceiveTime then
        local ageText = formatTimeAgo(meta.lastReceiveTime)
        self.footer:SetText(string_format("Last received: %s for %s from %s", Globals.ColorizeText(colorGray, ageText),
                                          meta.lastReceiveAlt or "?", meta.lastReceiveSource or "?"))
    else
        self.footer:SetText("")
    end
end

-- Update only the time-ago labels (called by ticker)
function UI_Network:UpdateDynamicLabels()
    if not self.isOpen or not self.rosterPool then
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

function UI_Network:RefreshIfOpen()
    if self.isOpen then
        self:Populate()
    end
end
