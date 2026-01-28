-- Handles all delta synchronization communication and protocol logic
-- This includes delta validation, computation, application, error tracking, and protocol coordination

GBankClassic_DeltaComms = {}

-- VALIDATION FUNCTIONS --

-- Validate that a delta structure is well-formed
function GBankClassic_DeltaComms:ValidateDeltaStructure(delta)
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

	if not delta.changes or type(delta.changes) ~= "table" then
		return false, "missing or invalid changes"
	end

	-- Validate changes structure
	local changes = delta.changes

	-- Money is optional but must be number if present
	if changes.money and type(changes.money) ~= "number" then
		return false, "invalid money in changes"
	end

	-- Validate bank delta if present
	if changes.bank then
		local valid, err = self:ValidateItemDelta(changes.bank)
		if not valid then
			return false, "invalid bank delta: " .. err
		end
	end

	-- Validate bags delta if present
	if changes.bags then
		local valid, err = self:ValidateItemDelta(changes.bags)
		if not valid then
			return false, "invalid bags delta: " .. err
		end
	end

	return true
end

-- Validate an item delta structure (added/modified/removed)
function GBankClassic_DeltaComms:ValidateItemDelta(itemDelta)
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
			if not item.Link or type(item.Link) ~= "string" then
				return false, "added item missing or invalid link"
			end
			-- slot is optional (merged items don't have slots)
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
			if not item.Link or type(item.Link) ~= "string" then
				return false, "modified item missing or invalid link"
			end
			-- slot is optional (merged items don't have slots)
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
			if not item.Link or type(item.Link) ~= "string" then
				return false, "removed item missing or invalid link"
			end
		end
	end

	return true
end

-- Sanitize a delta structure by removing malformed data
function GBankClassic_DeltaComms:SanitizeDelta(delta)
	if not delta or type(delta) ~= "table" then
		return nil
	end

	-- Create sanitized copy
	local sanitized = {
		type = delta.type,
		name = delta.name,
		version = delta.version,
		changes = {},
	}

	if not delta.changes or type(delta.changes) ~= "table" then
		return sanitized
	end

	local changes = delta.changes

	-- Sanitize money
	if changes.money and type(changes.money) == "number" then
		sanitized.changes.money = changes.money
	end

	-- Sanitize bank delta
	if changes.bank and type(changes.bank) == "table" then
		sanitized.changes.bank = self:SanitizeItemDelta(changes.bank)
	end

	-- Sanitize bags delta
	if changes.bags and type(changes.bags) == "table" then
		sanitized.changes.bags = self:SanitizeItemDelta(changes.bags)
	end

	return sanitized
end

-- Sanitize an item delta structure
function GBankClassic_DeltaComms:SanitizeItemDelta(itemDelta)
	local sanitized = {
		added = {},
		modified = {},
		removed = {},
	}

	-- Sanitize added items
	if itemDelta.added and type(itemDelta.added) == "table" then
		for _, item in pairs(itemDelta.added) do
			if type(item) == "table" and item.ID and item.slot then
				table.insert(sanitized.added, item)
			end
		end
	end

	-- Sanitize modified items
	if itemDelta.modified and type(itemDelta.modified) == "table" then
		for _, item in pairs(itemDelta.modified) do
			if type(item) == "table" and item.slot then
				table.insert(sanitized.modified, item)
			end
		end
	end

	-- Sanitize removed slots
	if itemDelta.removed and type(itemDelta.removed) == "table" then
		for _, slot in pairs(itemDelta.removed) do
			if type(slot) == "number" then
				table.insert(sanitized.removed, slot)
			end
		end
	end

	return sanitized
end

-- Compute a hash of inventory state to detect actual changes
-- Only updates version timestamps when this hash changes
function GBankClassic_DeltaComms:ComputeInventoryHash(bank, bags, money)
	local parts = {}

	-- Include money
	table.insert(parts, tostring(money or 0))

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

-- DELTA PROTOCOL FUNCTIONS --

-- Check if delta sync should be used
function GBankClassic_DeltaComms:ShouldUseDelta()
	-- Check force flags first (for testing)
	if FEATURES and FEATURES.FORCE_DELTA_SYNC then
		return true
	end

	-- Check feature flags
	if not FEATURES or not FEATURES.DELTA_ENABLED then
		return false
	end
	if FEATURES.FORCE_FULL_SYNC then
		return false
	end

	-- Delta protocol always enabled if feature flag is on
	-- No guild support threshold - clients will use delta if both sides support it
	return PROTOCOL.SUPPORTS_DELTA
end

-- Get peer protocol capabilities
function GBankClassic_DeltaComms:GetPeerCapabilities(guildName, sender)
	if not guildName or not sender then
		return nil
	end

	return GBankClassic_Database:GetPeerProtocol(guildName, sender)
end

-- Strip links from delta for bandwidth savings
function GBankClassic_DeltaComms:StripDeltaLinks(delta)
	if not delta or not delta.changes then
		return nil
	end

	local function stripItemArray(items)
		if not items then return nil end
		local stripped = {}
		for _, item in ipairs(items) do
			local strippedItem = {
				ID = item.ID,
				Count = item.Count
			}
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
		changes = {}
	}

	-- Copy money change (no link to strip)
	if delta.changes.money then
		strippedDelta.changes.money = delta.changes.money
	end

	-- Strip links from bank changes
	if delta.changes.bank then
		strippedDelta.changes.bank = {
			added = stripItemArray(delta.changes.bank.added),
			modified = stripItemArray(delta.changes.bank.modified),
			removed = stripItemArray(delta.changes.bank.removed)
		}
	end

	-- Strip links from bags changes
	if delta.changes.bags then
		strippedDelta.changes.bags = {
			added = stripItemArray(delta.changes.bags.added),
			modified = stripItemArray(delta.changes.bags.modified),
			removed = stripItemArray(delta.changes.bags.removed)
		}
	end

	return strippedDelta
end

-- DELTA COMPUTATION FUNCTIONS --

-- Compare two items for equality
function GBankClassic_DeltaComms:ItemsEqual(item1, item2)
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
	if item1.Link ~= item2.Link then
		return false
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
function GBankClassic_DeltaComms:GetChangedFields(oldItem, newItem)
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
function GBankClassic_DeltaComms:BuildItemIndex(items)
	local index = {}
	if not items then
		return index
	end

	for _, item in pairs(items) do
		if item and item.ID and item.Link then
			local key = tostring(item.ID) .. item.Link
			index[key] = item
		end
	end

	return index
end

-- Compute delta between old and new item sets
function GBankClassic_DeltaComms:ComputeItemDelta(oldItems, newItems)
	local delta = { added = {}, modified = {}, removed = {} }

	oldItems = oldItems or {}
	newItems = newItems or {}

	-- Build item index for old items by itemID + link key
	local oldByKey = self:BuildItemIndex(oldItems)

	-- Find added and modified items
	for _, newItem in pairs(newItems) do
		if newItem and newItem.ID and newItem.Link then
			local key = tostring(newItem.ID) .. newItem.Link
			local oldItem = oldByKey[key]

			if not oldItem then
				-- Item was added
				table.insert(delta.added, newItem)
			elseif not self:ItemsEqual(oldItem, newItem) then
				-- Item was modified (quantity or other field changed)
				table.insert(delta.modified, self:GetChangedFields(oldItem, newItem))
			end

			-- Mark as processed
			oldByKey[key] = nil
		end
	end

	-- Remaining old items were removed
	for _, item in pairs(oldByKey) do
		table.insert(delta.removed, { ID = item.ID })
	end

	return delta
end

-- Compute full delta for an alt
function GBankClassic_DeltaComms:ComputeDelta(guildName, altName, currentAlt)
	return GBankClassic_Performance:Track("ComputeDelta", function()
		if not guildName or not altName or not currentAlt then
			return nil
		end

		-- Get previous snapshot
		local previous = GBankClassic_Database:GetSnapshot(guildName, altName)
		if not previous then
			return nil
		end

		-- Build delta structure
		-- In pull-based protocol, receiver states what they have
		local delta = {
			type = "alt-delta",
			name = altName,
			version = currentAlt.version or GetServerTime(),
			changes = {},
		}

		-- Money change
		if currentAlt.money ~= previous.money then
			delta.changes.money = currentAlt.money
		end

		-- Bank items delta
		local previousBankItems = previous.bank and previous.bank.items or {}
		local currentBankItems = currentAlt.bank and currentAlt.bank.items or {}

		-- Bag items delta
		local previousBagItems = previous.bags and previous.bags.items or {}
		local currentBagItems = currentAlt.bags and currentAlt.bags.items or {}

		-- Log item counts for both bank and bags
		GBankClassic_Output:Debug(
			"DELTA",
			"Comparing %s: previous bank has %d items, bags have %d items; current bank has %d items, bags have %d items",
			altName,
			#previousBankItems,
			#previousBagItems,
			#currentBankItems,
			#currentBagItems
		)
		delta.changes.bank = self:ComputeItemDelta(previousBankItems, currentBankItems)
		delta.changes.bags = self:ComputeItemDelta(previousBagItems, currentBagItems)

		return delta
	end)
end

-- Estimate serialized size of a data structure
function GBankClassic_DeltaComms:EstimateSize(data)
	if not data then
		return 0
	end

	-- Rough estimate: serialize and measure length
	local serialized = GBankClassic_Core:SerializeWithChecksum(data)

	return string.len(serialized or "")
end

-- Check if delta has any actual changes
function GBankClassic_DeltaComms:DeltaHasChanges(delta)
	if not delta or not delta.changes then
		return false
	end

	local changes = delta.changes

	-- Check money change
	if changes.money then
		return true
	end

	-- Check bank changes
	if changes.bank then
		if next(changes.bank.added) or next(changes.bank.modified) or next(changes.bank.removed) then
			return true
		end
	end

	-- Check bag changes
	if changes.bags then
		if next(changes.bags.added) or next(changes.bags.modified) or next(changes.bags.removed) then
			return true
		end
	end

	return false
end

-- DELTA APPLICATION FUNCTIONS --

-- Apply item delta to an items table
function GBankClassic_DeltaComms:ApplyItemDelta(items, delta)
	if not items or not delta then
		return false
	end

	-- Build current items index by itemKey
	local itemsByKey = self:BuildItemIndex(items)

	-- Remove items
	if delta.removed then
		for _, removedItem in ipairs(delta.removed) do
			if removedItem and removedItem.ID then
				-- Match by ID only (link field removed)
				for i = #items, 1, -1 do
					local item = items[i]
					if item and item.ID == removedItem.ID then
						table.remove(items, i)
						break -- Remove first match only
					end
				end
			end
		end
	end

	-- Add new items
	if delta.added then
		for _, item in ipairs(delta.added) do
			if item and item.ID and item.Link then
				table.insert(items, item)
			end
		end
	end

	-- Modify existing items
	if delta.modified then
		for _, changes in ipairs(delta.modified) do
			if changes and changes.ID and changes.Link then
				local key = tostring(changes.ID) .. changes.Link
				local existingItem = itemsByKey[key]

				if existingItem then
					-- Apply changed fields to existing item
					for field, value in pairs(changes) do
						existingItem[field] = value
					end
				else
					-- Item doesn't exist (shouldn't happen), add as new
					table.insert(items, changes)
				end
			end
		end
	end

	return true
end

-- Apply a delta to alt data
function GBankClassic_DeltaComms:ApplyDelta(guildInfo, altName, deltaData, sender)
	return GBankClassic_Performance:Track("ApplyDelta", function()
		if not guildInfo then
			return ADOPTION_STATUS.IGNORED
		end

		local applyStart = debugprofilestop()
		local norm = GBankClassic_Guild:NormalizeName(altName)
		local current = guildInfo.alts[norm]

		-- Validate base version matches
		if not current then
			-- No existing data, request full sync
			local errorMsg = string.format("No existing data for %s", norm)
			GBankClassic_Output:Debug("DELTA", errorMsg .. ", requesting full sync")
			self:RecordDeltaError(guildInfo.name, norm, "NO_DATA", errorMsg)
			GBankClassic_Guild:QueryAlt(nil, norm, nil)
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

			-- Apply bank item changes
			if changes.bank then
				if not current.bank then
					current.bank = { items = {} }
				end
				if not current.bank.items then
					current.bank.items = {}
				end
				self:ApplyItemDelta(current.bank.items, changes.bank)
			end

			-- Apply bag item changes
			if changes.bags then
				if not current.bags then
					current.bags = { items = {} }
				end
				if not current.bags.items then
					current.bags.items = {}
				end
				self:ApplyItemDelta(current.bags.items, changes.bags)
			end

			-- Update version
			current.version = deltaData.version
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
			GBankClassic_Output:Debug(
				"DELTA",
				"✓ Applied delta for %s (v%d→v%d) in %.2fms",
				norm,
				deltaData.version,
				applyTime
			)
		end

		-- Reset error count on successful application
		self:ResetDeltaErrorCount(guildInfo.name, norm)

		-- Trigger UI refresh if Inventory window is open
		if GBankClassic_UI_Inventory and GBankClassic_UI_Inventory.isOpen then
			GBankClassic_UI_Inventory:DrawContent()
		end

		return ADOPTION_STATUS.ADOPTED
	end)
end

-- Apply a chain of deltas sequentially
function GBankClassic_DeltaComms:ApplyDeltaChain(guildInfo, altName, deltaChain)
	if not altName or not deltaChain or type(deltaChain) ~= "table" or #deltaChain == 0 then
		return ADOPTION_STATUS.INVALID
	end

	local norm = GBankClassic_Guild:NormalizeName(altName)
	local current = guildInfo and guildInfo.alts and guildInfo.alts[norm]

	if not current then
		GBankClassic_Output:Debug("DELTA", "No existing data for %s, cannot apply delta chain", norm)

		return ADOPTION_STATUS.INVALID
	end

	-- Validate chain
	if #deltaChain > (PROTOCOL.DELTA_CHAIN_MAX_HOPS or 10) then
		GBankClassic_Output:Debug(
			"DELTA",
			"Delta chain too long for %s (%d hops > %d max)",
			norm,
			#deltaChain,
			PROTOCOL.DELTA_CHAIN_MAX_HOPS or 10
		)

		return ADOPTION_STATUS.INVALID
	end

	-- Estimate total chain size
	local totalSize = self:EstimateSize(deltaChain)
	if totalSize > (PROTOCOL.DELTA_CHAIN_MAX_SIZE or 5000) then
		GBankClassic_Output:Debug(
			"DELTA",
			"Delta chain too large for %s (%d bytes > %d max), requesting full sync",
			norm,
			totalSize,
			PROTOCOL.DELTA_CHAIN_MAX_SIZE or 5000
		)
		GBankClassic_Guild:QueryAlt(nil, norm, nil)

		return ADOPTION_STATUS.INVALID
	end

	-- Apply each delta in sequence
	local chainStart = debugprofilestop()

	for i, deltaEntry in ipairs(deltaChain) do
		-- Apply this delta
		local deltaData = {
			type = "alt-delta",
			name = altName,
			version = deltaEntry.version,
			changes = deltaEntry.delta
		}

		local status = self:ApplyDelta(guildInfo, altName, deltaData)
		if status ~= ADOPTION_STATUS.ADOPTED then
			GBankClassic_Output:Debug(
				"DELTA",
				"Failed to apply delta chain for %s at hop %d (v%d→v%d)",
				norm,
				i,
				deltaEntry.version
			)

			return status
		end

		currentVersion = deltaEntry.version
	end

	local chainTime = debugprofilestop() - chainStart
	GBankClassic_Output:Debug(
		"DELTA",
		"✓ Applied delta chain for %s (%d hops, v%d→v%d) in %.2fms",
		norm,
		#deltaChain,
		deltaChain[#deltaChain].version,
		chainTime
	)

	return ADOPTION_STATUS.ADOPTED
end

-- ERROR TRACKING FUNCTIONS --

function GBankClassic_DeltaComms:RecordDeltaError(guildName, altName, errorType, errorMessage)
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
					GBankClassic_Output:Warn(
						"Repeated delta sync failures for %s. Falling back to full sync.",
						altName
					)
					db.deltaErrors.notifiedAlts[altName] = true
				end
			end
			return
		end
	end

	-- Fallback: Use temporary in-memory storage
	GBankClassic_Output:Debug(
		"DELTA",
		"Using temporary error storage for %s (%s): Guild.Info not initialized",
		altName or "unknown",
		errorType or "unknown"
	)

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
function GBankClassic_DeltaComms:ResetDeltaErrorCount(guildName, altName)
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

-- Get recent delta errors
function GBankClassic_DeltaComms:GetRecentDeltaErrors(guildName)
	-- Return from database if available
	if guildName then
		local db = GBankClassic_Database.db.factionrealm[guildName]
		if db and db.deltaErrors then
			return db.deltaErrors.lastErrors
		end
	end

	-- Fallback to temporary storage
	if GBankClassic_Guild.tempDeltaErrors then
		return GBankClassic_Guild.tempDeltaErrors.lastErrors
	end

	return {}
end

-- Get failure count for an alt
function GBankClassic_DeltaComms:GetDeltaFailureCount(guildName, altName)
	-- Check database first if available
	if guildName then
		local db = GBankClassic_Database.db.factionrealm[guildName]
		if db and db.deltaErrors then
			return db.deltaErrors.failureCounts[altName] or 0
		end
	end

	-- Fallback to temporary storage
	if GBankClassic_Guild.tempDeltaErrors then
		return GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] or 0
	end

	return 0
end

-- Reset error counters for an alt after successful full sync
function GBankClassic_DeltaComms:ResetDeltaErrorCount(guildName, altName)
	if not altName then
		return
	end

	-- Clear from database if available
	if guildName then
		local db = GBankClassic_Database.db.factionrealm[guildName]
		if db and db.deltaErrors then
			db.deltaErrors.failureCounts[altName] = nil
			db.deltaErrors.notifiedAlts[altName] = nil
		end
	end

	-- Clear from temporary storage
	if GBankClassic_Guild.tempDeltaErrors then
		GBankClassic_Guild.tempDeltaErrors.failureCounts[altName] = nil
		GBankClassic_Guild.tempDeltaErrors.notifiedAlts[altName] = nil
	end
end

-- Clear error counters for all offline players (called on roster update)
function GBankClassic_DeltaComms:ClearOfflineErrorCounters(guildName)
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

-- PULL-BASED PROTOCOL FUNCTIONS --

-- Request a chain of deltas to catch up from an old version
function GBankClassic_DeltaComms:RequestDeltaChain(guildName, altName, fromVersion, toVersion, sender)
	if not altName or not fromVersion or not toVersion or not sender then
		return false
	end

	-- Validate request parameters
	if fromVersion >= toVersion then
		GBankClassic_Output:Debug("DELTA", "Invalid delta chain request: fromVersion >= toVersion")
		return false
	end

	-- Check if sender is online before attempting WHISPER (DELTA-008)
	if not GBankClassic_Guild:IsPlayerOnline(sender) then
		GBankClassic_Output:Debug(
			"DELTA",
			"Cannot request delta chain for %s from %s - sender is offline",
			altName,
			sender
		)
		return false
	end

	-- Note: We don't check version gap age here - if we have the deltas, we use them.
	-- The delta history cleanup (DELTA_HISTORY_MAX_AGE) handles storage limits.
	-- If we can't build the chain, BuildDeltaChain will return nil and we'll fall back.

	-- Send delta range request
	local requestData = {
		altName = altName,
		fromVersion = fromVersion,
		toVersion = toVersion
	}

	local serialized = GBankClassic_Core:SerializeWithChecksum(requestData)
	GBankClassic_Core:SendWhisper("gbank-dr", serialized, sender, "ALERT")

	GBankClassic_Output:Debug(
		"DELTA",
		"Requesting delta chain for %s from v%d to v%d from %s",
		altName,
		fromVersion,
		toVersion,
		sender
	)

	return true
end

-- Fast-fill missing alts using pull-based protocol
function GBankClassic_DeltaComms:FastFillMissingAlts(guildInfo)
	if not guildInfo then
		return
	end

	-- Get live guild bank alt roster from current guild instead of using cached roster.alts
	-- The cached roster may contain stale cross-guild data
	local rosterAlts = GBankClassic_Guild:GetBanks()
	if not rosterAlts or #rosterAlts == 0 then
		return
	end

	local missing = {}
	for _, altName in ipairs(rosterAlts) do
		local norm = GBankClassic_Guild:NormalizeName(altName)
		-- Check if we have this alt locally
		if not guildInfo.alts or not guildInfo.alts[norm] then
			table.insert(missing, norm)
		end
	end

	if #missing == 0 then
		GBankClassic_Output:Debug("DELTA", "All %d roster alts present locally", #rosterAlts)
		return
	end

	GBankClassic_Output:Info("Requesting %d missing alts (have %d/%d)", #missing, #rosterAlts - #missing, #rosterAlts)

	-- Query each missing alt using pull-based protocol
	for _, norm in ipairs(missing) do
		GBankClassic_Guild:QueryAltPullBased(norm)
	end
end
