local _, ns = ...
local L = ns.L

local WIDTH = 330
local PADDING = 10
local BAR_HEIGHT = 18
local ROW_HEIGHT = 18
local LIST_HEIGHT = 320
local HEADER_HEIGHT = 24 + (BAR_HEIGHT + 4) * 2 + 6
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function Percent(done, total)
    if total <= 0 then return 0 end
    return done / total * 100
end

-- Rojo (0%) -> amarillo (50%) -> verde (100%)
local function PercentColor(pct)
    local f = math.min(math.max(pct / 100, 0), 1)
    if f < 0.5 then return 1, f * 2, 0 end
    return 2 - f * 2, 1, 0
end

local function FormatCount(done, total)
    local pct = Percent(done, total)
    local r, g, b = PercentColor(pct)
    return ("%d / %d  |cff%02x%02x%02x(%.1f%%)|r"):format(done, total, math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), pct)
end

local function CreateBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(1, 1, 1, 0.08)

    bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.left:SetPoint("LEFT", 4, 0)
    bar.left:SetJustifyH("LEFT")
    bar.left:SetWordWrap(false)

    bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.right:SetPoint("RIGHT", -4, 0)
    bar.right:SetJustifyH("RIGHT")
    bar.left:SetPoint("RIGHT", bar.right, "LEFT", -6, 0)

    function bar:SetProgress(done, total, alpha)
        self:SetValue(total > 0 and done / total or 0)
        local r, g, b = PercentColor(Percent(done, total))
        self:SetStatusBarColor(r * 0.7, g * 0.7, b * 0.2, alpha or 0.85)
        self.right:SetText(FormatCount(done, total))
    end
    return bar
end

----------------------------------------------------------------------

function ns.CreateUI()
    local db = ns.db
    local f = CreateFrame("Frame", "SimpleMissionCounterFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEADER_HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.8)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.point = { point, relPoint, x, y }
    end)

    function f:ResetPosition()
        db.point = nil
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end

    if db.point then
        f:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        f:ResetPosition()
    end

    -- Cabecera ---------------------------------------------------------
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PADDING, -8)
    title:SetText(L.TITLE)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Toggle() end)

    local expand = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    expand:SetSize(20, 18)
    expand:SetPoint("RIGHT", close, "LEFT", -2, 0)
    expand:SetScript("OnClick", function() f:SetExpanded(not db.expanded) end)
    expand:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.EXPAND_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    expand:SetScript("OnLeave", GameTooltip_Hide)
    f.expandButton = expand

    -- Línea 1: total; línea 2: zona actual --------------------------------
    local totalBar = CreateBar(f, BAR_HEIGHT)
    totalBar:SetPoint("TOPLEFT", PADDING, -28)
    totalBar:SetPoint("TOPRIGHT", -PADDING, -28)
    totalBar:EnableMouse(true)
    totalBar:SetScript("OnEnter", function(self)
        local zones = 0
        for _ in pairs(ns.zones) do zones = zones + 1 end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TOTAL, 1, 1, 1)
        GameTooltip:AddLine(L.TOTAL_TIP, nil, nil, nil, true)
        GameTooltip:AddLine(L.DB_INFO:format(ns.stats.total, zones, ns.learnedCount), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    totalBar:SetScript("OnLeave", GameTooltip_Hide)
    f.totalBar = totalBar

    local zoneBar = CreateBar(f, BAR_HEIGHT)
    zoneBar:SetPoint("TOPLEFT", totalBar, "BOTTOMLEFT", 0, -4)
    zoneBar:SetPoint("TOPRIGHT", totalBar, "BOTTOMRIGHT", 0, -4)
    f.zoneBar = zoneBar

    -- Desglose -----------------------------------------------------------
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", zoneBar, "BOTTOMLEFT", 0, -10)
    list:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    list:Hide()
    f.list = list

    local listTitle = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listTitle:SetPoint("TOPLEFT", 0, 0)
    listTitle:SetText(L.BREAKDOWN)

    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -16)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - PADDING * 2 - 22, 1)
    scroll:SetScrollChild(content)
    f.content = content

    local rows = {}
    local function GetRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Button", nil, content)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", content, "RIGHT")
        row.bar = CreateBar(row, ROW_HEIGHT - 2)
        row.bar:SetPoint("LEFT")
        row.bar:SetPoint("RIGHT")
        row.bar:EnableMouse(false)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if self.exp ~= nil then
                db.open[self.exp] = not db.open[self.exp] or nil
                f:Refresh()
            end
        end)
        rows[i] = row
        return row
    end

    local function SortedKeys(t, less)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, less)
        return keys
    end

    function f:RefreshList(currentZone)
        local n = 0
        local expansions = ns.stats.expansions
        for _, exp in ipairs(SortedKeys(expansions)) do
            local ec = expansions[exp]
            local isOpen = db.open[exp]
            n = n + 1
            local row = GetRow(n)
            row.exp = exp
            row.bar.left:SetPoint("LEFT", 4, 0)
            row.bar.left:SetFontObject("GameFontNormalSmall")
            row.bar.left:SetText((isOpen and "[-] " or "[+] ") .. ns.GetExpansionName(exp))
            row.bar:SetProgress(ec.done, ec.total, 0.85)
            row:Show()

            if isOpen then
                local zoneNames = {}
                for zoneID in pairs(ec.zones) do zoneNames[zoneID] = ns.GetMapName(zoneID) end
                local order = SortedKeys(ec.zones, function(a, b) return zoneNames[a] < zoneNames[b] end)
                for _, zoneID in ipairs(order) do
                    local zc = ec.zones[zoneID]
                    n = n + 1
                    row = GetRow(n)
                    row.exp = nil
                    row.bar.left:SetPoint("LEFT", 18, 0)
                    row.bar.left:SetFontObject(zoneID == currentZone and "GameFontNormalSmall" or "GameFontHighlightSmall")
                    row.bar.left:SetText((zoneID == currentZone and "> " or "") .. zoneNames[zoneID])
                    row.bar:SetProgress(zc.done, zc.total, 0.45)
                    row:Show()
                end
            end
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(n * ROW_HEIGHT, 1))
    end

    function f:Refresh()
        if not self:IsShown() then return end
        local stats = ns.stats
        self.totalBar.left:SetText(L.TOTAL)
        self.totalBar:SetProgress(stats.done, stats.total)

        local zoneID = ns:GetPlayerZone()
        if zoneID then
            local zc = ns:GetZoneStats(zoneID)
            self.zoneBar.left:SetText(L.ZONE .. ": " .. ns.GetMapName(zoneID))
            self.zoneBar:SetProgress(zc.done, zc.total)
        else
            self.zoneBar.left:SetText(L.ZONE .. ": " .. L.NO_ZONE)
            self.zoneBar:SetProgress(0, 0)
        end

        if db.expanded then self:RefreshList(zoneID) end
    end

    function f:SetExpanded(expanded)
        db.expanded = expanded and true or false
        self.expandButton:SetText(db.expanded and "-" or "+")
        self.list:SetShown(db.expanded)
        self:SetHeight(HEADER_HEIGHT + (db.expanded and LIST_HEIGHT or 0))
        self:Refresh()
    end

    function f:Toggle()
        db.shown = not self:IsShown()
        self:SetShown(db.shown)
        self:Refresh()
    end

    f:SetShown(db.shown)
    f:SetExpanded(db.expanded)
    return f
end
