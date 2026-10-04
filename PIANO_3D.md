# Piano conversione 3D — RiftStone Saga

Decisione (2026-10-04): il mondo di gioco passa da 2D (Tiny Swords) a 3D low-poly stilizzato.
Questo file è la fonte di verità del piano. Sostituisce l'approccio "sprite 2D" di `TODO_WARRIOR_BLENDER.md`
(le parti su modellazione/rig del warrior restano valide, le parti su render sprite sheet e layer 2D no).

## Cosa cambia e cosa no

| Resta uguale (circa 27.000 righe) | Va rifatto in 3D (circa 1.900 righe + scene) |
|---|---|
| UI (inventory, equip, skill, quest, tooltip...) — resta 2D sopra il mondo | `scripts/combat/*` (player, nemici, spawn, gathering, route, controller) |
| Sistemi: Enhancement, Quest, Level, Gathering, Crafting, Save | `scenes/combat/*` e mappe zona (`scenes/combat/zones/`) |
| Database (item, nemici, skill), autoload | Navigazione (NavigationRegion2D → 3D) |

Regola: le API pubbliche (segnali, metodi chiamati da UI/sistemi) dei nodi di combat restano identiche,
così il resto del gioco non si accorge del cambio.

## Modo di lavorare

1. **Git**: snapshot dello stato 2D su `main` (commit + tag `v2d-final`), poi tutto il lavoro 3D sul branch `feature/3d`.
   Merge in `main` solo quando il 3D raggiunge la parità con il 2D (fase 7).
2. **Il 2D non si cancella** finché il 3D non lo sostituisce: codice 3D in cartelle nuove
   (`scenes/world3d/`, `scripts/world3d/`, `assets/3d/`).
3. **Una sola conversazione Claude alla volta** modifica la repo, per evitare conflitti.
4. **Passi piccoli**: ogni passo finisce con verifica (screenshot editor/gioco o test GUT) e un commit.
5. **Checkpoint**: alla fine di ogni fase Claude mostra il risultato e aspetta l'ok prima della fase dopo.
   La fase 2 (prototipo) è un go/no-go: se il 3D non convince, si torna al piano 2D senza aver perso niente.

## Direzione artistica

- Low-poly stilizzato, toon shading a gradini + outline scuro, palette limitata, proporzioni chibi.
- Camera dall'alto a 3/4 (stile Metin2/ARPG), angolo ~45-55°, zoom con rotella, pan come nel 2D attuale.
- Personaggio giocante ed equip: modellati su misura in Blender (Claude via Blender MCP).
- Nemici, ambienti, props: pacchetti gratuiti CC0 (KayKit, Quaternius, Kenney), ricolorati per coerenza.
  Claude modella solo ciò che manca (es. pietre Metin, nodi risorsa particolari).
- Budget: ~3-6k triangoli per personaggio, texture piccole o solo colori/palette, ombre solo dalla luce principale.

## Pipeline asset

- Sorgenti `.blend` in `art/` (con `.gdignore`), export **glTF binario (.glb)** in `assets/3d/<categoria>/`.
- Export: +Y up, scala 1 = 1 m, solo ossa deform, animazioni come azioni separate, "in place" (niente root motion).
- Nomi animazioni standard: `idle`, `run`, `attack1`, `attack2`, `gather`, `hit`, `death` (+ `cast` per le skill).
- Ossa di aggancio con nomi fissi: `hand.R` (arma), `hand.L` (scudo), `head` (elmo).
- Fonti e licenze dei pacchetti esterni annotate in `assets/3d/CREDITS.md`.

## Equip visibile e potenziamento

- Arma e scudo: `BoneAttachment3D` sulle ossa delle mani, si sostituisce la scena dell'oggetto.
- Elmo, armatura, stivali (cintura opzionale): mesh skinnate sullo stesso scheletro, si sostituisce la mesh della `MeshInstance3D` dello slot.
- Dati item: campo nuovo `model_3d` (path .glb) negli item del database; slot vuoto = mesh base del corpo.
- +7 / +8 / +9: shader overlay (`next_pass`) con emissione, limitato alle zone metalliche tramite maschera
  (vertex color o texture) + `GPUParticles3D` agganciate alla lama. Stessi colori/idee degli shader esistenti
  `shaders/enhancement_plus7/8/9.gdshader` (+7 brace arancione pulsante, +8 viola instabile, +9 ciano con distorsione).
  Ogni slot ha il suo livello, gli effetti si combinano.

## Fasi

### Fase 0 — Preparazione
- [x] Commit dello stato attuale su `main` (file .import/.uid copiati, addon godot_ai aggiornato, art/warrior, piani)
- [ ] Tag `v2d-final` (fatto, locale), push su GitHub (chiedere conferma all'utente prima del push)
- [x] Branch `feature/3d`
- [x] Segnare in `TODO_WARRIOR_BLENDER.md` che le fasi sprite 2D sono sostituite da questo piano

### Fase 1 — Warrior 3D completo
- [x] Modello: corpo base + equip separati (elmo, armatura, stivali, spada, scudo), vista 3/4 come riferimento
  - `art/warrior/warrior.blend`: `Body` + `Eq_Helmet`, `Eq_Chest`, `Eq_Boots`, `Eq_Belt`, `Eq_Sword` (hand.R), `Eq_Shield` (hand.L)
  - ogni mesh ha vertex group = nome osso (head, chest, hips, upper_arm/forearm/hand/thigh/shin/foot .L/.R); ~6.1k tri con tutto addosso
  - render di revisione in `art/warrior/review/`
  - [ ] **OK utente sul modello**
- [x] Modifiche richieste: visiera più marcata, scudo un po' più piccolo
- [ ] Rig (Rigify o armatura semplice da gioco) con ossa di aggancio dai nomi standard
- [ ] Animazioni: idle, run, attack1, attack2, gather, hit, death
- [ ] Maschera zone metalliche sugli equip (per il bagliore)
- [ ] Export .glb in `assets/3d/characters/warrior/`

### Fase 2 — Prototipo 3D (go/no-go)
- [ ] Scena di test `scenes/world3d/Prototype3D.tscn`: terreno semplice, luce, camera 3/4 con follow/zoom/pan
- [ ] Shader toon + outline in Godot, confronto stile con il render Blender
- [ ] Warrior che corre verso un nemico (1 nemico da pacchetto CC0) e lo attacca
- [ ] Cambio spada a runtime + spada a +0, +7, +8, +9 una accanto all'altra
- [ ] UI esistente sopra la scena 3D (verifica che nulla si rompa)
- [ ] Misura prestazioni con 30-50 nemici
- [ ] **Checkpoint go/no-go con l'utente**

### Fase 3 — Fondamenta mondo 3D
- [ ] Controller camera definitivo (stessi comandi del 2D: follow, tasto destro pan, rotella zoom)
- [ ] Illuminazione e ambiente (cielo/colore di fondo, nebbia leggera)
- [ ] Prima zona in 3D (Red Plains / m1_z1): terreno, acqua, isola, props (GridMap con tile CC0 o mesh da Blender)
- [ ] NavigationRegion3D con navmesh dal terreno (niente pathing su acqua/alberi, come oggi)

### Fase 4 — Port del combattimento
- [ ] `PlayerPathController` → versione 3D (CharacterBody3D + NavigationAgent3D), stessa API e stessi stati
- [ ] `Enemy2D` → `Enemy3D` (modello + AnimationTree/AnimationPlayer al posto dell'animazione procedurale)
- [ ] `SpawnPoint`, `GatheringNode2D`, `RouteManager`, `ZoneCombatController` in 3D
- [ ] Danni, orb loot/xp/gold, skill visive: adattate al 3D (numeri e popup restano 2D a schermo)
- [ ] Test GUT aggiornati/nuovi

### Fase 5 — Sistema equip visibile
- [ ] Campo `model_3d` negli item + mappatura slot → aggancio
- [ ] Cambio equip dalla UI aggiorna il modello in tempo reale
- [ ] Effetti +7/+8/+9 per ogni slot
- [ ] Set di equip iniziali modellati (almeno 2-3 per slot visibile)

### Fase 6 — Contenuti
- [ ] Nemici della prima zona (pacchetti CC0, ricolorati), pietre Metin, nodi risorsa
- [ ] Altre zone, una alla volta

### Fase 7 — Sostituzione e merge
- [ ] Il gioco usa la scena 3D al posto di `ZoneCombatScene` 2D
- [ ] Rimozione del combat 2D non più usato (dopo conferma utente)
- [ ] Passata prestazioni
- [ ] Merge `feature/3d` → `main`, push
