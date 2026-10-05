# Simple Mission Counter

Addon para **World of Warcraft Retail 12.1.0 (Midnight)** que muestra cuántas misiones has completado:

```
┌ Simple Mission Counter ──────────── [+][x] ┐
│ Total               1234 / 25000  (4.9%)   │
│ Zona: Bosque de Elwynn   48 / 61  (78.7%)  │
└────────────────────────────────────────────┘
```

Con el botón **+** se despliega un desglose por expansión; al pulsar una expansión se ven sus zonas,
cada una con completadas / totales y porcentaje. La zona en la que estás aparece marcada con `>`.

## Instalación

Copia la carpeta `SimpleMissionCounter` en `World of Warcraft/_retail_/Interface/AddOns/`.

## Comandos

| Comando | Acción |
|---|---|
| `/smc` | Mostrar / ocultar la ventana (también desde el compartimento de addons del minimapa) |
| `/smc expand` | Desplegar / plegar el desglose |
| `/smc scan` | Recorrer todas las zonas del juego y aprender las misiones de sus líneas de misiones |
| `/smc info` | Tamaño de la base de datos |
| `/smc reset` | Recolocar la ventana |
| `/smc debug` | Avisar en el chat de cada misión nueva aprendida |

La ventana se arrastra con el ratón y recuerda su posición.

## De dónde salen los totales

El juego **no tiene ninguna API que diga cuántas misiones existen** ni a qué zona pertenecen; solo dice
qué misiones ha completado tu personaje (`C_QuestLog.GetAllCompletedQuestIDs`). Por eso el addon usa
dos fuentes para los totales:

1. **`Data/QuestDB.lua`** (estática): se genera con `tools/build_questdb.py` a partir de las tablas
   DB2 del cliente que publica [wago.tools](https://wago.tools):
   - `QuestPOIBlob` → en qué mapa están los objetivos de cada misión (cuevas y micro-mapas se suben a su zona).
   - `Map.ExpansionID` → a qué expansión pertenece cada zona.
   - `QuestLineXQuest` → misiones sin POI heredan la zona de su línea de misiones.
   - `QuestV2` / `QuestV2CliTask` → se descartan misiones inexistentes, misiones de mundo y objetivos de bonificación.
2. **Aprendizaje en juego** (guardado en `SimpleMissionCounterDB`, compartido entre personajes):
   misiones que aceptas o entregas, y las misiones de las líneas de misiones (`C_QuestLine`) de cada
   zona que visitas. `/smc scan` hace lo mismo para todas las zonas de golpe.

El repositorio incluye `Data/QuestDB.lua` **vacío**; genera la base de datos completa antes de jugar:

```sh
python3 tools/build_questdb.py                        # última build disponible en wago.tools
python3 tools/build_questdb.py --build 12.1.0.69933   # o una build concreta
python3 tools/build_questdb.py --csv-dir ./csv        # o CSV descargados a mano (QuestPOIBlob.csv, UiMap.csv, Map.csv, ...)
```

Opciones: `--include-world-quests` para contar también misiones de mundo; `--out` para otra ruta.

### Limitaciones conocidas

- Los totales incluyen misiones de **ambas facciones**, de clase, de profesión, etc. Ningún personaje
  puede llegar al 100 % en zonas con contenido de facción.
- El recuento de completadas es **por personaje**. Algunas misiones antiguas eliminadas siguen
  marcadas como completadas pero no cuentan si no están en la base de datos.
- Para zonas que no vienen en la base estática, la expansión se deduce del continente
  (`Core.lua`, tablas `CONTINENT_EXPANSION` / `ZONE_EXPANSION`); las zonas nuevas sin continente
  conocido con uiMapID ≥ 2393 se asignan a Midnight.
