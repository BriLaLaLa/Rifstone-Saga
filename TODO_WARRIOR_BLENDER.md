# TODO — Warrior 3D (Blender) → sprite 2D → Godot

> **2026-10-04 — SOSTITUITO in parte da `PIANO_3D.md`.** Il gioco passa al 3D: le fasi 4 (render 2D), 5 (sprite sheet) e 6 (integrazione Sprite2D) non si fanno più.
> Restano valide modellazione (fase 2) e rig/animazioni (fase 3), che proseguono nella Fase 1 di `PIANO_3D.md`.

Obiettivo: sostituire `icon.svg` del player (`PlayerSprite`, Sprite2D in `scenes/combat/ZoneCombatScene.tscn`)
con un warrior modellato in Blender, renderizzato in sprite sheet e animato in Godot.

Stato attuale rilevato:
- Player = `Sprite2D` con `icon.svg`, girato solo con `flip_h` (`scripts/combat/PlayerPathController.gd:284`)
- Stati player: IDLE / movimento / attacco / raccolta (gathering)
- Asset di riferimento: Tiny Swords, frame 192x192, vista laterale + flip, 6 frame per run
- Nemici 56px, Metin 120px — il warrior deve stare in quella scala
- Blender 4.2 installato, `uv` 0.9.9 installato

---

## Fase 0 — Decisioni (prima di modellare)
> Scelte: cartoon Tiny Swords, 1 lato (destra) + flip_h, ortografica ~30°, frame 192x192 (warrior ~60-70px), idle/run/attack1/attack2/gather, 10 fps, rig Rigify (opzione B).
- [x] Stile: cartoon "Tiny Swords" (toon shading + outline, colori piatti) **[consigliato]** oppure pixel art
- [x] Direzioni: 1 lato + flip (come Tiny Swords, zero modifiche al codice) **[consigliato per partire]**, oppure 4 / 8 direzioni
- [x] Angolo camera: ~30° dall'alto, ortografica (coerente con la mappa top-down 3/4)
- [x] Dimensione frame: 192x192 (come Tiny Swords) con personaggio alto ~60-70px a schermo
- [x] Lista animazioni minima: `idle`, `run`, `attack1`, `attack2`, `gather` (opz. `hit`, `death`, `guard`)
- [x] FPS animazioni: 10 fps (stesso valore già usato in `1a3e656 polish: animazioni a 10fps`)

## Fase 1 — Collegare Claude a Blender (Blender MCP)
- [x] Registrare il server MCP in Claude Code (`claude mcp add blender uvx mcp-for-blender`, pacchetto 2.1.3)
- [x] Installare e abilitare l'addon in Blender 4.2.1 LTS (già installato sul PC)
- [x] In Blender: sidebar `N` → tab MCP → "Connect to Claude"
- [x] Test: Claude crea un cubo e legge la scena
- [x] Regola: salvare il `.blend` prima di ogni `execute_blender_code`

## Fase 2 — Modellazione warrior (low-poly)
- [x] Cartella `art/warrior/` per `.blend` sorgenti (`art/.gdignore` presente; sorgente: `art/warrior/warrior.blend`)
- [x] Concept / reference: proporzioni chibi (testa grande), elmo, armatura, spada, scudo opzionale
- [x] Mesh base in T-pose, scala 1 unità = 1 m, Z-up, origine ai piedi
- [x] Spada e scudo come oggetti separati (per cambiare arma in futuro con l'equip)
- [x] Materiali piatti (palette limitata, coerente con Tiny Swords)
- [x] Applicare trasformazioni, controllare normali
- [ ] **OK utente sul modello** (render in `art/warrior/review/`)

## Fase 3 — Rig e animazioni
- [ ] ~~Opzione A: Mixamo~~ (scartata) (auto-rig + animazioni gratis, serve account Adobe — lo fai tu) **[più veloce]**
  - export FBX T-pose → upload Mixamo → scarica animazioni "without skin", 30 fps
  - import in Blender, una Action per animazione (`idle`, `run`, `attack1`...)
- [ ] Opzione B: rig manuale Rigify + animazioni fatte da Claude via script (più controllo, più lento)
- [ ] Animazioni "in place" (niente root motion, il movimento lo fa Godot)
- [ ] Loop puliti per `idle` / `run`
- [ ] Spada attaccata all'osso della mano (Child Of / parent to bone)

## Fase 4 — Setup render 2D in Blender — ~~SOSTITUITA da PIANO_3D.md~~
- [ ] Camera ortografica, angolo ~30°, inquadratura fissa
- [ ] Sfondo trasparente (Film → Transparent), formato PNG RGBA
- [ ] Shading: toon (Shader to RGB + ColorRamp a gradini) + outline (Line Art o Freestyle o inverted hull)
- [ ] Luce unica frontale-alta, ombre morbide, uguale per tutte le animazioni
- [ ] Engine: EEVEE (veloce) — Cycles solo se serve
- [ ] Script Python di render: per ogni Action → frame a 10 fps → (per ogni direzione) → PNG
  - alternativa addon gratuiti: BlenderSpriteGenerator (MIT), Sprite Sheet Generator (extensions.blender.org)
- [ ] Pixel art (solo se scelto): render a bassa risoluzione + filtro Nearest in Godot

## Fase 5 — Sprite sheet — ~~SOSTITUITA da PIANO_3D.md~~
- [ ] Script (Python/PIL) che impacchetta i frame: una riga per animazione (stile Tiny Swords: `Warrior_Run.png` = 6x192)
- [ ] Ritaglio coerente: stessa ancora (piedi) in tutti i frame, niente "salti"
- [ ] Salvare in `assets/characters/warrior/`

## Fase 6 — Integrazione Godot — ~~SOSTITUITA da PIANO_3D.md~~
- [ ] `PlayerSprite`: Sprite2D → AnimatedSprite2D con risorsa `SpriteFrames` (`warrior_frames.tres`)
- [ ] Animazioni nel SpriteFrames: `idle`, `run`, `attack`, `gather` (loop on/off giusti)
- [ ] `PlayerPathController.gd`: cambiare animazione in base allo stato (IDLE / moving / attacking / gathering)
- [ ] Mantenere `flip_h` (se 1 direzione) o scegliere animazione per direzione (se 4/8)
- [ ] Attacco: sincronizzare il frame del colpo con il danno (`frame_changed` / `animation_finished`)
- [ ] Offset sprite: piedi sulla posizione del CharacterBody2D, z_index/y-sort coerente con Props
- [ ] Filtro texture: Linear (cartoon) o Nearest (pixel art)
- [ ] Test GUT: animazione corretta per ogni stato

## Fase 7 — Rifinitura
- [ ] Confronto visivo con nemici e mappa Tiny Swords (scala, colori, outline)
- [ ] Varianti: colori armatura / armi diverse in base all'equip (render extra)
- [ ] Riutilizzare la stessa pipeline per nemici e altri personaggi
- [ ] Commit + push su GitHub
