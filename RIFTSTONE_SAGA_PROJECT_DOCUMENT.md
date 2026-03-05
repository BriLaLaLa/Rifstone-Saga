# 🎮 **RiftStone Saga - Documento di Progetto Completo**

## 📋 **Executive Summary**

**RiftStone Saga** è un ambizioso **Idle/AFK Action RPG** per PC sviluppato in Godot 4.5, che fonde meccaniche di giochi idle moderni con sistemi di progressione profonda ispirati a MMO classici. Il progetto combina l'automazione strategica dei giochi idle con la complessità e soddisfazione dei grandi Action RPG.

---

## 🎯 **Concept e Visione**

### Genere
**Idle/AFK Action RPG** con elementi MMO e progressione incrementale

### Ispirazione Principale
- **Metin2**: Sistema di combattimento, zone ed enhancement rischioso
- **Path of Exile**: Alberi passivi complessi e build diversity
- **Clash Royale**: Sistema di incontri a ondate dinamiche
- **Idle Games moderni**: Automazione e progressione passiva

### Gameplay Loop Core
```
Esplora Mappa Mondo → Seleziona Zona → Combattimento Automatico →
Raccogli Loot (Orbs) → Potenzia Equipaggiamento → Sblocca Zone Più Difficili
```

---

## 🌍 **Mondo di Gioco e Progressione Zone**

### Sistema World Map Multilivello

**3 Regni Principali:**

1. **Red Kingdom** (Livello 1-50) - ✅ **Implementato**
   - **Plains** (Lv 1-10): Zone iniziale per principianti
   - **Mountains** (Lv 11-30): Difficoltà intermedia
   - **Dark Forest** (Lv 31-50): Challenge avanzato

2. **Blue Kingdom** (Livello 50+) - 🚧 **Pianificato**
   - Unlock: Livello 50
   - Nuovi enemy types e meccaniche

3. **Green Kingdom** (Livello 75+) - 🚧 **Pianificato**
   - Unlock: Livello 75
   - Endgame content

### Caratteristiche Esplorazione
- **Mappa interattiva cliccabile** con regioni selezionabili
- **Level-gating progressivo**: Zone sbloccate in base al livello
- **Background dinamici**: Ogni zona ha ambientazioni uniche
- **Difficoltà scalabile**: Enemy stats aumentano con il livello zona

---

## ⚔️ **Sistema di Combattimento**

### Meccanica Core: Automated Combat

**Caratteristiche:**
- Attacco automatico del giocatore
- Target manuale cliccando i nemici
- 7 spawn points visuali per nemici (grid dinamica)
- Sistema di skill auto-cast

### Sistema Incontri (Clash Royale-Style)

**3 Tipi di Encounter:**

1. **Normal Encounter** (80% base)
   - 5-6 nemici standard
   - Gold e EXP regolare
   - Drop items comuni

2. **Miniboss Encounter** (15% → 40% con pity)
   - 1-2 boss + 3-4 nemici normali
   - Loot migliorato
   - Drop rate gemme aumentato

3. **Metin Encounter** (5% → 20% con pity)
   - Pietra Metin speciale (boss statico)
   - Loot premium garantito
   - Chance items rari/epici

### Pity System
**Sistema anti-frustrazione intelligente:**
- Contatori indipendenti per Miniboss e Metin
- +2% probabilità per ogni normal encounter consecutivo
- Reset automatico dopo encounter raro
- Max boost: 40% (Miniboss) / 20% (Metin)

### Nemici Attuali
- **Lupo** (Normal): Fast attacks, pack behavior
- **Cinghiale** (Normal): High HP, medium damage
- **Scrofa** (Boss): Giant boar, heavy attacks, high HP

---

## 💪 **Sistema Skill Warrior**

### Active Combat Skills

**Skill Bar da 4 Slot:**
- Customizzabile dal Skills Tab
- Auto-cast quando cooldown pronto
- Gestione mana (100 base)
- Sincronizzazione real-time tra UI

**Skill Types:**
- **Single Target**: Danno concentrato su un nemico
- **AoE (Area of Effect)**: Colpisce nemici multipli
- **Multi-target**: Divide danno tra obiettivi
- **Self-buff**: Potenziamenti temporanei

**Sistema Skill Properties:**
```gdscript
{
  "cooldown": 5.0,        # Secondi tra cast
  "mana_cost": 20,        # Costo mana
  "damage_min": 15,       # Danno minimo
  "damage_max": 25,       # Danno massimo
  "cast_time": 0.5,       # Tempo casting
  "effects": []           # Buff/debuff applicati
}
```

**Skill Attuale:**
- ✅ Basic Attack (no cooldown/mana)
- ✅ Hiss (intimidation skill)
- 🚧 Power Strike (planned)
- 🚧 Whirlwind (AoE planned)

---

## 📊 **Sistema Statistiche Avanzato**

### Attributi Primari
- **Strength** (STR): Physical damage, carry weight
- **Dexterity** (DEX): Attack speed, critical chance
- **Intelligence** (INT): Magic damage, mana pool
- **Vitality** (VIT): Max HP, HP regen
- **Luck** (LUK): Critical damage, item find

### Statistiche Offensive
- Physical Damage / Magic Damage
- Attack Speed (attacks/sec)
- Critical Chance (%)
- Critical Damage (multiplier)

### Statistiche Difensive
- Physical Defense / Magic Defense
- Evasion (%)
- Block Chance (%)
- Block Amount (flat reduction)

### Statistiche Elementali
**3 Elementi Implementati:**
- 🔥 Fire Damage & Resistance
- ❄️ Ice Damage & Resistance
- ⚡ Lightning Damage & Resistance

### Statistiche Utility
- HP Regeneration/sec
- Mana Regeneration/sec
- Movement Speed
- Cooldown Reduction (%)

### Statistiche Bonus (Loot/Farming)
- **Lifesteal** (%): HP recuperato da danno inflitto
- **Gold Find** (%): Bonus oro raccolto
- **Magic Find** (%): Migliora rarità loot
- **EXP Bonus** (%): Accelera leveling

---

## 🎒 **Sistema Inventario Grid-Based**

### Architettura Inventario

**Grid Tetris-Style:**
- Base: **6 colonne** (fisso)
- Righe: **Dinamiche** basate su bag equipaggiate
- Item sizes: 1×1, 1×2, 2×1, 2×2 (espandibile)

**Capacità:**
- **Base**: 30 slot (6×5 grid)
- **Con Starter Bag**: 20 slot extra → 50 totali (6×9)
- **Max teorico**: 5 bag × 20 slot = 120 slot totali

### Bag System (5 Slot)

**Slot Features:**
- **Slot 0**: Starter Bag (locked, non removibile)
- **Slot 1-4**: Bag equipaggiabili/removibili

**Protezione Rimozione:**
- Sistema can_remove_bag() verifica spazio disponibile
- Calcolo automatico redistribuzione items
- Blocco rimozione se items non fittano
- Messaggio errore visuale se fallisce

### Inventory Features
✅ **Drag & Drop completo**: Riposizionamento libero
✅ **Stacking intelligente**: Items stackabili (pozioni, materiali)
✅ **Position persistence**: Items ricordano posizione tra sessioni
✅ **Auto-sort**: Organizzazione automatica
✅ **Trash Bin**: Eliminazione drag-to-delete
✅ **Tooltip system**: Hover 0.2s delay, stats completi

---

## 🛡️ **Sistema Equipaggiamento**

### Equipment Slots (6 Total)
```
┌─────────────────────┐
│  Helmet    Weapon   │
│  Chest     Shield   │
│  Belt      Boots    │
└─────────────────────┘
```

**Slot Equipaggiabili:**
- **Helmet**: Difesa, HP bonus
- **Weapon**: Danno fisico/magico principale
- **Chest**: Difesa massima, Vitality
- **Shield**: Block chance, defensive stats
- **Belt**: Utility stats, inventory slots
- **Boots**: Movement speed, evasion

### Item Rarity System

**4 Livelli di Rarità:**

| Rarità | Colore | Effetti Visivi | Drop Rate |
|--------|--------|----------------|-----------|
| Common | Bianco | Nessuno | 60% |
| Rare | Blu | Glow leggero | 30% |
| Epic | Viola | Particle effects | 9% |
| Legendary | Arancione | Glow intenso + particles | 1% |

### Equipment Bonuses

**Stats Base + Bonus Procedurali:**
```json
{
  "iron_sword": {
    "stats": {
      "physical_damage": 15,
      "strength": 2
    },
    "bonuses": [
      {"stat": "attack_speed", "value": 5, "type": "percent"},
      {"stat": "critical_chance", "value": 3, "type": "flat"}
    ]
  }
}
```

---

## ✨ **Sistema Enhancement (Metin2-Style)**

### Enhancement Levels: +0 → +9

**Success Rates:**
```
+0 → +3:  100%  (Safe enhancement)
+3 → +4:   95%
+4 → +5:   90%
+5 → +6:   70%
+6 → +7:   50%
+7 → +8:   40%
+8 → +9:   30%  (High risk!)
```

**Destruction Chances (on Failure):**
```
+0 → +5:   0%   (No destruction risk)
+5 → +6:  10%
+6 → +7:  20%
+7 → +8:  40%
+8 → +9:  60%  (Molto rischioso!)
```

### Stat Multipliers per Level
```
+0: 1.0×  (Base stats)
+1: 1.05× (+5%)
+2: 1.10× (+10%)
+3: 1.15× (+15%)
+4: 1.20× (+20%)
+5: 1.30× (+30%)
+6: 1.45× (+45%)
+7: 1.60× (+60%)
+8: 2.00× (+100%)
+9: 2.50× (+150%)
```

### Effetti Shader Visuali

**+7: "Controlled Energy"**
- Aura luminosa attorno all'item
- Colore: Bianco/Azzurro

**+8: "Unstable Energy"**
- Particelle pulsanti
- Effetto glow intermittente
- Colore: Viola

**+9: "Manifested Artifact"**
- Radiosità leggendaria intensa
- Particle effects continui
- Colore: Oro/Arancione
- Trail effect quando equipaggiato

### Enhancement Costs

| Level | Gold | Ore | Mystic Stones | Ancient Crystals |
|-------|------|-----|---------------|------------------|
| +1 | 100 | 0 | 0 | 0 |
| +3 | 500 | 10 | 0 | 0 |
| +5 | 2,000 | 50 | 5 | 0 |
| +7 | 10,000 | 100 | 20 | 0 |
| +9 | 50,000 | 200 | 50 | 10 |

---

## 💎 **Sistema Gem Crafting**

### 5 Tipi di Gemme

**1. ForceGem** (Offensive)
- Aggiunge +1 Prefisso (max 2 totali)
- Prefissi: Physical Damage %, Attack Speed %, Crit Chance

**2. Gem of Agility** (Defensive/Utility)
- Aggiunge +1 Suffisso (max 2 totali)
- Suffissi: HP Regen, Auto-Heal on Damage, Evasion %

**3. Gem of Chaos** (Reroll)
- Randomizza TUTTI i bonus esistenti
- Alto rischio/alta ricompensa
- Può migliorare o peggiorare l'item

**4. Gem of Excellence** (Rarity Upgrade)
- Common → Rare → Epic → Legendary
- Success rate diminuisce per rarità alta
- Mantiene bonus esistenti

**5. Gem of Renewal** (Reset)
- Rimuove TUTTI i bonus dall'item
- Ritorna item a stato base
- Usato per "pulire" item mal rolled

### Gem Application Mechanics
```
Apply Gem → Check max bonuses → Generate random stat →
Add to item → Consume gem (if successful) → Update tooltip
```

**Gem Modified Items:**
- Icona speciale nell'angolo
- Tooltip mostra bonus procedurali
- Colore bordo diverso in inventory

---

## 🎁 **Sistema Loot Orbs Visuali**

### 3 Tipi di Orbs

**1. Gold Orbs** 💰
- Spawna alla morte nemico
- Attrazione magnetica automatica
- Particle effect: Monete rotanti
- Colore: Giallo/Oro

**2. XP Orbs** ⭐
- Spawna per ogni kill
- Quantità basata su livello nemico
- Colore: Verde/Blu brillante
- Effetto trail durante raccolta

**3. Item Orbs** 🎁
**Colori per Rarità:**
- Common: Bianco
- Rare: Blu
- Epic: Viola intenso
- Legendary: Arancione fiammeggiante

**Orb Physics:**
- Spawna in posizione morte nemico
- Movimento verso player (magnetic pull)
- Collision detection
- Despawn timer: 30 secondi

### Loot Tables per Enemy

**Drop Probabilities:**
```json
{
  "lupo": {
    "gold": {"min": 5, "max": 15},
    "xp": 20,
    "items": [
      {"id": "wolf_tail", "chance": 0.30},
      {"id": "wolf_liver", "chance": 0.15},
      {"id": "gem_of_agility", "chance": 0.05}
    ]
  }
}
```

### Loot Notification System
- Toast persistenti in alto a destra
- Stack automatico items identici
- Fade out dopo 3 secondi
- Click per dismiss

---

## 🌳 **Sistema Passive Skill Tree (PoE-Style)**

### 4 Alberi Separati

**1. Main Combat Tree**
- +1 Passive Point per livello combat
- ~50-100 nodi pianificati
- Focus: Combat stats, damage, defense

**2. Mining Tree**
- +1 Point per livello Mining
- Nodi: Ore yield, mining speed, rare ore chance

**3. Herbalism Tree**
- +1 Point per livello Herbalism
- Nodi: Herb yield, gathering speed, rare herb chance

**4. Fishing Tree**
- +1 Point per livello Fishing
- Nodi: Fish size, catch speed, rare fish chance

### Node Types

**Small Nodes** (Majority)
- +5/+10 to single stat
- Esempio: "+10 Strength", "+5% Physical Damage"

**Notable Nodes** (Intermedi)
- Bonus multipli moderati
- Esempio: "+15 Strength, +10% Physical Damage"

**Keystone Nodes** (Rari, game-changing)
- Effetti unici potenti con drawback
- Esempio: "Deal 50% more damage, but take 30% more damage"

### UI Features
- **Pan & Zoom**: Right-click drag, scroll zoom
- **Prerequisite chains**: Deve sbloccare nodi connessi
- **Visual connections**: Linee tra nodi correlati
- **Respec**: Costo oro per resettare points (pianificato)

---

## ⛏️ **Sistema Gathering**

### 4 Skill di Gathering

**1. Mining** ⛏️
- **Raccolta**: Ore, pietre, gemme grezze
- **Nodes**: Copper Ore, Iron Ore, Gold Ore
- **Tools**: Pickaxe (tiers: Stone → Iron → Steel)

**2. Herbalism** 🌿
- **Raccolta**: Erbe, fiori, ingredienti alchemici
- **Nodes**: Healing Herbs, Mana Flowers, Rare Roots
- **Tools**: Sickle (tiers: Basic → Advanced)

**3. Fishing** 🎣
- **Raccolta**: Pesci, tesori sommersi
- **Nodes**: River, Lake, Ocean fishing spots
- **Tools**: Fishing Rod (tiers: Bamboo → Carbon Fiber)

**4. Woodcutting** 🪓
- **Raccolta**: Legname, resina
- **Nodes**: Oak, Pine, Rare Wood
- **Tools**: Axe (tiers: Stone → Iron → Steel)

### Gathering Mechanics

**Node System:**
- Nodes spawnable nelle zone esplorazione
- Cooldown respawn: 2-5 minuti
- Quantità random: min/max range
- Rare nodes: 5% spawn chance

**Skill Leveling:**
```
Action → Gain Skill EXP → Level Up → +1 Passive Point →
Unlock migliori tools → Faster gathering → Higher yields
```

**Integration con Combat:**
- Gathering mentre in zona non blocca combat
- Nodes visibili sulla mappa
- Click to gather (animazione breve)

---

## 🏰 **Sistema Villaggio e NPC**

### Village Hub Centrale

**Mappa Interattiva:**
- Background artistico del villaggio
- NPC cliccabili con nomi
- Icone indicatrici per funzioni
- Pathfinding visuale

### NPC Implementati

**1. Fabbro (Blacksmith)** 🔨
- **Funzione**: Enhancement equipaggiamento
- **Servizi**:
  - Enhancement +0 → +9
  - Repair equipment
  - Gem socket installation (pianificato)

**2. Grocer** 🛒
- **Funzione**: General shop
- **Vende**:
  - Pozioni (Small, Medium, Large)
  - Materiali base
  - Bag espansioni

**3. Alchemist** ⚗️
- **Funzione**: Potion shop specializzato
- **Vende**:
  - HP Potions (instant heal)
  - Mana Potions (instant mana)
  - Buff potions (pianificati)

**4. Warehouse Manager** 📦
- **Funzione**: Storage extra (pianificato)
- **Features**:
  - 100 slot storage
  - Shared tra personaggi (pianificato)

**5. Quest NPCs** 📜
- **Struttura esistente**, logica quest da implementare
- Sistema dialoghi
- Quest tracking (pianificato)

---

## 🎚️ **Sistema Progressione Personaggio**

### Leveling System

**EXP Curve:**
```python
EXP_needed = base_exp * (1.15 ^ level)
```
- Livello 1 → 2: 100 EXP
- Livello 10: ~400 EXP
- Livello 50: ~10,000 EXP
- Livello 100: ~1,000,000 EXP

**Level Up Benefits:**
- Full HP/Mana restore
- +1 Passive Point
- Stat increases (auto o manual - TBD)
- Unlock zone superiori

### EXP Sources
- Enemy kills (20-400 XP/kill based on level)
- Quest completion (pianificato)
- Boss kills (bonus XP)
- Exploration milestones (pianificato)

### Multiple Progression Paths

**Combat Progression:**
- Character Level (main)
- Skill Mastery levels (pianificato)
- Equipment enhancement

**Gathering Progression:**
- Mining Level (independent)
- Herbalism Level (independent)
- Fishing Level (independent)
- Woodcutting Level (independent)

**Account Progression:** (Future)
- Achievement points
- Unlock permanent bonuses
- Cross-character benefits

---

## 💾 **Sistema Save/Load Avanzato**

### Formato Save: Binary (store_var)

**Vantaggi:**
- **10x più veloce** di JSON
- Supporto nativo tipi Godot (Vector2i, Dictionary)
- File più compatti
- Type-safe automatico

### Dati Salvati

**Character Data:**
```gdscript
{
  "level": int,
  "exp": int,
  "hp": float,
  "max_hp": float,
  "mana": float,
  "max_mana": float,
  "gold": int
}
```

**Inventory Data:**
```gdscript
inventory_items: [
  {
    "item_id": "iron_sword",
    "pos": {"x": 0, "y": 0},
    "instance_id": "unique_id_12345",
    "stack_count": 1,
    "bonuses": [...],
    "upgrade_level": 5,
    "enhancement_level": 7
  }
]
```

**Equipment Data:**
```gdscript
equipped_items: {
  "weapon": {
    "id": "iron_sword",
    "instance_id": "unique_id",
    "bonuses": [...],
    "enhancement_level": 5
  }
}
```

**Passive Trees:**
```gdscript
passive_trees: {
  "combat": [node_id_1, node_id_2, ...],
  "mining": [...],
  "herbalism": [...],
  "fishing": [...]
}
```

### Autosave System
- **Intervallo**: Ogni 5 secondi
- **Trigger**: Inventory changes, equipment, leveling
- **Exit save**: NOTIFICATION_WM_CLOSE_REQUEST handler
- **Corruption prevention**: Temp file → rename on success

---

## 🎨 **Sistema UI Tab-Based**

### 5 Tab Principali

**1. Village Tab** 🏘️
- Mappa villaggio interattiva
- Click NPC per interazioni
- Shop interfaces
- Quest log (pianificato)

**2. Inventory Tab** 🎒
- Grid 6×N (dinamico)
- Drag & Drop items
- Equipment slots visibili
- Trash bin
- Bag slots

**3. Combat Tab** ⚔️

**Layout Split:**
```
┌──────────────────────────────────────┐
│  Left Panel     │  Right Panel       │
│  - Character    │  - World Map       │
│  - Equipment    │  - Region Zoom     │
│  - Stats        │  - Battle Area     │
│  - Gathering    │  - Skill Bar       │
└──────────────────────────────────────┘
```

**4. Skills Tab** 🎯
- Skill loadout editor (4 slot)
- Skill library browsing
- Skill details panel
- Cooldown/mana display
- Drag skills to hotbar

**5. Passives Tab** 🌳
- 4 separate trees
- Pan & Zoom navigation
- Node details tooltip
- Allocated points display
- Respec button (pianificato)

### UI Features Globali

**Tooltip System:**
- 0.2s hover delay
- Rich text formatting
- Stat comparisons
- Dynamic positioning (screen edge aware)

**Notification System:**
- Loot notifications (top-right)
- Level up popup
- Achievement toast (pianificato)
- Error messages (red flash)

---

## 🎮 **Meccaniche Uniche e Innovative**

### 1. Hybrid Idle/Active Gameplay
- **Idle**: Combat automatico, gathering passivo
- **Active**: Skill timing, zone selection, equipment optimization
- **Balance**: Giocabile sia AFK che attivo

### 2. Visual Loot Collection
- **Satisfying feedback**: Orbs magnetici, particle effects
- **Rarity distinction**: Colori vividi per rarità
- **Non invasivo**: Auto-collect dopo delay

### 3. Risk/Reward Enhancement
- **Metin2 nostalgia**: Sistema enhancement distruttivo
- **Visual progression**: Shader effects a +7/+8/+9
- **Strategic choice**: Quando fermarsi vs. rischiare

### 4. Multi-Progression Economy
- **4 Passive trees separati**: Specializzazione vs. generalizzazione
- **Gathering integration**: Non solo combat-focused
- **Meaningful choices**: Points limitati

### 5. Instance-Based Item System
- **Unique IDs per item**: Ogni item tracciabile
- **Procedural bonuses**: Nessun item identico (con gem)
- **Trade-ready architecture**: Sistema pronto per multiplayer

---

## 🏗️ **Architettura Tecnica**

### Godot Autoload Singletons (13 Total)

**Core Systems:**
- `GameState`: State manager centrale
- `GameLogger`: Debug logging system
- `IData (ItemDatabase)`: Item definitions
- `EnemyDatabase`: Enemy templates
- `GatheringDatabase`: Gathering nodes/tools

**Crafting & Enhancement:**
- `BonusDatabase`: Gem bonus generation
- `GemCrafting`: Gem application logic
- `EnhancementSystem`: Equipment enhancement

**Loot & Rewards:**
- `ItemDropGenerator`: Loot generation
- `LootOrbManager`: Visual loot orbs
- `XpOrbManager`: XP orb system
- `GoldOrbManager`: Gold orb system

**UI Management:**
- `TooltipManager`: Global tooltip handler
- `LootNotificationManager`: Drop notifications

### Scene Hierarchy

```
Main.tscn (TabContainer)
├── MainMenu.tscn
├── Village Tab
│   ├── VillageMap (background)
│   └── VillageOverlay (NPC clickables)
├── Inventory Tab
│   ├── GridContainer (6×N slots)
│   ├── ItemsLayer (item instances)
│   ├── BagSection (5 bag slots)
│   └── TrashBin
├── Combat Tab
│   ├── LeftPanel
│   │   ├── CharacterDisplay (equipment preview)
│   │   ├── StatsScrollPanel
│   │   └── GatheringSkillDisplay
│   └── RightPanel
│       ├── WorldMapView
│       ├── RegionZoomView
│       └── BattleArea
│           ├── BackgroundTexture
│           ├── EnemySlots (7 spawn points)
│           └── CombatSkillBar
├── Skills Tab
│   ├── SkillLibrary (scrollable)
│   ├── SkillDetailsPanel
│   └── SkillLoadout (4 slots)
└── Passives Tab
    ├── TreeSelector (4 trees)
    └── NodeCanvas (pan/zoom)
```

### Code Quality & Patterns

**Design Patterns Utilizzati:**
- **Singleton Pattern**: Autoload per servizi globali
- **Observer Pattern**: Signal-based communication
- **Factory Pattern**: Item/Enemy creation
- **Strategy Pattern**: Different loot strategies per enemy

**Best Practices:**
- ✅ Separation of concerns (UI vs. Logic)
- ✅ Data-driven design (JSON configs)
- ✅ Signal-driven architecture (loose coupling)
- ✅ Inspector-exposed values (86+ configurable)
- ✅ Extensive logging (debug friendly)

---

## 📈 **Stato Attuale del Progetto**

### ✅ Sistemi Completi (100%)

**Core Gameplay:**
- ✅ Combat loop (exploration → battle → loot)
- ✅ Character stats system (30+ stats)
- ✅ Equipment system (6 slots)
- ✅ Inventory grid-based (con bag system)
- ✅ Save/Load (binary format)

**Progression:**
- ✅ Level system con EXP curve
- ✅ Passive skill trees (4 trees)
- ✅ Warrior skills (auto-cast)
- ✅ Enhancement system (+0 → +9)
- ✅ Gem crafting (5 gem types)

**Loot & Rewards:**
- ✅ Visual loot orbs (3 types)
- ✅ Pity system per rare encounters
- ✅ Drop tables configurabili
- ✅ Loot notification system

**World & Exploration:**
- ✅ World map navigation
- ✅ Zone progression (Red Kingdom)
- ✅ Background system dinamico
- ✅ Village NPC interactions

### 🚧 Sistemi Parziali (50-80%)

**Gathering System:**
- ✅ 4 skills definite (Mining, Herbalism, Fishing, Woodcutting)
- ✅ Database nodes e tools
- ✅ Skill leveling structure
- ⏳ Node spawning nelle zone
- ⏳ Gathering animations
- ⏳ Full integration con world map

**Quest System:**
- ✅ NPC structure (dialoghi)
- ✅ Quest data format definito
- ⏳ Quest logic implementation
- ⏳ Quest tracking UI
- ⏳ Reward distribution

**Content:**
- ✅ Red Kingdom completo
- ⏳ Blue Kingdom (livello 50+)
- ⏳ Green Kingdom (livello 75+)
- ⏳ More enemy varieties
- ⏳ Boss mechanics unique

### 📋 Pianificati (0-30%)

**PvP System:**
- Arena matchmaking
- Ranked seasons
- PvP-specific rewards

**Guild System:**
- Guild creation/management
- Guild skills/buffs
- Guild wars

**Advanced Features:**
- Pet system (combat companions)
- Mount system (travel speed)
- Achievement system
- Daily/Weekly quests
- Endgame raids
- Cross-server events

---

## 📊 **Metriche Progetto**

### Codebase Statistics

**Linee di Codice:**
- **Scripts GDScript**: ~15,000+ linee
- **JSON Data**: ~3,000+ linee
- **Scene Files**: 50+ file .tscn

**File Organization:**
```
📁 Project Root
├── 📁 scenes/ (50+ files)
├── 📁 scripts/ (100+ files)
│   ├── 📁 battle/
│   ├── 📁 crafting/
│   ├── 📁 gathering/
│   ├── 📁 systems/
│   └── 📁 ui/
├── 📁 data/ (15 JSON files)
├── 📁 Icons/ (100+ images)
├── 📁 Item_Texture/ (200+ images)
└── 📁 addons/ (GUT framework)
```

**Asset Count:**
- **Item Icons**: 150+
- **Enemy Sprites**: 10+
- **Background Images**: 5+
- **UI Elements**: 30+
- **Skill Icons**: 20+

### Performance Metrics

**Target Performance:**
- **FPS**: 60 (V-Sync)
- **Load Time**: <2 seconds
- **Save Time**: <0.1 seconds
- **Memory**: <500 MB RAM

**Optimization:**
- Object pooling per orbs
- Lazy loading per textures
- Batch rendering per grid slots

---

## 🎯 **Unique Selling Points**

### 1. Profondità senza Complessità
- Sistema facile da apprendere
- Complessità emergente da interazione sistemi
- Curva apprendimento graduale

### 2. Progressione Multi-Dimensionale
- Non solo "kill more, get stronger"
- 4 path gathering indipendenti
- Equipment crafting strategico
- Passive trees customizzabili

### 3. Soddisfazione Visuale
- Loot orbs magnetici (dopamine hit)
- Shader effects su enhancement alto
- Particle effects per rarità
- Smooth animations

### 4. Rispetto del Tempo del Giocatore
- Sistema idle permette progressione AFK
- Autosave frequente (no progress loss)
- No pay-to-win mechanics
- Grind opzionale, non obbligatorio

### 5. Nostalgia Modernizzata
- Metin2 enhancement (senza frustrazione eccessiva)
- PoE passive trees (semplificati)
- Idle game automation (con depth)

---

## 🚀 **Roadmap Futura**

### Short-Term (1-3 mesi)
1. ✅ **Fix bug bag system** (Completato!)
2. ⏳ Completare gathering integration
3. ⏳ Implementare quest system basic
4. ⏳ Aggiungere 5+ enemy types
5. ⏳ Blue Kingdom content (primo passo)

### Mid-Term (3-6 mesi)
1. ⏳ PvP Arena system
2. ⏳ Guild system basic
3. ⏳ Pet system
4. ⏳ Achievement system
5. ⏳ Daily/Weekly quests

### Long-Term (6-12 mesi)
1. ⏳ Green Kingdom + endgame
2. ⏳ Multiplayer trading
3. ⏳ Seasonal events
4. ⏳ Raid bosses
5. ⏳ Cross-server features

---

## 🎓 **Conclusione**

**RiftStone Saga** è un progetto ambizioso ma ben strutturato che combina il meglio di diversi generi:
- **Automazione** degli idle games
- **Profondità** degli Action RPG
- **Progressione** degli MMO
- **Soddisfazione** dei loot games

Con **15,000+ linee di codice**, **50+ scene**, e **15+ sistemi interconnessi**, il progetto dimostra:
- Architettura solida e scalabile
- Code quality professionale
- Design modulare per espansione
- Vision chiara e coerente

Il gioco è **production-ready per i sistemi core** e pronto per espansione contenuti. La base tecnica permette facilmente di aggiungere nuove features senza refactoring maggiore.

**Target Audience:** Giocatori che amano progression profonda ma vogliono gameplay rilassante, fans di Metin2/PoE/Idle RPGs, e chi cerca un MMO-lite single player con possibilità multiplayer futura.

---

**Versione Documento**: 1.0
**Ultimo Aggiornamento**: Marzo 2026
**Engine**: Godot 4.5
**Stato**: Early Development (Core Systems Complete)
