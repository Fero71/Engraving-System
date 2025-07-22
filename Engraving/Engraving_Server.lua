local AIO = AIO or require("AIO")

local EngravingNPC_ID = 1450000
local EngravingCheckRange = 5          -- Yards
local EngravingCheckInterval = 1000    -- Milliseconds

-- Table to cache each player's event object
local EngravingTimers = {} -- [playerGUID] = ElunaEvent

local ENGRAVE_ENCHANTS = {
    [1] = 10000,
    [2] = 10001,
    [3] = 10002,
}

-- Combined Class + SubClass
local ALLOWED_CLASS_AND_SUB_CLASS = {
    [2] = {
		[0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
		[5] = true, [6] = true, [7] = true, [8] = true, [10] = true,
		[13] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true,
	}, -- Weapon
    [4] = {
		[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, 
		[7] = true, [8] = true, [9] = true, [10] = true, 
	}, -- Armor
}

-- Gossip
local function OnGossipHello(event, player, creature)
	if creature:GetEntry() ~= EngravingNPC_ID then return end

    player:GossipClearMenu()
    player:GossipComplete()

    AIO.Handle(player, "Engraving", "ShowEngravingUI")

    local playerGUID = player:GetGUIDLow()

    -- Stop any old timer
    local oldEvent = EngravingTimers[playerGUID]
    if oldEvent then
        oldEvent:Cancel()
    end

    -- Register new distance-checking event
    local event = player:RegisterEvent(function(_, _, _, player)
		local playerGUID = player:GetGUIDLow()
		local creatures = player:GetCreaturesInRange(EngravingCheckRange, EngravingNPC_ID)
        if (#creatures == 0) then
			player:RemoveEventById(EngravingTimers[playerGUID])
			EngravingTimers[playerGUID] = nil
            AIO.Handle(player, "Engraving", "ForceCloseUI")
            return
        end
    end, EngravingCheckInterval, 0)

    -- Cache event
    EngravingTimers[playerGUID] = event
end

local function OnGossipSelect(event, player, creature, sender, intid)
    if intid == 1 then
        AIO.Handle(player, "Engraving", "ShowEngravingUI")
    end
end

-- Utility
local function IsAllowedItem(itemEntry)
    if not itemEntry then return false end

    local class = itemEntry:GetClass()
    local subClass = itemEntry:GetSubClass()

    return ALLOWED_CLASS_AND_SUB_CLASS[class] and ALLOWED_CLASS_AND_SUB_CLASS[class][subClass]
end

local function GetSocketCountFromTemplate(itemId)
    local q = WorldDBQuery("SELECT socketColor_1, socketColor_2, socketColor_3 FROM item_template WHERE entry = "..itemId)
		if not q then return 0 end
		return (q:GetInt8(0) > 0 and 1 or 0) +
			(q:GetInt8(1) > 0 and 1 or 0) +
			(q:GetInt8(2) > 0 and 1 or 0)
	end

local function GetNextEnchant(itemEnchant)
 	local nextEnchantMap = {
		[0] = ENGRAVE_ENCHANTS[1],
		[ENGRAVE_ENCHANTS[1]] = ENGRAVE_ENCHANTS[2],
		[ENGRAVE_ENCHANTS[2]] = ENGRAVE_ENCHANTS[3],
	}
	return nextEnchantMap[itemEnchant]
end

local function GetRequiredMaterials(player, itemTemplate, itemEnchant, socketCount)
	local rarity = itemTemplate:GetQuality()
	local requiredLevel = itemTemplate:GetRequiredLevel()
	
	if (itemEnchant == ENGRAVE_ENCHANTS[3]) then
		return ENGRAVE_ENCHANTS[3], 0, {}
	elseif(socketCount == 3) then
		return itemEnchant, 0, {}
	end

	
	if (itemEnchant == 0) then
		itemEnchant = ENGRAVE_ENCHANTS[1]
	else
		itemEnchant =  GetNextEnchant(itemEnchant)
	end

	local query = WorldDBQuery(string.format([[
		SELECT 
			cost,
			material_1,
			material_1_count,
			material_2, 
			material_2_count,
			material_3, 
			material_3_count,
			material_4, 
			material_4_count,
			material_5, 
			material_5_count
		FROM engraving_upgrade_costs
		WHERE rarity = %d
			AND min_req_level < %d 
			AND max_req_level >= %d
			AND enchant_id = %d
		ORDER BY max_req_level  DESC 
		LIMIT 1
	]], rarity, requiredLevel, requiredLevel, itemEnchant))

	if not query then
		player:SendBroadcastMessage("|cffff0000[Engraving]|r No upgrade data found.")
		return
	end

	local cost = query:GetInt32(0)
	local materials = {}

	for i = 1, 5 do
		local matIndex = 1 + ((i - 1) * 2)
		local matId = query:GetInt32(matIndex)
		local matCount = query:GetInt32(matIndex + 1)

		if matId > 0 and matCount > 0 then
			local matItem = GetItemTemplate(matId)
			table.insert(materials, {
				id = matId,
				count = matCount,
				playerCount = player:GetItemCount(matId, false, false),
				name = matItem and matItem:GetName() or "Unknown",
				displayId = matItem and matItem:GetDisplayId() or 0,
				matItemLink = GetItemLink(matId),
			})
		end
	end
	return itemEnchant, cost, materials
end

AIO.AddHandlers("Engraving", {
	RequestItemByLink = function(player, itemId)
		if not itemId then return end

		local itemTemplate = GetItemTemplate(itemId)
		if not itemTemplate then
			player:SendBroadcastMessage("|cffff0000[Engraving]|r Item template not found.")
			return
		end

		local itemEntry = player:GetItemByEntry(itemId)
		local allowed = IsAllowedItem(itemEntry)

		local itemEnchant = itemEntry:GetEnchantmentId(6)
		local socketCount = GetSocketCountFromTemplate(itemId)

		local nextEnchant = 0
		local cost = 0
		local materials = {}
		if (allowed) then
			nextEnchant, cost, materials = GetRequiredMaterials(player, itemTemplate, itemEnchant, socketCount)
		end

		if itemEnchant == ENGRAVE_ENCHANTS[1] then socketCount = socketCount + 1
		elseif itemEnchant == ENGRAVE_ENCHANTS[2] then socketCount = socketCount + 2
		elseif itemEnchant == ENGRAVE_ENCHANTS[3] then socketCount = socketCount + 3 end

		if socketCount > 3 then socketCount = 3 end

		AIO.Msg():Add("Engraving", "ReturnUpgradeInfo", {
			itemId    = itemId,
			nextEnchant = nextEnchant,
			socketCount = socketCount,
			cost        = cost or 0,
			materials   = materials or {},
			allowedItem = allowed,
		}):Send(player)
	end,

	HandleEngraveRequest = function(player, itemId)
		if not itemId then return end
		local itemEntry = player:GetItemByEntry(itemId)
		local itemEnchant = itemEntry:GetEnchantmentId(6)
		local socketCount = GetSocketCountFromTemplate(itemId)
		local nextEnchant, cost, materials = GetRequiredMaterials(player, itemEntry, itemEnchant, socketCount)

		local allowed = IsAllowedItem(itemEntry)
		if (not allowed) then
		    player:SendBroadcastMessage("|cffff0000[Engraving]|r Item cannot be engraved")
			return
		end

		local playerMoney = player:GetCoinage()

		if (playerMoney < cost) then
		    player:SendBroadcastMessage("|cffff0000[Engraving]|r Not enough money.")
			return
		end

		for k,table in pairs(materials) do
			local hasMats = table.playerCount
			local needsMats = table.count
			if (hasMats > needsMats) then
				player:SendBroadcastMessage("|cffff0000[Engraving]|r Not enough materials.")
				return
			end
		end
	
		if itemEnchant == ENGRAVE_ENCHANTS[1] then socketCount = socketCount + 1
		elseif itemEnchant == ENGRAVE_ENCHANTS[2] then socketCount = socketCount + 2
		elseif itemEnchant == ENGRAVE_ENCHANTS[3] then socketCount = socketCount + 3 end

		if socketCount >= 3 then
		    player:SendBroadcastMessage("|cffff0000[Engraving]|r Max sockets reached.")
		    return
		end

		if itemEntry then
		    itemEntry:SetEnchantment(nextEnchant, 6)
		    player:SendBroadcastMessage("|cff00ff00[Engraving]|r Socket added.")

			player:SaveToDB()
			AIO.Msg():Add("Engraving", "SuccessfullyEngraved", {
				itemLink = itemEntry:GetItemLink(),
			}):Send(player)
		else
		    player:SendBroadcastMessage("|cffff0000[Engraving]|r Item not found.")
		end
	end,

	NotifyUIClose = function(player)
        local guid = player:GetGUIDLow()
        if EngravingTimers[guid] then
            EngravingTimers[guid]:Cancel()
            EngravingTimers[guid] = nil
        end
    end
})

RegisterCreatureGossipEvent(EngravingNPC_ID, 1, OnGossipHello)
RegisterCreatureGossipEvent(EngravingNPC_ID, 2, OnGossipSelect)

RegisterPlayerEvent(4, function(_, player) -- PLAYER_EVENT_ON_LOGOUT
    local playerGUID = player:GetGUIDLow()
    if EngravingTimers[playerGUID] then
        EngravingTimers[playerGUID]:Cancel()
        EngravingTimers[playerGUID] = nil
    end
end)
