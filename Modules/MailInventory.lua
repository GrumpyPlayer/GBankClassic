GBankClassic_MailInventory = GBankClassic_MailInventory or {}

local MailInventory = GBankClassic_MailInventory

MailInventory.hasUpdated = false

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("time")
local time = upvalues.time
local upvalues = Globals.GetUpvalues("GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink", "GetServerTime")
local GetInboxNumItems = upvalues.GetInboxNumItems
local GetInboxHeaderInfo = upvalues.GetInboxHeaderInfo
local GetInboxItem = upvalues.GetInboxItem
local GetInboxItemLink = upvalues.GetInboxItemLink
local GetServerTime = upvalues.GetServerTime
local upvalues = Globals.GetUpvalues("ATTACHMENTS_MAX_RECEIVE")
local ATTACHMENTS_MAX_RECEIVE = upvalues.ATTACHMENTS_MAX_RECEIVE

-- Scans the current mailbox and returns structured mail inventory data
-- Called from Bank:Scan() when mail was accessed (hasUpdated = true)
function MailInventory:ScanMailInventory()
	-- Only scan if mail was accessed this session
	if not self.hasUpdated then
		GBankClassic_Output:Debug("MAIL", "ScanMailInventory called but hasUpdated=false, returning nil")

		return nil
	end
	
	-- Use same structure as bank/bags: aggregate by composite key, store as array
	local mailItemsTable = {}
	local numItems = GetInboxNumItems()
	
	GBankClassic_Output:Debug("MAIL", "Starting mailbox scan: %d mail messages", numItems)
	
	for i = 1, numItems do
		local _, _, sender, _, _, CODAmount, _, hasItem = GetInboxHeaderInfo(i)
		
		-- Skip COD mail (can't take items without payment)
		if hasItem and CODAmount == 0 then
			for j = 1, ATTACHMENTS_MAX_RECEIVE do
				local name, itemID, _, count = GetInboxItem(i, j)
				
				if itemID and name then
					local link = GetInboxItemLink(i, j)
					
					-- Conditionally include link based on item class
					-- Gear (weapons/armor) needs full link for suffix differentiation
					-- Consumables/trade goods don't need link (saves bandwidth in d3 sync)
					local storageLink = nil
					if link and GBankClassic_Item:NeedsLink(link) then
						storageLink = link -- Store full link for gear
					end
					
					-- Use normalized key for deduplication (strips unique instance ID)
					-- This allows identical items to merge even if they have different instance IDs
					local itemKey = GBankClassic_Item:GetItemKey(link)
					local key = tostring(itemID) .. itemKey
					
					if mailItemsTable[key] then
						-- Item already exists, add to count
						local item = mailItemsTable[key]
						mailItemsTable[key] = { ID = item.ID, Count = item.Count + count, Link = item.Link or storageLink }
						GBankClassic_Output:Debug("MAIL", "Item %s: merged (key=%s) added %d, total now %d", name, key, count, mailItemsTable[key].Count)
					else
						-- New item
						mailItemsTable[key] = { ID = itemID, Count = count, Link = storageLink }
						GBankClassic_Output:Debug("MAIL", "New item in mailbox: %s (ID: %d, Count: %d, link: %s, Key: %s)", name, itemID, count, storageLink and "preserved" or "stripped", key)
					end
				end
			end
		elseif hasItem and CODAmount > 0 then
			GBankClassic_Output:Debug("MAIL", "Skipping COD mail from %s (COD: %d copper)", sender or "Unknown", CODAmount)
		end
	end
	
	-- Convert to array format (same as bank/bags)
	local mailItems = {}
	for _, item in pairs(mailItemsTable) do
		table.insert(mailItems, item)
	end
	
	-- Verify mailItems is a proper sequential array
	GBankClassic_Output:Debug("MAIL", "Created mail items array with %d items", #mailItems)
	for i = 1, math.min(3, #mailItems) do
		if mailItems[i] then
			GBankClassic_Output:Debug("MAIL", "  [%d] ID=%s, Count=%s", i, tostring(mailItems[i].ID), tostring(mailItems[i].Count))
		end
	end
	
	-- Build result structure (match bank/bags format for consistency)
	local result = {
		slots = { count = #mailItems, total = 50 }, -- Match bank/bags structure
		items = mailItems, -- Now an array like bank/bags
		version = GetServerTime(),
		lastScan = GetServerTime()
	}
	
	-- Verify result structure
	GBankClassic_Output:Debug("MAIL", "Mail result structure: items type=%s, length=%d", type(result.items), #result.items)
	GBankClassic_Output:Debug("MAIL", "Mail result slots.count=%d", result.slots.count)
	GBankClassic_Output:Debug("MAIL", "Mail scan complete: %d unique items across %d mail messages", #mailItems, numItems)
	
	return result
end

-- Returns list of alts that have the specified item in their mail
function MailInventory:GetItemsInMail(itemID)
	local alts = {}
	
	if not GBankClassic_Guild.Info or not GBankClassic_Guild.Info.alts then
		return alts
	end
	
	for name, alt in pairs(GBankClassic_Guild.Info.alts) do
		if alt.mail and alt.mail.items then
			-- Search for matching ID
			for _, item in ipairs(alt.mail.items) do
				if item.ID == itemID then
					table.insert(alts, { name = name, count = item.Count, lastScan = alt.mail.lastScan or 0 })
					break -- Found the item, no need to continue
				end
			end
		end
	end
	
	return alts
end

-- -- Returns total count of item across all alts' mail
-- function MailInventory:GetTotalInMail(itemID)
-- 	local total = 0
-- 	local alts = self:GetItemsInMail(itemID)
	
-- 	for _, alt in ipairs(alts) do
-- 		total = total + alt.count
-- 	end
	
-- 	return total
-- end

-- Returns age of mail scan data in seconds
function MailInventory:GetMailDataAge(alt)
	if not alt or not alt.mail or not alt.mail.lastScan then
		return nil
	end
	
	return time() - alt.mail.lastScan
end

-- -- Checks if alt has mail inventory data
-- function MailInventory:HasMailInventory(alt)
-- 	if not alt or not alt.mail or not alt.mail.items then
-- 		return false
-- 	end
	
-- 	-- Check if there are any items (mail.items is array format)
-- 	return #alt.mail.items > 0
-- end