GBankClassic_Mail = GBankClassic_Mail or {}

local Mail = GBankClassic_Mail

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("CheckInbox", "GetInboxHeaderInfo", "GetInboxItemLink", "GetInboxItem", "GetItemInfo", "GetMoney", "GetCoinTextureString")
local CheckInbox = upvalues.CheckInbox
local GetInboxHeaderInfo = upvalues.GetInboxHeaderInfo
local GetInboxItemLink = upvalues.GetInboxItemLink
local GetInboxItem = upvalues.GetInboxItem
local GetItemInfo = upvalues.GetItemInfo
local GetMoney = upvalues.GetMoney
local GetCoinTextureString = upvalues.GetCoinTextureString
local upvalues = Globals.GetUpvalues("ATTACHMENTS_MAX_RECEIVE", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF")
local ATTACHMENTS_MAX_RECEIVE = upvalues.ATTACHMENTS_MAX_RECEIVE
local LOOT_ITEM_SELF_MULTIPLE = upvalues.LOOT_ITEM_SELF_MULTIPLE
local LOOT_ITEM_SELF = upvalues.LOOT_ITEM_SELF
local LOOT_ITEM_PUSHED_SELF_MULTIPLE = upvalues.LOOT_ITEM_PUSHED_SELF_MULTIPLE
local LOOT_ITEM_PUSHED_SELF = upvalues.LOOT_ITEM_PUSHED_SELF

Mail.donationItemRegistry = {}
Mail.itemDonationVerificationQueue = {}
Mail.isGoldDonationPending = nil
Mail.goldBalanceBeforeDonation = nil

local subjectPatterns = {
	AHCancelled = gsub(AUCTION_REMOVED_MAIL_SUBJECT, "%%s", ".*"),
	AHExpired = gsub(AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", ".*"),
	AHOutbid = gsub(AUCTION_OUTBID_MAIL_SUBJECT, "%%s", ".*"),
	AHSuccess = gsub(AUCTION_SOLD_MAIL_SUBJECT, "%%s", ".*"),
	AHWon = gsub(AUCTION_WON_MAIL_SUBJECT, "%%s", ".*")
}

function Mail:Check()
    CheckInbox()
end

-- Helper to update the donation ledger
function Mail:RecordDonationInLedger(sender, itemLink, quantity, money, isMoney)
    if not sender then
        return
    end

    local senderNorm = GBankClassic_Guild:NormalizeName(sender) or sender
    if self.Roster and self.Roster[senderNorm] then
        GBankClassic_Output:Debug("DONATION", "Only items and money sent by non-guild bank alts are consider a donation")

        return
    end

    local playerNorm = GBankClassic_Guild:GetNormalizedPlayer()
    local info = GBankClassic_Guild.Info
    if not info or not info.alts or not info.alts[playerNorm] then
        return
    end

    if not info.alts[playerNorm].ledger then
        info.alts[playerNorm].ledger = {}
    end
    local ledger = info.alts[playerNorm].ledger

    if isMoney then
        GBankClassic_Output:Debug("DONATION", "Proceeding to record money donation in ledger of %s by %s to the donation ledger", GetCoinTextureString(money), senderNorm)
        if money and money > 0 then
            local score = money / 10000
            if GBankClassic_Options:GetBankReporting() then
                GBankClassic_Output:Info("Donation of %s received from %s.", GetCoinTextureString(money), senderNorm)
            end
            ledger[senderNorm] = (ledger[senderNorm] or 0) + score
        end
    else
        GBankClassic_Output:Debug("DONATION", "Proceeding to record item donation in ledger of %sx %s by %s to the donation ledger", quantity, itemLink, senderNorm)
        if itemLink and quantity then
            local name, _, _, level, _, _, _, _, _, _, price = GetItemInfo(itemLink)
            if name and level and not GBankClassic_Item:IsUnique(itemLink) then
                local effectivePrice = (price and price > 0) and price or 1
                local score = (effectivePrice * quantity) / 10000
                if GBankClassic_Options:GetBankReporting() then
                    GBankClassic_Output:Info("Donation of %s x%d received from %s (vendor value recorded as %s).", itemLink, quantity, senderNorm, GetCoinTextureString((effectivePrice * quantity)))
                end
                ledger[senderNorm] = (ledger[senderNorm] or 0) + score
            end
        end
    end
end

-- Helper to determine if the mail is from the Auction House (cancelled, expired, outbid, success, won)
local function getMailType(msgSubject)
	if msgSubject then
		for k, v in pairs(subjectPatterns) do
			if msgSubject:find(v) then
				return k
			end
		end
	end

	return "NotAH"
end

-- Helper to extract informatiom from a mail
function Mail:ProcessMail(mailId, attachmentIndex)
    local _, _, sender, subject, moneyString, _, daysLeft, itemCount, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(mailId)
    local money = tonumber(moneyString) or 0

    if not sender or wasReturned or isGM then
        GBankClassic_Output:Debug("DONATION", "Processing aborted: invalid mail state")

        return
    end

	local mailType = getMailType(subject)
	if mailType ~= "NotAH" then
        GBankClassic_Output:Debug("DONATION", "Processing aborted: ignoring Auction House mail (type=%s)", mailType)

		return
	end

	if not GBankClassic_Guild.guildMembersCache[sender] then
        GBankClassic_Output:Debug("DONATION", "Processing aborted: sender %s is not in our guild (%d members)", sender, GBankClassic_Globals:Count(GBankClassic_Guild.guildMembersCache))

		return
	end

    local key, itemLink, itemID, quantity
    if attachmentIndex then
        itemLink = GetInboxItemLink(mailId, attachmentIndex)
        if itemLink then
            itemID = itemLink:match("item:(%d+)")
            quantity = select(4, GetInboxItem(mailId, attachmentIndex)) or 1

            if not (itemLink and itemID) or quantity <= 0 then 
                GBankClassic_Output:Debug("DONATION", "Processing aborted: invalid item")

                return
            end

            -- Create a truly unique key for this mail attachment
            -- The daysLeft field is the "secret sauce" (it's a float that is unique to that mail)
            key = string.format("%s-%.12f-%d-%d-%d-%d", sender, daysLeft or 0, attachmentIndex, quantity)

            -- Check if we have already scored this specific mail attachment
            if self.donationItemRegistry[key] then
                GBankClassic_Output:Debug("DONATION", "Prevented duplicate scoring for key = %s due to mail shifting", key)

                return
            end

            -- Proceed and mark the key as recorded
            GBankClassic_Output:Debug("DONATION", "Updating donationItemRegistry key = %s", key)
            self.donationItemRegistry[key] = true
        end
    end

    return sender, key, money, itemLink, itemID, quantity, itemCount
end

-- When you shift-click a mail from the inbox
function Mail:ProcessDonation(mailId)
    GBankClassic_Output:Debug("DONATION", "Processing donated mail for mailId %s", mailId)

    local sender, _, money, _, _, _, itemCount = self:ProcessMail(mailId)

    -- Handle money
    if sender and money then
        self:ProcessMoneyDonation(mailId)
    end

    -- Handle items
    if sender and itemCount and itemCount > 0 then
        for attachmentIndex = 1, ATTACHMENTS_MAX_RECEIVE do
            self:ProcessItemDonation(mailId, attachmentIndex)
        end
    end
end

-- When you manually click on a single mail attachment
-- When you click "Open All" from the inbox
function Mail:ProcessItemDonation(mailId, attachmentIndex)
    local sender, key, _, itemLink, itemID, quantity = self:ProcessMail(mailId, attachmentIndex)
    if sender and key and itemLink and itemID and quantity then
        GBankClassic_Output:Debug("DONATION", "Updating itemDonationVerificationQueue for sender = %s, item = %s, quantity = %s, key = %s", sender, itemLink, quantity, key)
        table.insert(self.itemDonationVerificationQueue, { sender = sender, link = itemLink, qty = quantity, itemID = itemID })
    end
end

-- Any time money is taken from mails
function Mail:ProcessMoneyDonation(mailId)
    local sender, _, money = Mail:ProcessMail(mailId)
    if sender and money then
        GBankClassic_Output:Debug("DONATION", "Updating isGoldDonationPending for sender = %s, amount = %s", sender, money)
        self.isGoldDonationPending = { sender = sender, amount = money }
        self.goldBalanceBeforeDonation = GetMoney()
    end
end

-- When the CHAT_MSG_LOOT event is fired
function Mail:ProcessPossibleItemDonation(message)
    local queue = self.itemDonationVerificationQueue
    if not queue or #queue == 0 then
        return
    end

	GBankClassic_Output:Debug("DONATION", "Processing possible item donation for message = %s", message)

    -- Extract item ID in case we run into item link formatting differences
    local itemID = tonumber(message:match("|Hitem:(%d+):"))
	-- "You receive loot: [Item]x2"
	local itemLink, amountString = strmatch(message, string.gsub(string.gsub(LOOT_ITEM_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)"));
	if not itemLink then
 		-- "You receive loot: [Item]"
    	itemLink = message:match(LOOT_ITEM_SELF:gsub("%%s", "(.+)"));
		if not itemLink then
			-- "You receive item: [Item]x2"
			itemLink, amountString = strmatch(message, string.gsub(string.gsub(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)"));
			if not itemLink then
	 			-- "You receive item: [Item]"
				itemLink = message:match(LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"));
			end
    	end
    end
	local amount = tonumber(amountString) or 1

    if itemID and itemLink and itemLink:find("|Hitem:") then
	    GBankClassic_Output:Debug("DONATION", "Donation identified of %sx %s (ID %s)", amount, itemLink, itemID)
    else
        GBankClassic_Output:Debug("DONATION", "ERROR: Failed to parse donation item from message: %s", message)
    end

    -- Server sends loot messages in same order items are looted
    -- Queue is FIFO: first matching entry is the correct one to remove
    for i = 1, #queue do
        local pending = queue[i]
		local idMatch = pending.itemID and itemID and pending.itemID == itemID
		local linkMatch = pending.link == itemLink
        if pending.sender and (idMatch or linkMatch) and pending.qty == amount then
            GBankClassic_Output:Debug("DONATION", "Committing a donation of %sx %s by %s to the donation ledger", pending.qty, pending.link, pending.sender)
            self:RecordDonationInLedger(pending.sender, pending.link, pending.qty, nil, false)
            table.remove(queue, i)

            return
        end
    end

    GBankClassic_Output:Debug("DONATION", "ERROR: No match identified in the itemDonationVerificationQueue queue for message")
end

-- When the PLAYER_MONEY event is fired
function Mail:ProcessPossibleMoneyDonation()
    if not self.isGoldDonationPending or not self.goldBalanceBeforeDonation then

        return
    end

    local currentMoney = GetMoney()
    local delta = currentMoney - self.goldBalanceBeforeDonation
    if currentMoney > self.goldBalanceBeforeDonation then
        GBankClassic_Output:Debug("DONATION", "Committing a donation of %s by %s to the donation ledger", self.isGoldDonationPending.amount, self.isGoldDonationPending.sender)
        self:RecordDonationInLedger(self.isGoldDonationPending.sender, nil, nil, self.isGoldDonationPending.amount, true)
        self.isGoldDonationPending = nil
        self.goldBalanceBeforeDonation = nil
    else
        GBankClassic_Output:Debug("DONATION", "Processing of money donation failed (currentMoney = %s, delta = %s, goldBalanceBeforeDonation = %s, check = %s)", currentMoney, delta, self.goldBalanceBeforeDonation, currentMoney > self.goldBalanceBeforeDonation)
    end
end