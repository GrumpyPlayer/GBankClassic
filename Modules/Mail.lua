GBankClassic_Mail = GBankClassic_Mail or {
	-- -- State for split operation
	-- splitState = nil -- {bag, slot, amount, attachmentSlot, request}
}

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

--[[
-- Initialize split stack popup dialog
if not StaticPopupDialogs["GBANK_SPLIT_STACK"] then
	StaticPopupDialogs["GBANK_SPLIT_STACK"] = {
		text = "%s",
		button1 = "Split",
		button2 = "Cancel",
		OnAccept = function(self, data)
			if not data then
             return
         end

			ClearCursor()
			-- Find an empty bag slot to place the split items
			local emptyBag, emptySlot
			for bag = 0, 4 do
				local numSlots = GetContainerNumSlots(bag)
				for slot = 1, numSlots do
					if not GetContainerItemInfo(bag, slot) then
						emptyBag, emptySlot = bag, slot
						break
					end
				end
				if emptyBag then
                 break
             end
			end
			if not emptyBag then
				return
			end

			-- Step 1: Split - puts amount on cursor
			SplitContainerItem(data.bag, data.slot, data.amount)
			After(0.1, function()
				-- Step 2: Place split items into empty slot to "commit" the split
				PickupContainerItem(emptyBag, emptySlot)
				After(0.05, function()
					-- Done! The split stack is now in inventory
					if GBankClassic_UI_Requests and GBankClassic_UI_Requests.Window then
						local message = string.format("Split %d %s complete. Click fulfill again to attach items",
							data.amount, data.itemName)
						GBankClassic_UI_Requests.Window:SetStatusText(message)
						-- Refresh the request list to update the fulfill button icon
						GBankClassic_UI_Requests:DrawContent()
					end
				end)
			end)
		end,
		OnCancel = function()
			-- Nothing to clean up
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

function Mail:IsMailboxOpen()
	local frameOpen = MailFrame and MailFrame:IsShown() or false
	if self.isOpen ~= frameOpen then
		self.isOpen = frameOpen
	end

	return frameOpen
end
]]--

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

--[[
-- Check if received item matches an active request from current player
function Mail:CheckForFulfilledRequest(itemName, quantity, sender)
       local info = GBankClassic_Guild.Info
       if not info or not info.requests then
               return false
       end

       local currentPlayer = GBankClassic_Guild:GetNormalizedPlayer()
       local normSender = GBankClassic_Guild:NormalizeName(sender)
       local normItemName = string.lower(itemName)

       -- Check if sender is a bank alt
       local banks = GBankClassic_Guild:GetBanks()
       local isBankAlt = false
       if banks then
               for _, bank in pairs(banks) do
                       if GBankClassic_Guild:NormalizeName(bank) == normSender then
                               isBankAlt = true
                               break
                       end
               end
       end

       if not isBankAlt then
               return false
       end

       -- Look for matching active request from current player
       for _, req in pairs(info.requests) do
               if req.requester == currentPlayer and 
                  string.lower(req.item or "") == normItemName and
                  req.status ~= "complete" and 
                  req.status ~= "cancelled" then
                       local fulfilled = tonumber(req.fulfilled or 0)
                       local requested = tonumber(req.quantity or 0)
                       if fulfilled < requested then
                               return true, req
                       end
               end
       end

       return false
end

function Mail:Scan()
	if not GBankClassic_Options:GetDonationEnabled() then
		return
	end

	if not Mail.isOpen then
		return
	end
	if self.isScanning then
		return
	end

	local info = GBankClassic_Guild.Info
	if not info then
		return
	end

	local player = GBankClassic_Guild:GetNormalizedPlayer()

	local isBank = false
	local banks = GBankClassic_Guild:GetBanks()
	if banks == nil then
		return
	end
	self.Roster = self.Roster or {}
	for _, v in pairs(banks) do
		local norm = GBankClassic_Guild:NormalizeName(v)
		if self.Roster and norm then
			self.Roster[norm] = true
		end
		if norm == player then
			isBank = true
		end
	end
	if not isBank then
		return
	end
	if not GBankClassic_Options:GetBankEnabled() then
		return
	end

	self.isScanning = true

	local numItems, totalItems = GetInboxNumItems()

	if numItems > 0 then
		for mailId = 1, numItems do
			local _, _, sender, _, money, CODAmount, _, itemCount, _, wasReturned, _, canReply, isGM =
				GetInboxHeaderInfo(mailId)
			if not sender then
				Mail:ResetScan()
				return
			end

			if
				CODAmount == 0
				and not wasReturned
				and not isGM
				and canReply
				and not self.Roster[sender]
				and (money > 0 or (itemCount and itemCount > 0))
			then
				local hasNonUnique = nil
				if itemCount and itemCount > 0 then
					for attachmentIndex = 1, ATTACHMENTS_MAX_RECEIVE do
						local link = GetInboxItemLink(mailId, attachmentIndex)
						if link then
							local isUnique = GBankClassic_Item:IsUnique(link)
							if not isUnique then
								hasNonUnique = true
								break
							elseif hasNonUnique == nil then
								hasNonUnique = false
							end
						end
					end
				end

				if hasNonUnique == nil or hasNonUnique then
					GBankClassic_UI_Mail:SetMailId(mailId)
					GBankClassic_UI_Mail:Open()
					return
				end
			end
		end
	end
end

-- Hook SendMail to update request fulfillment when sending items from bank alts
function Mail:InitSendHook()
	if self.sendHooked then
		return
	end

	self.sendHooked = true

	hooksecurefunc("SendMail", function(recipient, subject, body)
		self:OnSendMail(recipient)
	end)
end

function Mail:OnSendMail(recipient)
	GBankClassic_Output:Debug("MAIL", "OnSendMail: hook fired for recipient=%s", tostring(recipient))
	
	-- If pendingSend was set recently by PrepareFulfillMail (within 10 seconds), keep it
	-- Otherwise, read items from mail attachments (fallback for non-fulfill mails)
	local now = GetTime()
	if self.pendingSend and self.pendingSendAt and (now - self.pendingSendAt) < 10 then
		GBankClassic_Output:Debug("MAIL", "OnSendMail: Using pendingSend from PrepareFulfillMail")

		return
	end
	
	-- Clear old pendingSend and read from mail attachments
	self.pendingSend = nil
	self.pendingSendAt = nil

	local sender = GBankClassic_Guild:GetNormalizedPlayer()
	local items = {}

	for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
		local itemName, _, _, quantity = GetSendMailItem(attachmentIndex)
		if itemName and quantity and quantity > 0 then
			table.insert(items, { name = itemName, quantity = quantity })
		end
	end

	GBankClassic_Output:Debug("UI", "OnSendMail: sender=%s, recipient=%s, items=%d", tostring(sender), tostring(recipient), #items)

	if #items == 0 then
		return
	end

	local info = GBankClassic_Guild.Info
	if not info or not info.requests or next(info.requests) == nil then
		return
	end

	if not sender or not GBankClassic_Guild:IsGuildBankAlt(sender) then
		GBankClassic_Output:Debug("MAIL", "OnSendMail: Sender %s is not a guild bank alt, skipping", tostring(sender))

		return
	end

	GBankClassic_Output:Debug("MAIL", "OnSendMail: Sender %s IS a guild bank alt, setting pendingSend", tostring(sender))
	local normRecipient = GBankClassic_Guild:NormalizeName(recipient) or recipient

	self.pendingSend = {
		sender = sender,
		recipient = normRecipient,
		items = items,
	}
	self.pendingSendAt = GetTime()
	
	-- Log at info level so user can see manual sends are tracked
	local itemList = {}
	for _, item in ipairs(items) do
		table.insert(itemList, string.format("%dx %s", item.quantity, item.name))
	end
	GBankClassic_Output:Info("Tracking manual mail to %s: %s.", recipient, table.concat(itemList, ", "))
end

function GBankClassic_Mail:DebugSendMailState(contextMessage)
	local recipient = SendMailNameEditBox and SendMailNameEditBox:GetText() or nil
	local subject = SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() or nil
	local items = {}
	local totalCount = 0
	for attachmentIndex = 1, (ATTACHMENTS_MAX_SEND or 12) do
		local itemName, itemID, texture, quantity = GetSendMailItem(attachmentIndex)
		if itemName and quantity and quantity > 0 then
			table.insert(items, { name = itemName, id = itemID, quantity = quantity })
			totalCount = totalCount + quantity
		end
	end

	GBankClassic_Output:Debug("MAIL", "SendMail error: %s | recipient=%s subject=%s items=%d total=%d", tostring(contextMessage), tostring(recipient), tostring(subject), #items, totalCount)

	for i, item in ipairs(items) do
		GBankClassic_Output:Debug("MAIL", "  Attachment %d: %s (id=%s) x%d", i, tostring(item.name), tostring(item.id), item.quantity)
	end

	if self.pendingSend then
		GBankClassic_Output:Debug("MAIL", "  pendingSend: sender=%s recipient=%s items=%d", tostring(self.pendingSend.sender), tostring(self.pendingSend.recipient), self.pendingSend.items and #self.pendingSend.items or 0)
	end
end

function Mail:ApplyPendingSend()
	GBankClassic_Output:Debug("MAIL", "ApplyPendingSend: Called, pendingSend=%s", tostring(self.pendingSend ~= nil))
	local pending = self.pendingSend
	if not pending then
		GBankClassic_Output:Debug("MAIL", "ApplyPendingSend: No pendingSend, returning")

		return
	end

	self.pendingSend = nil
	self.pendingSendAt = nil

	GBankClassic_Output:Info("Applying fulfillment for mail sent to %s.", pending.recipient)

	local totalApplied = 0
	for _, item in ipairs(pending.items) do
		local applied = GBankClassic_Guild:FulfillRequest(pending.sender, pending.recipient, item.name, item.quantity, pending.requestId)
		if applied > 0 then
			GBankClassic_Output:Info("  Applied %dx %s toward %s's request (ID: %s).", applied, item.name, pending.recipient, tostring(pending.requestId))
		end
		totalApplied = totalApplied + applied
	end

	if totalApplied > 0 then
		GBankClassic_Output:Info("Total fulfilled: %d item(s) for %s.", totalApplied, pending.recipient)
		GBankClassic_Guild:RefreshRequestsUI()
	else
		GBankClassic_Output:Info("No matching requests found for items sent to %s.", pending.recipient)
	end
end

-- Check if a request can be fulfilled by the current player
-- Returns: canFulfill (boolean), reason (string), itemsInBags (number), smallestStack (number)
function Mail:CanFulfillRequest(request, actor)
	local normActor = GBankClassic_Guild:NormalizeName(actor or GBankClassic_Guild:GetNormalizedPlayer())

	-- Must be a bank alt
	if not GBankClassic_Guild:IsGuildBankAlt(normActor) then
		return false, "Only bank alts can fulfill requests.", 0, 0
	end

	-- Request must be valid and not completed
	if not request or not request.item then
		return false, "Invalid request.", 0, 0
	end

	local qtyRequested = tonumber(request.quantity or 0) or 0
	local qtyFulfilled = tonumber(request.fulfilled or 0) or 0
	local qtyNeeded = qtyRequested - qtyFulfilled

	if request.status == "complete" or request.status == "fulfilled" or request.status == "cancelled" then
		return false, "Request is already completed.", 0, 0
	end

	if qtyFulfilled >= qtyRequested and qtyRequested > 0 then
		return false, "Request is already fulfilled.", 0, 0
	end

	-- Check if items are in bags and find usable stacks
	local totalInBags, items = GBankClassic_Bank:CountItemInBags(request.item)

	if totalInBags == 0 then
		return false, "Items not in bags. Pick up from bank first.", 0, 0
	end

	-- Use unified fulfillment calc (make copy of items array to avoid mutation)
	local itemsCopy = {}
	for i, item in ipairs(items) do
		itemsCopy[i] = {bag = item.bag, slot = item.slot, count = item.count}
	end

	local plan = self:CalculateFulfillmentPlan(itemsCopy, qtyNeeded, totalInBags)

	-- Find smallest stack for legacy return value
	local smallestStack = nil
	for _, item in ipairs(items) do
		if not smallestStack or item.count < smallestStack then
			smallestStack = item.count
		end
	end

	return plan.canFulfill, plan.reason, totalInBags, smallestStack or 0
end

function GBankClassic_Mail:ResetScan()
	-- have to wait for server to remove item from inbox before we can take another
	-- so we wait a second before trying the next item
	GBankClassic_Core:ScheduleTimer(function(...)
		GBankClassic_Mail:OnTimer()
	end, 1)
end

function GBankClassic_Mail:OnTimer()
	self.isScanning = false
	GBankClassic_Mail:Scan()
end

function Mail:Open(mailId)
	local _, _, sender, _, money, _, _, itemCount, _, _, _, _, _, _ = GetInboxHeaderInfo(mailId)
	if not sender then
		Mail:RetryOpen(mailId)
		return
	end

	local info = GBankClassic_Guild.Info
	---START CHANGES
	if not info then
		return
	end
	---END CHANGES
	local player = GBankClassic_Guild:GetPlayer()
	local norm = GBankClassic_Guild:GetNormalizedPlayer(player)

	if not info.alts then
		info.alts = {}
	end

	if info.alts and not info.alts[norm] then
		info.alts[norm] = {}
	end

	local alt = info.alts[norm]

	if not alt.ledger then
		alt.ledger = {}
	end

	local ledger = alt.ledger

	local current_score = 0
	if ledger[sender] then
		current_score = ledger[sender]
	end

	local score = 0
	if money > 0 then
		-- convert from copper to gold
		score = money / 10000

		if GBankClassic_Options:GetBankReporting() then
			GBankClassic_Output:Info("Received %s gold from %s.", score, sender)
		end

		if GBankClassic_UI_Mail.ScoreMail and not self.Roster[sender] then
			ledger[sender] = current_score + score
		end

		TakeInboxMoney(mailId)
		if itemCount and itemCount > 0 then
			Mail:RetryOpen(mailId)
			return
		end
	end
	if itemCount then
		if not GBankClassic_Bank:HasInventorySpace() then
			GBankClassic_Output:Warn("Inventory is full.")
			return
		end

		for attachmentIndex = 1, ATTACHMENTS_MAX_RECEIVE do
			local link = GetInboxItemLink(mailId, attachmentIndex)
			if link then
				local _, _, _, quantity, _ = GetInboxItem(mailId, attachmentIndex)
				local name, _, quality, level, _, _, _, _, _, _, price = GetItemInfo(link)
				if not name or level == nil then
					Mail:RetryOpen(mailId)
					return
				end

				if not GBankClassic_Item:IsUnique(link) then
					score = ((price + 1) / 10000) * quantity

					if GBankClassic_Options:GetBankReporting() then
						GBankClassic_Output:Info("Received %s (%d) from %s.", name, quantity, sender)
					end

					-- Check if this fulfills an active request
					local isFulfillment, request = self:CheckForFulfilledRequest(name, quantity, sender)
					if isFulfillment and request then
						-- Play completion sound and show notification
						PlaySound("AuctionWindowClose") -- Pleasant "ding" sound (Classic Era compatible)
						local fulfilled = tonumber(request.fulfilled or 0) + quantity
						local requested = tonumber(request.quantity or 0)
						if fulfilled >= requested then
							GBankClassic_Output:Response("|cff00ff00[Order Filled]|r Received %dx %s from %s - Request Complete!", quantity, name, sender)
						else
							GBankClassic_Output:Response("|cff00ff00[Order Filled]|r Received %dx %s from %s (%d/%d).", quantity, name, sender, fulfilled, requested)
						end
					end

					if GBankClassic_UI_Mail.ScoreMail and not self.Roster[sender] then
						ledger[sender] = current_score + score
					end

					TakeInboxItem(mailId, attachmentIndex)
					if itemCount > 1 then
						Mail:RetryOpen(mailId)
						return
					end
				end
			end
		end
	end

	GBankClassic_UI_Mail:Close()
	Mail:ResetScan()
end

function Mail:RetryOpen(mailId)
	-- have to wait for server to remove item from inbox before we can take another
	-- so we wait a second before trying the next item
	GBankClassic_Core:ScheduleTimer(function(...)
		Mail:OnRetryTimer(mailId)
	end, 1)
end

function Mail:OnRetryTimer(mailId)
	Mail:Open(mailId)
end

-- Unified fulfillment plan calculator
-- Returns plan: {
--   canFulfill = boolean,
--   reason = string or nil,
--   stacksToAttach = {{bag, slot, count, originalIndex}, ...},
--   splitStack = {bag, slot, count, amount} or nil,
--   totalAttachable = number,
--   requiresMailbox = boolean
-- }
function GBankClassic_Mail:CalculateFulfillmentPlan(items, qtyNeeded, totalInBags)
	if not items or #items == 0 then
		return {
			canFulfill = false,
			reason = "No items found in bags.",
			stacksToAttach = {},
			splitStack = nil,
			totalAttachable = 0,
			requiresMailbox = false
		}
	end

	-- Add original index for stable sorting
	for i, item in ipairs(items) do
		item.originalIndex = i
	end

	-- Sort: largest first, maintain scan order for equal counts
	table.sort(items, function(a, b)
		if a.count == b.count then
			return a.originalIndex < b.originalIndex
		end

		return a.count > b.count
	end)

	local largestStack = items[1].count
	local smallestStack = items[#items].count

	-- PHASE 1: Try greedy exact match (accumulate stacks that fit without exceeding)
	local accumulated = 0
	local attachList = {}
	
	for i, item in ipairs(items) do
		local remaining = qtyNeeded - accumulated
		if item.count <= remaining then
			accumulated = accumulated + item.count
			table.insert(attachList, {
				bag = item.bag,
				slot = item.slot,
				count = item.count,
				originalIndex = item.originalIndex
			})
		end
	end

	-- SUCCESS: Exact match without splitting
	if accumulated == qtyNeeded then
		return {
			canFulfill = true,
			reason = nil,
			stacksToAttach = attachList,
			splitStack = nil,
			totalAttachable = accumulated,
			requiresMailbox = true
		}
	end

	-- PHASE 2: Try skipping small stacks to find exact match
	if accumulated < qtyNeeded and totalInBags >= qtyNeeded then
		local bestAccumulated = accumulated
		local bestAttachList = attachList
		local bestSkipIndex = nil

		for skipIndex = 1, math.min(5, #items) do
			local testAccumulated = 0
			local testAttachList = {}
			
			for i, item in ipairs(items) do
				if i ~= skipIndex then
					local remaining = qtyNeeded - testAccumulated
					if item.count <= remaining then
						testAccumulated = testAccumulated + item.count
						table.insert(testAttachList, {
							bag = item.bag,
							slot = item.slot,
							count = item.count,
							originalIndex = item.originalIndex
						})
					end
				end
			end

			-- Found exact match by skipping
			if testAccumulated == qtyNeeded then
				return {
					canFulfill = true,
					reason = nil,
					stacksToAttach = testAttachList,
					splitStack = nil,
					totalAttachable = testAccumulated,
					requiresMailbox = true
				}
			end

			-- Better fit than before (closer to target)
			if testAccumulated > bestAccumulated and testAccumulated < qtyNeeded then
				bestAccumulated = testAccumulated
				bestAttachList = testAttachList
				bestSkipIndex = skipIndex
			end
		end

		-- Use best fit found
		accumulated = bestAccumulated
		attachList = bestAttachList
	end

	-- PHASE 3: Need to split to fulfill
	if accumulated < qtyNeeded and totalInBags >= qtyNeeded then
		local remaining = qtyNeeded - accumulated
		
		-- Find a stack large enough to split from
		-- Prefer splitting from largest available stack
		local splitCandidate = nil
		for i, item in ipairs(items) do
			if item.count >= remaining then
				-- Check if this stack is already in attach list
				local alreadyAttaching = false
				for _, attached in ipairs(attachList) do
					if attached.originalIndex == item.originalIndex then
						alreadyAttaching = true
						break
					end
				end
				
				if not alreadyAttaching then
					-- Prefer largest split candidate (first one found due to sorting)
					if not splitCandidate then
						splitCandidate = item
					end
				end
			end
		end

		if splitCandidate then
			return {
				canFulfill = true,
				reason = string.format("Split %d from stack of %d.", remaining, splitCandidate.count),
				stacksToAttach = attachList,
				splitStack = {
					bag = splitCandidate.bag,
					slot = splitCandidate.slot,
					count = splitCandidate.count,
					amount = remaining
				},
				totalAttachable = accumulated,
				requiresMailbox = true
			}
		end
	end

	-- PHASE 4: Can't fulfill even with splitting
	local deficit = qtyNeeded - totalInBags
	if deficit > 0 then
		return {
			canFulfill = false,
			reason = string.format("Need %d more items.", deficit),
			stacksToAttach = {},
			splitStack = nil,
			totalAttachable = totalInBags,
			requiresMailbox = false
		}
	end

	-- Edge case: single large stack, need to split
	if accumulated == 0 and smallestStack > qtyNeeded and totalInBags >= qtyNeeded then
		return {
			canFulfill = true,
			reason = string.format("Split from stack of %d.", smallestStack),
			stacksToAttach = {},
			splitStack = {
				bag = items[1].bag,
				slot = items[1].slot,
				count = items[1].count,
				amount = qtyNeeded
			},
			totalAttachable = 0,
			requiresMailbox = true
		}
	end

	-- Shouldn't reach here, but fallback
	return {
		canFulfill = false,
		reason = "Unable to determine fulfillment strategy.",
		stacksToAttach = {},
		splitStack = nil,
		totalAttachable = accumulated,
		requiresMailbox = false
	}
end

-- Prepare mail to fulfill a request: sets recipient and attaches items
-- Returns: success (boolean), message (string), attachedCount (number)
function Mail:PrepareFulfillMail(request)
	if not self:IsMailboxOpen() then
		return false, "Mailbox is not open.", 0
	end

	if not request or not request.item or not request.requester then
		return false, "Invalid request.", 0
	end

	local itemName = request.item
	local requester = request.requester
	local qtyRequested = tonumber(request.quantity or 0) or 0
	local qtyFulfilled = tonumber(request.fulfilled or 0) or 0
	local qtyNeeded = qtyRequested - qtyFulfilled

	if qtyNeeded <= 0 then
		return false, "Request is already fulfilled.", 0
	end

	-- Find items in inventory
	local totalInBags, items = GBankClassic_Bank:CountItemInBags(itemName)

	if totalInBags == 0 then
		return false, "No " .. itemName .. " found in bags.", 0
	end

	-- Check if mail already has items attached
	if GetSendMailItem(1) then
		return false, "Mail already has items attached. Send or clear first.", 0
	end

	-- Set recipient
	if SendMailNameEditBox then
		SendMailNameEditBox:SetText(requester)
	end

	-- Use unified fulfillment plan
	local plan = self:CalculateFulfillmentPlan(items, qtyNeeded, totalInBags)

	if not plan.canFulfill then
		return false, plan.reason, 0
	end

	-- If plan requires split, show popup first without attaching anything
	if plan.splitStack then
		local splitInfo = plan.splitStack

		-- Show confirmation popup
		local popupText = string.format("Split %d from stack of %d %s?", splitInfo.amount, splitInfo.count, itemName)
		local dialog = StaticPopup_Show("GBANK_SPLIT_STACK", popupText)
		if dialog then
			dialog.data = {
				bag = splitInfo.bag,
				slot = splitInfo.slot,
				amount = splitInfo.amount,
				attachmentSlot = 1,
				itemName = itemName,
				requester = requester
			}
		end

		local message = string.format("Click split to prepare %d %s for mailing.", splitInfo.amount, itemName)

		return false, message, 0
	end

	-- No split needed, attach items from plan
	local attached = 0
	local attachmentSlot = 1
	local maxSlots = ATTACHMENTS_MAX_SEND or 12

	for _, stack in ipairs(plan.stacksToAttach) do
		if attached >= qtyNeeded then
			break
		end
		if attachmentSlot > maxSlots then
			break
		end

		ClearCursor()
		C_Container.PickupContainerItem(stack.bag, stack.slot)
		ClickSendMailItemButton(attachmentSlot)

		attached = attached + stack.count
		attachmentSlot = attachmentSlot + 1
	end

	local message
	if attached >= qtyNeeded then
		message = string.format("Attached %d %s for %s. Click send to complete.", attached, itemName, requester)
	elseif attached > 0 then
		message = string.format("Attached %d of %d %s (partial). Click send, then fulfill again.", attached, qtyNeeded, itemName)
	else
		message = string.format("No %s found in bags.", itemName)

		return false, message, 0
	end
	
	-- Set pendingSend now (when items are attached), not in SendMail hook
	-- This ensures pendingSend is set BEFORE MAIL_SEND_SUCCESS fires
	if attached > 0 then
		local sender = GBankClassic_Guild:GetNormalizedPlayer()
		local normRecipient = GBankClassic_Guild:NormalizeName(requester) or requester
		self.pendingSend = {
			sender = sender,
			recipient = normRecipient,
			requestId = request.id,
			items = {{ name = itemName, quantity = attached }}
		}
		self.pendingSendAt = GetTime()
		GBankClassic_Output:Debug("MAIL", "PrepareFulfillMail: Set pendingSend for %s (%d %s) - requestId=%s", tostring(normRecipient), attached, itemName, tostring(request.id))
	end
	
	return true, message, attached
end
]]--