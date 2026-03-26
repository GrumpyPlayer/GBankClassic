GBankClassic_Item = GBankClassic_Item or {}

local Items = GBankClassic_Item

-- Item classes that require link to be preserved (for suffix differentiation)
local ITEM_CLASSES_NEEDING_LINK = {
	[Enum.ItemClass.Weapon] = true,
	[Enum.ItemClass.Armor] = true,
}

local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("GetItemInfo", "GetItemInventoryTypeByID", "CreateFrame")
local GetItemInfo = upvalues.GetItemInfo
local GetItemInventoryTypeByID = upvalues.GetItemInventoryTypeByID
local CreateFrame = upvalues.CreateFrame
local upvalues = Globals.GetUpvalues("Item")
local Item = upvalues.Item
local upvalues = Globals.GetUpvalues("UIParent")
local UIParent = upvalues.UIParent
local upvalues = Globals.GetUpvalues("ITEM_UNIQUE")
local ITEM_UNIQUE = upvalues.ITEM_UNIQUE

-- Check if an item needs its link preserved based on item class
function Items:NeedsLink(itemLink)
	if not itemLink then
        return false
    end

   	local classID = select(12, GetItemInfo(itemLink))

	-- If item isn't cached, preserve the link to avoid losing suffix data
	if classID == nil then
		return true
	end

	-- Gear (weapons/armor) can have random suffixes, so link is required
	if ITEM_CLASSES_NEEDING_LINK[classID] == true then
		return true
	end

	-- Other items don't vary, so link can be stripped
	return false
end

-- Get normalized item key for deduplication
-- Format: itemID:enchant:suffixID (3 parts)
function Items:GetImprovedItemKey(link)
	if not link or link == "" then
		return ""
	end

	local itemString = link:match("|Hitem:([^|]+)|h")
	if not itemString then
		itemString = link:match("item:([%d:]+)")
	end

	if itemString then
		-- Split into parts
		local parts = {}
		for part in string.gmatch(itemString, "([^:]+)") do
			table.insert(parts, part)
		end

		-- Return ID, ID:enchant, ID::suffix, or ID:enchant:suffix
		if parts[7] then
			return table.concat({parts[1], parts[2] or "", parts[7]}, ":")
		elseif parts[2] then
			return parts[1] .. ":" .. parts[2]
		else
			return parts[1]
		end
	end
end

function Items:GetItems(items, callback)
	if not items or type(items) ~= "table" then
		callback({})

		return
	end

    -- Only consider items that have a valid ID
    local total = 0
	local validItems = {}
	for idx, item in pairs(items) do
		-- Log every item we encounter to identify corrupted data
		if not item then
			GBankClassic_Output:Debug("ITEM", "Skipping nil item at index %s", tostring(idx))
		elseif type(item) ~= "table" then
			GBankClassic_Output:Debug("ITEM", "Skipping non-table item at index %s (type=%s)", tostring(idx), type(item))
		elseif not item.ID then
			GBankClassic_Output:Debug("ITEM", "Skipping item with nil ID at index %s", tostring(idx))
		elseif type(item.ID) ~= "number" then
			GBankClassic_Output:Debug("ITEM", "Skipping item with non-number ID at index %s (ID=%s, type=%s)", tostring(idx), tostring(item.ID), type(item.ID))
		elseif item.ID <= 0 then
			GBankClassic_Output:Debug("ITEM", "Skipping corrupted item with invalid ID at index %s (ID=%d)", tostring(idx), item.ID)
		else
			-- Valid item - add to processing list
			total = total + 1
			table.insert(validItems, { original = item, id = item.ID, link = item.Link })
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
		local itemID = wrapper.id
		local itemLink = wrapper.link
		local item = wrapper.original

		-- Log what we're about to process
		GBankClassic_Output:Debug("ITEM", "Processing wrapper: id=%s, link=%s, original.ID=%s", tostring(itemID), tostring(itemLink), tostring(item and item.ID or "nil item"))

		-- Final safety check before calling WoW API
		if not itemID or type(itemID) ~= "number" or itemID <= 0 then
			GBankClassic_Output:Debug("ITEM", "Skipping invalid: itemID=%s (type=%s)", tostring(itemID), type(itemID))
			processed = processed + 1
			checkComplete()
		else
			-- Capture itemID in local scope to prevent closure corruption
			local capturedItemID = itemID
			local capturedItemLink = itemLink
			local capturedItem = item

			-- Double-check captured values
			if not capturedItemID or type(capturedItemID) ~= "number" or capturedItemID <= 0 then
				GBankClassic_Output:Debug("ITEM", "ERROR: itemID validation failed after capture!")
				processed = processed + 1
				checkComplete()
			else

				if capturedItemLink then
					GBankClassic_Output:Debug("ITEM", "Item %d has link, using directly", capturedItemID)
					if not capturedItem.Info then
						local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(capturedItemID)
						if name then
							GBankClassic_Output:Debug("ITEM", "Item %d already cached", capturedItemID)
							local equip = GetItemInventoryTypeByID(capturedItemID)
							capturedItem.Info = { class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon }
						end
					end
					table.insert(list, capturedItem)
					count = count + 1
					processed = processed + 1
				else
					-- Check if item data is already cached (fast path)
					local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(capturedItemID)
					if name then
						GBankClassic_Output:Debug("ITEM", "Item %d already cached", capturedItemID)
						local equip = GetItemInventoryTypeByID(capturedItemID)
						capturedItem.Info = { class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon }
						table.insert(list, capturedItem)
						count = count + 1
						processed = processed + 1
					else
						-- Item not cached, need async load
						GBankClassic_Output:Debug("ITEM", "Item %d not cached, calling CreateFromItemID", capturedItemID)
						pendingAsync = pendingAsync + 1

						local success, itemData = pcall(Item.CreateFromItemID, Item, capturedItemID)
						GBankClassic_Output:Debug("ITEM", "CreateFromItemID result: success=%s, itemData=%s, type=%s", tostring(success), tostring(itemData), type(itemData))

						if not success then
							GBankClassic_Output:Debug("ITEM", "CreateFromItemID pcall failed: %s", tostring(itemData))
							pendingAsync = pendingAsync - 1
							processed = processed + 1
							checkComplete()
						elseif not itemData then
							GBankClassic_Output:Debug("ITEM", "CreateFromItemID returned nil")
							pendingAsync = pendingAsync - 1
							processed = processed + 1
							checkComplete()
						elseif type(itemData) ~= "table" then
							GBankClassic_Output:Debug("ITEM", "CreateFromItemID returned non-table: %s", type(itemData))
							pendingAsync = pendingAsync - 1
							processed = processed + 1
							checkComplete()
						else
							-- Got an item object, now inspect its internal state
							GBankClassic_Output:Debug("ITEM", "Inspecting item object for ID %d", capturedItemID)

							-- Try to access internal fields safely
							local objectItemID = nil
							local accessSuccess = pcall(function()
								objectItemID = itemData.itemID
							end)
							GBankClassic_Output:Debug("ITEM", "Internal field access: accessSuccess=%s, itemData.itemID=%s, type=%s", tostring(accessSuccess), tostring(objectItemID), type(objectItemID))

							-- Check if itemID matches what we expect
							if not accessSuccess then
								GBankClassic_Output:Debug("ITEM", "Cannot access itemData.itemID")
								pendingAsync = pendingAsync - 1
								processed = processed + 1
								checkComplete()
							elseif objectItemID == nil then
								GBankClassic_Output:Debug("ITEM", "ERROR: itemData.itemID is nil for requested ID %d", capturedItemID)
								pendingAsync = pendingAsync - 1
								processed = processed + 1
								checkComplete()
							elseif type(objectItemID) ~= "number" then
								GBankClassic_Output:Debug("ITEM", "itemData.itemID is not a number: %s", type(objectItemID))
								pendingAsync = pendingAsync - 1
								processed = processed + 1
								checkComplete()
							elseif objectItemID ~= capturedItemID then
								GBankClassic_Output:Debug("ITEM", "itemData.itemID mismatch: expected %d, got %d", capturedItemID, objectItemID)
								pendingAsync = pendingAsync - 1
								processed = processed + 1
								checkComplete()
							else
								-- Everything looks good, try ContinueOnItemLoad
								GBankClassic_Output:Debug("ITEM", "Item object valid (itemID=%d), calling ContinueOnItemLoad", objectItemID)

								local callbackSuccess, callbackError = pcall(function()
									itemData:ContinueOnItemLoad(function()
										GBankClassic_Output:Debug("ITEM", "ContinueOnItemLoad callback fired for ID %d", capturedItemID)
										capturedItem.Info = self:GetInfo(capturedItemID, capturedItemLink)
										table.insert(list, capturedItem)
										count = count + 1
										pendingAsync = pendingAsync - 1
										checkComplete()
									end)
								end)
								GBankClassic_Output:Debug("ITEM", "ContinueOnItemLoad pcall result: success=%s, error=%s", tostring(callbackSuccess), tostring(callbackError))

								processed = processed + 1

								if not callbackSuccess then
									GBankClassic_Output:Debug("ITEM", "ContinueOnItemLoad pcall failed for ID %d: %s", capturedItemID, tostring(callbackError))
									pendingAsync = pendingAsync - 1
									checkComplete()
								end
							end
						end
					end
				end
			end
		end
	end

	-- After processing all items, check if we can fire callback (handles case where all items had links and were processed synchronously)
	checkComplete()
end

function Items:GetInfo(id, link)
	local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId

	-- Try link first if available
	if link and link ~= "" then
		name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(link)
	end

	-- Fallback to ID if link didn't work
	if not name and id and id > 0 then
		name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(id)
	end

	-- If still no data, return basic info with ID only and the default grey question mark icon
	if not name then
		return { class = 0, subClass = 0, equipId = 0, rarity = 1, name = "Item " .. tostring(id or "?"), level = 1, price = 0, icon = 134400 }
	end

    local equip = GetItemInventoryTypeByID(id)

	return { class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon }
end

local function basicSort(a, b)
    if a.Info.level ~= b.Info.level and a.Info.level and b.Info.level then
        return a.Info.level < b.Info.level
    end
    if a.Info.price ~= b.Info.price and a.Info.price and b.Info.price then
        return a.Info.price < b.Info.price
    end
    if a.Info.name and b.Info.name then
        return a.Info.name < b.Info.name
    end
end

function Items:Sort(items, mode)
	-- Ensure all items have the required fields for sorting
	for _, item in ipairs(items) do
		if not item.Info then
			-- Create minimal
			item.Info = { class = 0, subClass = 0, equipId = 0, rarity = 1, name = item.Link and item.Link:match("%[(.-)%]") or ("Item " .. tostring(item.ID or "?")), level = 1, price = 0, icon = 134400 }
		elseif not item.Info.class then
			-- Missing sort fields, add defaults
			item.Info.class = item.Info.class or 0
			item.Info.subClass = item.Info.subClass or 0
			item.Info.equipId = item.Info.equipId or 0
			item.Info.rarity = item.Info.rarity or 1
			item.Info.level = item.Info.level or 1
			item.Info.price = item.Info.price or 0
			item.Info.name = item.Info.name or (item.Link and item.Link:match("%[(.-)%]")) or ("Item " .. tostring(item.ID or "?"))
		end
	end

	-- mode = "default" (grouped by rarity, item class, equipId, equip slot, subclass)
	if not mode or mode == "default" then
		table.sort(items, function(a, b)
			if a.Info.rarity ~= b.Info.rarity and a.Info.rarity and b.Info.rarity then
				return a.Info.rarity < b.Info.rarity
			end
			if a.Info.class ~= b.Info.class then
				return (a.Info.class or 99) < (b.Info.class or 99)
			end
			if (a.Info.equipId or 0) > 0 then
				if a.Info.equipId == b.Info.equipId then
					return basicSort(a, b)
				end
				if a.Info.equip and b.Info.equip then
					return a.Info.equip < b.Info.equip
				end
			end
			if a.Info.class == b.Info.class and a.Info.subClass == b.Info.subClass then
				return basicSort(a, b)
			end

			return (a.Info.subClass or 99) < (b.Info.subClass or 99)
		end)
	-- mode = "alpha" (alphabetically by name)
	elseif mode == "alpha" then
		table.sort(items, function(a, b)
			return (a.Info.name or "") < (b.Info.name or "")
		end)
	-- mode = "type" (grouped by item class, equip slot, subclass, rarity, then name)
	elseif mode == "type" then
		table.sort(items, function(a, b)
			if a.Info.class ~= b.Info.class then
				return (a.Info.class or 99) < (b.Info.class or 99)
			end
			local aEquip = a.Info.equip or ""
			local bEquip = b.Info.equip or ""
			if aEquip ~= bEquip then
				return aEquip < bEquip
			end
			if a.Info.subClass ~= b.Info.subClass then
				return (a.Info.subClass or 99) < (b.Info.subClass or 99)
			end
			if a.Info.rarity ~= b.Info.rarity then
				return (a.Info.rarity or 0) < (b.Info.rarity or 0)
			end
			return (a.Info.name or "") < (b.Info.name or "")
		end)
	-- mode = "rarity" (epic before rare before uncommon and so on, then A-Z)
	elseif mode == "rarity" then
		table.sort(items, function(a, b)
			local aRarity = a.Info.rarity or 0
			local bRarity = b.Info.rarity or 0
			if aRarity ~= bRarity then
				return aRarity > bRarity
			end
			return (a.Info.name or "") < (b.Info.name or "")
		end)
	-- mode = "level" (highest required level first, then A-Z)
	elseif mode == "level" then
		table.sort(items, function(a, b)
			local aLevel = a.Info.level or 0
			local bLevel = b.Info.level or 0
			if aLevel ~= bLevel then
				return aLevel > bLevel
			end
			return (a.Info.name or "") < (b.Info.name or "")
		end)
	end
end

function Items:Aggregate(a, b)
    local items = {}
    local itemsByID = {}
    local itemsByKey = {}

    local function processItem(v)
        if type(v) ~= "table" or not v.ID then
            -- Skip malformed entries
            return
        end

        -- Ensure Count is set
        v.Count = v.Count or 1

        -- Define a key for deduplication
		local idStr = tostring(v.ID)
		local key = idStr

		-- For weapons/armor, include enchant and suffix differences
		if v.Link then
			if self:NeedsLink(v.Link) then
				local linkKey = self:GetImprovedItemKey(v.Link)
				if linkKey and linkKey ~= "" then
					key = linkKey
				end
			else
				v.Link = nil
			end
		end

        -- Skip if we already have this exact key
        if itemsByKey[key] then
            local existingItem = itemsByKey[key]
            existingItem.Count = existingItem.Count + v.Count
            local existingItemLink = existingItem.Link or v.Link
			if self:NeedsLink(existingItemLink) then
				existingItem.Link = existingItemLink
			end

            return
        end

        if key and not itemsByKey[key] then
            items[key] = { ID = v.ID, Count = v.Count, Link = v.Link }
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
        if item and item.ID then
            table.insert(result, item)
        end
    end

    return result
end

function Items:IsUnique(link)
	if not link then
		return false
	end

    local tip = CreateFrame("GameTooltip", "scanTip", UIParent, "GameTooltipTemplate")
    tip:ClearLines()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetHyperlink(link)
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