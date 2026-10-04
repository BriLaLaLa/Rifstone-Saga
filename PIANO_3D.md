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
- Camera dall'alto a 3/4 (stile Metin2/ARPG), angolo ~45-55°, **fissa come oggi** (follow, tasto destro pan, rotella zoom, niente rotazione).
- Personaggio giocante, equip, **tutti i nemici** e le **tessere della mappa**: modellati su misura in Blender (Claude via Blender MCP),
  stesso stile e palette del warrior. Niente pacchetti esterni salvo eccezioni concordate.
- Scheletri condivisi per famiglia: lo scheletro del warrior (`Warrior_Rig`, 20 ossa) è lo **scheletro umanoide base**
  (classi future + nemici umanoidi); più avanti uno quadrupede e uno per creature volanti/informi. Animazioni riusate per famiglia.
- Budget (**solo PC**): fino a ~10k triangoli per personaggio, texture piccole o solo colori/palette, ombre in tempo reale dalla luce principale.

## Decisioni di gioco (2026-10-04)

1. Camera fissa come oggi.
2. Il gioco resta **autoplay/idle**: nessun controllo manuale o click-to-move.
3. Mappa costruita a **tessere 3D** (`GridMap` + `MeshLibrary`), tessere fatte in Blender.
4. Nemici tutti fatti in Blender.
5. Per ora **solo la classe warrior**; altre classi dopo, sullo stesso scheletro umanoide.
6. Piattaforma: **solo PC**.
7. Ogni skill avrà un'animazione descritta dall'utente (animazione Blender + effetti Godot + tempismo del colpo):
   fase dedicata dopo il port del combattimento. Skill attuali del warrior: Attacco Base, Sibilare, Vortice della Spada,
   Grido di Battaglia, Guardia, Taglio a Tre Vie (`scripts/battle/SkillDatabase.gd`).

## Pipeline asset

- Sorgenti `.blend` in `art/` (con `.gdignore`), export **glTF binario (.glb)** in `assets/3d/<categoria>/`.
- Export: +Y up, scala 1 = 1 m, solo ossa deform, animazioni come azioni separate, "in place" (niente root motion).
- Nomi animazioni standard: `idle`, `run`, `attack1`, `attack2`, `gather`, `hit`, `death` (+ `cast` per le skill).
- Ossa di aggancio con nomi fissi: `hand.R` (arma), `hand.L` (scudo), `head` (elmo).
- Fonti e licenze dei pacchetti esterni annotate in `assets/3d/CREDITS.md`.

## Scheletro del warrior e retargeting umanoide Godot

Gerarchia: `root` > `hips` > `spine` > `chest` > `neck` > `head`; `chest` > `shoulder.X` > `upper_arm.X` > `forearm.X` > `hand.X`;
`hips` > `thigh.X` > `shin.X` > `foot.X` (X = L/R). Rest pose = T-pose, piedi a terra sull'origine, scala 1 = 1 m.

Mappa per `BoneMap` con `SkeletonProfileHumanoid` (import .glb → Skeleton3D → Retarget):

| Osso Blender/glTF | Profilo umanoide Godot |
|---|---|
| `root` | `Root` |
| `hips` | `Hips` |
| `spine` | `Spine` |
| `chest` | `Chest` |
| — | `UpperChest` (assente, opzionale) |
| `neck` | `Neck` |
| `head` | `Head` |
| `shoulder.L` / `shoulder.R` | `LeftShoulder` / `RightShoulder` |
| `upper_arm.L` / `upper_arm.R` | `LeftUpperArm` / `RightUpperArm` |
| `forearm.L` / `forearm.R` | `LeftLowerArm` / `RightLowerArm` |
| `hand.L` / `hand.R` | `LeftHand` / `RightHand` |
| `thigh.L` / `thigh.R` | `LeftUpperLeg` / `RightUpperLeg` |
| `shin.L` / `shin.R` | `LeftLowerLeg` / `RightLowerLeg` |
| `foot.L` / `foot.R` | `LeftFoot` / `RightFoot` |
| — | `LeftToes`/`RightToes`, dita, occhi, mascella (assenti, opzionali: le tracce di animazioni esterne su queste ossa vengono ignorate) |

Note: in Godot L = sinistra del personaggio. Per animazioni esterne (es. Quaternius Universal Animation Library) usare
lo stesso `SkeletonProfileHumanoid` su entrambi i modelli, con "Fix Silhouette" attivo nell'import.

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
- [x] Tag `v2d-final`, push su GitHub (main, tag, feature/3d)
- [x] Branch `feature/3d`
- [x] Segnare in `TODO_WARRIOR_BLENDER.md` che le fasi sprite 2D sono sostituite da questo piano

### Fase 1 — Warrior 3D completo
- [x] Modello: corpo base + equip separati (elmo, armatura, stivali, spada, scudo), vista 3/4 come riferimento
  - `art/warrior/warrior.blend`: `Body` + `Eq_Helmet`, `Eq_Chest`, `Eq_Boots`, `Eq_Belt`, `Eq_Sword` (hand.R), `Eq_Shield` (hand.L)
  - ogni mesh ha vertex group = nome osso (head, chest, hips, upper_arm/forearm/hand/thigh/shin/foot .L/.R); ~6.1k tri con tutto addosso
  - render di revisione in `art/warrior/review/`
  - [ ] **OK utente sul modello**
- [x] Modifiche richieste: visiera più marcata, scudo un po' più piccolo
- [x] Rig (Rigify o armatura semplice da gioco) con ossa di aggancio dai nomi standard
  - armatura semplice `Warrior_Rig` (niente Rigify), T-pose, personaggio rivolto a -Y in Blender (= +Z in Godot)
  - pesi sfumati su collo, spalle, gomiti, polsi, anche, ginocchia, caviglie (corpo base, corazza, stivali); rigidi su elmo, cintura; spada/scudo figli delle ossa `hand.R`/`hand.L`
  - la tunica copia i pesi della corazza vertice per vertice → il corpo non buca l'equip in nessuna posa
  - controllo automatico compenetrazioni: script `clip_check.py` dentro il .blend (posa estrema: 0 vertici fuori)
  - [x] posa estrema mostrata all'utente (`art/warrior/review/p1_rig_pose.png`)
- [x] Animazioni: idle, run, attack1, attack2, gather, hit, death
  - 30 fps, in place, una Action per animazione (rigenerabili con lo script `anim_actions.py` dentro il .blend)
  - | anim | durata | loop | evento |
    |---|---|---|---|
    | `idle` | 1.60 s | sì | — |
    | `run` | 0.67 s (2 passi) | sì | — |
    | `attack1` | 0.67 s | no | colpo al frame 9 = **0.30 s** (fendente orizzontale) |
    | `attack2` | 0.73 s | no | colpo al frame 11 = **0.37 s** (colpo dall'alto) |
    | `gather` | 1.00 s | sì | impatto al frame 12 = **0.40 s** |
    | `hit` | 0.47 s | no | — |
    | `death` | 1.20 s | no | a terra dal frame 20 (0.67 s), resta sull'ultimo frame |
  - verifiche automatiche su ogni frame: corpo visibile dentro l'equip (max 2.5 mm fuori), spada/scudo contro corazza/elmo (max 7 mm), niente sotto il terreno (max 1.4 cm)
- [x] Maschera zone metalliche sugli equip (per il bagliore)
  - colore per vertice `metal_mask` → `COLOR_0` nel .glb, solo sugli equip: 1.0 metallo (elmo, piastre, lama, guardia, borchia, fibbia), 0.6 scudo dipinto, 0.5 cuoio, 0.3 pennacchio, 0 fessure visiera
- [x] Export .glb in `assets/3d/characters/warrior/`
  - `assets/3d/characters/warrior/warrior.glb` (script `export_glb.py` nel .blend): scheletro 20 ossa, 7 animazioni, materiali come colore piatto (il toon lo farà lo shader Godot)
  - mesh: `Body` (sempre visibile), `Body_Head` / `Body_Torso` / `Body_Feet` (da **nascondere** quando è equipaggiato rispettivamente elmo / corazza / stivali), `Eq_Helmet`, `Eq_Chest`, `Eq_Boots`, `Eq_Belt` (skinnate), `Eq_Sword` figlio di `hand.R`, `Eq_Shield` figlio di `hand.L` (→ `BoneAttachment3D` all'import)
  - con tutto l'equip addosso (pezzi coperti nascosti): ~4.6k triangoli

### Fase 2 — Prototipo 3D (go/no-go)
Scena: `scenes/world3d/Prototype3D.tscn` (F6 nell'editor). Screenshot in `art/prototype3d/`.
Codice: `scripts/world3d/` (WarriorVisual, CameraRig3D, Enhancement3D, ToonMaterials, TrainingDummy3D, Prototype3D, Prototype3DHost),
shader in `shaders/world3d/` (toon, outline_post, enhance_glow, spark).
- [x] Scena di test: isola con acqua, alberi, rocce, luce con ombre, camera 3/4 fissa (follow, tasto destro pan, rotella zoom)
- [x] Shader toon a due bande (ombra azzurrata) + contorno a schermo intero (profondità + normali, funziona su tutto senza modificare le mesh)
- [x] Warrior in autoplay: corre al manichino, alterna attack1/attack2, il danno parte al momento del colpo (0.30 s / 0.37 s),
      ogni 5 colpi subisce `hit`, dopo 3 uccisioni va a raccogliere (`gather`, 3 colpi), tasto K = `death`
  - manichino di paglia come segnaposto (i nemici veri da Blender), numeri danno 3D, lampeggio e oscillazione al colpo
- [x] Equip on/off a runtime (H C B L S X) con le parti del corpo coperte nascoste/mostrate
- [x] Bagliore +7/+8/+9 (tasti 1-4 spada, 5-8 armatura): overlay limitato al metallo con la maschera per vertice,
      scintille e luce per arma/scudo, armature più tenui; vetrina con 4 spade +0/+7/+8/+9
- [x] UI esistente: il prototipo dentro la BattleTab vera (al posto del combat 2D) funziona, nessun errore
- [x] Prestazioni (RTX 2070 Super, vsync spento): base 633 FPS · +50 warrior animati 179 FPS · +100 warrior 95 FPS
  - nota: ogni warrior ha ~10 mesh separate (equip); i nemici, senza equip intercambiabile, potranno avere una mesh unica → molto più leggeri
- [ ] **Checkpoint go/no-go con l'utente**

### Fase 3 — Fondamenta mondo 3D
- [ ] Controller camera definitivo (stessi comandi del 2D: follow, tasto destro pan, rotella zoom)
- [ ] Illuminazione e ambiente (cielo/colore di fondo, nebbia leggera)
- [ ] Prima zona in 3D (Red Plains / m1_z1): terreno, acqua, isola, props (GridMap con tessere fatte in Blender)
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

### Fase 5b — Skill animate
- [ ] L'utente descrive ogni skill (movimento del corpo, effetti visivi, momento del colpo)
- [ ] Animazioni in Blender sullo scheletro umanoide base, export nel .glb
- [ ] Effetti in Godot (particelle, scie, onde d'urto) + eventi di danno/stordimento/buff sincronizzati

### Fase 6 — Contenuti
- [ ] Nemici della prima zona (Blender, scheletri per famiglia), pietre Metin, nodi risorsa
- [ ] Altre zone, una alla volta

### Fase 7 — Sostituzione e merge
- [ ] Il gioco usa la scena 3D al posto di `ZoneCombatScene` 2D
- [ ] Rimozione del combat 2D non più usato (dopo conferma utente)
- [ ] Passata prestazioni
- [ ] Merge `feature/3d` → `main`, push
