# RiftStone Saga - Idle RPG (Godot 4)

## Struttura progetto

```
Icons/              # Icone UI e oggetti
Item_Texture/       # Texture degli item
addons/gut/         # Framework di test GUT 9.5.0
data/               # Dati JSON/risorse statiche
scenes/             # Scene .tscn
  battle/           # Scene combattimento, orb, worldmap, backgrounds
  gathering/        # Scene nodi raccolta risorse
  ui/               # Componenti UI (tooltip, loot, slot...)
scripts/            # Script GDScript
  battle/           # Logica combattimento, esplorazione, spawn, mappa
  crafting/         # Sistema gemme e bonus
  data/             # ItemDatabase
  gathering/        # Raccolta risorse
  systems/          # Sistemi core (Enhancement, Quest, Level, Gathering)
  ui/               # Tutti i componenti UI (inventory, equip, skill, quest...)
shaders/            # Shader visivi
tests/              # Test GUT
```

> Nota: alcune scene .tscn si trovano in `scripts/ui/` anziché in `scenes/`.

## Sistemi implementati

- **Inventory**: multi-cell drag-and-drop, bag system, grid resize
- **Equipment**: slot equipaggiamento, drag/drop da inventory
- **Tooltip**: hover con delay (0.2s), TooltipManager autoload
- **Battle**: combattimento idle, encounter generator, skill bar, orb system (loot/xp/gold)
- **World Map**: zone cliccabili, region zoom, background variabili per zona
- **Gathering**: nodi raccolta, GatheringDatabase, skill manager
- **Crafting**: gem crafting, bonus database, item bonus
- **Enhancement**: sistema potenziamento item
- **Quest**: QuestSystem, QuestLog UI, NPC indicators, obiettivi
- **Level System**: progressione XP
- **Loot Notification**: popup notifiche drop
- **Save/Diagnostic**: GameState persistenza, SaveDiagnostic

## Autoload (Singleton)

| Nome | Script |
|------|--------|
| `GameLogger` | `scripts/GameLogger.gd` |
| `GameState` | `scripts/GameState.gd` |
| `BonusDatabase` | `scripts/crafting/BonusDatabase.gd` |
| `GemCrafting` | `scripts/crafting/GemCrafting.gd` |
| `ItemDropGenerator` | `scripts/battle/ItemDropGenerator.gd` |
| `IData` | `scripts/data/ItemDatabase.gd` |
| `TooltipManager` | `scripts/ui/TooltipManager.gd` |
| `EnemyDatabase` | `scripts/battle/EnemyDatabase.gd` |
| `GatheringDatabase` | `scripts/gathering/GatheringDatabase.gd` |
| `EnhancementSystem` | `scripts/systems/EnhancementSystem.gd` |
| `QuestSystem` | `scripts/systems/QuestSystem.gd` |
| `LootOrbManager` | `scripts/battle/LootOrbManager.gd` |
| `XpOrbManager` | `scripts/battle/XpOrbManager.gd` |
| `GoldOrbManager` | `scripts/battle/GoldOrbManager.gd` |
| `LootNotificationManager` | `scripts/ui/LootNotificationManager.gd` |

## Convenzioni

- GDScript snake_case per variabili e funzioni
- PascalCase per nomi di classi e scene
- Autoload usati come singleton globali (non istanziare direttamente)
- `IData` è l'alias del singleton ItemDatabase — usare `IData.items["id"]`
- Scene e script UI spesso co-locati in `scripts/ui/`

## Test

- **Framework**: GUT 9.5.0 (by Butch Wesley)
- **Cartella test**: `tests/`
- **Comando headless**:
  ```
  godot --headless --script addons/gut/gut_cmdln.gd
  ```

## MCP Server

| Nome | Stato | Note |
|------|-------|------|
| `godot-ai` | **Connesso** | Plugin Godot AI v2.5.6 installato, server su `http://127.0.0.1:8000/mcp` — deve essere attivo Godot con il plugin abilitato |

> Il server parte automaticamente quando Godot è aperto con il progetto e il plugin **Godot AI** è abilitato in Project → Project Settings → Plugins.
> Usa `uvx` (Python) per avviare il processo: `uvx --from godot-ai==2.5.6 godot-ai --transport streamable-http --port 8000 --ws-port 9500`
> Per aggiornare: clicca **Update** nel dock Godot AI dentro l'editor.

## File da non toccare

- `addons/gut/` — framework esterno, non modificare
- `scripts/ui/SkillsTab_OLD_BACKUP.gd` — backup da eliminare quando confermato inutilizzato
- `scripts/ui/DACANCELLAREbottone.gd` — file da eliminare (nome esplicito)
