#!/usr/bin/env python3
"""
Genera SimpleMissionCounter/Data/QuestDB.lua a partir de las tablas DB2 del
cliente de WoW exportadas en CSV por https://wago.tools.

Tablas usadas:
  QuestPOIBlob     QuestID -> UiMapID / MapID   (dónde están los objetivos de cada misión)
  UiMap            jerarquía de mapas (para subir de cuevas/micro-mapas a la zona)
  Map              ExpansionID de cada mapa del mundo
  QuestLineXQuest  (opcional) misiones sin POI heredan la zona de su línea de misiones
  QuestV2          (opcional) lista de misiones que existen en el cliente
  QuestV2CliTask   (opcional) misiones de mundo / objetivos de bonificación (se excluyen)

Uso:
  python3 tools/build_questdb.py                       # descarga de wago.tools (última build)
  python3 tools/build_questdb.py --build 12.1.0.69933  # una build concreta
  python3 tools/build_questdb.py --csv-dir ./csv       # CSV ya descargados (<Tabla>.csv)
"""

import argparse
import csv
import datetime
import io
import os
import sys
import urllib.request
from collections import Counter, defaultdict

# Tipos de UiMap (Enum.UIMapType)
COSMIC, WORLD, CONTINENT, ZONE, DUNGEON, MICRO, ORPHAN = range(7)

# Mismo criterio que Core.lua: zonas en continentes antiguos que son de otra expansión.
ZONE_EXPANSION = {
    174: 3, 179: 3, 194: 3, 198: 3, 201: 3, 202: 3, 203: 3, 204: 3, 205: 3,
    207: 3, 217: 3, 241: 3, 244: 3, 245: 3, 249: 3,
    1355: 7, 1462: 7,
    1409: 8,
    2133: 9, 2200: 9,
}

REQUIRED = ["QuestPOIBlob", "UiMap", "Map"]
OPTIONAL = ["QuestLineXQuest", "QuestV2", "QuestV2CliTask"]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "SimpleMissionCounter", "Data", "QuestDB.lua")


def load_table(name, args):
    if args.csv_dir:
        path = os.path.join(args.csv_dir, name + ".csv")
        if not os.path.exists(path):
            return None
        with open(path, newline="", encoding="utf-8-sig") as fh:
            return list(csv.DictReader(fh))
    url = "https://wago.tools/db2/%s/csv" % name
    if args.build:
        url += "?build=" + args.build
    print("Descargando", url, file=sys.stderr)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "SimpleMissionCounter-builder"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            text = resp.read().decode("utf-8-sig")
    except Exception as exc:  # noqa: BLE001
        print("  no se pudo descargar %s: %s" % (name, exc), file=sys.stderr)
        return None
    return list(csv.DictReader(io.StringIO(text)))


def col(row, *names, default=None):
    for n in names:
        if n in row and row[n] != "":
            return row[n]
    return default


def as_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", help="build del cliente, p. ej. 12.1.0.69933 (por defecto la última)")
    ap.add_argument("--csv-dir", help="carpeta con los CSV ya descargados")
    ap.add_argument("--out", default=DEFAULT_OUT, help="fichero Lua de salida")
    ap.add_argument("--include-world-quests", action="store_true",
                    help="no excluir misiones de mundo ni objetivos de bonificación")
    args = ap.parse_args()

    tables = {}
    for name in REQUIRED + OPTIONAL:
        tables[name] = load_table(name, args)
        if tables[name] is None and name in REQUIRED:
            sys.exit("Falta la tabla obligatoria %s" % name)

    # --- Mapas -----------------------------------------------------------
    uimap = {}
    for r in tables["UiMap"]:
        uimap[as_int(r["ID"])] = {
            "parent": as_int(col(r, "ParentUiMapID", default=0)),
            "type": as_int(col(r, "Type", default=-1), -1),
        }
    map_expansion = {as_int(r["ID"]): as_int(col(r, "ExpansionID", default=0)) for r in tables["Map"]}

    def resolve_zone(ui_map_id):
        """Igual que ns.ResolveZone en Core.lua."""
        info = uimap.get(ui_map_id)
        cur = ui_map_id
        guard = 0
        while info and info["type"] > ZONE and guard < 10:
            parent = uimap.get(info["parent"])
            if not parent or parent["type"] < ZONE:
                break
            cur, info = info["parent"], parent
            guard += 1
        if info and info["type"] >= ZONE:
            return cur
        return None

    # --- Filtros ---------------------------------------------------------
    existing = None
    if tables["QuestV2"]:
        existing = {as_int(r["ID"]) for r in tables["QuestV2"]}
    excluded = set()
    if tables["QuestV2CliTask"] and not args.include_world_quests:
        excluded = {as_int(r["ID"]) for r in tables["QuestV2CliTask"]}

    def wanted(qid):
        return qid > 0 and qid not in excluded and (existing is None or qid in existing)

    # --- Misión -> zona (por mayoría de POIs) ------------------------------
    quest_zone_votes = defaultdict(Counter)
    zone_exp_votes = defaultdict(Counter)
    for r in tables["QuestPOIBlob"]:
        qid = as_int(col(r, "QuestID"))
        if not wanted(qid):
            continue
        zone = resolve_zone(as_int(col(r, "UiMapID", default=0)))
        if zone is None:
            continue
        quest_zone_votes[qid][zone] += 1
        map_id = as_int(col(r, "MapID", default=-1), -1)
        if map_id in map_expansion:
            zone_exp_votes[zone][map_expansion[map_id]] += 1

    quest_zone = {qid: votes.most_common(1)[0][0] for qid, votes in quest_zone_votes.items()}
    from_poi = len(quest_zone)

    # --- Misiones sin POI: zona dominante de su línea de misiones ---------
    from_lines = 0
    if tables["QuestLineXQuest"]:
        line_quests = defaultdict(list)
        for r in tables["QuestLineXQuest"]:
            line_quests[as_int(r["QuestLineID"])].append(as_int(r["QuestID"]))
        for quests in line_quests.values():
            votes = Counter(quest_zone[q] for q in quests if q in quest_zone)
            if not votes:
                continue
            zone = votes.most_common(1)[0][0]
            for q in quests:
                if q not in quest_zone and wanted(q):
                    quest_zone[q] = zone
                    from_lines += 1

    # --- Agrupar por zona ---------------------------------------------------
    zones = defaultdict(list)
    for qid, zone in quest_zone.items():
        zones[zone].append(qid)

    def zone_expansion(zone):
        if zone in ZONE_EXPANSION:
            return ZONE_EXPANSION[zone]
        votes = zone_exp_votes.get(zone)
        return votes.most_common(1)[0][0] if votes else 99

    # --- Escribir Lua -------------------------------------------------------
    build = args.build or "latest"
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out = [
        "-- Este fichero lo genera tools/build_questdb.py. No editar a mano.",
        "-- Formato: D[uiMapID de zona] = { e = expansión (0 = Classic ... 11 = Midnight), q = { questIDs } }",
        "-- Build: %s  Generado: %s  Misiones: %d  Zonas: %d" % (build, now, len(quest_zone), len(zones)),
        "local _, ns = ...",
        "local D = {}",
        "ns.QuestDB = D",
        'ns.QuestDBInfo = { build = "%s", generated = "%s" }' % (build, now),
    ]
    for zone in sorted(zones):
        ids = sorted(zones[zone])
        chunks = [",".join(str(q) for q in ids[i:i + 25]) for i in range(0, len(ids), 25)]
        out.append("D[%d]={e=%d,q={\n%s\n}}" % (zone, zone_expansion(zone), ",\n".join(chunks)))
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")

    print("OK: %d misiones (%d por POI, %d por línea de misiones) en %d zonas -> %s"
          % (len(quest_zone), from_poi, from_lines, len(zones), args.out), file=sys.stderr)


if __name__ == "__main__":
    main()
