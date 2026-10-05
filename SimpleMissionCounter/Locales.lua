local _, ns = ...

local L = {
    TITLE          = "Simple Mission Counter",
    TOTAL          = "Total",
    ZONE           = "Zona",
    NO_ZONE        = "Sin zona",
    OTHER          = "Otros",
    BREAKDOWN      = "Desglose por expansión",
    EXPAND_TIP     = "Mostrar / ocultar el desglose por expansión y zona",
    TOTAL_TIP      = "Misiones completadas por este personaje que están en la base de datos del addon.",
    DB_INFO        = "Base de datos: %d misiones en %d zonas (%d aprendidas en juego).",
    DB_EMPTY       = "La base de datos de misiones está vacía. Genera Data\\QuestDB.lua con tools/build_questdb.py (ver README) o deja que el addon aprenda mientras juegas.",
    SCAN_START     = "Escaneando líneas de misiones de %d zonas...",
    SCAN_DONE      = "Escaneo terminado: %d misiones nuevas aprendidas.",
    LEARNED        = "Nueva misión aprendida en %s: %s",
    HELP           = "Comandos: /smc (mostrar/ocultar), /smc expand, /smc scan, /smc reset, /smc info, /smc debug",
    RESET_DONE     = "Posición restablecida.",
}

if GetLocale() ~= "esES" and GetLocale() ~= "esMX" then
    L.ZONE        = "Zone"
    L.NO_ZONE     = "No zone"
    L.OTHER       = "Other"
    L.BREAKDOWN   = "Breakdown by expansion"
    L.EXPAND_TIP  = "Show / hide the per-expansion and per-zone breakdown"
    L.TOTAL_TIP   = "Quests completed by this character that are present in the addon database."
    L.DB_INFO     = "Database: %d quests in %d zones (%d learned in game)."
    L.DB_EMPTY    = "The quest database is empty. Generate Data\\QuestDB.lua with tools/build_questdb.py (see README) or let the addon learn while you play."
    L.SCAN_START  = "Scanning quest lines for %d zones..."
    L.SCAN_DONE   = "Scan finished: %d new quests learned."
    L.LEARNED     = "New quest learned in %s: %s"
    L.HELP        = "Commands: /smc (show/hide), /smc expand, /smc scan, /smc reset, /smc info, /smc debug"
    L.RESET_DONE  = "Position reset."
end

ns.L = L
