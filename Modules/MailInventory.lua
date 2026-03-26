GBankClassic_MailInventory = GBankClassic_MailInventory or {}

local MailInventory = GBankClassic_MailInventory

MailInventory.hasUpdated = false

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink", "GetItemInfo")
local GetInboxNumItems = upvalues.GetInboxNumItems
local GetInboxHeaderInfo = upvalues.GetInboxHeaderInfo
local GetInboxItem = upvalues.GetInboxItem
local GetInboxItemLink = upvalues.GetInboxItemLink
local GetItemInfo = upvalues.GetItemInfo
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
					if not link and itemID then
						link = select(2, GetItemInfo(itemID))
					end

					-- Conditionally include link based on item class
					-- Gear (weapons/armor) needs full link for suffix differentiation
					-- Consumables/trade goods don't need link (saves bandwidth)
					local storageLink = nil
					if link and GBankClassic_Item:NeedsLink(link) then
						storageLink = link
					end

					-- Use normalized key for deduplication
					local key = GBankClassic_Item:GetImprovedItemKey(link)

					if mailItemsTable[key] then
						-- Item already exists, add to count
						local item = mailItemsTable[key]
						local newCount = item.Count + count
						mailItemsTable[key] = { ID = item.ID, Count = newCount, Link = item.Link }
						GBankClassic_Output:Debug("MAIL", "Item %s: merged (key=%s) added %d, total now %d", name, key, count, mailItemsTable[key].Count)
					else
						-- New item
						mailItemsTable[key] = { ID = itemID, Count = count, Link = storageLink }
						GBankClassic_Output:Debug("MAIL", "New item in mailbox: %s (ID: %d, Count: %d, Link: %s, Key: %s)", name, itemID, count, storageLink and "preserved" or "stripped", key)
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

	-- Build result structure
	local result = mailItems

	-- Verify result structure
	GBankClassic_Output:Debug("MAIL", "Mail result structure: items type=%s, length=%d", type(result), #result)
	GBankClassic_Output:Debug("MAIL", "Mail scan complete: %d unique items across %d mail messages", #mailItems, numItems)

	return result
end