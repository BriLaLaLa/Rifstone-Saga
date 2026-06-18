# COMBAT OVERHAUL — REFERENCE INTERNO (solo per Claude)
# Aggiornato: 2026-06-15
# Leggimi SEMPRE prima di toccare codice del nuovo sistema combat.

---

## 1. COSA STIAMO FACENDO

Sostituzione completa del sistema combat "slot statico" con un sistema top-down 2D:
- Tilemap per zona (con collision layer per ostacoli al pathfinding)
- Player centrato a schermo (icona quadrata, vista dall'alto)
- Nemici come icone che si avvicinano al player quando aggroed
- Player segue un PATH (array di waypoint), NON si muove autonomamente con AI
- Route predefinite per zona + route custom salvabili per personaggio
- Quando aggro: player devia dal path → combatte → torna al punto di uscita → riprende path
- Skill: TUTTE AUTOMATICHE (nessun input manuale). Sistema auto-cast invariato.
- Minimap in basso a destra centrata sul player

---

## 2. AUDIT DEL CODICE ESISTENTE

### AUTOLOAD (tutti in project.godot, tutti riusabili)
| Singleton | File | Status |
|---|---|---|
| GameLogger | scripts/GameLogger.gd | ✅ Riusa |
| GameState | scripts/GameState.gd | ✅ Riusa |
| BonusDatabase | scripts/crafting/BonusDatabase.gd | ✅ Riusa |
| GemCrafting | scripts/crafting/GemCrafting.gd | ✅ Riusa |
| ItemDropGenerator | scripts/battle/ItemDropGenerator.gd | ✅ Riusa |
| IData | scripts/data/ItemDatabase.gd | ✅ Riusa |
| TooltipManager | scripts/ui/TooltipManager.gd | ✅ Riusa |
| EnemyDatabase | scripts/battle/EnemyDatabase.gd | ✅ Riusa |
| GatheringDatabase | scripts/gathering/GatheringDatabase.gd | ✅ Riusa |
| EnhancementSystem | scripts/systems/EnhancementSystem.gd | ✅ Riusa |
| QuestSystem | scripts/systems/QuestSystem.gd | ✅ Riusa |
| LootOrbManager | scripts/battle/LootOrbManager.gd | ✅ Riusa |
| XpOrbManager | scripts/battle/XpOrbManager.gd | ✅ Riusa |
| GoldOrbManager | scripts/battle/GoldOrbManager.gd | ✅ Riusa |
| LootNotificationManager | scripts/ui/LootNotificationManager.gd | ✅ Riusa |

### FILE DA SOSTITUIRE COMPLETAMENTE
| File | Perché |
|---|---|
| scripts/battle/BattleArea.gd | Slot-based, incompatibile con top-down |
| scripts/battle/SlotManager.gd | Gestisce slot fissi, non nemici con posizione 2D |
| scripts/battle/EnemySlot.gd | Slot UI astratto, va sostituito con CharacterBody2D enemy |
| scripts/battle/GridLayoutManager.gd | Non serve più |
| scripts/battle/BackgroundManager.gd | Sostituito da tilemap loader |
| scripts/battle/ExplorationUI.gd | UI exploration da rifare per top-down |
| scripts/battle/ExplorationCombatController.gd | Riscritto (logica riusabile, architettura no) |
| scripts/battle/CombatStateManager.gd | Riscritto (stati diversi per top-down) |
| scenes/battle/BattlefieldBase.tscn + tutte m1_z1_* | Sostituiti da tilemap scenes |
| scenes/battle/EnemySlot.tscn | Sostituito da Enemy.tscn (CharacterBody2D) |

### FILE DA ADATTARE (non riscrivere)
| File | Cosa cambia |
|---|---|
| scripts/battle/SkillCastController.gd | Target da EnemySlot → Enemy (CharacterBody2D). Logica auto-cast invariata. |
| scripts/battle/WarriorSkill.gd | Nessuna modifica |
| scripts/battle/SkillDatabase.gd | Nessuna modifica |
| scripts/battle/CombatSkillBar.gd | Nessuna modifica visiva |
| scripts/battle/EncounterGenerator.gd | Adattare output: non più slot assignment, ma spawn positions su tilemap |
| scripts/battle/PitySystem.gd | Nessuna modifica |
| scripts/battle/ItemDropGenerator.gd | Nessuna modifica |
| scripts/battle/ZoneData.gd | Aggiungere: tilemap_scene path, spawn_points array, default_routes array |
| scripts/GameState.gd | Aggiungere: current_route, current_path_index, zone_routes dict |
| scripts/CharacterStats.gd | Nessuna modifica |
| scripts/systems/LevelSystem.gd | Nessuna modifica |

### FILE CHE RESTANO INTATTI
- Tutto in scripts/crafting/
- Tutto in scripts/data/
- Tutto in scripts/gathering/
- Tutto in scripts/systems/ (Quest, Enhancement, Level, ecc.)
- Tutto in scripts/ui/ (Inventory, Equipment, Skills tab, ecc.)
- XpOrb.tscn, GoldOrb.tscn, LootOrb.tscn e relativi .gd
- CharacterDisplay.tscn / CharacterDisplay.gd
- WorldMapView / WorldMapController (navigazione mappa mondo)
- RegionZoomView / RegionZoomController (navigazione regione)

---

## 3. NUOVA ARCHITETTURA

### 3.1 Scene Structure nuova zona combat

```
ZoneCombatScene.tscn (sostituisce BattleArea)
├── TileMapLayer (collision + visual, baked NavigationRegion2D)
├── NavigationRegion2D (navmesh per player e nemici)
├── PlayerCharacter (CharacterBody2D)
│   ├── Sprite2D (icona quadrata)
│   ├── CollisionShape2D
│   ├── NavigationAgent2D
│   ├── DetectionArea (Area2D — rileva nemici in range)
│   └── PlayerPathController.gd
├── EnemySpawnPoints (Node2D)
│   ├── SpawnPoint1..N (Marker2D — posizioni spawn fixed per zona)
├── ActiveEnemies (Node2D — container nemici vivi)
├── PathDisplay (Node2D — visualizza route corrente, debug/UI)
├── Minimap (SubViewportContainer — angolo basso destra)
│   └── SubViewport
│       └── MinimapCamera
└── CombatHUD (CanvasLayer)
    ├── CombatSkillBar
    ├── RouteSelector (UI per scegliere route)
    └── ExitButton
```

### 3.2 Script principali da creare

#### PlayerPathController.gd (CharacterBody2D script)
Stati:
```
enum PlayerState {
    FOLLOWING_PATH,     # Segue waypoint corrente del path
    DEVIATING,          # Si sta muovendo verso nemico aggroed
    ENGAGING,           # In combat range, fermo, auto-combat attivo
    RETURNING           # Torna al punto di uscita dal path
}
```

Variabili chiave:
```gdscript
var current_path: Array[Vector2]      # Waypoint del path corrente
var current_path_index: int           # Waypoint corrente
var return_target: Vector2            # Dove tornare dopo combat
var state: PlayerState
var nav_agent: NavigationAgent2D
var detection_radius: float = 150.0   # Raggio aggro
var combat_range: float = 60.0        # Range per fermarsi e combattere
var move_speed: float = 120.0
```

Logica core:
```gdscript
func _physics_process(delta):
    match state:
        FOLLOWING_PATH:   _follow_path()
        DEVIATING:        _move_to_enemy()
        ENGAGING:         pass  # Fermo, SkillCastController fa tutto
        RETURNING:        _return_to_path()

# Detection area signal
func _on_enemy_entered_detection(enemy):
    if state == FOLLOWING_PATH or state == RETURNING:
        return_target = nav_agent.target_position  # Salva posizione corrente nel path
        state = DEVIATING
        nav_agent.set_target_position(enemy.global_position)

# Quando tutti nemici morti
func on_combat_ended():
    state = RETURNING
    nav_agent.set_target_position(return_target)

# Quando raggiunto return_target
func _on_return_complete():
    state = FOLLOWING_PATH
    # Riprende dal waypoint corrente (non torna indietro)
```

#### Enemy2D.gd (CharacterBody2D)
Stati:
```
enum EnemyState { IDLE, CHASING, ATTACKING, DEAD }
```

Variabili chiave:
```gdscript
var enemy_data: Dictionary            # Da EnemyDatabase
var current_hp, max_hp: float
var attack_timer: float
var attack_damage: float
var nav_agent: NavigationAgent2D
var aggro_range: float = 200.0
var attack_range: float = 50.0
var player: CharacterBody2D
```

Logica: IDLE → player in aggro_range → CHASING → player in attack_range → ATTACKING (timer).

#### ZoneCombatController.gd (Node — gestisce la zona intera)
Responsabilità:
- Carica tilemap della zona
- Spawna nemici ai spawn points (usa EncounterGenerator + PitySystem)
- Connette SkillCastController al player e ai nemici
- Gestisce ciclo: spawn → combat → rewards → respawn
- Gestisce route: carica default, salva/carica custom
- Espone segnali a BattleTab

#### RouteManager.gd (Node)
Responsabilità:
- Mantiene lista route disponibili per ogni zona (default + custom)
- Salva/carica route custom su file (user://routes_ZONE_ID.json)
- Fornisce current_route al PlayerPathController
- UI per disegnare nuova route cliccando sulla minimap

### 3.3 Route Data Structure
```gdscript
# Una route è:
{
    "id": "route_m1_z1_default_1",
    "name": "Giro degli Slime",
    "zone_id": "m1_z1",
    "is_default": true,
    "waypoints": [Vector2(100,200), Vector2(300,150), ...]  # In coordinate tilemap
    "loop": true   # true = loop infinito, false = ping-pong
}
```

### 3.4 ZoneData aggiornato
Aggiungere a ZoneData.gd:
```gdscript
@export var tilemap_scene: String     # path a .tscn della tilemap
@export var spawn_points: Array       # [{position: Vector2, id: String}, ...]
@export var default_routes: Array     # Array di route dict
```

---

## 4. ROADMAP IMPLEMENTATIVA (Step by Step)

### STEP 1 — Tilemap base + Player che segue path
**File da creare:**
- scenes/combat/ZoneCombatScene.tscn
- scripts/combat/PlayerPathController.gd
- scripts/combat/ZoneCombatController.gd
- scenes/combat/zones/m1_z1_tilemap.tscn (prima zona di test)

**File da modificare:**
- scripts/battle/ZoneData.gd (aggiungere tilemap_scene, spawn_points, default_routes)
- scenes/battle/BattleTab.tscn (aggiungere ZoneCombatScene come view alternativa)
- scripts/battle/BattleTab.gd (routing verso nuova view quando zona cliccata)

**Risultato verificabile:** Player si muove su tilemap seguendo waypoint, loop infinito.

---

### STEP 2 — Nemici + Aggro + Pathfinding
**File da creare:**
- scenes/combat/Enemy2D.tscn
- scripts/combat/Enemy2D.gd

**File da modificare:**
- scripts/combat/ZoneCombatController.gd (spawn nemici + gestione ciclo)
- scripts/combat/PlayerPathController.gd (aggro detection, deviation, return)
- scripts/battle/EncounterGenerator.gd (output spawn positions invece di slot assignment)

**Risultato verificabile:** Nemici spawnano, si avvicinano al player, player devia, combat visibile.

---

### STEP 3 — Auto-combat + Loot
**File da modificare:**
- scripts/battle/SkillCastController.gd (target Enemy2D invece di EnemySlot)
- scripts/combat/Enemy2D.gd (take_damage, death, spawn orbs)
- scripts/combat/ZoneCombatController.gd (connette SkillCastController, gestisce death events)

**File da lasciare invariati:**
- XpOrbManager, GoldOrbManager, LootOrbManager (funzionano già con posizione 2D)

**Risultato verificabile:** Player auto-casta skill sui nemici. Nemici muoiono. Orb XP/Gold/Loot spawnano.

---

### STEP 4 — Route System (Default + Custom)
**File da creare:**
- scripts/combat/RouteManager.gd

**File da modificare:**
- scripts/GameState.gd (aggiungere current_route per zona)
- ZoneData.gd (aggiungere default_routes)

**Risultato verificabile:** Player cicla su route default. UI mostra route disponibili. Possibile salvare route custom.

---

### STEP 5 — Minimap
**File da creare:**
- scenes/combat/Minimap.tscn
- scripts/combat/Minimap.gd

**Note:** SubViewport con camera che segue player, scala ridotta, mostra spawn points e path.

---

### STEP 6 — Polishing + Integrazione completa
- Animazioni player (direzione movimento, combat idle)
- Visual feedback aggro (cerchio rosso, effetto)
- Transizione WorldMap → RegionZoom → ZoneCombat (sostituisce vecchia BattleArea view)
- GUT tests per PlayerPathController state machine
- GUT tests per Enemy2D aggro logic
- GUT tests per ZoneCombatController spawn cycle

---

## 5. COSE DA NON DIMENTICARE

1. **NavigationRegion2D bake** va fatto in editor DOPO aver disegnato la tilemap. Serve layer collision sulla tilemap.

2. **SkillCastController** usa `get_random_alive_enemy()` e `get_all_alive_enemies()` via SlotManager. Nel nuovo sistema queste query vanno a ZoneCombatController che tiene `active_enemies: Array[Enemy2D]`.

3. **XpOrbManager** cerca `CharacterDisplay` nel scene tree navigando da `/root`. Verificare che il path rimanga valido dopo il refactor della BattleTab.

4. **CharacterStats.take_damage()** è il metodo che riceve danno da nemici. Enemy2D lo userà identicamente a EnemySlot attuale.

5. **PitySystem** si aggiorna chiamando `on_encounter_result(type)` dopo ogni combat. ZoneCombatController deve farlo.

6. **Save/Load route custom** in `user://routes_{zone_id}.json`. Non nel save principale per non appesantirlo.

7. **GUT test suite** esiste in `/tests/`. Prima di ogni step fare: Run GUT → tutti verdi → poi codice.

8. **Godot AI** disponibile per generare snippet. Usarlo per boilerplate ma sempre rivedere output.

9. **EnemyDatabase** ha `get_enemy_stats(enemy_id, level)` con scaling. Enemy2D deve usarlo al posto di dati raw.

10. **Il path è in loop**: quando il player raggiunge l'ultimo waypoint, torna al primo. Il `return_target` deve puntare al waypoint ESATTO che stava raggiungendo, non alla posizione fisica corrente (altrimenti salta waypoint).

---

## 6. STATO CORRENTE

- [x] Audit codebase completo
- [x] Architettura definita
- [x] Step 1: Tilemap + Player path  ← FATTO (2026-06-15)
- [x] Step 2: Nemici + Aggro  ← FATTO e verificato a runtime (2026-06-16)
- [x] Step 3: Auto-combat + Loot  ← FATTO e verificato a runtime (2026-06-16)
- [x] Step 4: Route System (selezione default + persistenza)  ← FATTO e verificato (2026-06-16)
- [x] Step 5: Route custom disegnate sull'arena (al posto della minimap, decisione utente)  ← FATTO e verificato (2026-06-16). Minimap separata SALTATA (arena già interamente visibile, sarebbe ridondante).
- [x] Step 6: Polishing  ← FATTO (2026-06-16). Barre HP nemici, skill bar in zona (reparent), feedback aggro ("!") + flash danno, fix priorità skill (attacco base come ripiego), test GUT (test_enemy2d 7/7, test_zone_combat_controller 7/7). NON fatto: animazioni-sprite skill nel SubViewport (vortice/sibilare) — richiede rework coordinate, lasciato come task dedicato.

## ✅ OVERHAUL COMBAT COMPLETO (tutti e 6 gli step). Sistema top-down funzionante e verificato a runtime.

## STEP 1 — DETTAGLIO FILE CREATI

### Nuovi file
| File | Descrizione |
|---|---|
| scripts/combat/PlayerPathController.gd | CharacterBody2D con state machine 5 stati + NavigationAgent2D |
| scripts/combat/ZoneCombatController.gd | Node2D root della scena: setup zona, path, HUD exit |
| scenes/combat/ZoneCombatScene.tscn | Scena base: Background, NavigationRegion2D, PathDisplay, PlayerCharacter, EnemySpawnPoints, ActiveEnemies |
| scenes/combat/zones/m1_z1_combat.tscn | Prima zona: TileMapLayer + SpawnPoints (da configurare in editor) |

### File modificati
| File | Cosa è cambiato |
|---|---|
| scripts/battle/ZoneData.gd | +background_key, +tilemap_scene, +default_routes (export + from_dict) |
| scripts/battle/BattleTab.gd | +ZONE_COMBAT nav state, +zone_combat_instance, +_show_zone_combat(), +_on_zone_combat_exited(), +_cleanup_zone_combat(), +_get_default_route(). _on_zone_clicked() ora smista tra vecchio e nuovo sistema basandosi su zone_data.tilemap_scene |

## STEP 6 — DETTAGLIO (polishing)

### Modifiche
| File | Cosa |
|---|---|
| scenes/combat/Enemy2D.tscn | +HPBar (ProgressBar, stili StyleBoxFlat nel tscn) +AggroMark (Label "!"). |
| scripts/combat/Enemy2D.gd | _hp_bar aggiornato in setup/take_damage; _flash_hit (modulate bianco→base 0.14s); _base_modulate; AggroMark visibile in CHASING/ATTACKING; congela se `not is_visible_in_tree()`. |
| scripts/battle/BattleTab.gd | _show_zone_combat: combat_skill_bar.reparent(_zone_combat) + visible; _cleanup_zone_combat: reparent indietro su battle_area + hide. |
| scripts/battle/SkillCastController.gd | _check_and_cast_next_skill: salta id=="basic_attack" nel loop priorità (è il ripiego). PRIMA: basic_attack equipaggiato in slot alto vinceva sempre → hiss/vortex mai castate. |
| tests/test_enemy2d.gd | NUOVO 7/7 (setup/take_damage/morte/is_alive/aggro). Nemico sotto un Node2D (DamageNumber usa parent.global_position). |
| tests/test_zone_combat_controller.gd | NUOVO 7/7 (spawn 3-6, route default, targeting, clear_combat). |

### Note
- Skill animazioni-sprite (vortice/sibilare) NON riattivate: erano in spazio-schermo Control, in zona il mondo è in SubViewport → serve rework coordinate (spawn effetti in game_world Node2D a pos world). Feedback combat coperto da: numeri danno + flash + barra HP + aggro mark.
- GUT: 59 test, 51 pass, 7 fail PRE-ESISTENTI (bag, item_drops, quest, stacking — non legati al combat).

## STEP 5 — DETTAGLIO (route custom su arena, niente minimap)

### File modificati
| File | Cosa è cambiato |
|---|---|
| scenes/combat/ZoneCombatScene.tscn | +DrawButton/SaveRouteButton/CancelRouteButton in HudInner; +DrawOverlay (Control, copre l'arena offset_top=46, visible=false, mouse_filter IGNORE→STOP in draw mode). |
| scripts/combat/ZoneCombatController.gd | +_draw_mode/_draft. _enter/_exit_draw_mode, _on_overlay_input (click→_screen_to_world→append draft→preview via _draw_path), _save_draft_route (RouteManager.save_custom_route, append a _available_routes, refresh dropdown, applica), _cancel_draw. +_route_to_path (refactor da _apply_route), _clear_path_display, _redraw_active_path. _screen_to_world = local_pos * (SubViewport.size/SubViewportContainer.size) [con stretch=true il fattore è ~1]. |

### Bugfix correlati (stessa sessione)
- "Zona appesa dopo morte / back to map": _show_world_map e _show_region_zoom spengono _zone_combat se ancora visibile; Enemy2D._physics_process si congela se `not is_visible_in_tree()` (niente combat in background a scheda cambiata); _cleanup_zone_combat chiama _zone_combat.clear_combat() (queue_free nemici).
- "Re-targeting": il player tracciava un solo _target_enemy → se moriva, ignorava altri nemici già aggrati (nessun nuovo body_entered). Fix in PlayerPathController: _tick_engage controlla se il target è morto; _retarget_or_return sceglie il nemico più vicino in DetectionArea.get_overlapping_bodies(); torna al path solo se nessuno. _is_target_valid/_nearest_enemy_in_detection.

## STEP 4 — DETTAGLIO FILE CREATI/MODIFICATI

### Nuovi file
| File | Descrizione |
|---|---|
| scripts/combat/RouteManager.gd | RefCounted (NO class_name, preloadato). get_routes(zone_id, default_routes)=default+custom; get/set_selected_route_id; save_custom_route. Persistenza user://routes_{zone_id}.json → {custom:[...], selected:"id"}. |

### File modificati
| File | Cosa è cambiato |
|---|---|
| scenes/combat/ZoneCombatScene.tscn | +RouteLabel ("Rotta:") +RouteOption (OptionButton) in HudBar/HudInner. |
| scripts/combat/ZoneCombatController.gd | +RouteManagerScript preload, +_route_option @onready, +zone_id/_available_routes/_route_manager. setup() costruisce lista route via RouteManager, sceglie quella ricordata (o la prima), popola dropdown, _apply_route(true). +_selected_route_index/_populate_route_dropdown/_on_route_selected. _apply_route(teleport): teleport=true solo allo start; cambio rotta → player.change_path (no teleport, no interruzione combat). |
| scripts/combat/PlayerPathController.gd | +change_path(waypoints, loop): aggiorna rotta SENZA teleport; ridirige al waypoint più vicino solo se in FOLLOWING_PATH/RETURNING; se in combat (DEVIATING/ENGAGING) la nuova rotta entra in vigore al ritorno. |
| scripts/battle/BattleTab.gd | _show_zone_combat: zone_dict include default_routes. |

### Note Step 4
- Disegno route CUSTOM non ancora fatto (era previsto via minimap Step 5). Per ora si scelgono solo le default della zona dal dropdown.
- Cambio rotta a caldo: niente teleport, e se combatte finisce i nemici prima di incamminarsi alla nuova rotta.

## STEP 3 — DETTAGLIO FILE MODIFICATI

### File modificati
| File | Cosa è cambiato |
|---|---|
| scripts/combat/Enemy2D.gd | ATTACKING infligge danno al player su cooldown (attack_speed sec) via GameState.character_stats.take_damage. take_damage mostra DamageNumber (preload script) sul parent. |
| scripts/combat/ZoneCombatController.gd | +COMBAT_RADIUS 160. Interfaccia targeting per SkillCastController: get_alive_enemy_count/get_random_alive_enemy/get_all_alive_enemies → SOLO nemici entro COMBAT_RADIUS dal player (gating: skill partono solo quando ingaggia). _on_enemy_died → _spawn_reward_orbs (XP/Gold/Loot via manager autoload). _world_to_screen converte pos SubViewport→schermo per gli orb. |
| scripts/battle/BattleTab.gd | _show_zone_combat: collega skill_cast_controller (set_slot_manager(_zone_combat), set_battle_area(null), start_combat), is_battle_active=true, overlay skills. _cleanup_zone_combat: stop_combat + slot_manager null + overlay off. _show_world_map/_show_region_zoom: difensivo, spengono _zone_combat se ancora visibile (fix "zona appesa dopo morte"). |
| scripts/battle/SkillCastController.gd | _check_and_cast_next_skill: guard `not slot_manager and not battle_area` (prima richiedeva battle_area, bloccava il nuovo sistema con battle_area=null). |

### Note tecniche Step 3
- Le skill colpiscono SOLO entro COMBAT_RADIUS → il gating sull'ingaggio è nei metodi targeting di ZoneCombatController, NON in SkillCastController (che resta generico).
- battle_area=null in zone combat → niente visual effects skill (sword vortex/sibilare fanno fallback a danno diretto). Skill bar non visibile in zona. Entrambi rimandati a Step 6.
- Orb: i nemici sono in SubViewport (spazio 800×600); _world_to_screen scala con SubViewportContainer.size/SubViewport.size + global_position per spawnare gli orb nel punto schermo giusto.
- Player death in zone: character_stats.take_damage→player_died→BattleTab._on_player_died→_show_world_map (che ora chiama _cleanup_zone_combat).

## STEP 2 — DETTAGLIO FILE CREATI/MODIFICATI

### Nuovi file
| File | Descrizione |
|---|---|
| scripts/combat/Enemy2D.gd | CharacterBody2D, state machine IDLE→CHASING→ATTACKING→DEAD. setup(id,level,player) usa EnemyDatabase.get_enemy_stats. take_damage/_die con segnale died(enemy). aggro_range 220, attack_range 48, move_speed 80. Sprite da stats.icon, fallback icon.svg rosso a ~36px. |
| scenes/combat/Enemy2D.tscn | CharacterBody2D groups=["enemies"], collision_layer=4 (rilevato da DetectionArea del player, mask=4), collision_mask=2 (boundary walls). Sprite2D + CollisionShape2D circle 16. |

### File modificati
| File | Cosa è cambiato |
|---|---|
| scripts/combat/ZoneCombatController.gd | +ENEMY_SCENE preload, +_enemies (Array untyped), +_spawn_wave/_spawn_enemy/_random_spawn_pos/_on_enemy_died/_on_wave_cleared/_clear_enemies/get_alive_enemies. setup() chiama _spawn_wave(). Ondata 3-6 nemici da zone_data.enemies, posizioni random nel mondo 800x600 a ≥200px dal player. Su wave_cleared: combat_ended + player.on_all_enemies_dead() + respawn dopo 2s (se ancora visible). |

### Note tecniche Step 2
- PlayerPathController aveva GIÀ tutta la logica aggro (_on_detect_enter→DEVIATING→ENGAGING, on_all_enemies_dead→RETURNING). Nessuna modifica necessaria al player.
- Aggro funziona via gruppo "enemies" + collision_layer 4 ↔ DetectionArea mask 4.
- IMPORTANTE: i tipi `Enemy2D` NON vanno usati come annotazione in ZoneCombatController (class_name non in cache durante GUT headless → parse error). Usare Array/var untyped + duck typing sulla scena preloadata.
- Step 2 = solo spawn + aggro + inseguimento. NESSUN danno reale: i nemici non muoiono finché Step 3 non collega SkillCastController→Enemy2D.take_damage e Enemy2D.ATTACKING→player.

### Come attivare il nuovo sistema su una zona
In zones.json (o via editor), aggiungere alla zona:
```json
"tilemap_scene": "res://scenes/combat/zones/m1_z1_combat.tscn",
"background_key": "m1_z1_1"
```
Quando present, BattleTab usa ZoneCombatController invece di ExplorationCombatController.

### Note tecniche Step 1 (post-fix)
- ZoneCombatScene root = Control (non Node2D) con anchors FULL_RECT → si ridimensiona col parent
- GameWorld = Node2D figlio del Control → qui vivono player, nemici, path
- PlayerPathController usa SOLO movimento diretto (no NavigationAgent2D per il path)
  - NavigationAgent2D è in scena ma inutilizzato finché Step 2 (ostacoli reali)
- ZoneCombatController.resized → _update_layout() → resize background + rebuild boundary walls
- Player parte dal primo waypoint della route (non da posizione fissa in .tscn)
- zones.json: red_kingdom_lv1_10 ha tilemap_scene + 2 default_routes (coordinate assolute in px)
- GUT test: tests/test_player_path_controller.gd (14 test cases, path = GameWorld/PlayerCharacter)
- BattleTab: set_anchors_preset(FULL_RECT) sull'istanza prima di addChild
