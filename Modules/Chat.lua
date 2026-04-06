local addonName, GBCR = ...

GBCR.Chat = {}
local Chat = GBCR.Chat

local Globals = GBCR.Globals
local ipairs = Globals.ipairs
local math_floor = Globals.math_floor
local pairs = Globals.pairs
local select = Globals.select
local string_format = Globals.string_format
local table_sort = Globals.table_sort
local time = Globals.time
local tonumber = Globals.tonumber

local GetClassColor = Globals.GetClassColor

local Constants = GBCR.Constants
local colorGold = Constants.COLORS.GOLD
local colorGreen = Constants.COLORS.GREEN
local commandHandlers = Constants.COMMAND_HANDLERS
local commandRegistry = Constants.COMMAND_REGISTRY
local helpInstructions = Constants.HELP_INSTRUCTIONS

-- Print all tracked addon versions from other guild members in respone to /bank versions
local function printVersions(self)
	local now = time()
	local myPlayer = GBCR.Guild:GetNormalizedPlayer()
	local versions = {}
	local position = 1

	versions[position] = { playerName = myPlayer, addonVersionNumber = GBCR.Core.addonVersionNumber, seen = time(), isSelf = true }
	position = position + 1

	for playerName, info in pairs(GBCR.Protocol.guildMembersFingerprintData) do
		versions[position] = { playerName = playerName, addonVersionNumber = tonumber(info.addonVersionNumber), seen = info.seen, isSelf = false }
		position = position + 1
	end

	table_sort(versions, function(a, b)
		if (a and a.addonVersionNumber and b and b.addonVersionNumber) and (a.addonVersionNumber ~= b.addonVersionNumber) then
			return a.addonVersionNumber > b.addonVersionNumber
		end

		return a.playerName < b.playerName
	end)

	GBCR.Output:Response("Addon versions (%d members):", #versions)

	for _, entry in ipairs(versions) do
		local age = ""

		if not entry.isSelf then
			local seconds = now - entry.seen

			if seconds < 60 then
				age = " (just now)"
			elseif seconds < 3600 then
				age = string_format(" (%dm ago)", math_floor(seconds / 60))
			else
				age = string_format(" (%dh ago)", math_floor(seconds / 3600))
			end
		end

		GBCR.Output:Response("  %s: %s%s%s", Globals:Colorize(select(4, GetClassColor(GBCR.Guild:GetGuildMemberInfo(entry.playerName))), entry.playerName), entry.addonVersionNumber, entry.isSelf and Globals:Colorize(colorGold, " (you)") or "", age)
	end
end

-- Print all help commands in response to /bank help
local function showHelp(self)
	GBCR.Output:Response("\n", Globals:Colorize(colorGreen, "Commands:"))
	GBCR.Output:Response("%s - display the %s UI", GBCR.Core.addonTitle, Globals:Colorize(colorGold, "/bank"))
	for _, cmd in ipairs(commandRegistry) do
		if cmd.help and not cmd.expert then
			local usage = cmd.usage and (" " .. cmd.usage) or ""
			GBCR.Output:Response("%s - %s", Globals:Colorize(colorGold, "/bank " .. cmd.name .. usage), cmd.help)
		end
	end

	GBCR.Output:Response("\n", Globals:Colorize(colorGreen, "Expert commands:"))
	for _, cmd in ipairs(commandRegistry) do
		if cmd.help and cmd.expert then
			local usage = cmd.usage and (" " .. cmd.usage) or ""
			GBCR.Output:Response("%s - %s", Globals:Colorize(colorGold, "/bank " .. cmd.name .. usage), cmd.help)
		end
	end

	for _, instruction in ipairs(helpInstructions) do
		GBCR.Output:Response("\n%s", Globals:Colorize(colorGreen, instruction.title))
		GBCR.Output:Response(instruction.text)
	end
end

-- Helper to execute chat commands (toggles the UI if no other arguments are provided)
local function chatCommand(self, input)
	if input == nil or input == "" then
		GBCR.UI.Inventory:Toggle()
	else
		local prefix, arg1 = GBCR.Addon:GetArgs(input, 2)
		local handler = commandHandlers[prefix]

		if handler then
			handler(arg1)
		else
			GBCR.Output:Response("Unknown command: %s.", Globals:Colorize(colorGold, prefix))
			showHelp(self)
		end
	end

	return false
end

-- Register /bank as the chat command for this addon
local function init(self)
    GBCR.Addon:RegisterChatCommand("bank", function(input)
        return chatCommand(self, input)
    end)
end

-- Export functions for other modules
Chat.PrintVersions = printVersions
Chat.ShowHelp = showHelp
Chat.Init = init