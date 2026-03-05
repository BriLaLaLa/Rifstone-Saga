# Quest System Implementation - Complete

## Overview
Implemented a complete quest system with NPC quest indicators, quest dialogs, Quest Log UI, and 8 example quests.

## What Was Implemented

### 1. Core Quest System
**Files Created:**
- `scripts/systems/QuestObjective.gd` - Resource class for quest objectives (kill/collect)
- `scripts/systems/Quest.gd` - Resource class for quests with objectives, rewards, and status
- `scripts/systems/QuestSystem.gd` - Autoload singleton managing all quests

**Features:**
- Tracks available, active, and completed quests
- Listens to `enemy_killed` signal from SlotManager for kill objectives
- Listens to `on_inventory_changed` signal from GameState for collect objectives
- Progress tracking for each objective type
- Quest status management: AVAILABLE → ACTIVE → READY_TO_TURN_IN → COMPLETED
- Save/load integration

### 2. NPC Quest Indicators
**Files Created:**
- `scripts/ui/NPCQuestIndicator.gd` - Visual indicator Label showing ! or ?

**Modified:**
- `scripts/ui/VillageMap.gd` - Added quest indicators to NPC buttons

**Features:**
- Yellow "!" when quest available
- Grey "?" when quest in progress
- Yellow "?" when quest ready to turn in
- Auto-updates based on quest status

### 3. Quest Dialog System
**Modified:**
- `scripts/ui/VillageOverlay.gd` - Extended to show quest dialogs

**Features:**
- Accept quest dialog with description, objectives, and rewards
- Turn in quest dialog for completed quests
- In-progress status display
- Checks for quests FIRST before showing other NPC interactions

### 4. Quest Log UI
**Files Created:**
- `scripts/ui/QuestCard.gd` - Visual card for displaying individual quests
- `scripts/ui/QuestLogTab.gd` - Quest Log tab script
- `scripts/ui/QuestLogTab.tscn` - Quest Log scene

**Modified:**
- `scenes/Main.tscn` - Removed Crafting tab, added QuestLog tab at index 3

**Features:**
- Displays all active quests
- Shows objectives with progress bars and counters
- Highlights quests ready to turn in
- Real-time notifications for quest progress
- Empty state message when no active quests

### 5. Quest Data
**Files Created:**
- `data/quests.json` - 8 example quests

**Quests Included:**
1. **Wolf Pack Threat** (Bounty Hunter) - Kill 10 Lupo
2. **Wolf Tail Collection** (Biologist) - Collect 5 Wolf Tail
3. **Mystical Gems** (Alchemist) - Collect 3 Force Gems
4. **Quality Lumber** (Woodcutter) - Collect 10 Logs
5. **Boar Problem** (Bounty Hunter) - Kill 5 Cinghiale
6. **Warehouse Supply Run** (Warehouse) - Multi-step: Kill 8 Lupo + Collect 5 Boar Tusks
7. **The Scrofa Menace** (Uriel) - Boss quest: Kill 1 Scrofa
8. **Complete Wildlife Study** (Biologist) - Multi-collect: 3 Wolf Tail + 2 Boar Tusks

### 6. Integration
**Modified:**
- `project.godot` - Added QuestSystem to autoloads
- `scripts/GameState.gd` - Integrated quest save/load

## Tab Structure (New)
After implementation:
- Tab 0: Inventory
- Tab 1: Passives
- Tab 2: Skills
- Tab 3: **QuestLog** (NEW - replaced Crafting)
- Tab 4: Combat
- Tab 5: Villaggio

## How It Works

### Quest Flow
1. **Discovery**: Player enters Village tab, sees NPCs with yellow "!" indicators
2. **Accept**: Player clicks NPC, sees quest dialog with description/objectives/rewards, clicks "Accept Quest"
3. **Progress**:
   - Kill objectives tracked via SlotManager.enemy_killed signal
   - Collect objectives tracked via GameState.on_inventory_changed signal
   - Quest Log shows real-time progress with notifications
4. **Completion**: When all objectives complete, NPC indicator turns yellow "?"
5. **Turn In**: Player returns to NPC, clicks "Turn In Quest", receives rewards
6. **Persistence**: Quests saved/loaded with game state

### Technical Architecture
```
QuestSystem (Autoload)
├── Loads quests from data/quests.json
├── Connects to SlotManager.enemy_killed
├── Connects to GameState.on_inventory_changed
├── Emits signals: quest_accepted, quest_progressed, quest_ready, quest_completed
└── Manages quest lifecycle and rewards

Quest (Resource)
├── Contains QuestObjective array
├── Tracks status (available/active/ready/completed)
└── Serializes to Dictionary for save/load

QuestObjective (Resource)
├── Type: KILL or COLLECT
├── Target: enemy_id or item_id
├── Progress: current/target count
└── Completion check

NPCQuestIndicator (Label)
├── Listens to QuestSystem signals
├── Updates ! or ? with colors
└── Attached to each NPC button

VillageOverlay
├── Shows quest dialogs
├── Accept/turn-in buttons
└── Priority: Quests > Forge > Grocer > Generic

QuestLogTab
├── Displays active quest cards
├── Shows notifications
└── Updates on quest progress
```

## Files Modified Summary
- `scenes/Main.tscn` - Removed Crafting tab, added QuestLog tab
- `scripts/ui/VillageMap.gd` - Added quest indicator creation
- `scripts/ui/VillageOverlay.gd` - Added quest dialog system
- `project.godot` - Added QuestSystem autoload
- `scripts/GameState.gd` - Added quest save/load integration

## Files Created Summary
- `scripts/systems/QuestObjective.gd` (81 lines)
- `scripts/systems/Quest.gd` (151 lines)
- `scripts/systems/QuestSystem.gd` (330 lines)
- `scripts/ui/NPCQuestIndicator.gd` (79 lines)
- `scripts/ui/QuestCard.gd` (122 lines)
- `scripts/ui/QuestLogTab.gd` (172 lines)
- `scripts/ui/QuestLogTab.tscn` (11 lines)
- `data/quests.json` (130 lines)

**Total:** 8 new files, 5 modified files, ~1076 lines of code

## Testing Checklist
- [ ] Open game, verify QuestLog tab appears at index 3
- [ ] Enter Village tab, verify NPCs show yellow "!" indicators
- [ ] Click NPC with quest, verify quest dialog shows
- [ ] Accept quest, verify indicator changes to grey "?"
- [ ] Kill enemies, verify quest progress updates
- [ ] Collect items, verify quest progress updates
- [ ] Check Quest Log, verify quest appears with progress
- [ ] Complete objectives, verify NPC indicator turns yellow "?"
- [ ] Turn in quest, verify rewards received
- [ ] Save and reload, verify quests persist
- [ ] Test multi-step quest (Warehouse Supply Run)
- [ ] Test boss quest (Scrofa Menace)

## Future Enhancements
- Quest chains (completing one unlocks another)
- Daily/weekly repeatable quests
- Quest failure conditions (time limits)
- Quest markers on exploration map
- Quest reward choices
- Quest level requirements
- Achievement/title rewards
