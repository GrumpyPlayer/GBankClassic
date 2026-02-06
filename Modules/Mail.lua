GBankClassic_Mail = GBankClassic_Mail or {
	-- -- State for split operation
	-- splitState = nil -- {bag, slot, amount, attachmentSlot, request}
}

local Mail = GBankClassic_Mail

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("MailFrame")
local MailFrame = upvalues.MailFrame
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

-- -- Initialize split stack popup dialog
-- if not StaticPopupDialogs["GBANK_SPLIT_STACK"] then
-- 	StaticPopupDialogs["GBANK_SPLIT_STACK"] = {
-- 		text = "%s",
-- 		button1 = "Split",
-- 		button2 = "Cancel",
-- 		OnAccept = function(self, data)
-- 			if not data then
--              return
--          end
--
-- 			ClearCursor()
-- 			-- Find an empty bag slot to place the split items
-- 			local emptyBag, emptySlot
-- 			for bag = 0, 4 do
-- 				local numSlots = GetContainerNumSlots(bag)
-- 				for slot = 1, numSlots do
-- 					if not GetContainerItemInfo(bag, slot) then
-- 						emptyBag, emptySlot = bag, slot
-- 						break
-- 					end
-- 				end
-- 				if emptyBag then
 --                 break
--              end
-- 			end
-- 			if not emptyBag then
-- 				return
-- 			end

-- 			-- Step 1: Split - puts amount on cursor
-- 			SplitContainerItem(data.bag, data.slot, data.amount)
-- 			After(0.1, function()
-- 				-- Step 2: Place split items into empty slot to "commit" the split
-- 				PickupContainerItem(emptyBag, emptySlot)
-- 				After(0.05, function()
-- 					-- Done! The split stack is now in inventory
-- 					if GBankClassic_UI_Requests and GBankClassic_UI_Requests.Window then
-- 						local message = string.format("Split %d %s complete. Click fulfill again to attach items.",
-- 							data.amount, data.itemName)
-- 						GBankClassic_UI_Requests.Window:SetStatusText(message)
-- 						-- Refresh the request list to update the fulfill button icon
-- 						GBankClassic_UI_Requests:DrawContent()
-- 					end
-- 				end)
-- 			end)
-- 		end,
-- 		OnCancel = function()
-- 			-- Nothing to clean up
-- 		end,
-- 		timeout = 0,
-- 		whileDead = true,
-- 		hideOnEscape = true,
-- 		preferredIndex = 3,
-- 	}
-- end

function Mail:IsMailboxOpen()
	local frameOpen = MailFrame and MailFrame:IsShown() or false
	if self.isOpen ~= frameOpen then
		self.isOpen = frameOpen
	end

	return frameOpen
end

function Mail:Check()
    CheckInbox()
end

-- Helper to update the donation ledger
function Mail:RecordDonationInLedger(sender, itemLink, quantity, money, isMoney)
    if not sender then
        return
    end
    
    local senderNorm = GBankClassic_Guild:GetNormalizedPlayer(sender)
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
                GBankClassic_Output:Info("Donation of %s received from %s", GetCoinTextureString(money), senderNorm)
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
                    GBankClassic_Output:Info("Donation of %s x%d received from %s (vendor value recorded as %s)", itemLink, quantity, senderNorm, GetCoinTextureString((effectivePrice * quantity)))
                end
                ledger[senderNorm] = (ledger[senderNorm] or 0) + score
            end
        end
    end
end

-- Helper to extract informatiom from a mail
function Mail:ProcessMail(mailId, attachmentIndex)
    local _, _, sender, _, moneyString, _, daysLeft, itemCount, _, wasReturned, _, _, isGM = GetInboxHeaderInfo(mailId)
    local money = tonumber(moneyString) or 0

    if not sender or wasReturned or isGM then
        GBankClassic_Output:Debug("DONATION", "Processing aborted - invalid mail state")

        return 
    end

    local key, itemLink, itemID, quantity
    if attachmentIndex then
        itemLink = GetInboxItemLink(mailId, attachmentIndex)
        if itemLink then
            itemID = itemLink:match("item:(%d+)")
            quantity = select(4, GetInboxItem(mailId, attachmentIndex)) or 1

            if not (itemLink and itemID) or quantity <= 0 then 
                GBankClassic_Output:Debug("DONATION", "Processing aborted - invalid item")

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

-- -- Hook SendMail to update request fulfillment when sending items from bank alts
-- function Mail:InitSendHook()
-- 	if self.sendHooked then
-- 		return
-- 	end

-- 	self.sendHooked = true

-- 	hooksecurefunc("SendMail", function(recipient, subject, body)
-- 		self:OnSendMail(recipient)
-- 	end)
-- end

-- function Mail:OnSendMail(recipient)
-- 	GBankClassic_Output:Debug("MAIL", "OnSendMail: hook fired for recipient=%s", tostring(recipient))
	
-- 	-- If pendingSend was set recently by PrepareFulfillMail (within 10 seconds), keep it
-- 	-- Otherwise, read items from mail attachments (fallback for non-fulfill mails)
-- 	local now = GetTime()
-- 	if self.pendingSend and self.pendingSendAt and (now - self.pendingSendAt) < 10 then
-- 		GBankClassic_Output:Debug("MAIL", "OnSendMail: Using pendingSend from PrepareFulfillMail")

-- 		return
-- 	end
	
-- 	-- Clear old pendingSend and read from mail attachments
-- 	self.pendingSend = nil
-- 	self.pendingSendAt = nil

-- 	local sender = GBankClassic_Guild:GetNormalizedPlayer()
-- 	local items = {}

-- 	for attachmentIndex = 1, ATTACHMENTS_MAX_SEND do
-- 		local itemName, _, _, quantity = GetSendMailItem(attachmentIndex)
-- 		if itemName and quantity and quantity > 0 then
-- 			table.insert(items, { name = itemName, quantity = quantity })
-- 		end
-- 	end

-- 	GBankClassic_Output:Debug("UI", "OnSendMail: sender=%s, recipient=%s, items=%d", tostring(sender), tostring(recipient), #items)

-- 	if #items == 0 then
-- 		return
-- 	end

-- 	local info = GBankClassic_Guild.Info
-- 	if not info or not info.requests or #info.requests == 0 then
-- 		return
-- 	end

-- 	if not sender or not GBankClassic_Guild:IsBank(sender) then
-- 		GBankClassic_Output:Debug("MAIL", "OnSendMail: Sender %s is not a guild bank alt, skipping", tostring(sender))

-- 		return
-- 	end

-- 	GBankClassic_Output:Debug("MAIL", "OnSendMail: Sender %s IS a guild bank alt, setting pendingSend", tostring(sender))
-- 	local normRecipient = GBankClassic_Guild:NormalizeName(recipient)

-- 	self.pendingSend = {
-- 		sender = sender,
-- 		recipient = normRecipient,
-- 		items = items,
-- 	}
-- 	self.pendingSendAt = GetTime()
	
-- 	-- Log at info level so user can see manual sends are tracked
-- 	local itemList = {}
-- 	for _, item in ipairs(items) do
-- 		table.insert(itemList, string.format("%dx %s", item.quantity, item.name))
-- 	end
-- 	GBankClassic_Output:Info("Tracking manual mail to %s: %s", recipient, table.concat(itemList, ", "))
-- end

-- function Mail:ApplyPendingSend()
-- 	GBankClassic_Output:Debug("MAIL", "ApplyPendingSend: Called, pendingSend=%s", tostring(self.pendingSend ~= nil))
-- 	local pending = self.pendingSend
-- 	if not pending then
-- 		GBankClassic_Output:Debug("MAIL", "ApplyPendingSend: No pendingSend, returning")

-- 		return
-- 	end

-- 	self.pendingSend = nil
-- 	self.pendingSendAt = nil

-- 	GBankClassic_Output:Info("Applying fulfillment for mail sent to %s...", pending.recipient)

-- 	local totalApplied = 0
-- 	for _, item in ipairs(pending.items) do
-- 		local applied = GBankClassic_Guild:FulfillRequest(pending.sender, pending.recipient, item.name, item.quantity)
-- 		if applied > 0 then
-- 			GBankClassic_Output:Info("  Applied %dx %s toward %s's request", applied, item.name, pending.recipient)
-- 		end
-- 		totalApplied = totalApplied + applied
-- 	end

-- 	if totalApplied > 0 then
-- 		GBankClassic_Output:Info("Total fulfilled: %d item(s) for %s", totalApplied, pending.recipient)
-- 		GBankClassic_Guild:RefreshRequestsUI()
-- 	else
-- 		GBankClassic_Output:Info("No matching requests found for items sent to %s", pending.recipient)
-- 	end
-- end

-- -- Check if a request can be fulfilled by the current player
-- -- Returns: canFulfill (boolean), reason (string), itemsInBags (number), smallestStack (number)
-- function Mail:CanFulfillRequest(request, actor)
-- 	local normActor = GBankClassic_Guild:NormalizeName(actor or GBankClassic_Guild:GetPlayer())

-- 	-- Must be a bank alt
-- 	if not GBankClassic_Guild:IsBank(normActor) then
-- 		return false, "Only bank alts can fulfill requests.", 0, 0
-- 	end

-- 	-- Request must be valid and not completed
-- 	if not request or not request.item then
-- 		return false, "Invalid request.", 0, 0
-- 	end

-- 	local qtyRequested = tonumber(request.quantity or 0) or 0
-- 	local qtyFulfilled = tonumber(request.fulfilled or 0) or 0
-- 	local qtyNeeded = qtyRequested - qtyFulfilled

-- 	if request.status == "complete" or request.status == "fulfilled" or request.status == "cancelled" then
-- 		return false, "Request is already completed.", 0, 0
-- 	end

-- 	if qtyFulfilled >= qtyRequested and qtyRequested > 0 then
-- 		return false, "Request is already fulfilled.", 0, 0
-- 	end

-- 	-- Check if items are in bags and find usable stacks
-- 	local totalInBags, items = GBankClassic_Bank:CountItemInBags(request.item)

-- 	if totalInBags == 0 then
-- 		return false, "Items not in bags. Pick up from bank first.", 0, 0
-- 	end

-- 	-- Sort items by stack size (largest first) to match attachment behavior
-- 	table.sort(items, function(a, b) return a.count > b.count end)

-- 	-- Find smallest and largest stacks, and count usable items (stacks that fit without exceeding qtyNeeded)
-- 	local smallestStack = nil
-- 	local largestStack = nil
-- 	local usableItems = 0
-- 	for _, item in ipairs(items) do
-- 		if not smallestStack or item.count < smallestStack then
-- 			smallestStack = item.count
-- 		end
-- 		if not largestStack or item.count > largestStack then
-- 			largestStack = item.count
-- 		end
-- 		-- Only count this stack if adding it doesn't exceed what we need
-- 		if usableItems + item.count <= qtyNeeded then
-- 			usableItems = usableItems + item.count
-- 		end
-- 	end

-- 	-- If greedy smallest-first didn't get exact match, try skipping individual small stacks
-- 	if usableItems < qtyNeeded and totalInBags >= qtyNeeded then
-- 		for skipIndex = 1, math.min(5, #items) do
-- 			local testUsable = 0
-- 			for i = 1, #items do
-- 				if i ~= skipIndex and testUsable + items[i].count <= qtyNeeded then
-- 					testUsable = testUsable + items[i].count
-- 				end
-- 			end
-- 			if testUsable == qtyNeeded then
-- 				usableItems = testUsable
-- 				break
-- 			elseif testUsable > usableItems and testUsable <= qtyNeeded then
-- 				-- Better fit, use it
-- 				usableItems = testUsable
-- 			end
-- 		end
-- 	end

-- 	-- Check if we need to split
-- 	if usableItems < qtyNeeded and totalInBags >= qtyNeeded then
-- 		-- We have enough total, but need to split to fulfill
-- 		-- Efficiency check: if we have any stack large enough to provide what we need,
-- 		-- Prefer splitting from it rather than using multiple small stacks
-- 		if largestStack and largestStack >= qtyNeeded then
-- 			-- Can split exactly what we need from a single stack - more efficient
-- 			local reason = string.format("Split %d from available stacks.", qtyNeeded)

-- 			return true, reason, totalInBags, smallestStack
-- 		end
		
-- 		local remaining = qtyNeeded - usableItems
		
-- 		-- Additional efficiency check: if using small partials requires a split,
-- 		-- Check if using only the largest stacks would require similar or smaller effort
-- 		-- Example: [1,20,20,20,20,20] need 90 -> better to use 4×20+split(10) than 1+4×20+split(9)
-- 		-- The trade-off: splitting 10 from one stack vs using a 1-stack + splitting 9
-- 		if largestStack and largestStack > 1 and remaining > 0 then
-- 			-- Count how many complete largest stacks we can use
-- 			local largeStacksUsable = 0
-- 			for _, item in ipairs(items) do
-- 				if item.count == largestStack and largeStacksUsable + item.count <= qtyNeeded then
-- 					largeStacksUsable = largeStacksUsable + item.count
-- 				end
-- 			end
			
-- 			-- If we have at least one more largest stack available to split from
-- 			local hasExtraLargeStack = false
-- 			for _, item in ipairs(items) do
-- 				if item.count == largestStack then
-- 					local testTotal = largeStacksUsable + item.count
-- 					if testTotal > largeStacksUsable and testTotal >= qtyNeeded then
-- 						hasExtraLargeStack = true
-- 						break
-- 					end
-- 				end
-- 			end
			
-- 			if hasExtraLargeStack and largeStacksUsable < qtyNeeded then
-- 				local largeSplitAmount = qtyNeeded - largeStacksUsable
-- 				-- Prefer this if it means not attaching tiny partial stacks
-- 				-- (using fewer mail attachment slots is more efficient)
-- 				if largeSplitAmount <= largestStack then
-- 					usableItems = largeStacksUsable
-- 					remaining = largeSplitAmount
-- 				end
-- 			end
-- 		end
		
-- 		local reason = string.format("Splitting %d to fill the order.", remaining)

-- 		return true, reason, totalInBags, smallestStack
-- 	end

-- 	-- If no stacks are small enough, we can split automatically
-- 	if usableItems == 0 and smallestStack and smallestStack > qtyNeeded then
-- 		local reason = string.format("Split from stack of %d.", smallestStack)

-- 		return true, reason, totalInBags, smallestStack
-- 	end

-- 	-- Check if we have enough usable items to fulfill the request
-- 	if usableItems >= qtyNeeded then
-- 		return true, nil, usableItems, smallestStack
-- 	end

-- 	-- Not enough items even with splitting
-- 	return false, string.format("Need %d more items.", qtyNeeded - usableItems), totalInBags, smallestStack
-- end

-- -- Prepare mail to fulfill a request: sets recipient and attaches items
-- -- Returns: success (boolean), message (string), attachedCount (number)
-- function Mail:PrepareFulfillMail(request)
-- 	if not self:IsMailboxOpen() then
-- 		return false, "Mailbox is not open.", 0
-- 	end

-- 	if not request or not request.item or not request.requester then
-- 		return false, "Invalid request.", 0
-- 	end

-- 	local itemName = request.item
-- 	local requester = request.requester
-- 	local qtyRequested = tonumber(request.quantity or 0) or 0
-- 	local qtyFulfilled = tonumber(request.fulfilled or 0) or 0
-- 	local qtyNeeded = qtyRequested - qtyFulfilled

-- 	if qtyNeeded <= 0 then
-- 		return false, "Request is already fulfilled.", 0
-- 	end

-- 	-- Find items in inventory
-- 	local totalInBags, items = GBankClassic_Bank:CountItemInBags(itemName)

-- 	if totalInBags == 0 then
-- 		return false, "No " .. itemName .. " found in bags.", 0
-- 	end

-- 	-- Check if mail already has items attached
-- 	if GetSendMailItem(1) then
-- 		return false, "Mail already has items attached. Send or clear first.", 0
-- 	end

-- 	-- Set recipient
-- 	if SendMailNameEditBox then
-- 		SendMailNameEditBox:SetText(requester)
-- 	end

-- 	-- Attach items (up to ATTACHMENTS_MAX_SEND slots)
-- 	-- Classic Era doesn't support programmatic stack splitting,
-- 	-- So we only attach stacks that won't exceed the needed quantity
-- 	local attached = 0
-- 	local attachmentSlot = 1
-- 	local maxSlots = ATTACHMENTS_MAX_SEND or 12
-- 	local skippedLargeStack = nil

-- 	-- Sort items by stack size (largest first) - full stacks before partial stacks
-- 	-- When counts are equal, maintain the original scan order (bottom-right to top-left in bags)
-- 	-- By adding an index to each item before sorting
-- 	for i, item in ipairs(items) do
-- 		item.originalIndex = i
-- 	end
-- 	table.sort(items, function(a, b)
-- 		if a.count == b.count then
-- 			return a.originalIndex < b.originalIndex -- Maintain physical order for equal counts
-- 		end

-- 		return a.count > b.count
-- 	end)

-- 	-- First pass: Calculate minimum useful stack size based on split requirement
-- 	-- Strategy: Don't use stacks smaller than what we'll need to split
-- 	-- Example: Need 95, have [20,20,20,20,14] → need to split 15, so exclude 14
	
-- 	-- Accumulate largest stacks to see what we'd need to split
-- 	local accumulated = 0
-- 	local largestStack = items[1] and items[1].count or 0
	
-- 	for _, item in ipairs(items) do
-- 		if accumulated >= qtyNeeded then
-- 			break
-- 		end
-- 		-- Only accumulate stacks that are at least half the largest stack size
-- 		-- This gets us the "main" stacks and ignores tiny partials
-- 		if item.count >= (largestStack * 0.5) then
-- 			accumulated = accumulated + item.count
-- 		end
-- 	end
	
-- 	-- Calculate what we'd need to split
-- 	local wouldNeedToSplit = math.max(0, qtyNeeded - accumulated)
	
-- 	-- Minimum stack size = the split amount (must be able to split that much from a stack)
-- 	-- If no split needed, use min(5, qtyNeeded) to avoid filtering out perfectly sized stacks
-- 	-- Example: Need 1 item → minStackSize should be 1, not 5
-- 	-- Never set minStackSize higher than largestStack (fixes non-stackable items like bags)
-- 	local minStackSize = math.min(largestStack, wouldNeedToSplit > 0 and wouldNeedToSplit or math.min(5, qtyNeeded))
	
-- 	-- Build useful stacks list
-- 	local usefulStacks = {}
-- 	for i, item in ipairs(items) do
-- 		if item.count >= minStackSize then
-- 			table.insert(usefulStacks, item)
-- 		end
-- 	end
	
-- 	GBankClassic_Output:Debug("FULFILL", "Need %d, accumulated %d from large stacks, would split %d", qtyNeeded, accumulated, wouldNeedToSplit)
-- 	GBankClassic_Output:Debug("FULFILL", "Filtered %d useful stacks from %d total (min size: %d)", #usefulStacks, #items, minStackSize)

-- 	-- Second pass: Run greedy algorithm on useful stacks only
-- 	local simulatedAttached = 0
-- 	local skipStackIndex = nil -- Track which stack to skip during attachment for optimal fit
-- 	local splitStackIndex = nil -- Track which stack we'll split from

-- 	-- Greedy pass: accumulate items until we need more than a stack can provide
-- 	-- Process in two stages to prefer exact-fit stacks before splits
-- 	-- Stage 1: Accumulate all stacks that fit exactly without exceeding qtyNeeded
-- 	for i, item in ipairs(usefulStacks) do
-- 		if simulatedAttached >= qtyNeeded then
-- 			break
-- 		end
-- 		local remaining = qtyNeeded - simulatedAttached

-- 		if item.count <= remaining then
-- 			-- This stack fits completely - accumulate it
-- 			simulatedAttached = simulatedAttached + item.count
-- 			GBankClassic_Output:Debug("FULFILL", "Stack %d: count=%d, accumulate, total=%d", i, item.count, simulatedAttached)
-- 		end
-- 	end
	
-- 	-- Stage 2: If we didn't get enough, look for a stack to split
-- 	if simulatedAttached < qtyNeeded then
-- 		local remaining = qtyNeeded - simulatedAttached
-- 		for i, item in ipairs(usefulStacks) do
-- 			if item.count > remaining and item.count >= remaining then
-- 				-- This stack can provide the remaining amount
-- 				skippedLargeStack = item
-- 				splitStackIndex = i
-- 				GBankClassic_Output:Debug("FULFILL", "Stack %d: count=%d, can split (need %d), mark as candidate", i, item.count, remaining)
-- 				break -- Found a split candidate, stop looking
-- 			end
-- 		end
-- 	else
-- 		-- We accumulated enough - no split needed
-- 		GBankClassic_Output:Debug("FULFILL", "Accumulated enough - no split needed")
-- 	end
	
-- 	GBankClassic_Output:Debug("FULFILL", "Greedy result: attached=%d, splitStackIndex=%s", simulatedAttached, tostring(splitStackIndex))

-- 	-- If greedy didn't get exact match and didn't find a split candidate, try skipping individual stacks to find better fit
-- 	if simulatedAttached < qtyNeeded and totalInBags >= qtyNeeded and not skippedLargeStack then
-- 		for skipIndex = 1, math.min(5, #items) do
-- 			local testAttached = 0
-- 			local testSkippedLargeStack = nil
-- 			local testSplitStackIndex = nil
-- 			for i = 1, #items do
-- 				if i ~= skipIndex then
-- 					local remaining = qtyNeeded - testAttached
-- 					if testAttached >= qtyNeeded then
-- 						break
-- 					elseif items[i].count <= remaining then
-- 						testAttached = testAttached + items[i].count
-- 					elseif items[i].count >= remaining then
-- 						-- This stack can provide the remaining amount - keep track of it
-- 						-- Continue iterating to find the last stack that can be split
-- 						testSkippedLargeStack = items[i]
-- 						testSplitStackIndex = i
-- 					else
-- 						-- This stack is too small to split - stop here
-- 						break
-- 					end
-- 				end
-- 			end
-- 			if testAttached == qtyNeeded then
-- 				simulatedAttached = testAttached
-- 				skipStackIndex = skipIndex -- Remember to skip this stack during attachment
-- 				skippedLargeStack = nil -- No split needed - found exact match!
-- 				splitStackIndex = nil
-- 				break
-- 			elseif testAttached > simulatedAttached or (testAttached == simulatedAttached and testSplitStackIndex and splitStackIndex and testSplitStackIndex > splitStackIndex) then
-- 				-- Better fit found, or same fit but with split from a later stack (preferred)
-- 				simulatedAttached = testAttached
-- 				skipStackIndex = skipIndex
-- 				skippedLargeStack = testSkippedLargeStack
-- 				splitStackIndex = testSplitStackIndex
-- 			end
-- 		end
-- 	end

-- 	-- If we need to split, show popup first without attaching anything
-- 	if skippedLargeStack then
-- 		local remaining = qtyNeeded - simulatedAttached

-- 		-- Show confirmation popup
-- 		local popupText = string.format("Split %d from stack of %d %s?", remaining, skippedLargeStack.count, itemName)
-- 		local dialog = StaticPopup_Show("GBANK_SPLIT_STACK", popupText)
-- 		if dialog then
-- 			dialog.data = {
-- 				bag = skippedLargeStack.bag,
-- 				slot = skippedLargeStack.slot,
-- 				amount = remaining,
-- 				attachmentSlot = attachmentSlot,
-- 				itemName = itemName,
-- 				requester = requester
-- 			}
-- 		end

-- 		local message = string.format("Click split to prepare %d %s for mailing.", remaining, itemName)

-- 		return false, message, 0
-- 	end

-- 	-- No split needed, proceed with normal attachment
-- 	for i, item in ipairs(usefulStacks) do
-- 		if attached >= qtyNeeded then
-- 			break
-- 		end
-- 		if attachmentSlot > maxSlots then
-- 			break
-- 		end

-- 		-- Skip this stack if it was identified as needing to be skipped for optimal fit
-- 		if not (skipStackIndex and i == skipStackIndex) then
-- 			local remaining = qtyNeeded - attached

-- 			-- Attach full stacks that don't exceed what we need
-- 			if item.count <= remaining then
-- 				ClearCursor()
-- 				PickupContainerItem(item.bag, item.slot)
-- 				ClickSendMailItemButton(attachmentSlot)

-- 				attached = attached + item.count
-- 				attachmentSlot = attachmentSlot + 1
-- 			end
-- 		end
-- 	end

-- 	local message
-- 	if attached >= qtyNeeded then
-- 		message = string.format("Attached %d %s for %s. Click send to complete.", attached, itemName, requester)
-- 	elseif attached > 0 then
-- 		message = string.format("Attached %d of %d %s (partial). Click send, then fulfill again.", attached, qtyNeeded, itemName)
-- 	else
-- 		message = string.format("No %s found in bags.", itemName)

-- 		return false, message, 0
-- 	end
	
-- 	-- Set pendingSend now (when items are attached), not in SendMail hook
-- 	-- This ensures pendingSend is set BEFORE MAIL_SEND_SUCCESS fires
-- 	if attached > 0 then
-- 		local sender = GBankClassic_Guild:GetNormalizedPlayer()
-- 		local normRecipient = GBankClassic_Guild:NormalizeName(requester)
-- 		self.pendingSend = {
-- 			sender = sender,
-- 			recipient = normRecipient,
-- 			items = {{ name = itemName, quantity = attached }}
-- 		}
-- 		self.pendingSendAt = GetTime()
-- 		GBankClassic_Output:Debug("MAIL", "PrepareFulfillMail: Set pendingSend for %s (%d %s)", tostring(normRecipient), attached, itemName)
-- 	end
	
-- 	return true, message, attached
-- end