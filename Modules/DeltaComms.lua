GBankClassic_DeltaComms = GBankClassic_DeltaComms or {}

local DeltaComms = GBankClassic_DeltaComms

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("GetServerTime", "debugprofilestop", "UnitName", "GetNormalizedRealmName")
local GetServerTime = upvalues.GetServerTime
local debugprofilestop = upvalues.debugprofilestop
local UnitName = upvalues.UnitName
local GetNormalizedRealmName = upvalues.GetNormalizedRealmName

-- Validate that a delta structure is well-formed
function DeltaComms:ValidateDeltaStructure(delta)
	if not delta or type(delta) ~= "table" then
		return false, "delta is not a table"
	end

	-- Check required fields
	if delta.type ~= "alt-delta" then
		return false, "invalid delta type"
	end

	if not delta.name or type(delta.name) ~= "string" then
		return false, "missing or invalid name"
	end

	if not delta.version or type(delta.version) ~= "number" then
		return false, "missing or invalid version"
	end

	if delta.inventoryHash and type(delta.inventoryHash) ~= "number" then
		return false, "invalid inventoryHash"
	end

	if delta.updatedAt and type(delta.updatedAt) ~= "number" then
		return false, "invalid updatedAt"
	end

	if delta.baseVersion and type(delta.baseVersion) ~= "number" then
		return false, "invalid baseVersion"
	end

	if not delta.changes or type(delta.changes) ~= "table" then
		return false, "missing or invalid changes"
	end

	-- Validate changes structure
	local changes = delta.changes

	-- Money is optional but must be number if present
	if changes.money and type(changes.money) ~= "number" then
		return false, "invalid money in changes"
	end

	-- Validate items delta if present
	if changes.items then
		local valid, err = self:ValidateItemDelta(changes.items)
		if not valid then
			return false, "invalid items delta: " .. err
		end
	end

	return true
end

-- Validate an item delta structure (added/modified/removed)
function DeltaComms:ValidateItemDelta(itemDelta)
	if not itemDelta or type(itemDelta) ~= "table" then
		return false, "itemDelta is not a table"
	end

	-- Check added array
	if itemDelta.added then
		if type(itemDelta.added) ~= "table" then
			return false, "added is not a table"
		end

		for _, item in pairs(itemDelta.added) do
			if type(item) ~= "table" then
				return false, "added item is not a table"
			end
			if not item.ID or type(item.ID) ~= "number" then
				return false, "added item missing or invalid ID"
			end
			if item.Link and type(item.Link) ~= "string" then
				return false, "added item has invalid link"
			end
		end
	end

	-- Check modified array
	if itemDelta.modified then
		if type(itemDelta.modified) ~= "table" then
			return false, "modified is not a table"
		end

		for _, item in pairs(itemDelta.modified) do
			if type(item) ~= "table" then
				return false, "modified item is not a table"
			end
			if not item.ID or type(item.ID) ~= "number" then
				return false, "modified item missing or invalid ID"
			end
			if item.Link and type(item.Link) ~= "string" then
				return false, "modified item has invalid link"
			end
		end
	end

	-- Check removed array
	if itemDelta.removed then
		if type(itemDelta.removed) ~= "table" then
			return false, "removed is not a table"
		end

		for _, item in pairs(itemDelta.removed) do
			if type(item) ~= "table" then
				return false, "removed item is not a table"
			end
			if not item.ID or type(item.ID) ~= "number" then
				return false, "removed item missing or invalid ID"
			end
		end
	end

	return true
end

-- Compute a hash of inventory state to detect actual changes
-- Only updates version timestamps when this hash changes
function DeltaComms:ComputeInventoryHash(bank, bags, mailOrMoney, money)
	-- Handle multiple calling conventions:
	-- 2.6.0+ (aggregated): ComputeInventoryHash(items, nil, nil, money) - items is direct array
	-- Pre 2.6.0: ComputeInventoryHash(bank, bags, money) - bank/bags have .items, no mail
	
	-- Detect aggregated call: first param is array, second is nil
	if bank and type(bank) == "table" and bags == nil and mailOrMoney == nil then
		-- Bank is actually the aggregated items array, money is the 4th param
		local items = bank
		local actualMoney = money or 0
		
		local parts = {}
		table.insert(parts, tostring(actualMoney))
		
		-- Hash aggregated items directly
		local function hashItems(itemsArray)
			if not itemsArray or type(itemsArray) ~= "table" then
				return ""
			end

			local sorted = {}
			for _, item in ipairs(itemsArray) do
				if item and item.ID then
					table.insert(sorted, string.format("%d:%d", item.ID, item.Count or 0))
				end
			end
			table.sort(sorted)

			return table.concat(sorted, ",")
		end
		
		table.insert(parts, "I:" .. hashItems(items))
		local combined = table.concat(parts, "|")

		return GBankClassic_Core:Checksum(combined)
	end
	
	-- Legacy calling convention: ComputeInventoryHash(bank, bags, money)
	-- Parameter mailOrMoney is actually money (number), no mail parameter exists
	local actualMoney = mailOrMoney or 0
	local parts = {}

	-- Include money
	table.insert(parts, tostring(actualMoney))

	-- Helper to hash an items array
	local function hashItems(items)
		if not items or type(items) ~= "table" then
			return ""
		end

		-- Sort items by ID+Count to get consistent order
		local sorted = {}
		for _, item in ipairs(items) do
			if item and item.ID then
				table.insert(sorted, string.format("%d:%d", item.ID, item.Count or 0))
			end
		end
		table.sort(sorted)

		return table.concat(sorted, ",")
	end

	-- Include bank items
	if bank and bank.items then
		table.insert(parts, "B:" .. hashItems(bank.items))
	end

	-- Include bag items
	if bags and bags.items then
		table.insert(parts, "G:" .. hashItems(bags.items))
	end

	-- Concatenate all parts and compute simple hash
	local combined = table.concat(parts, "|")

	-- Use same hash function as checksum for consistency
	local sum = 0
	local len = #combined
	for i = 1, len do
		local byte = string.byte(combined, i)
		sum = (sum * 31 + byte) % 2147483647
	end
	sum = (sum * 31 + len) % 2147483647

	return sum
end

-- Strip links from delta for bandwidth savings
function DeltaComms:StripDeltaLinks(delta)
	if not delta or not delta.changes then
		return nil
	end

	local function stripItemArray(items)
		if not items then
			return nil
		end

		local stripped = {}
		for _, item in ipairs(items) do
			local strippedItem = {
				ID = item.ID,
				Count = item.Count
			}
			-- Preserve link
			if item.Link and GBankClassic_Item:NeedsLink(item.Link) then
				strippedItem.Link = item.Link
			end
			-- Preserve info if present (for modified items)
			if item.Info then
				strippedItem.Info = item.Info
			end
			table.insert(stripped, strippedItem)
		end

		return stripped
	end

	local strippedDelta = {
		type = delta.type,
		name = delta.name,
		version = delta.version,
		updatedAt = delta.updatedAt,
		inventoryHash = delta.inventoryHash,
		changes = {}
	}

	-- Copy money change (no link to strip)
	if delta.changes.money then
		strippedDelta.changes.money = delta.changes.money
	end

	-- Copy mailHash change
	if delta.changes.mailHash then
		strippedDelta.changes.mailHash = delta.changes.mailHash
	end

	-- Strip links from items changes
	if delta.changes.items then
		strippedDelta.changes.items = {
			added = stripItemArray(delta.changes.items.added),
			modified = stripItemArray(delta.changes.items.modified),
			removed = stripItemArray(delta.changes.items.removed)
		}
	end

	return strippedDelta
end

-- Compare two items for equality
function DeltaComms:ItemsEqual(item1, item2)
	if not item1 and not item2 then
		return true
	end
	if not item1 or not item2 then
		return false
	end

	-- Compare key fields
	if item1.ID ~= item2.ID then
		return false
	end
	if item1.Count ~= item2.Count then
		return false
	end

	if item1.Link ~= nil and item2.Link ~= nil then
		if item1.Link ~= item2.Link then
			return false
		end
	end

	-- Compare info table if present (deep comparison)
	if item1.Info or item2.Info then
		if not item1.Info or not item2.Info then
			return false
		end
		for k, v in pairs(item1.Info) do
			if item2.Info[k] ~= v then
				return false
			end
		end
		for k, v in pairs(item2.Info) do
			if item1.Info[k] ~= v then
				return false
			end
		end
	end

	return true
end

-- Extract only the fields that changed between two items
function DeltaComms:GetChangedFields(oldItem, newItem)
	-- Always include ID and link for identification (merged items use these as keys)
	local changes = {
		ID = newItem.ID,
		Link = newItem.Link
	}

	-- Include changed fields
	if oldItem.Count ~= newItem.Count then
		changes.Count = newItem.Count
	end
	if oldItem.Info or newItem.Info then
		if not oldItem.Info or not newItem.Info or not self:ItemsEqual(oldItem, newItem) then
			changes.Info = newItem.Info
		end
	end

	return changes
end

-- Build a slot-indexed lookup table from items array
function DeltaComms:BuildItemIndex(items)
	local index = {}
	if not items then
		return index
	end

	for _, item in pairs(items) do
		if item and item.ID then
			if item.Link then
				local normalizedKey = GBankClassic_Item:GetItemKey(item.Link)
				local key = tostring(item.ID) .. normalizedKey
				index[key] = item
			else
				local key = tostring(item.ID)
				if not index[key] then
					index[key] = item
				end
			end
		end
	end

	return index
end

-- Compute delta between old and new item sets
function DeltaComms:ComputeItemDelta(oldItems, newItems)
	local delta = { added = {}, modified = {}, removed = {} }

	oldItems = oldItems or {}
	newItems = newItems or {}

	-- Build item index for old items by itemID + link key
	local oldByKey = self:BuildItemIndex(oldItems)
	
	-- Build ID-only lookup for items without links (from minimal baselines)
	local oldByIDOnly = {}
	for _, item in pairs(oldItems) do
		if item and item.ID and not (item.Link or item.ItemString) then
			oldByIDOnly[tostring(item.ID)] = item
		end
	end

	-- Find added and modified items
	local deepFallbackUsed = {}
	for _, newItem in pairs(newItems) do
		if newItem and newItem.ID then
			local key
			local oldItem = nil
			local usedDeepFallback = false
			
			if newItem.Link then
				local normalizedKey = GBankClassic_Item:GetItemKey(newItem.Link)
				key = tostring(newItem.ID) .. normalizedKey
				oldItem = oldByKey[key]
				
				if not oldItem then
					oldItem = oldByIDOnly[tostring(newItem.ID)]
					if oldItem then
						key = tostring(newItem.ID)
					end
				end
				
				if not oldItem then
					for _, item in pairs(oldItems) do
						if item and item.ID == newItem.ID and not deepFallbackUsed[item] then
							oldItem = item
							key = tostring(newItem.ID)
							usedDeepFallback = true
							deepFallbackUsed[item] = true
							break
						end
					end
				end
			else
				-- Minimal item without Link - use ID-only key
				key = tostring(newItem.ID)
				oldItem = oldByKey[key] or oldByIDOnly[key]
			end

			if not oldItem then
				-- Item was added
				table.insert(delta.added, newItem)
			elseif not self:ItemsEqual(oldItem, newItem) then
				-- Item was modified (quantity or other field changed)
				table.insert(delta.modified, self:GetChangedFields(oldItem, newItem))
			end

			-- Mark as processed
			if key then
				oldByKey[key] = nil
				oldByIDOnly[key] = nil
			end
			if usedDeepFallback and oldItem then
				for k, v in pairs(oldByKey) do
					if v == oldItem then
						oldByKey[k] = nil
						break
					end
				end
				local idKey = tostring(oldItem.ID)
				if oldByIDOnly[idKey] == oldItem then
					oldByIDOnly[idKey] = nil
				end
			end
		end
	end

	-- Remaining old items were removed
	for _, item in pairs(oldByKey) do
		local removed = { ID = item.ID }
		if item.Link then
			removed.Link = item.Link
		end
		table.insert(delta.removed, removed)
	end
	for _, item in pairs(oldByIDOnly) do
		table.insert(delta.removed, { ID = item.ID })
	end

	return delta
end

-- Compute full delta for an alt
function DeltaComms:ComputeDelta(guildName, altName, currentAlt, requesterInventoryHash, requesterMailHash, requesterBaseline)
	if not guildName or not altName or not currentAlt then
		return nil
	end

	-- Compute delta using requester's actual baseline from state summary
	local previous = nil
	local currentHash = currentAlt.inventoryHash or 0
	local currentMailHash = currentAlt.mailHash or 0
	requesterMailHash = requesterMailHash or 0

	if requesterInventoryHash and requesterInventoryHash ~= 0 then
		-- Requester has data - check if it matches current (both inventory AND mail)
		if requesterInventoryHash == currentHash and requesterMailHash == currentMailHash then
			-- Hash match (both hashes) - no changes needed (empty delta)
			GBankClassic_Output:Debug("DELTA", "Hash match: requester inv=%d mail=%d, guild bank alt inv=%d mail=%d (no changes)", requesterInventoryHash, requesterMailHash, currentHash, currentMailHash)
			previous = currentAlt -- Use current as previous (results in empty delta)
		elseif requesterInventoryHash == currentHash and requesterMailHash ~= currentMailHash then
			-- Inventory matches but mail changed - use requester's actual baseline if available
			if requesterBaseline then
				previous = {
					items = requesterBaseline.items,
					money = requesterBaseline.money or 0,
					mailHash = requesterMailHash,
				}
				GBankClassic_Output:Debug("DELTA", "Mail changed: using requester's actual baseline (items=%d)", #previous.items)
			else
				-- No requester baseline - cannot compute accurate delta
				-- Force full sync by using empty baseline instead
				previous = { items = {}, money = 0, mailHash = 0, bank = { items = {} }, bags = { items = {} }, mail = { items = {} } }
				GBankClassic_Output:Warn("DELTA", "[Missing requester baseline (mail change) - forcing full sync for %s (mail=%d->%d)", altName, requesterMailHash, currentMailHash)
			end
		else
			-- Hash mismatch - use requester's actual baseline if available
			if requesterBaseline then
				previous = {
					items = requesterBaseline.items,
					money = requesterBaseline.money or 0,
					mailHash = requesterMailHash,
				}
				GBankClassic_Output:Debug("DELTA", "Using requester's actual baseline: inv=%d->%d (items=%d)", requesterInventoryHash, currentHash, #previous.items)
			else
				-- No requester baseline - cannot compute accurate delta
				-- Force full sync by using empty baseline instead
				previous = { items = {}, money = 0, mailHash = 0 }
				GBankClassic_Output:Warn("DELTA", "Missing requester baseline - forcing full sync for %s (hash=%d->%d)", altName, requesterInventoryHash or 0, currentHash)
			end
		end
	else
		-- Requester has no data (hash 0 or nil) - send everything as delta additions
		previous = { items = {}, money = 0, mailHash = 0 }
		GBankClassic_Output:Debug("DELTA", "Requester has no data (hash=%s), sending all as additions", tostring(requesterInventoryHash))
	end

	if not previous then
		return nil
	end

	-- Build delta structure
	-- In pull-based protocol, receiver states what they have
	local delta = {
		type = "alt-delta",
		name = altName,
		version = currentAlt.version or GetServerTime(),
		updatedAt = currentAlt.inventoryUpdatedAt or currentAlt.version or GetServerTime(),
		inventoryHash = currentAlt.inventoryHash or 0,
		changes = {},
	}

	-- Money change
	if currentAlt.money ~= previous.money then
		delta.changes.money = currentAlt.money
	end

	-- Track mailHash changes so receivers can detect mail updates
	if currentAlt.mailHash ~= previous.mailHash then
		delta.changes.mailHash = currentAlt.mailHash
		GBankClassic_Output:Debug("DELTA", "Mail hash changed for %s: %s -> %s", altName, tostring(previous.mailHash), tostring(currentAlt.mailHash))
	end

	-- Compute delta for items
	local previousItems = previous.items or {}
	local currentItems = currentAlt.items or {}
	delta.changes.items = self:ComputeItemDelta(previousItems, currentItems)

	-- Log what's being sent
	GBankClassic_Output:Debug("DELTA", "Delta for %s: items=%d->%d", altName, #previousItems, #currentItems)

	return delta
end

-- Check if delta has any actual changes
function DeltaComms:DeltaHasChanges(delta)
	if not delta or not delta.changes then
		return false
	end

	local changes = delta.changes

	-- Check money change
	if changes.money then
		return true
	end

	-- Check mailHash change
	if changes.mailHash ~= nil then
		return true
	end

	-- Check bank changes
	if changes.bank then
		if next(changes.bank.added) or next(changes.bank.modified) or next(changes.bank.removed) then
			return true
		end
	end

	-- Check bags changes
	if changes.bags then
		if next(changes.bags.added) or next(changes.bags.modified) or next(changes.bags.removed) then
			return true
		end
	end

	-- Check mail changes
	if changes.mail then
		if next(changes.mail.added) or next(changes.mail.modified) or next(changes.mail.removed) then
			return true
		end
	end

	-- Check items changes
	if changes.items then
		if next(changes.items.added) or next(changes.items.modified) or next(changes.items.removed) then
			return true
		end
	end

	return false
end

-- Apply item delta to an items table
function DeltaComms:ApplyItemDelta(items, delta)
	if not items or not delta then
		return false
	end

	-- Build current items index by itemKey
	local itemsByKey = self:BuildItemIndex(items)
	
	-- Build ID-only lookup for items without Links
	local itemsByIDOnly = {}
	for _, item in pairs(items) do
		if item and item.ID and not (item.Link) then
			itemsByIDOnly[tostring(item.ID)] = item
		end
	end

	-- Remove items
	if delta.removed then
		for _, removedItem in ipairs(delta.removed) do
			if removedItem and removedItem.ID then
				-- Match by ID only (link field removed)
				if removedItem.Link then
					local normalizedRemovedKey = GBankClassic_Item:GetItemKey(removedItem.Link)
					local key = tostring(removedItem.ID) .. normalizedRemovedKey
					for i = #items, 1, -1 do
						local item = items[i]
						if item and item.ID and (item.Link) then
							local normalizedItemKey = GBankClassic_Item:GetItemKey(item.Link)
							local itemKey = tostring(item.ID) .. normalizedItemKey
							if itemKey == key then
								table.remove(items, i)
								break
							end
						end
					end
				else
					for i = #items, 1, -1 do
						local item = items[i]
						if item and item.ID == removedItem.ID then
							table.remove(items, i)
							break
						end
					end
				end
			end
		end
	end

	-- Modify existing items
	if delta.modified then
		for _, changes in ipairs(delta.modified) do
			if changes and changes.ID then
				local existingItem = nil
				
				if changes.Link then
					local normalizedKey = GBankClassic_Item:GetItemKey(changes.Link)
					local key = tostring(changes.ID) .. normalizedKey
					existingItem = itemsByKey[key]
					
					-- Check ID-only index if not found
					if not existingItem then
						existingItem = itemsByIDOnly[tostring(changes.ID)]
					end
				else
					-- Minimal item without link
					local key = tostring(changes.ID)
					existingItem = itemsByKey[key] or itemsByIDOnly[key]
				end

				if existingItem then
					-- Apply changed fields to existing item
					for field, value in pairs(changes) do
						existingItem[field] = value
					end
				else
					-- Item doesn't exist (shouldn't happen), add as new
					local guardBlock = false
					if not changes.Link then
						local needsLink = GBankClassic_Item:NeedsLink(changes.ID)
						if needsLink == true then
							guardBlock = true
							GBankClassic_Output:Debug("DELTA", "Blocked linkless modified-as-new weapon/armor ID=%d", changes.ID)
						elseif needsLink == nil then
							-- Class not cached; block if any linked entry already exists for this base ID
							for _, existingEntry in ipairs(items) do
								if existingEntry and existingEntry.ID == changes.ID and existingEntry.Link then
									guardBlock = true
									GBankClassic_Output:Debug("DELTA", "Blocked linkless modified-as-new ID=%d (linked entry exists, class uncached)", changes.ID)
									break
								end
							end
						end
					end
					if not guardBlock then
						table.insert(items, changes)
						GBankClassic_Output:Debug("DELTA", "Modified item not found, adding as new: ID=%d", changes.ID)
					end
				end
			end
		end
	end

	-- Add new items (can invalidate indexes, but no more operations depend on them)
	if delta.added then
		local updated = 0
		local added = 0

		for _, newItem in ipairs(delta.added) do
			if newItem and newItem.ID then
				local existingItem = nil
				local newNormKey = GBankClassic_Item:GetItemKey(newItem.Link)
				local newFullKey = tostring(newItem.ID) .. newNormKey

				-- Exact normalized-key match (distinguishes suffix variants)
				for _, item in ipairs(items) do
					if item and item.ID == newItem.ID then
						local existingNormKey = GBankClassic_Item:GetItemKey(item.Link or "")
						if (tostring(item.ID) .. existingNormKey) == newFullKey then
							existingItem = item
							break
						end
					end
				end

				-- ID-only match only for linkless existing entries
				if not existingItem then
					for _, item in ipairs(items) do
						if item and item.ID == newItem.ID and not item.Link then
							existingItem = item
							break
						end
					end
				end

				if existingItem then
					-- Item exists - update quantities and fields
					existingItem.Count = newItem.Count
					existingItem.Link = newItem.Link or existingItem.Link
					if newItem.Info then
						existingItem.Info = newItem.Info
					end
					updated = updated + 1
				else
					-- Item doesn't exist - add it
					local guardBlock = false
					if not newItem.Link and GBankClassic_Item then
						local needsLink = GBankClassic_Item:NeedsLink(newItem.ID)
						if needsLink == true then
							guardBlock = true
							GBankClassic_Output:Debug("DELTA", "Bocked linkless weapon/armor ID=%d (class confirmed)", newItem.ID)
						elseif needsLink == nil then
							-- Class not cached; block if any linked entry already exists for this base ID
							for _, existingEntry in ipairs(items) do
								if existingEntry and existingEntry.ID == newItem.ID and existingEntry.Link then
									guardBlock = true
									GBankClassic_Output:Debug("DELTA", "Blocked linkless ID=%d (linked entry exists, class uncached)", newItem.ID)
									break
								end
							end
						end
					end
					if not guardBlock then
						table.insert(items, newItem)
						added = added + 1
					end
				end
			end
		end

		GBankClassic_Output:Debug("DELTA", "Applied %d added items (%d updated existing, %d new)", #delta.added, updated, added)
	end

	return true
end

-- Apply a delta to alt data
function DeltaComms:ApplyDelta(guildInfo, altName, deltaData, sender)
	if not guildInfo then
		return ADOPTION_STATUS.IGNORED
	end

	local applyStart = debugprofilestop()
	local norm = GBankClassic_Guild:NormalizeName(altName)
	local current = guildInfo.alts[norm]

	-- Validate base version matches
	if not current then
		-- No existing data: adopt delta against empty baseline to avoid full sync fallback
		if not guildInfo.alts then
			guildInfo.alts = {}
		end
		current = {
			name = norm,
			version = 0,
			money = 0,
			items = {},
			inventoryHash = 0,
			inventoryUpdatedAt = 0,
			mailHash = 0,
		}
		guildInfo.alts[norm] = current
		GBankClassic_Output:Debug("DELTA", "No existing data for %s; applying delta against empty baseline", norm)
	end

	-- Protect guild bank alt data as source of truth
	-- Non-guild bank alts accept all deltas (they're not the authority)
	local player = UnitName("player")
	local realm = GetNormalizedRealmName()
	local playerFull = player .. "-" .. realm
	local playerNorm = GBankClassic_Guild:NormalizeName(playerFull)
	local playerIsGuildBankAlt = GBankClassic_Guild:IsGuildBankAlt(playerNorm)
	local currentIsGuildBankAlt = GBankClassic_Guild:IsGuildBankAlt(norm)
	if playerIsGuildBankAlt then
		-- We are a guild bank alt - protect our own data and other guild bank alt data

		-- If this delta is about US, reject it (we are the source of truth for our own data)
		if norm == playerNorm then
			local errorMsg = string.format("Rejected delta from %s about ourselves (guild bank alt is source of truth for own data)", sender or "unknown")
			GBankClassic_Output:Debug("DELTA", "%s", errorMsg)

			return ADOPTION_STATUS.UNAUTHORIZED
		end
		
		-- Also protect other guild bank alt data from non-guild bank alt updates
		local senderNorm = sender and GBankClassic_Guild:NormalizeName(sender) or nil
		local senderIsGuildBankAlt = senderNorm and GBankClassic_Guild:IsGuildBankAlt(senderNorm) or false
		if currentIsGuildBankAlt and not senderIsGuildBankAlt then
			-- Reject: non-guild bank alt trying to update guild bank alt data
			local errorMsg = string.format("Rejected delta from non-guild bank alt %s for guild bank alt %s (guild bank alts are source of truth)", sender or "unknown", norm)
			GBankClassic_Output:Debug("DELTA", "%s", errorMsg)

			return ADOPTION_STATUS.UNAUTHORIZED
		end
	end
	-- Non-guild bank alts accept all deltas (they're not the authority)

	-- Newest-wins for non-guild bank alts alts
	local incomingUpdatedAt = deltaData.updatedAt or deltaData.version
	local existingUpdatedAt = current.inventoryUpdatedAt or current.version
	if not currentIsGuildBankAlt and incomingUpdatedAt and existingUpdatedAt and incomingUpdatedAt < existingUpdatedAt then
		return ADOPTION_STATUS.STALE
	end

	local currentVersion = current.version or 0
	local baseVersion = deltaData.baseVersion or currentVersion

	-- Only check version mismatch if delta included baseVersion
	if deltaData.baseVersion and currentVersion ~= baseVersion then
		-- Version mismatch - try delta chain replay
		local errorMsg = string.format(
			"Version mismatch: have %d, delta expects %d",
			currentVersion,
			baseVersion
		)

		-- Can't use delta chain, request full sync
		GBankClassic_Output:Debug("DELTA", "Version mismatch for %s (have %d, delta expects %d), requesting full sync", norm, currentVersion, baseVersion)
		GBankClassic_Guild:QueryAlt(nil, norm, nil)

		self:RecordDeltaError(guildInfo.name, norm, "VERSION_MISMATCH", errorMsg)
		if guildInfo and guildInfo.name then
			GBankClassic_Database:RecordDeltaFailed(guildInfo.name)
		end

		return ADOPTION_STATUS.INVALID
	end

	-- Apply changes (wrapped in pcall for safety)
	local success, err = pcall(function()
		local changes = deltaData.changes

		if changes.money then
			current.money = changes.money
		end

		-- Apply item changes (aggregated bank + bags + mail)
		if changes.items then
			if not current.items then
				current.items = {}
			end
			self:ApplyItemDelta(current.items, changes.items)
			GBankClassic_Output:Debug("DELTA", "Applied aggregated items delta for %s: now %d items", norm, #current.items)
		end

		-- Update version
		current.version = deltaData.version
		current.inventoryUpdatedAt = deltaData.updatedAt or deltaData.version or current.inventoryUpdatedAt

		-- Derive inventoryHash from the actual applied items
		local recomputedInvHash = self:ComputeInventoryHash(current.items or {}, nil, nil, current.money or 0)
		current.inventoryHash = recomputedInvHash
		GBankClassic_Output:Debug("DELTA", "%s inventoryHash recomputed=%d (delta had %d)", norm, recomputedInvHash, deltaData.inventoryHash or 0)

		-- Also recompute mailHash from actual mail items after delta application
		if current.mail and current.mail.items then
			local recomputedMailHash = self:ComputeInventoryHash(current.mail.items, nil, nil, nil)
			current.mailHash = recomputedMailHash
			GBankClassic_Output:Debug("DELTA", "%s mailHash recomputed=%d (delta had %d)", norm, recomputedMailHash, changes.mailHash or 0)
			end
	end)

	if not success then
		-- Delta application failed, request full sync
		local errorMsg = string.format("Delta application error: %s", tostring(err))
		GBankClassic_Output:Error("Failed to apply delta for %s: %s", norm, tostring(err))
		self:RecordDeltaError(guildInfo.name, norm, "APPLICATION_ERROR", errorMsg)
		GBankClassic_Guild:QueryAlt(nil, norm, nil)
		if guildInfo and guildInfo.name then
			GBankClassic_Database:RecordDeltaFailed(guildInfo.name)
		end

		return ADOPTION_STATUS.INVALID
	end

	-- Save new snapshot for future deltas
	if guildInfo and guildInfo.name then
		GBankClassic_Database:SaveSnapshot(guildInfo.name, norm, current)
		GBankClassic_Database:RecordDeltaApplied(guildInfo.name)

		-- Record apply time
		local applyTime = debugprofilestop() - applyStart
		GBankClassic_Database:RecordDeltaApplyTime(guildInfo.name, applyTime)
		GBankClassic_Output:Debug("DELTA", "Applied delta for %s (v%d->v%d) in %.2fms", norm, baseVersion, deltaData.version, applyTime)
	end

	-- Reset error count on successful application
	self:ResetDeltaErrorCount(guildInfo.name, norm)

	-- Trigger UI refresh if inventory window is open
	if GBankClassic_UI_Inventory.isOpen then
		if not GBankClassic_UI_Inventory.currentTab or GBankClassic_UI_Inventory.currentTab == norm then
			GBankClassic_UI_Inventory:DrawContent()
			GBankClassic_UI_Inventory:RefreshCurrentTab()
		end
	end
	if GBankClassic_UI_Search.isOpen then
		GBankClassic_UI_Search:BuildSearchData()
		GBankClassic_UI_Search:DrawContent()
		GBankClassic_UI_Search.searchField:Fire("OnEnterPressed")
	end
	if GBankClassic_UI_Donations.isOpen then
		GBankClassic_UI_Donations:DrawContent()
	end

	return ADOPTION_STATUS.ADOPTED
end

-- Error tracking
function DeltaComms:RecordDeltaError(guildName, altName, errorType, errorMessage)
	local error = {
		altName = altName,
		errorType = errorType,
		message = errorMessage,
		timestamp = GetServerTime(),
	}

	-- Try to use database storage first
	if guildName then
		local db = GBankClassic_Database.db.factionrealm[guildName]
		if db and db.deltaErrors then
			-- Use database storage
			table.insert(db.deltaErrors.lastErrors, 1, error)

			-- Keep only recent errors (max 10)
			while #db.deltaErrors.lastErrors > 10 do
				table.remove(db.deltaErrors.lastErrors)
			end

			-- Track failure count per alt
			if not db.deltaErrors.failureCounts[altName] then
				db.deltaErrors.failureCounts[altName] = 0
			end
			db.deltaErrors.failureCounts[altName] = db.deltaErrors.failureCounts[altName] + 1

			-- Notify user if repeated failures (3+ failures for same alt) and player is online
			if db.deltaErrors.failureCounts[altName] >= 3 and not db.deltaErrors.notifiedAlts[altName] then
				if GBankClassic_Guild:IsPlayerOnline(altName) then
					GBankClassic_Output:Warn("Repeated delta sync failures for %s. Falling back to full sync.", altName)
					db.deltaErrors.notifiedAlts[altName] = true
				end
			end

			return
		end
	end

	-- Fallback: Use temporary in-memory storage
	GBankClassic_Output:Debug("DELTA", "Using temporary error storage for %s (%s): initialization issue", altName or "unknown", errorType or "unknown")

	if not GBankClassic_Guild.tempDeltaErrors then
		GBankClassic_Guild.tempDeltaErrors = {
			lastErrors = {},
			failureCounts = {},
			notifiedAlts = {}
		}
	end

	table.insert(GBankClassic_Guild.tempDeltaErrors.lastErrors, 1, error)

	-- Keep only recent errors (max 10)
	while #GBankClassic_Guild.tempDeltaErrors.lastErrors > 10 do
		table.remove(GBankClassic_Guild.tempDeltaErrors.lastErrors)
	end

	-- Track failure count per alt
	if not GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] then
		GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] = 0
	end
	GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] = GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] + 1

	-- Notify user if repeated failures (3+ failures for same alt) and player is online
	if GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] >= 3 and not GBankClassic_Guild.tempDeltaErrors.notifiedAlts[altName] then
		if GBankClassic_Guild:IsPlayerOnline(altName) then
			GBankClassic_Output:Warn("Repeated delta sync failures for %s. Falling back to full sync.", altName)
			GBankClassic_Guild.tempDeltaErrors.notifiedAlts[altName] = true
		end
	end
end

-- Reset failure count for an alt (called on successful sync)
function DeltaComms:ResetDeltaErrorCount(guildName, altName)
	if not altName then
		return
	end

	-- Reset in database if available
	if guildName then
		local db = GBankClassic_Database.db.factionrealm[guildName]
		if db and db.deltaErrors then
			if db.deltaErrors.failureCounts[altName] then
				db.deltaErrors.failureCounts[altName] = 0
			end
			if db.deltaErrors.notifiedAlts[altName] then
				db.deltaErrors.notifiedAlts[altName] = nil
			end
		end
	end

	-- Also reset in temporary storage
	if GBankClassic_Guild.tempDeltaErrors then
		if GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] then
			GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] = 0
		end
		if GBankClassic_Guild.tempDeltaErrors.notifiedAlts[altName] then
			GBankClassic_Guild.tempDeltaErrors.notifiedAlts[altName] = nil
		end
	end
end

-- Clear error counters for all offline players (called on roster update)
function DeltaComms:ClearOfflineErrorCounters(guildName)
	if not guildName then
		return
	end

	local db = GBankClassic_Database.db.factionrealm[guildName]
	if not db or not db.deltaErrors then
		return
	end

	-- Check each alt with error counters
	for altName, _ in pairs(db.deltaErrors.failureCounts) do
		if not GBankClassic_Guild:IsPlayerOnline(altName) then
			db.deltaErrors.failureCounts[altName] = nil
			db.deltaErrors.notifiedAlts[altName] = nil
		end
	end
end