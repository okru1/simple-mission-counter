local ADDON, ns = ...
local L = ns.L

-- Índices de expansión (iguales a LE_EXPANSION_* y a Map.ExpansionID en los DB2).
ns.OTHER_EXPANSION = 99
ns.LATEST_EXPANSION = 11 -- Midnight

local EXPANSION_FALLBACK_NAMES = {
    [0] = "Classic", [1] = "The Burning Crusade", [2] = "Wrath of the Lich King",
    [3] = "Cataclysm", [4] = "Mists of Pandaria", [5] = "Warlords of Draenor",
    [6] = "Legion", [7] = "Battle for Azeroth", [8] = "Shadowlands",
    [9] = "Dragonflight", [10] = "The War Within", [11] = "Midnight",
}

-- Continentes (uiMapID) -> expansión. Solo se usa para zonas que no vienen en
-- Data\QuestDB.lua (las generadas ya traen su expansión).
local CONTINENT_EXPANSION = {
    [12] = 0, [13] = 0,             -- Kalimdor, Reinos del Este
    [101] = 1,                      -- Terrallende
    [113] = 2,                      -- Rasganorte
    [948] = 3,                      -- La Vorágine
    [424] = 4,                      -- Pandaria
    [572] = 5,                      -- Draenor
    [619] = 6, [905] = 6,           -- Islas Abruptas, Argus
    [875] = 7, [876] = 7,           -- Zandalar, Kul Tiras
    [1550] = 8,                     -- Las Tierras Sombrías
    [1978] = 9,                     -- Islas Dragón
    [2274] = 10,                    -- Khaz Algar
}

-- Zonas que viven en un continente antiguo pero pertenecen a otra expansión.
local ZONE_EXPANSION = {
    -- Cataclysm
    [174] = 3, [179] = 3, [194] = 3, [198] = 3, [201] = 3, [202] = 3, [203] = 3,
    [204] = 3, [205] = 3, [207] = 3, [217] = 3, [241] = 3, [244] = 3, [245] = 3,
    [249] = 3,
    -- Battle for Azeroth
    [1355] = 7, [1462] = 7,
    -- Shadowlands (Isla del Exilio)
    [1409] = 8,
    -- Dragonflight
    [2133] = 9, [2200] = 9,
}

-- Primer uiMapID creado para Midnight (aprox.). Si una zona no cuelga de un
-- continente conocido y su ID es mayor, se asume Midnight.
local FIRST_MIDNIGHT_MAP = 2393

local MAPTYPE_CONTINENT = Enum.UIMapType.Continent
local MAPTYPE_ZONE = Enum.UIMapType.Zone

function ns.GetExpansionName(exp)
    if exp == ns.OTHER_EXPANSION then return L.OTHER end
    return _G["EXPANSION_NAME" .. exp] or EXPANSION_FALLBACK_NAMES[exp] or (L.OTHER .. " " .. exp)
end

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    print("|cff33ff99" .. L.TITLE .. "|r: " .. msg)
end

----------------------------------------------------------------------
-- Mapas
----------------------------------------------------------------------

local mapInfoCache = {}
local function GetMapInfo(mapID)
    if not mapID or mapID <= 0 then return nil end
    local info = mapInfoCache[mapID]
    if info == nil then
        info = C_Map.GetMapInfo(mapID) or false
        mapInfoCache[mapID] = info
    end
    return info or nil
end
ns.GetMapInfo = GetMapInfo

-- Sube desde mazmorras / micro-mapas / huérfanos hasta la zona que los contiene.
-- Devuelve nil para continentes, mundo o cosmos.
function ns.ResolveZone(mapID)
    local info = GetMapInfo(mapID)
    local guard = 0
    while info and info.mapType > MAPTYPE_ZONE and guard < 10 do
        local parent = GetMapInfo(info.parentMapID)
        if not parent or parent.mapType < MAPTYPE_ZONE then break end
        info = parent
        guard = guard + 1
    end
    if info and info.mapType >= MAPTYPE_ZONE then
        return info.mapID, info
    end
end

function ns.GetMapName(mapID)
    local info = GetMapInfo(mapID)
    return info and info.name or ("#" .. tostring(mapID))
end

function ns.GuessExpansion(mapID)
    local id, guard = mapID, 0
    while id and id > 0 and guard < 15 do
        if ZONE_EXPANSION[id] then return ZONE_EXPANSION[id] end
        if CONTINENT_EXPANSION[id] then return CONTINENT_EXPANSION[id] end
        local info = GetMapInfo(id)
        if not info or info.mapType < MAPTYPE_CONTINENT then break end
        id = info.parentMapID
        guard = guard + 1
    end
    if mapID >= FIRST_MIDNIGHT_MAP then return ns.LATEST_EXPANSION end
    return ns.OTHER_EXPANSION
end

----------------------------------------------------------------------
-- Índice de misiones: base de datos estática + misiones aprendidas
----------------------------------------------------------------------

ns.zones = {}       -- [zoneID] = { exp = n, quests = { questID, ... } }
ns.questZone = {}   -- [questID] = zoneID
ns.learnedCount = 0

local function GetZoneEntry(zoneID, exp)
    local z = ns.zones[zoneID]
    if not z then
        z = { exp = exp, quests = {} }
        ns.zones[zoneID] = z
    elseif z.exp == nil then
        z.exp = exp
    end
    return z
end

local function IndexQuest(questID, zoneID, exp)
    if ns.questZone[questID] then return false end
    ns.questZone[questID] = zoneID
    local z = GetZoneEntry(zoneID, exp)
    z.quests[#z.quests + 1] = questID
    return true
end

function ns:BuildIndex()
    wipe(self.zones)
    wipe(self.questZone)
    self.learnedCount = 0

    for zoneID, entry in pairs(self.QuestDB or {}) do
        for _, questID in ipairs(entry.q) do
            IndexQuest(questID, zoneID, entry.e)
        end
    end

    for zoneID, set in pairs(self.db.learned) do
        for questID in pairs(set) do
            if IndexQuest(questID, zoneID) then
                self.learnedCount = self.learnedCount + 1
            else
                set[questID] = nil -- ya está en la base estática, no hace falta guardarla
            end
        end
        if next(set) == nil then self.db.learned[zoneID] = nil end
    end

    for zoneID, z in pairs(self.zones) do
        if z.exp == nil then z.exp = self.GuessExpansion(zoneID) end
    end
end

-- Añade una misión descubierta en juego. Devuelve true si era nueva.
function ns:LearnQuest(questID, zoneID)
    if not questID or not zoneID or self.questZone[questID] then return false end
    self.db.learned[zoneID] = self.db.learned[zoneID] or {}
    self.db.learned[zoneID][questID] = true
    IndexQuest(questID, zoneID)
    local z = self.zones[zoneID]
    if z.exp == nil then z.exp = self.GuessExpansion(zoneID) end
    self.learnedCount = self.learnedCount + 1
    if self.db.debug then
        self.Print(L.LEARNED, self.GetMapName(zoneID), C_QuestLog.GetTitleForQuestID(questID) or questID)
    end
    self:RequestRecount()
    return true
end

local function IsTrackableQuest(questID)
    if C_QuestLog.IsWorldQuest(questID) or C_QuestLog.IsQuestTask(questID) then return false end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if logIndex then
        local info = C_QuestLog.GetInfo(logIndex)
        if info and (info.isHidden or info.isHeader) then return false end
    end
    return true
end

function ns:LearnFromQuestLog(questID)
    if not IsTrackableQuest(questID) then return end
    local zoneID = self.ResolveZone(GetQuestUiMapID(questID)) or self:GetPlayerZone()
    self:LearnQuest(questID, zoneID)
end

----------------------------------------------------------------------
-- Líneas de misiones (C_QuestLine) por zona
----------------------------------------------------------------------

local pendingQuestLineMaps = {}

function ns:RequestQuestLines(zoneID)
    if not zoneID then return end
    pendingQuestLineMaps[zoneID] = true
    C_QuestLine.RequestQuestLinesForMap(zoneID)
end

function ns:HarvestZone(zoneID)
    local learned = 0
    for _, line in ipairs(C_QuestLine.GetAvailableQuestLines(zoneID) or {}) do
        for _, questID in ipairs(C_QuestLine.GetQuestLineQuests(line.questLineID) or {}) do
            if self:LearnQuest(questID, zoneID) then learned = learned + 1 end
        end
    end
    return learned
end

function ns:HarvestPendingQuestLines()
    for zoneID in pairs(pendingQuestLineMaps) do
        self:HarvestZone(zoneID)
        pendingQuestLineMaps[zoneID] = nil
    end
end

-- Recorre todas las zonas del juego pidiendo sus líneas de misiones, una a una
-- (se avanza al recibir QUESTLINE_UPDATE o tras un pequeño timeout).
function ns:ScanAllZones()
    if self.scan then return end
    local queue, seen = {}, {}
    for _, info in ipairs(C_Map.GetMapChildrenInfo(946, MAPTYPE_ZONE, true) or {}) do -- 946 = Cosmos
        if not seen[info.mapID] then
            seen[info.mapID] = true
            queue[#queue + 1] = info.mapID
        end
    end
    self.Print(L.SCAN_START, #queue)
    self.scan = { queue = queue, i = 0, startLearned = self.learnedCount }
    self:ScanNext()
end

function ns:ScanNext()
    local scan = self.scan
    if not scan then return end
    if scan.current then self:HarvestZone(scan.current) end
    scan.i = scan.i + 1
    scan.current = scan.queue[scan.i]
    if not scan.current then
        self.scan = nil
        self.Print(L.SCAN_DONE, self.learnedCount - scan.startLearned)
        return
    end
    C_QuestLine.RequestQuestLinesForMap(scan.current)
    self:ScheduleScanStep(0.5)
end

function ns:ScheduleScanStep(delay)
    local scan = self.scan
    local step = scan.i
    C_Timer.After(delay, function()
        if self.scan == scan and scan.i == step then self:ScanNext() end
    end)
end

----------------------------------------------------------------------
-- Recuento
----------------------------------------------------------------------

ns.stats = { done = 0, total = 0, expansions = {} }
ns.justCompleted = {}

local function NewCounter() return { done = 0, total = 0 } end

function ns:Recount()
    local completed = {}
    for _, questID in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do
        completed[questID] = true
    end
    for questID in pairs(self.justCompleted) do completed[questID] = true end

    local stats = { done = 0, total = 0, expansions = {}, zones = {} }
    for zoneID, z in pairs(self.zones) do
        local zc = NewCounter()
        for _, questID in ipairs(z.quests) do
            zc.total = zc.total + 1
            if completed[questID] then zc.done = zc.done + 1 end
        end
        if zc.total > 0 then
            local exp = z.exp or self.OTHER_EXPANSION
            local ec = stats.expansions[exp]
            if not ec then
                ec = NewCounter()
                ec.zones = {}
                stats.expansions[exp] = ec
            end
            ec.zones[zoneID] = zc
            ec.done, ec.total = ec.done + zc.done, ec.total + zc.total
            stats.done, stats.total = stats.done + zc.done, stats.total + zc.total
            stats.zones[zoneID] = zc
        end
    end
    self.stats = stats
    self:UpdateUI()
end

function ns:RequestRecount(delay)
    if self.recountPending then return end
    self.recountPending = true
    C_Timer.After(delay or 0.5, function()
        self.recountPending = false
        self:Recount()
    end)
end

function ns:GetPlayerZone()
    return self.ResolveZone(C_Map.GetBestMapForUnit("player"))
end

function ns:GetZoneStats(zoneID)
    return zoneID and self.stats.zones and self.stats.zones[zoneID] or NewCounter()
end

function ns:UpdateUI()
    if self.ui then self.ui:Refresh() end
end

----------------------------------------------------------------------
-- Eventos
----------------------------------------------------------------------

local DEFAULTS = {
    shown = true,
    expanded = false,
    open = {},       -- [exp] = true si la expansión está desplegada en el desglose
    learned = {},
    debug = false,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if ns[event] then ns[event](ns, ...) end
end)

function ns:ADDON_LOADED(name)
    if name ~= ADDON then return end
    frame:UnregisterEvent("ADDON_LOADED")

    SimpleMissionCounterDB = SimpleMissionCounterDB or {}
    self.db = SimpleMissionCounterDB
    for k, v in pairs(DEFAULTS) do
        if self.db[k] == nil then self.db[k] = type(v) == "table" and {} or v end
    end

    self:BuildIndex()
    self.ui = self.CreateUI()

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUESTLINE_UPDATE")
end

function ns:PLAYER_ENTERING_WORLD()
    self:Recount()
    self:RequestQuestLines(self:GetPlayerZone())
    if not self.dbWarningShown and next(self.QuestDB) == nil then
        self.dbWarningShown = true
        self.Print(L.DB_EMPTY)
    end
end

function ns:ZONE_CHANGED_NEW_AREA()
    self:RequestQuestLines(self:GetPlayerZone())
    self:UpdateUI()
end

function ns:ZONE_CHANGED()
    self:UpdateUI()
end
ns.ZONE_CHANGED_INDOORS = ns.ZONE_CHANGED

function ns:QUEST_ACCEPTED(questID)
    self:LearnFromQuestLog(questID)
end

function ns:QUEST_TURNED_IN(questID)
    -- El flag de completada puede tardar un instante en aparecer en GetAllCompletedQuestIDs.
    self.justCompleted[questID] = true
    if not self.questZone[questID] then self:LearnFromQuestLog(questID) end
    self:RequestRecount(1)
end

function ns:QUESTLINE_UPDATE()
    if self.scan then
        self:ScheduleScanStep(0.05)
    end
    if next(pendingQuestLineMaps) then
        self:HarvestPendingQuestLines()
    end
end

----------------------------------------------------------------------
-- Comandos
----------------------------------------------------------------------

SLASH_SIMPLEMISSIONCOUNTER1 = "/smc"
SLASH_SIMPLEMISSIONCOUNTER2 = "/missioncounter"
SlashCmdList.SIMPLEMISSIONCOUNTER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "" or cmd == "toggle" then
        ns.ui:Toggle()
    elseif cmd == "expand" then
        ns.ui:SetExpanded(not ns.db.expanded)
    elseif cmd == "scan" then
        ns:ScanAllZones()
    elseif cmd == "reset" then
        ns.ui:ResetPosition()
        ns.Print(L.RESET_DONE)
    elseif cmd == "info" then
        local zones = 0
        for _ in pairs(ns.zones) do zones = zones + 1 end
        ns.Print(L.DB_INFO, ns.stats.total, zones, ns.learnedCount)
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("debug = %s", tostring(ns.db.debug))
    else
        ns.Print(L.HELP)
    end
end

function SimpleMissionCounter_OnAddonCompartmentClick()
    ns.ui:Toggle()
end
