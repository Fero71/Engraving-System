-- Only create once
local EngravingFrame

local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local function ResetEngravingUI()
    local frame = EngravingFrame
    if not frame then return end
    
    frame.itemLink = nil
    frame.itemGuid = nil
    frame.itemId = nil

    if frame.ItemSlot then
        frame.ItemSlot.itemLink = nil
        frame.ItemSlot.IconTexture:SetTexture(nil)
        frame.ItemSlot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    end

    if frame.TooltipPreview then
        frame.TooltipPreview:Hide()
        frame.TooltipPreview:ClearLines()
    end

    if frame.EngraveButton then
        frame.EngraveButton:Disable()
        frame.EngraveButton:SetText("Engrave")
    end

    if frame.MaterialSlots then
        for _, reagent in ipairs(frame.MaterialSlots) do
            reagent:Hide()
            if reagent.icon then reagent.icon:SetTexture(nil) end
            if reagent.Count then reagent.Count:SetText("") end
            reagent:SetScript("OnEnter", nil)
            reagent:SetScript("OnLeave", nil)
        end
    end

    if frame.CostText then
        frame.CostText:SetText("")
    end
end

local MyHandlers = AIO.AddHandlers("Engraving", {
    ShowEngravingUI = function()
        if not EngravingFrame then
            CreateEngravingUI()
        end

        -- Always reset state when opening
        ResetEngravingUI()

        -- Close gossip only
        if GossipFrame and GossipFrame:IsShown() then
            CloseGossip()
        end

        ShowUIPanel(EngravingFrame)
    end,

    ForceCloseUI = function()
        if EngravingFrame and EngravingFrame:IsShown() then
            ResetEngravingUI()
            HideUIPanel(EngravingFrame)
        end
    end,

    ReturnUpgradeInfo = function(player, data)
        if not data.allowedItem then
            ResetEngravingUI()
            return
        end
        
        if data.itemId  == nil then return end
        if data.nextEnchant == nil then return end
        if data.socketCount == nil then return end
        if data.cost  == nil then return end

        local itemLink = EngravingFrame.itemLink
        if not itemLink then
            return
        end

        -- create HyperLink for preview
        local modifiedLink = itemLink
        if data.socketCount then
            modifiedLink = itemLink:gsub("item:(%d+):%d+", "item:%1:" .. data.nextEnchant)
        end

        local tooltipFrame = EngravingFrame.TooltipPreview
        if not tooltipFrame then
            tooltipFrame = CreateFrame("GameTooltip", "EngravingTooltipPreview", UIParent, "GameTooltipTemplate")
            EngravingFrame.TooltipPreview = tooltipFrame
        end

        tooltipFrame:SetOwner(EngravingFrame, "ANCHOR_NONE")
        tooltipFrame:SetPoint("TOP", EngravingFrame, "TOP", 0, -49) -- Adjust as needed
        tooltipFrame:ClearLines()

        tooltipFrame:SetHyperlink(modifiedLink)
        tooltipFrame:SetFrameLevel(5)
        tooltipFrame:Show()

        if EngravingFrame.ItemInfoBox then
            EngravingFrame.ItemInfoBox:Hide()
        end

        -- Cost text
        if EngravingFrame.CostText then
            local gold = 0
            local silver = 0
            local copper = 0
            if (data.cost) then 
                gold = math.floor(data.cost / 10000)
                silver = math.floor((data.cost % 10000) / 100)
                copper = data.cost % 100
            end
            
            EngravingFrame.CostText:SetText(string.format(
                "|cffffff00%d|r|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t " ..
                "|cffcccccc%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t " ..
                "|cffcc9966%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t",
                gold, silver, copper
            ))
        end

        -- itemGuid
        EngravingFrame.itemGuid = data.itemGuid
        EngravingFrame.itemId = data.itemId

        -- Check socket count
        if EngravingFrame.EngraveButton then
            if data.socketCount and data.socketCount >= 3 then
                EngravingFrame.EngraveButton:Disable()
                EngravingFrame.EngraveButton:SetText("Max Sockets")
            else
                EngravingFrame.EngraveButton:Enable()
                EngravingFrame.EngraveButton:SetText("Engrave")
            end
        end

        -- Reagents
        for _, reagent in ipairs(EngravingFrame.MaterialSlots) do
            reagent:Hide()
        end

        for i, mat in ipairs(data.materials or {}) do
            if mat.id and mat.id > 0 then
                local reagent = EngravingFrame.MaterialSlots[i]
                if reagent then
                    if not reagent.icon then
                        local icon = reagent:CreateTexture(nil, "BORDER")
                        icon:SetAllPoints()
                        reagent.icon = icon
                    end

                    if not reagent.Count then
                        reagent.Count = reagent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        reagent.Count:SetPoint("BOTTOMRIGHT", -4, 4)
                    end

                    local _, _, _, _, _, _, _, _, _, matIcon = GetItemInfo(mat.id)
                    reagent.icon:SetTexture(matIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

                    local have = mat.playerCount or 0
                    local need = mat.count or 0
                    reagent.Count:SetText(have .. "/" .. need)
                    reagent.Count:SetTextColor(have >= need and 0 or 1, 1, 0)

                    reagent:SetScript("OnEnter", function(self)
                        if mat.matItemLink then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetHyperlink(mat.matItemLink)
                            GameTooltip:SetFrameLevel(100)
                            GameTooltip:Show()
                        end
                    end)
                    reagent:SetScript("OnLeave", GameTooltip_Hide)

                    reagent:Show()
                end
            end
        end
    end,

    SuccessfullyEngraved = function(player, data)

        if not EngravingFrame then
            return
        end

        if not data.itemLink then
            return
        end

        -- Update main itemLink reference
        EngravingFrame.itemLink = data.itemLink

        -- Reparse item ID from new itemLink if needed
        local itemId = tonumber(data.itemLink:match("item:(%d+):")) or EngravingFrame.itemId
        EngravingFrame.itemId = itemId

        -- Update visual slot
        if EngravingFrame.ItemSlot then
            EngravingFrame.ItemSlot.itemLink = data.itemLink
            local texture = select(10, GetItemInfo(data.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark"
            _G[EngravingFrame.ItemSlot:GetName() .. "IconTexture"]:SetTexture(texture)
        end

        -- Update tooltip preview
        if EngravingFrame.TooltipPreview and EngravingFrame.TooltipPreview:IsVisible() then
            EngravingFrame.TooltipPreview:SetHyperlink(data.itemLink)
        end

        -- Re-request material/cost info
        if itemId then
            AIO.Handle("Engraving", "RequestItemByLink", itemId)
        end
    end,
})

function CreateEngravingUI()
    EngravingFrame = CreateFrame("Frame", "EngravingUI", UIParent)
    UIPanelWindows["EngravingUI"] = { area = "left", pushable = 1, whileDead = 1 }

    local frame = EngravingFrame
    
    frame:SetSize(500, 500)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetToplevel(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.Title:SetPoint("TOP", 0, -20)
    frame.Title:SetText("Socket Engraving")

    -- Item Slot
    local ItemSlot = CreateFrame("Button", "EngravingItemSlot", frame, "ItemButtonTemplate")
    ItemSlot:SetSize(50, 50)
    ItemSlot:SetPoint("TOPLEFT", 30, -50)
    ItemSlot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    ItemSlot.IconTexture = _G[ItemSlot:GetName() .. "IconTexture"]
    ItemSlot:EnableMouse(true)
    ItemSlot:SetFrameStrata("DIALOG")
    ItemSlot:SetFrameLevel(3)
    ItemSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ItemSlot:RegisterForDrag("LeftButton")

    -- Tooltip Preview
    local tooltipFrame = CreateFrame("GameTooltip", "EngravingTooltipPreview", frame, "GameTooltipTemplate")
    tooltipFrame:SetOwner(frame, "ANCHOR_NONE")
    tooltipFrame:SetPoint("TOP", frame, "TOP", 0, -49)
    tooltipFrame:SetFrameLevel(5)
    tooltipFrame:Hide()
    frame.TooltipPreview = tooltipFrame

    -- Reagent Slots
    frame.MaterialSlots = {}
    local spacing = 48
    local startX = 30
    local posY = 55

    for i = 1, 5 do
        local reagent = CreateFrame("Button", nil, frame, "ItemButtonTemplate")
        reagent:SetSize(40, 40)
        reagent:SetPoint("BOTTOMLEFT", startX + ((i - 1) * spacing), posY)
        reagent:Hide()
        frame.MaterialSlots[i] = reagent
    end

    -- Cost and Buttons
    frame.CostText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.CostText:SetPoint("BOTTOMLEFT", 35, 25)
    frame.CostText:SetText("")

    frame.CancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.CancelButton:SetSize(100, 26)
    frame.CancelButton:SetPoint("BOTTOMRIGHT", -140, 20)
    frame.CancelButton:SetText("Cancel")
    frame.CancelButton:SetScript("OnClick", function()
        ResetEngravingUI()
        HideUIPanel(frame)
        AIO.Handle("Engraving", "NotifyUIClose")
    end)

    frame.EngraveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.EngraveButton:SetSize(100, 26)
    frame.EngraveButton:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.EngraveButton:SetText("Engrave")
    frame.EngraveButton:SetScript("OnClick", function()
        if EngravingFrame.itemId then
            AIO.Handle("Engraving", "HandleEngraveRequest", EngravingFrame.itemId)
        else
            print("Missing item data.")
        end
    end)

    -- events

     EngravingFrame:SetScript("OnHide", function(self)
        self.itemLink = nil
        self.itemId = nil

        if self.ItemSlot then
            self.ItemSlot.itemLink = nil

            local icon = _G[self.ItemSlot:GetName() .. "IconTexture"]
            if icon then
                icon:SetTexture(nil)
            end

            self.ItemSlot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
        end

        -- The rest is fine:
        if self.TooltipPreview then
            self.TooltipPreview:Hide()
            self.TooltipPreview:ClearLines()
        end

        if self.EngraveButton then
            self.EngraveButton:Disable()
            self.EngraveButton:SetText("Engrave")
        end

        if self.MaterialSlots then
            for _, reagent in ipairs(self.MaterialSlots) do
                reagent:Hide()
                if reagent.icon then
                    reagent.icon:SetTexture(nil)
                end
                if reagent.Count then
                    reagent.Count:SetText("")
                end
                reagent:SetScript("OnEnter", nil)
                reagent:SetScript("OnLeave", nil)
            end
        end

        if self.CostText then
            self.CostText:SetText("")
        end

        self.itemGuid = nil
    end)
    
    ItemSlot:SetScript("OnReceiveDrag", function(self)
        local cursorType, itemId, itemLink = GetCursorInfo()
        if cursorType ~= "item" then return end

        itemLink = itemLink or (itemId and select(2, GetItemInfo(itemId)))
        if not itemLink then return end

        ClearCursor()
        self.itemLink = itemLink -- still keep for UI updates if needed
        EngravingFrame.itemLink = itemLink

        _G[self:GetName() .. "IconTexture"]:SetTexture(select(10, GetItemInfo(itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark")
        self:SetNormalTexture(nil)

        AIO.Handle("Engraving", "RequestItemByLink", itemId)
    end)

    ItemSlot:SetScript("OnClick", function(self)
        local cursorType = GetCursorInfo()
        if cursorType == "item" then
            self:GetScript("OnReceiveDrag")(self)
            return
        end

        if self.itemLink then
            PickupItem(self.itemLink)
            self.itemLink = nil
            
            -- Reset Engrave button
            if EngravingFrame.EngraveButton then
                EngravingFrame.EngraveButton:Disable()
                EngravingFrame.EngraveButton:SetText("Engrave")
            end

            _G[self:GetName() .. "IconTexture"]:SetTexture(nil)
            self:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")

            if EngravingFrame.ItemInfoBox then
                EngravingFrame.ItemInfoBox:Hide()
            end
            if EngravingFrame.TooltipPreview then
                EngravingFrame.TooltipPreview:Hide()
            end

            EngravingFrame.CostText:SetText("")
            for _, reagent in ipairs(EngravingFrame.MaterialSlots) do
                reagent:Hide()
            end
        end
    end)

    ItemSlot:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    ItemSlot:SetScript("OnLeave", GameTooltip_Hide)
end