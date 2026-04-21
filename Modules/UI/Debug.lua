local addonName, GBCR = ...

GBCR.UI.Debug = {}
local UI_Debug = GBCR.UI.Debug

local Globals = GBCR.Globals
local string_len = Globals.string_len
local table_concat = Globals.table_concat

local function onClose()
    UI_Debug.isOpen = false

    if UI_Debug.window then
        UI_Debug.window:Hide()
    end
end

local function drawContent(self)
    if not self.window or not self.window:IsVisible() then
        return
    end

    local fullText = table_concat(GBCR.Output.debugMessageBuffer, "\n")

    self.content:SetText(fullText)

    local messageCount = #GBCR.Output.debugMessageBuffer
    self.window:SetStatusText("Select text and press Ctrl + C to copy " .. messageCount .. " messages")

    local editBoxObj = self.content.editBox
    if editBoxObj then
        editBoxObj:SetCursorPosition(string_len(fullText))
    end
end

local function drawWindow(self)
    local aceGUI = GBCR.Libs.AceGUI
    local optionsDB = GBCR.Options:GetOptionsDB()

    local debugOutput = aceGUI:Create("Frame")
    debugOutput:Hide()
    debugOutput:SetCallback("OnClose", onClose)
    debugOutput:SetTitle(GBCR.Core.addonHeader .. " - Debug output")
    debugOutput:SetStatusText("Select text and press Ctrl + C to copy")
    debugOutput:SetLayout("Fill")
    debugOutput:SetStatusTable(optionsDB.profile.framePositions.debug)
    debugOutput.frame:SetClampedToScreen(true)
    self.window = debugOutput

    local debugEditBox = aceGUI:Create("MultiLineEditBox")
    debugEditBox:SetLabel("")
    debugEditBox:DisableButton(true)
    debugEditBox:SetFullWidth(true)
    debugEditBox:SetFullHeight(true)
    debugOutput:AddChild(debugEditBox)
    self.content = debugEditBox
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

    drawContent(self)
end

local function closeWindow(self)
    if not self.isOpen or not self.window then
        return
    end

    onClose()
end

local function toggleWindow(self)
    if self.isOpen then
        closeWindow(self)
    else
        if not GBCR.Options:IsDebugEnabled() then
            GBCR.Output:Response("Debugging is disabled. Enable with %s.",
                                 GBCR.Globals.ColorizeText(GBCR.Constants.COLORS.GOLD, "/bank debug"))

            return
        end

        openWindow(self)
        GBCR.Output:Response(
            "All debug output appears in a dedicated window. Use the %s command to toggle the visibility of that window.",
            GBCR.Globals.ColorizeText(GBCR.Constants.COLORS.GOLD, "/bank debuglog"))
    end
end

local function init(self)
    GBCR.Output.debugMessageBuffer = GBCR.Output.debugMessageBuffer or {}

    drawWindow(self)
end

-- Export functions for other modules
UI_Debug.DrawContent = drawContent
UI_Debug.Open = openWindow
UI_Debug.Close = closeWindow
UI_Debug.Toggle = toggleWindow
UI_Debug.Init = init
