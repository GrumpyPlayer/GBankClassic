local addonName, GBCR = ...

GBCR.Inventory = {}
local Inventory = GBCR.Inventory

local Globals = GBCR.Globals
local GetContainerNumFreeSlots = Globals.GetContainerNumFreeSlots
local GetContainerItemInfo = Globals.GetContainerItemInfo
local GetContainerNumSlots = Globals.GetContainerNumSlots
local GetMoney = Globals.GetMoney
local GetServerTime = Globals.GetServerTime
local GetInboxNumItems = Globals.GetInboxNumItems
local GetInboxHeaderInfo = Globals.GetInboxHeaderInfo
local GetInboxItem = Globals.GetInboxItem
local GetInboxItemLink = Globals.GetInboxItemLink
local GetItemInfo = Globals.GetItemInfo
local BANK_CONTAINER = Globals.BANK_CONTAINER
local NUM_BANKGENERIC_SLOTS = Globals.NUM_BANKGENERIC_SLOTS
local ATTACHMENTS_MAX_RECEIVE = Globals.ATTACHMENTS_MAX_RECEIVE
local GetItemInventoryTypeByID = Globals.GetItemInventoryTypeByID
local CreateFrame = Globals.CreateFrame
local UIParent = Globals.UIParent
local ITEM_UNIQUE = Globals.ITEM_UNIQUE

local Constants = GBCR.Constants
local itemClassesNeedingLink = Constants.ITEM_CLASSES_NEEDING_LINK

local function isBankAvailable()
    local _, bagType = GetContainerNumFreeSlots(BANK_CONTAINER)

    return bagType ~= nil
end

local function hasUpdated()
    return Inventory.hasUpdated
end

local function scanBag(bag, slots)
    local items = {}

    for slot = 1, slots do
        local itemInfo = GetContainerItemInfo(bag, slot)
        if itemInfo then
            local itemCount = itemInfo.stackCount
            local itemLink = itemInfo.hyperlink
            local itemId = itemInfo.itemID
            if itemLink then
                local key = itemId .. itemLink
                if items[key] then
                    local item = items[key]
                    items[key] = { itemId = item.itemId, itemCount = item.itemCount + itemCount, itemLink = item.itemLink }
                else
                    items[key] = { itemId = itemId, itemCount = itemCount, itemLink = itemLink }
                end
            end
        end
    end

    return items
end

local function scanBags(bagTable)
    local bagItems = nil

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        local items = scanBag(bag, slots)
        if bagItems == nil then
            bagItems = items
        else
            for k, v in pairs(items) do
                if bagItems[k] then
                    local item = bagItems[k]
                    bagItems[k] = { itemId = item.itemId, itemCount = item.itemCount + v.itemCount, itemLink = item.itemLink }
                else
                    bagItems[k] = v
                end
            end
        end
    end

    for _, v in pairs(bagItems) do
        table.insert(bagTable, v)
    end
end

local function scanBank(bankTable)
	if isBankAvailable() then
		local bankItems = scanBag(BANK_CONTAINER, NUM_BANKGENERIC_SLOTS)

		for bag = 5, 11 do
			local slots = GetContainerNumSlots(bag)
			local items = scanBag(bag, slots)
			for k, v in pairs(items) do
				if bankItems[k] then
					local item = bankItems[k]
					bankItems[k] = { itemId = item.itemId, itemCount = item.itemCount + v.itemCount, itemLink = item.itemLink }
				else
					bankItems[k] = v
				end
			end
		end

		for _, v in pairs(bankItems) do
			table.insert(bankTable, v)
		end
	end
end

local function scanMailInventory()
	-- Only scan if mail was accessed this session
	if not Inventory.mailHasUpdated then
		GBCR.Output:Debug("INVENTORY", "scanMailInventory called but mailHasUpdated=false, returning nil")

		return nil
	end

	-- Use same structure as bank/bags: aggregate by composite key, store as array
	local mailItemsTable = {}
	local numItems = GetInboxNumItems()

	GBCR.Output:Debug("INVENTORY", "Starting mailbox scan: %d mail messages", numItems)

	for i = 1, numItems do
		local _, _, sender, _, _, CODAmount, _, hasItem = GetInboxHeaderInfo(i)

		-- Skip COD mail (can't take items without payment)
		if hasItem and CODAmount == 0 then
			for j = 1, ATTACHMENTS_MAX_RECEIVE do
				local name, itemId, _, count = GetInboxItem(i, j)

				if itemId and name then
					local itemLink = GetInboxItemLink(i, j)
					if not itemLink and itemId then
						itemLink = select(2, GetItemInfo(itemId))
					end

					-- Conditionally include itemLink based on item class
					-- Gear (weapons/armor) needs full itemLink for suffix differentiation
					-- Consumables/trade goods don't need itemLink (saves bandwidth)
					local storageLink = nil
					if itemLink and Inventory:NeedsLink(itemLink) then
						storageLink = itemLink
					end

					-- Use normalized key for deduplication
					local key = Inventory:GetItemKey(itemLink)

					if mailItemsTable[key] then
						-- Item already exists, add to count
						local item = mailItemsTable[key]
						local newCount = item.itemCount + count
						mailItemsTable[key] = { itemId = item.itemId, itemCount = newCount, itemLink = item.itemLink }
						GBCR.Output:Debug("INVENTORY", "Item %s: merged (key=%s) added %d, total now %d", name, key, count, mailItemsTable[key].itemCount)
					else
						-- New item
						mailItemsTable[key] = { itemId = itemId, itemCount = count, itemLink = storageLink }
						GBCR.Output:Debug("INVENTORY", "New item in mailbox: %s (itemId: %d, itemCount: %d, itemLink: %s, Key: %s)", name, itemId, count, storageLink and "preserved" or "stripped", key)
					end
				end
			end
		elseif hasItem and CODAmount > 0 then
			GBCR.Output:Debug("INVENTORY", "Skipping COD mail from %s (COD: %d copper)", sender or "Unknown", CODAmount)
		end
	end

	-- Convert to array format (same as bank/bags)
	local mailItems = {}
	for _, item in pairs(mailItemsTable) do
		table.insert(mailItems, item)
	end

	-- Verify mailItems is a proper sequential array
	GBCR.Output:Debug("INVENTORY", "Created mail items array with %d items", #mailItems)
	for i = 1, math.min(3, #mailItems) do
		if mailItems[i] then
			GBCR.Output:Debug("INVENTORY", "  [%d] itemId=%s, itemCount=%s", i, tostring(mailItems[i].itemId), tostring(mailItems[i].itemCount))
		end
	end

	-- Build result structure
	local result = mailItems

	-- Verify result structure
	GBCR.Output:Debug("INVENTORY", "Mail result structure: items type=%s, length=%d", type(result), #result)
	GBCR.Output:Debug("INVENTORY", "Mail scan complete: %d unique items across %d mail messages", #mailItems, numItems)

	return result
end

function Inventory:Scan()
    if self.eventsRegistered then
        if not hasUpdated() then
            return
        end
    end

    local info = GBCR.Database.savedVariables
    if not info then
        return
    end

    local guildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
	if not guildBankAlts or #guildBankAlts == 0 then
		return
	end

	local player = GBCR.Guild:GetNormalizedPlayer()
    local isBank = false
	for i = 1, #guildBankAlts do
        local guildBankAltName = guildBankAlts[i]
        local normV = GBCR.Guild:NormalizeName(guildBankAltName) or guildBankAltName
        if normV == player then
            isBank = true
            break
        end
    end
	if not isBank then
		return
	end

    if not GBCR.Options:GetInventoryTrackingEnabled() then
		return
	end

	local alt = {}
	if info.alts and info.alts[player] then
		alt = info.alts[player]
	end

    -- Initialize persistent storage if needed
	if not alt.cache then alt.cache = {} end
    if not alt.cache.bank then alt.cache.bank = { items = {} } end
    if not alt.cache.bags then alt.cache.bags = { items = {} } end
    if not alt.cache.mail then alt.cache.mail = { items = {} } end

    -- Scan bank if available, otherwise keep existing data
    if isBankAvailable() then
        local bankData = {}
        scanBank(bankData)
        alt.cache.bank.items = bankData
    end

	-- Scan bags (always available)
	local bagData = {}
	scanBags(bagData)
    alt.cache.bags.items = bagData

	-- Scan money (always available)
	local money = GetMoney()
	alt.money = money

	-- Scan mail inventory if mail was accessed
	local mailData = nil
	GBCR.Output:Debug("INVENTORY", "Mail scan for %s (mailHasUpdated=%s)", player, tostring(self.mailHasUpdated))
	if self.mailHasUpdated then
		GBCR.Output:Debug("INVENTORY", "Starting mail scan for %s", player)
		mailData = scanMailInventory()
        if mailData then
            alt.cache.mail.items = mailData
        end
		GBCR.Output:Debug("INVENTORY", "Clearing mailHasUpdated flag after successful scan")
		self.mailHasUpdated = false
	end

	-- Aggregate bank + bags + mail into alt.items
	self:RecalculateAggregatedItems(alt.cache.bank.items, alt.cache.bags.items, alt.cache.mail.items, alt)

	local previousItemsHash = alt.itemsHash

	-- Compute hash of the current inventory state
	local currentItemsHash = self:ComputeItemsHash(alt.items, money)
	alt.itemsHash = currentItemsHash
	if (not previousItemsHash and currentItemsHash) or currentItemsHash ~= previousItemsHash then
		alt.version = GetServerTime()
		GBCR.Output:Debug("INVENTORY", "Inventory changed for %s, version updated to %d (itemsHash=%s)", player, alt.version, tostring(currentItemsHash))
	else
		GBCR.Output:Debug("INVENTORY", "No inventory changes for %s, version unchanged (itemsHash=%s)", player, tostring(currentItemsHash))
	end

	-- Write to GBCR.Database.savedVariables for normal use
	if not info.alts then
		info.alts = {}
	end
	info.alts[player] = alt

    -- Always share inventory with guild after a scan
    GBCR.Protocol:Share()
end

function Inventory:OnUpdateStart()
    self.hasUpdated = true
end

function Inventory:OnUpdateStop()
	GBCR.Output:Debug("INVENTORY", "OnUpdateStop called, hasUpdated=%s", tostring(self.hasUpdated))
    if self.hasUpdated then
		GBCR.Output:Debug("INVENTORY", "Calling scan")
        self:Scan()
		GBCR.Output:Debug("INVENTORY", "Scan completed")
		GBCR.UI:QueueUIRefresh()
	else
		GBCR.Output:Debug("INVENTORY", "Skipping scan because hasUpdated is false")
    end
    self.hasUpdated = false
end

-- Recalculate aggregate alt.items from bank, bags, mail, and money
function Inventory:RecalculateAggregatedItems(bankData, bagData, mailData, alt)
	local bankItems = {}
	if bankData then
		local deduped = Inventory:Aggregate(bankData, nil)
		for _, item in pairs(deduped) do
			table.insert(bankItems, item)
		end
	end

	local bagItems = {}
	if bagData then
		local deduped = Inventory:Aggregate(bagData, nil)
		for _, item in pairs(deduped) do
			table.insert(bagItems, item)
		end
	end

	local mailItems = {}
	if mailData then
		local deduped = Inventory:Aggregate(mailData, nil)
		for _, item in pairs(deduped) do
			table.insert(mailItems, item)
		end
	end

	-- Aggregate all three sources
	GBCR.Output:Debug("INVENTORY", "Before aggregation of items: bank=%d, bags=%d, and mail=%d", #bankItems, #bagItems, #mailItems)
	local aggregated = Inventory:Aggregate(bankItems, bagItems)
	GBCR.Output:Debug("INVENTORY", "After aggregating bank + bags: %d unique items", Globals:Count(aggregated))
	aggregated = Inventory:Aggregate(aggregated, mailItems)
	GBCR.Output:Debug("INVENTORY", "After adding mail: %d unique items", Globals:Count(aggregated))

	-- Convert table to array format
	alt.items = {}
	for _, item in pairs(aggregated) do
		if item.itemId then
			table.insert(alt.items, item)
		end
	end

	GBCR.Output:Debug("INVENTORY", "After aggregation of items: bank=%d, bags=%d, mail=%d, total=%d", #bankItems, #bagItems, #mailItems, #alt.items)
end

-- Compute an immproved hash of inventory state to detect changes considering enchant/suffix for weapons/gear
function Inventory:ComputeItemsHash(items, money)
	local parts = {}
	table.insert(parts, tostring(money))

	-- Hash aggregated items directly
	local function hashItems(itemsArray)
		if not itemsArray or type(itemsArray) ~= "table" then
			return ""
		end

		local sorted = {}
		for _, item in ipairs(itemsArray) do
			if item and item.itemId and item.itemId > 0 then
				local itemCount = item.itemCount or 1
				local itemIdentity = tostring(item.itemId)

				-- For weapons/armor, include link key to catch suffix differences
				if item.itemLink and Inventory:NeedsLink(item.itemLink) then
					local linkKey = Inventory:GetItemKey(item.itemLink)
					if linkKey and linkKey ~= "" then
						itemIdentity = linkKey
					end
				end

				table.insert(sorted, string.format("%s:%d", itemIdentity, itemCount))
			end
		end
		table.sort(sorted)

		return table.concat(sorted, ",")
	end

	table.insert(parts, "I:" .. hashItems(items))
	local combined = table.concat(parts, "|")

	-- Inline checksum
	if type(combined) ~= "string" then
		return 0
	end

	local sum = 0
	local len = #combined
	for i = 1, len do
		local byte = string.byte(combined, i)
		sum = (sum * 31 + byte) % 2147483647
	end

	-- Include length to catch truncation
	sum = (sum * 31 + len) % 2147483647

	return sum
end

---

-- Check if an item needs its itemLink preserved based on item class
function Inventory:NeedsLink(itemLink)
	if not itemLink then
        return false
    end

   	local classID = select(12, GetItemInfo(itemLink))

	-- If item isn't cached, preserve the itemLink to avoid losing suffix data
	if classID == nil then
		return true
	end

	-- Gear (weapons/armor) can have random suffixes, so itemLink is required
	if itemClassesNeedingLink[classID] == true then
		return true
	end

	-- Other items don't vary, so itemLink can be stripped
	return false
end

function Inventory:SplitItemString(str)
   local parts = {}
   local start = 1

   while true do
      local colonPos = string.find(str, ":", start, true)

      if colonPos then
         table.insert(parts, string.sub(str, start, colonPos - 1))
         start = colonPos + 1
      else
         table.insert(parts, string.sub(str, start))
         break
      end
   end

   return parts
end

-- Get normalized item key for deduplication
-- Format: itemId:enchant:suffix (3 parts)
function Inventory:GetItemKey(itemLink)
	if not itemLink or itemLink == "" then
		return ""
	end

	local itemString = itemLink:match("|Hitem:([^|]+)|h")
	if not itemString then
		return ""
	end

	local parts = self:SplitItemString(itemString)

	local itemId = parts[1]
	local enchant = parts[2]
	local suffix = parts[7]

	-- Return itemId, itemId:enchant, itemId::suffix, or itemId:enchant:suffix
	-- While unique (the 8th part) contains content, just the itemId + enchant + suffix are sufficient to recreate the corect item link
	if suffix and suffix ~= "" and suffix ~= "0" then
		return table.concat({itemId, enchant or "", suffix}, ":")
	elseif enchant and enchant ~= "" and enchant ~= "0" then
		return table.concat({itemId, enchant}, ":")
	else
		return itemId
	end
end

function Inventory:GetItems(items, callback)
	if not items or type(items) ~= "table" then
		callback({})

		return
	end

    -- Only consider items that have a valid itemId
    local total = 0
	local validItems = {}
	for idx, item in pairs(items) do
		-- Log every item we encounter to identify corrupted data
		if not item then
			GBCR.Output:Debug("ITEM", "Skipping nil item at index %s", tostring(idx))
		elseif type(item) ~= "table" then
			GBCR.Output:Debug("ITEM", "Skipping non-table item at index %s (type=%s)", tostring(idx), type(item))
		elseif not item.itemId then
			GBCR.Output:Debug("ITEM", "Skipping item with nil itemId at index %s", tostring(idx))
		elseif type(item.itemId) ~= "number" then
			GBCR.Output:Debug("ITEM", "Skipping item with non-number itemId at index %s (itemId=%s, type=%s)", tostring(idx), tostring(item.itemId), type(item.itemId))
		elseif item.itemId <= 0 then
			GBCR.Output:Debug("ITEM", "Skipping corrupted item with invalid itemId at index %s (itemId=%d)", tostring(idx), item.itemId)
		else
			-- Valid item - add to processing list
			total = total + 1
			table.insert(validItems, { original = item, itemId = item.itemId, itemLink = item.itemLink })
		end
	end

    local list = {}
    local count = 0
	local processed = 0 -- Track total items processed (success + failures)
	local callbackFired = false -- Ensure callback only fires once
	local pendingAsync = 0 -- Track items waiting for async load

    -- If there are no valid items to load, return an empty list immediately
    if total == 0 then
        callback(list)

        return
    end

	local function checkComplete()
		if not callbackFired and processed >= total and pendingAsync == 0 then
			callbackFired = true
			callback(list)
		end
	end

	for _, wrapper in ipairs(validItems) do
		local itemId = wrapper.itemId
		local itemLink = wrapper.itemLink
		local item = wrapper.original

		-- Log what we're about to process
		GBCR.Output:Debug("ITEM", "Processing wrapper: itemId=%s, itemLink=%s, originalItemId=%s", tostring(itemId), tostring(itemLink), tostring(item and item.itemId or "nil item"))

		-- Final safety check before calling WoW API
		if not itemId or type(itemId) ~= "number" or itemId <= 0 then
			GBCR.Output:Debug("ITEM", "Skipping invalid: itemId=%s (type=%s)", tostring(itemId), type(itemId))
			processed = processed + 1
			checkComplete()
		else
			-- Capture itemId in local scope to prevent closure corruption
			local capturedItemId = itemId
			local capturedItemLink = itemLink
			local capturedItem = item

			-- Double-check captured values
			if not capturedItemId or type(capturedItemId) ~= "number" or capturedItemId <= 0 then
				GBCR.Output:Debug("ITEM", "ERROR: itemId validation failed after capture!")
				processed = processed + 1
				checkComplete()
			else
				if capturedItemLink then
					GBCR.Output:Debug("ITEM", "Item %d has itemLink, using directly", capturedItemId)
					if not capturedItem.itemInfo then
						local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(capturedItemLink)
						if name then
							GBCR.Output:Debug("ITEM", "Item %d already cached", capturedItemId)
							local equip = GetItemInventoryTypeByID(capturedItemId)
							capturedItem.itemInfo = { class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon }
						end
					end
					table.insert(list, capturedItem)
					count = count + 1
					processed = processed + 1
				else
					-- Check if item data is already cached (fast path)
					local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(capturedItemId)
					if name then
						GBCR.Output:Debug("ITEM", "Item %d already cached", capturedItemId)
						local equip = GetItemInventoryTypeByID(capturedItemId)
						capturedItem.itemInfo = { class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon }
						table.insert(list, capturedItem)
						count = count + 1
						processed = processed + 1
					else
						-- TODO: remove
						GBCR.Output:Error("ITEM", "Item %d not cached, how is this possible? We're calling GBCR.Protocol:ReconstructItemLinks on load and on receipt of data.", capturedItemId)
					end
				end
			end
		end
	end

	-- After processing all items, check if we can fire callback (handles case where all items had links and were processed synchronously)
	checkComplete()
end

function Inventory:GetInfo(itemId, itemLink)
	local name, rarity, level, icon, price, itemClassId, itemSubClassId, _

	-- Try itemLink first if available
	if itemLink and itemLink ~= "" then
		name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(itemLink)
	end

	-- Fallback to itemId if itemLink didn't work
	if not name and itemId and itemId > 0 then
		name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(itemId)
	end

	-- If still no data, return basic info with itemId only and the default grey question mark icon
	if not name then
		return { class = 0, subClass = 0, equipId = 0, rarity = 1, name = "Item " .. tostring(itemId or "?"), level = 1, price = 0, icon = 134400 }
	end

    local equip = GetItemInventoryTypeByID(itemId)

	return { class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon }
end

function Inventory:Sort(items, mode)
	for _, item in ipairs(items) do
		if not item.itemInfo then
			item.itemInfo = { class = 0, subClass = 0, equipId = 0, rarity = 1, name = item.itemLink and item.itemLink:match("%[(.-)%]") or ("Item " .. tostring(item.itemId or "?")), level = 1, price = 0, icon = 134400 }
		elseif not item.itemInfo.class then
			item.itemInfo.class = item.itemInfo.class or 0
			item.itemInfo.subClass = item.itemInfo.subClass or 0
			item.itemInfo.equipId = item.itemInfo.equipId or 0
			item.itemInfo.rarity = item.itemInfo.rarity or 1
			item.itemInfo.level = item.itemInfo.level or 1
			item.itemInfo.price = item.itemInfo.price or 0
			item.itemInfo.name = item.itemInfo.name or (item.itemLink and item.itemLink:match("%[(.-)%]")) or ("Item " .. tostring(item.itemId or "?"))
		end
	end

    local comparator = Constants.COMPARATORS[mode] or Constants.COMPARATORS.default
    table.sort(items, comparator)
end

function Inventory:Aggregate(a, b)
    local items = {}
    local itemsByID = {}
    local itemsByKey = {}

    local function processItem(v)
        if type(v) ~= "table" or not v.itemId then
            -- Skip malformed entries
            return
        end

        -- Ensure itemCount is set
        v.itemCount = v.itemCount or 1

        -- Define a key for deduplication
		local idStr = tostring(v.itemId)
		local key = idStr

		-- For weapons/armor, include enchant and suffix differences
		if v.itemLink then
			if self:NeedsLink(v.itemLink) then
				local linkKey = self:GetItemKey(v.itemLink)
				if linkKey and linkKey ~= "" then
					key = linkKey
				end
			else
				v.itemLink = nil
			end
		end

        -- Skip if we already have this exact key
        if itemsByKey[key] then
            local existingItem = itemsByKey[key]
            existingItem.itemCount = existingItem.itemCount + v.itemCount
            local existingItemLink = existingItem.itemLink or v.itemLink
			if self:NeedsLink(existingItemLink) then
				existingItem.itemLink = existingItemLink
			end

            return
        end

        if key and not itemsByKey[key] then
            items[key] = { itemId = v.itemId, itemCount = v.itemCount, itemLink = v.itemLink, itemInfo = v.itemInfo }
            itemsByKey[key] = items[key]
            if not itemsByID[idStr] then
                itemsByID[idStr] = {}
            end
            table.insert(itemsByID[idStr], key)
        end
    end

    if a then
		-- Handle both array and hash table formats
        if type(a) == "table" and a[1] then
            for _, v in ipairs(a) do
				processItem(v)
            end
        else
            for _, v in pairs(a) do
				processItem(v)
            end
        end
    end

    if b then
		-- Handle both array and hash table formats
        if type(b) == "table" and b[1] then
            for _, v in ipairs(b) do
                processItem(v)
            end
		else
            for _, v in pairs(b) do
                processItem(v)
            end
        end
    end

    -- Convert hash table to array for return value
    local result = {}
    for _, item in pairs(items) do
        if item and item.itemId then
            table.insert(result, item)
        end
    end

    return result
end

function Inventory:IsUnique(itemLink)
	if not itemLink then
		return false
	end

    local tip = CreateFrame("GameTooltip", "scanTip", UIParent, "GameTooltipTemplate")
    tip:ClearLines()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetHyperlink(itemLink)
	for i = 1, tip:NumLines() do
		local line = _G["scanTipTextLeft" .. i]
        if line and line:IsVisible() then
            local l = line:GetText()
            if l and l:find(ITEM_UNIQUE) then
                return true
            end
        end
    end

    return false
end