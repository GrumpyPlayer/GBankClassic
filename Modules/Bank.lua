GBankClassic_Bank = {...}

local function AreInventoriesEqual(alt1, alt2)
    if alt1 == alt2 then return true end
    if not alt1 or not alt2 then return false end

    local items1 = GBankClassic_Item:Aggregate(alt1.bags and alt1.bags.items, alt1.bank and alt1.bank.items)
    local items2 = GBankClassic_Item:Aggregate(alt2.bags and alt2.bags.items, alt2.bank and alt2.bank.items)

    for k, v in pairs(items1) do
        if not items2[k] or items2[k].Count ~= v.Count then return false end
    end
    for k, _ in pairs(items2) do
        if not items1[k] then return false end
    end
    return true
end

local function IsBankAvailable()
    local _, bagType = C_Container.GetContainerNumFreeSlots(BANK_CONTAINER)
    return bagType ~= nil
end

local function HasUpdated()
    return GBankClassic_Bank.hasUpdated
end

local function ScanBag(bag, slots)
    local count = 0
    local items = {}

    for slot = 1, slots do
        local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
        if itemInfo then 
            local itemCount = itemInfo.stackCount
            local itemLink = itemInfo.hyperlink
            local itemID = itemInfo.itemID
            if itemLink then
                local key = itemID .. itemLink
                if items[key] then
                    local item = items[key]
                    items[key] = {ID = item.ID, Count = item.Count + itemCount, Link = item.Link}
                else
                    items[key] = {ID = itemID, Count = itemCount, Link = itemLink}
                end
                count = count + 1
            end
        end
    end

    return count, items
end

local function ScanBags(bag_info)
    local total = 0
    local numslots = 0
    local bagItems = nil

    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        local count, items = ScanBag(bag, slots)
        if bagItems == nil then
            bagItems = items
        else
        for k, v in pairs(items) do
            if bagItems[k] then
                local item = bagItems[k]
                bagItems[k] = {ID = item.ID, Count = item.Count + v.Count, Link = item.Link}
            else
                bagItems[k] = v
                end
            end
        end
        total = total + count
        numslots = numslots + slots
    end

    for _, v in pairs(bagItems) do
        table.insert(bag_info, v)
    end

    return total, numslots
end

local function ScanBank(bank_info)
    local numslots = NUM_BANKGENERIC_SLOTS
    local total, bankItems = ScanBag(BANK_CONTAINER, NUM_BANKGENERIC_SLOTS)

    for bag = 5, 11 do
        local slots = C_Container.GetContainerNumSlots(bag)
        local count, items = ScanBag(bag, slots)
        for k, v in pairs(items) do
            if bankItems[k] then
                local item = bankItems[k]
                bankItems[k] = {ID = item.ID, Count = item.Count + v.Count, Link = item.Link}
            else
                bankItems[k] = v
            end
        end
        total = total + count
        numslots = numslots + slots
    end

    for _, v in pairs(bankItems) do
        table.insert(bank_info, v)
    end

    return total, numslots
end

function GBankClassic_Bank:Scan()
    if GBankClassic_Bank.eventsRegistered then
        if not HasUpdated() then
            return
        end
    end

    local info = GBankClassic_Guild.Info
    if not info then return end

    local player = GBankClassic_Guild:GetPlayer()
    if not player then return end
    player = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(player) or player

    local isBank = false
    local banks = GBankClassic_Guild:GetBanks()
    if banks == nil then return end

    for _, v in pairs(banks) do
        local normV = (GBankClassic_Guild and GBankClassic_Guild.NormalizePlayerName) and GBankClassic_Guild.NormalizePlayerName(v) or v
        if normV == player then
            isBank = true
            break
        end
    end
    if not isBank then return end

    if not GBankClassic_Options:GetBankEnabled() then return end

    local updateRoster = false
    if info.roster["version"] ~= nil then
        if table.concat(banks) ~= table.concat(info.roster.alts) then
            updateRoster = true
        end
    else
        updateRoster = true
    end
    if updateRoster then
        info.roster.alts = banks
        info.roster.version = GetServerTime()
    end

    local current_data = {
        money = GetMoney(),
        bank = { items = {}, slots = {} },
        bags = { items = {}, slots = {} },
    }

    if IsBankAvailable() then
        local count, slots = ScanBank(current_data.bank.items)
        current_data.bank.slots = {count = count, total = slots}
    else
        -- Inherit existing bank data if bank is not open
        if info.alts[player] and info.alts[player].bank then
            current_data.bank = info.alts[player].bank
        end
    end

    local count, slots = ScanBags(current_data.bags.items)
    current_data.bags.slots = {count = count, total = slots}

    local existing = info.alts[player]
    local changed = false

    if not existing then
        changed = true
    else
        if existing.money ~= current_data.money then
            changed = true
        elseif not AreInventoriesEqual(existing, current_data) then
            changed = true
        end
    end

    if changed then
        current_data.version = GetServerTime()
        info.alts[player] = current_data
        if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("Local gbank data changed, updating version.") end
        if GBankClassic_UI_Inventory.isOpen then GBankClassic_UI_Inventory:DrawContent() end
        --TODO: Share with just the online peers privately instead of guild-wide (no peers may be online)
        GBankClassic_Guild:AuthorRosterData()
        GBankClassic_Guild:Share("reply")
    else
        if GBankClassic_Chat.debug then GBankClassic_Core:DebugPrint("No changes detected after scan.") end
    end
end

function GBankClassic_Bank:HasInventorySpace()
    local total = 0
    for bag = 0, 4 do
        local slots, _ = C_Container.GetContainerNumFreeSlots(bag)
        total = total + slots
    end
    return total > 0
end

function GBankClassic_Bank:OnUpdateStart()
    self.hasUpdated = true
end

function GBankClassic_Bank:OnUpdateStop()
    if self.hasUpdated then
        self:Scan()
    end
    self.hasUpdated = false
end
