GBankClassic_Item = {}

function GBankClassic_Item:GetItems(items, callback)
    local total = 0
    for _, _ in pairs(items) do
        total = total + 1
    end

    local list = {}
    local count = 0
    for _, item in pairs(items) do
        local itemData = Item:CreateFromItemID(item.ID)
        itemData:ContinueOnItemLoad(function()
            item.Info = self:GetInfo(item.ID, item.Link)
            table.insert(list, item)
            count = count + 1
            if count == total then
                callback(list)
            end
        end)
    end
end

function GBankClassic_Item:GetInfo(id, link)
    local name, _, rarity, level, _, _, _, _, _, icon, price, itemClassId, itemSubClassId = GetItemInfo(link)
    local equip = C_Item.GetItemInventoryTypeByID(id)

    return {class = itemClassId, subClass = itemSubClassId, equipId = equip, rarity = rarity, name = name, level = level, price = price, icon = icon}
end

-- NOTE: Sort was adapted from ElvUI
local function BasicSort(a, b)
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

-- NOTE: Sort was adapted from ElvUI
function GBankClassic_Item:Sort(items)
    table.sort(items, function (a, b)
        if a.Info.rarity ~= b.Info.rarity and a.Info.rarity and b.Info.rarity then
            return a.Info.rarity < b.Info.rarity
        end
        if a.Info.class ~= b.Info.class then
            return (a.Info.class or 99) < (b.Info.class or 99)
        end
        if a.Info.equipId > 0 then
            if a.Info.equipId == b.Info.equipId then
                return BasicSort(a, b)
            end

            if a.Info.equip and b.Info.equip then
                return a.Info.equip < b.Info.equip
            end
        end
        if a.Info.class == b.Info.class and a.Info.subClass == b.Info.subClass then
            return BasicSort(a, b)
        end
        return (a.Info.subClass or 99) < (b.Info.subClass or 99)
    end)
end

function GBankClassic_Item:Aggregate(a, b)
    local items = {}
    if a then
        for _, v in pairs(a) do
            local key = v.ID .. v.Link
            if items[key] then
                local item = items[key]
                items[key] = {ID = item.ID, Count = item.Count + v.Count, Link = item.Link}
            else
                items[key] = v
            end
        end
    end

    if b then
        for _, v in pairs(b) do
            local key = v.ID .. v.Link
            if items[key] then
                local item = items[key]
                items[key] = {ID = item.ID, Count = item.Count + v.Count, Link = item.Link}
            else
                items[key] = v
            end
        end
    end

    return items
end

function GBankClassic_Item:IsUnique(link)
    local tip = CreateFrame("GameTooltip", "scanTip", UIParent, "GameTooltipTemplate")
    tip:ClearLines()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetHyperlink(link)
    for i=1, tip:NumLines() do
        local line = _G["scanTipTextLeft"..i]
        if line and line:IsVisible() then
            local l = line:GetText()
            if l and l:find(ITEM_UNIQUE) then
                return true
            end
        end
    end

    return false
end
