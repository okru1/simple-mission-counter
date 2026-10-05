-- Este fichero lo genera tools/build_questdb.py. No editar a mano.
-- Formato: D[uiMapID de zona] = { e = expansión (0 = Classic ... 11 = Midnight), q = { questIDs } }
-- Vacío por defecto: el addon funciona igualmente aprendiendo misiones en juego
-- (misiones aceptadas/entregadas y líneas de misiones de cada zona).
local _, ns = ...
local D = {}
ns.QuestDB = D
ns.QuestDBInfo = { build = "none", generated = "never" }
