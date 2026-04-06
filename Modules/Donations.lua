local addonName, GBCR = ...

GBCR.Donations = {}
local Donations = GBCR.Donations

local Globals = GBCR.Globals
local pairs = Globals.pairs
local select = Globals.select
local string_format = Globals.string_format
local string_match = Globals.string_match
local table_remove = Globals.table_remove
local table_sort = Globals.table_sort
local tonumber = Globals.tonumber
local wipe = Globals.wipe

local CheckInbox = Globals.CheckInbox
local After = Globals.After
local GetInboxHeaderInfo = Globals.GetInboxHeaderInfo
local GetInboxItemLink = Globals.GetInboxItemLink
local GetInboxItem = Globals.GetInboxItem
local GetItemInfo = Globals.GetItemInfo
local GetMoney = Globals.GetMoney
local GetCoinTextureString = Globals.GetCoinTextureString
local attachementsMaxReceive = Globals.ATTACHMENTS_MAX_RECEIVE

local Constants = GBCR.Constants
local patternLootMultiple = Constants.PATTERN_LOOT_MULTIPLE
local patternLootPushedMultiple = Constants.PATTERN_LOOT_PUSHED_MULTIPLE
local patternLootPushedSingle = Constants.PATTERN_LOOT_PUSHED_SINGLE
local patternLootSingle = Constants.PATTERN_LOOT_SINGLE

local Output = GBCR.Output

-- Build a cache of donation data after a quiet period after the last triggering event (trailing debouce, stays quiet until activity is done)
local function buildDonationCache(self)
    Output:Debug("DONATIONS", "buildDonationCache called")

	if GBCR.UI.Donations.donationTimer then
        GBCR.UI.Donations.donationTimer:Cancel()
    end

    GBCR.UI.Donations.donationTimer = After(Constants.TIMER_INTERVALS.BUILD_DONATION_CACHE, function()
		Output:Debug("DONATIONS", "Executing throttled buildDonationCache")

		local savedVariables = GBCR.Database.savedVariables
		local rosterGuildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
		if not savedVariables or not rosterGuildBankAlts then
			Output:Debug("DONATIONS", "buildDonationCache: early exit due to missing data")

			return
		end

		local players = {}
		local alts = savedVariables.alts

		for i = 1, #rosterGuildBankAlts do
			local guildBankAltName = rosterGuildBankAlts[i]
			local alt = alts[guildBankAltName]

			if alt and alt.ledger then
				for donatedBy, donationValue in pairs(alt.ledger) do
					players[donatedBy] = (players[donatedBy] or 0) + donationValue
				end
			end
		end

        GBCR.UI.Donations.cachedDonations = GBCR.UI.Donations.cachedDonations or {}
        local cache = GBCR.UI.Donations.cachedDonations
        wipe(cache)

        local idx = 1
        for donatedBy, donationValue in pairs(players) do
            cache[idx] = { donatedBy = donatedBy, donationValue = donationValue }
            idx = idx + 1
        end

        table_sort(cache, function(a, b)
            return a.donationValue > b.donationValue
        end)

        GBCR.UI.Donations.needsDonationRebuild = false
        GBCR.UI.Donations.donationTimer = nil

        if GBCR.UI.Donations.isOpen then
            GBCR.UI.Donations:DrawContent()
        end
    end)
end

-- Helper to update the donation ledger
local function recordDonationInLedger(self, sender, itemLink, quantity, money, isMoney)
    if not sender then
        return
    end

    local rosterGuildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
    local senderNorm = GBCR.Guild:NormalizeName(sender) or sender
    local isSenderGuildMember = GBCR.Guild:GetGuildMemberInfo(senderNorm) and true or false

    if rosterGuildBankAlts and rosterGuildBankAlts[senderNorm] and isSenderGuildMember then
        Output:Debug("DONATIONS", "Only items and money sent by non-guild bank alts that are guild members are consider a donation")

        return
    end

    local playerNorm = GBCR.Guild:GetNormalizedPlayer()
    local info = GBCR.Database.savedVariables
    if not info or not info.alts or not info.alts[playerNorm] then
        return
    end

    info.alts[playerNorm].ledger = info.alts[playerNorm].ledger or {}
    local ledger = info.alts[playerNorm].ledger

    if isMoney then
        Output:Debug("DONATIONS", "Proceeding to record money donation in ledger of %s by %s to the donation ledger", GetCoinTextureString(money), senderNorm)

        if money and money > 0 then
            if GBCR.Options:GetDonationReportingEnabled() then
                Output:Info("Donation of %s received from %s.", GetCoinTextureString(money), senderNorm)
            end

            ledger[senderNorm] = (ledger[senderNorm] or 0) + (money / 10000)
            buildDonationCache()
        end
    else
        Output:Debug("DONATIONS", "Proceeding to record item donation in ledger of %sx %s by %s to the donation ledger", quantity, itemLink, senderNorm)

        if itemLink and quantity then
            local name, _, _, level, _, _, _, _, _, _, price = GetItemInfo(itemLink)

            if name and level then
                local effectivePrice = (price and price > 0) and price or 1

                if GBCR.Options:GetDonationReportingEnabled() then
                    Output:Info("Donation of %s x%d received from %s (vendor value recorded as %s).", itemLink, quantity, senderNorm, GetCoinTextureString((effectivePrice * quantity)))
                end

                ledger[senderNorm] = (ledger[senderNorm] or 0) + ((effectivePrice * quantity) / 10000)
                buildDonationCache()
            end
        end
    end
end

-- Helper to extract informatiom from a mail
local function processMail(self, mailId, attachmentIndex)
    local _, _, sender, subject, moneyString, _, daysLeft, itemCount, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(mailId)
    local money = tonumber(moneyString) or 0
    local key, itemLink, itemId, quantity

    if not sender or wasReturned or isGM then
        Output:Debug("DONATIONS", "Processing aborted: invalid mail state")

        return
    end

    local subjectPatterns = GBCR.Constants.AH_MAIL_SUBJECT_PATTERNS

    if subject then
        for mailType, pattern in pairs(subjectPatterns) do
            if string_match(subject, pattern) then
                Output:Debug("DONATIONS", "Processing aborted: ignoring Auction House mail (type=%s)", mailType)

                return
            end
        end
	end

        Output:Debug("DONATIONS", "Processing aborted: sender %s is not in our guild", sender)

    if attachmentIndex then
        itemLink = GetInboxItemLink(mailId, attachmentIndex)
        if itemLink then
            itemId = string_match(itemLink, "item:(%d+)")
            quantity = select(4, GetInboxItem(mailId, attachmentIndex)) or 1

            if not (itemLink and itemId) or quantity <= 0 then
                Output:Debug("DONATIONS", "Processing aborted: invalid item")

                return
            end

            -- Create a truly unique key for this mail attachment
            -- The daysLeft field is the "secret sauce" (it's a float that is unique to that mail)
            key = string_format("%s-%.12f-%d-%d-%d-%d", sender, daysLeft or 0, attachmentIndex, quantity)

            -- Check if we have already scored this specific mail attachment
            if self.donationItemRegistry[key] then
                Output:Debug("DONATIONS", "Prevented duplicate scoring for key = %s due to mail shifting", key)

                return
            end

            -- Proceed and mark the key as recorded
            self.donationItemRegistry[key] = true

            Output:Debug("DONATIONS", "Updated donationItemRegistry key = %s", key)
        end
    end

    return sender, key, money, itemLink, itemId, quantity, itemCount
end

-- When you manually click on a single mail attachment
-- When you click "Open All" from the inbox
local function processItemDonation(self, mailId, attachmentIndex)
    local sender, key, _, itemLink, itemId, itemCount = processMail(self, mailId, attachmentIndex)

    if sender and key and itemLink and itemId and itemCount then
        Output:Debug("DONATIONS", "Updating itemDonationVerificationQueue for sender = %s, itemLink = %s, itemCount = %s, key = %s", sender, itemLink, itemCount, key)

        self.itemDonationVerificationQueue[#self.itemDonationVerificationQueue + 1] = { sender = sender, itemLink = itemLink, itemCount = itemCount, itemId = itemId }
    end
end

-- Any time money is taken from mails
local function processMoneyDonation(self, mailId)
    local sender, _, money = processMail(self, mailId)

    if sender and money then
        Output:Debug("DONATIONS", "Updating isGoldDonationPending for sender = %s, amount = %s", sender, money)

        self.isGoldDonationPending = { sender = sender, amount = money }
        self.goldBalanceBeforeDonation = GetMoney()
    end
end

-- When you shift-click a mail from the inbox
local function processDonation(self, mailId)
    Output:Debug("DONATIONS", "Processing donated mail for mailId %s", mailId)

    local sender, _, money, _, _, _, itemCount = processMail(self, mailId)

    if sender and money then
        processMoneyDonation(self, mailId)
    end

    if sender and itemCount and itemCount > 0 then
        for attachmentIndex = 1, attachementsMaxReceive do
            processItemDonation(self, mailId, attachmentIndex)
        end
    end
end

-- When the CHAT_MSG_LOOT event is fired
local function processPossibleItemDonation(self, message)
    local queue = self.itemDonationVerificationQueue
    if not queue or #queue == 0 then
        return
    end

	Output:Debug("DONATIONS", "Processing possible item donation for message = %s", message)

    local itemLink, amountString = string_match(message, patternLootMultiple)

    if not itemLink then
        itemLink = string_match(message, patternLootSingle)
        if not itemLink then
            itemLink, amountString = string_match(message, patternLootPushedMultiple)
            if not itemLink then
                itemLink = string_match(message, patternLootPushedSingle)
            end
        end
    end

    local itemId = string_match(message, "|Hitem:(%d+):")
    local amount = tonumber(amountString) or 1

    itemId = tonumber(itemId)

    if itemId and itemLink and string_match(itemLink, "|Hitem:") then
        Output:Debug("DONATIONS", "Donation identified of %sx %s (itemId=%s)", amount, itemLink, itemId)
    else
        Output:Debug("DONATIONS", "ERROR: Failed to parse donation item from message: %s", message)
    end

    -- Server sends loot messages in same order items are looted (queue is FIFO)
    for i = 1, #queue do
        local pending = queue[i]
        local idMatch = pending.itemId and itemId and tonumber(pending.itemId) == itemId
		local linkMatch = pending.itemLink == itemLink

        if pending.sender and (idMatch or linkMatch) and pending.itemCount == amount then
            Output:Debug("DONATIONS", "Committing a donation of %sx %s by %s to the donation ledger", pending.itemCount, pending.itemLink, pending.sender)

            recordDonationInLedger(self, pending.sender, pending.itemLink, pending.itemCount, nil, false)
            table_remove(queue, i)

            return
        end
    end

    Output:Debug("DONATIONS", "ERROR: No match identified in the itemDonationVerificationQueue queue for message")
end

-- When the PLAYER_MONEY event is fired
local function processPossibleMoneyDonation(self)
    if not self.isGoldDonationPending or not self.goldBalanceBeforeDonation then
        return
    end

    local currentMoney = GetMoney()
    if currentMoney > self.goldBalanceBeforeDonation then
        Output:Debug("DONATIONS", "Committing a donation of %s by %s to the donation ledger", self.isGoldDonationPending.amount, self.isGoldDonationPending.sender)

        recordDonationInLedger(self, self.isGoldDonationPending.sender, nil, nil, self.isGoldDonationPending.amount, true)
        self.isGoldDonationPending = nil
        self.goldBalanceBeforeDonation = nil
    else
        Output:Debug("DONATIONS", "Processing of money donation failed (currentMoney = %s, delta = %s, goldBalanceBeforeDonation = %s, check = %s)", currentMoney, currentMoney - self.goldBalanceBeforeDonation, self.goldBalanceBeforeDonation, currentMoney > self.goldBalanceBeforeDonation)
    end
end

-- Calls a game API that populates client's inbox with messages so that mailbox information can be accessed from anywhere in the world
local function checkInbox(self)
    CheckInbox()
end

-- Initialie state tracking
local function init(self)
    self.donationItemRegistry = {}
    self.itemDonationVerificationQueue = {}
    self.isGoldDonationPending = nil
    self.goldBalanceBeforeDonation = nil
end

-- Export functions for other modules
Donations.BuildDonationCache = buildDonationCache
Donations.ProcessItemDonation = processItemDonation
Donations.ProcessMoneyDonation = processMoneyDonation
Donations.ProcessDonation = processDonation
Donations.ProcessPossibleItemDonation = processPossibleItemDonation
Donations.ProcessPossibleMoneyDonation = processPossibleMoneyDonation
Donations.Check = checkInbox
Donations.Init = init