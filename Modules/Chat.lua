local addonName, GBCR = ...

GBCR.Chat = {}
local Chat = GBCR.Chat

local Globals = GBCR.Globals
local time = Globals.time
local UIParent = Globals.UIParent
local GetClassColor = Globals.GetClassColor

local Constants = GBCR.Constants
local colorGreen = Constants.COLORS.GREEN
local colorGold = Constants.COLORS.GOLD
local commandRegistry = Constants.COMMAND_REGISTRY
local commandHandlers = Constants.COMMAND_HANDLERS
local helpInstructions = Constants.HELP_INSTRUCTIONS

function Chat:Init()
    GBCR.Addon:RegisterChatCommand("bank", function(input)
        return self:ChatCommand(input)
    end)
end

function Chat:ChatCommand(input)
	if input == nil or input == "" then
		GBCR.UI.Inventory:Toggle()
	else
		local prefix, arg1 = GBCR.Addon:GetArgs(input, 2)
		local handler = commandHandlers[prefix]
		if handler then
			handler(arg1)
		else
			GBCR.Output:Response("Unknown command: %s.", prefix)
			self:ShowHelp()
		end
	end

	return false
end

function Chat:ShowHelp()
	GBCR.Output:Response("\n", GBCR.Globals:Colorize(colorGreen, "Commands:"))
	GBCR.Output:Response("%s - display the GBankClassic - Revived interface", GBCR.Globals:Colorize(colorGold, "/bank"))
	for _, cmd in ipairs(commandRegistry) do
		if cmd.help and not cmd.expert then
			local usage = cmd.usage and (" " .. cmd.usage) or ""
			GBCR.Output:Response("%s - %s", GBCR.Globals:Colorize(colorGold, "/bank " .. cmd.name .. usage), cmd.help)
		end
	end

	GBCR.Output:Response("\n", GBCR.Globals:Colorize(colorGreen, "Expert commands:"))
	for _, cmd in ipairs(commandRegistry) do
		if cmd.help and cmd.expert then
			local usage = cmd.usage and (" " .. cmd.usage) or ""
			GBCR.Output:Response("%s - %s", GBCR.Globals:Colorize(colorGold, "/bank " .. cmd.name .. usage), cmd.help)
		end
	end

	for _, instruction in ipairs(helpInstructions) do
		GBCR.Output:Response("\n%s", GBCR.Globals:Colorize(colorGreen, instruction.title))
		GBCR.Output:Response(instruction.text)
	end
end

function Chat:PrintVersions()
	local myPlayer = GBCR.Guild:GetNormalizedPlayer()
	local versions = {}

	-- Add ourselves
	table.insert(versions, { playerName = myPlayer, addonVersionNumber = GBCR.Core.addonVersionNumber, seen = time(), isSelf = true })

	-- Add tracked guild members
	for playerName, info in pairs(GBCR.Protocol.guildMembersFingerprintData) do
		table.insert(versions, { playerName = playerName, addonVersionNumber = tonumber(info.addonVersionNumber), seen = info.seen, isSelf = false })
	end

	-- Sort by version (descending), then by name
	table.sort(versions, function(a, b)
		if (a and a.addonVersionNumber and b and b.addonVersionNumber) and (a.addonVersionNumber ~= b.addonVersionNumber) then
			return a.addonVersionNumber > b.addonVersionNumber
		end

		return a.playerName < b.playerName
	end)

	local count = #versions
	GBCR.Output:Response("Addon versions (%d members):", count)

	local now = time()
	for _, entry in ipairs(versions) do
		local age = ""
		if not entry.isSelf then
			local seconds = now - entry.seen
			if seconds < 60 then
				age = " (just now)"
			elseif seconds < 3600 then
				age = string.format(" (%dm ago)", math.floor(seconds / 60))
			else
				age = string.format(" (%dh ago)", math.floor(seconds / 3600))
			end
		end
		local marker = entry.isSelf and GBCR.Globals:Colorize(colorGold, " (you)") or ""
		local playerClass = GBCR.Guild:GetGuildMemberInfo(entry.playerName)
		local classColor = select(4, GetClassColor(playerClass))
		GBCR.Output:Response("  %s: %s%s%s", GBCR.Globals:Colorize(classColor, entry.playerName), entry.addonVersionNumber, marker, age)
	end
end

function Chat:RestoreUI()
	local optionsDB = GBCR.Options:GetOptionsDB()
	if not optionsDB then
		return
	end

	local count = Globals:Count(optionsDB.char.framePositions)
	if count > 0 then
		optionsDB.char.framePositions = nil
	end

	local frame = GBCR.UI.Inventory.Window.frame
    local defaults = optionsDB.defaults.char.framePositions
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0 ,0)
    if defaults then
        frame:SetSize(defaults.width, defaults.height)
    end

	if GBCR.UI.Inventory.isOpen then
		GBCR.UI.Inventory:Close()
		GBCR.UI.Inventory:Toggle()
	else
		GBCR.UI.Inventory:Open()
	end

	GBCR.Output:Response("The user interface window size and position have been reset to their defaults.")
end