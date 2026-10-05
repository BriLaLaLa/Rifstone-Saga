# Skill del warrior — specifica (gameplay, animazioni, effetti)

Decisione utente (2026-10-04): queste 6 skill sostituiscono il set attuale di `scripts/battle/SkillDatabase.gd`.
**Attacco Base** resta come attacco normale (animazioni `attack1` / `attack2`).

| Skill nuova | Oggi nel gioco | Cambia |
|---|---|---|
| Aura della Spada | — (prende il posto di **Guardia**, che viene tolta) | nuova: danno extra fisso a ogni colpo |
| Estasi da Combattimento | **Grido di Battaglia** (`battle_cry`) | stesso effetto (+40% attacco, −30% difesa), nuovo nome e aspetto |
| Vortice della Spada | `sword_vortex` | solo aspetto |
| Taglio a Tre Vie | `three_way_slash` | solo aspetto |
| Sibilare | `hiss` | solo aspetto (diventa uno scatto) |
| Volontà di Vivere | — | nuova: colpo potente frontale ad area che cura |

Implementazione gameplay (SkillDatabase, SkillCastController, `data/skills.json`, icone) nella Fase 5b, insieme agli effetti.
I numeri marcati *proposta* sono da bilanciare.

## Stili di combattimento (armi)

Decisione utente (2026-10-04): il warrior può combattere in 3 stili, decisi dalle armi equipaggiate.

| Stile | Armi | Prefisso animazioni |
|---|---|---|
| Spada + scudo | spada a una mano + scudo (o niente) nella mano sinistra | nessuno: `idle`, `attack1`, `skill_hiss`... (nomi attuali) |
| Due spade | spada a una mano + seconda spada a una mano nella mano sinistra | `dual_` (es. `dual_attack1`, `dual_skill_sword_vortex`) |
| Spadone a due mani | spada a due mani, mano sinistra bloccata | `gs_` (es. `gs_idle`, `gs_skill_life_force`) |

- Lo slot `shield` diventa la **mano sinistra**: ci va uno scudo **oppure** una seconda spada a una mano. Equipaggiando uno spadone a due mani
  lo slot sinistro si blocca (l'oggetto torna nell'inventario). Le armi avranno un campo `weapon_type`: `one_hand` / `two_hand`.
- Ogni skill esiste in tutti e 3 gli stili: stesso effetto di gioco, animazione e tempi propri. Eventi e durate vanno indicati per stile.
- Animazioni in comune (es. `gather`) possono non avere la versione con prefisso: Godot usa quella base se manca la variante.
- Rig: arma destra su `hand.R`; scudo **o** seconda spada su `hand.L`; lo spadone sta su `hand.R` con la mano sinistra sull'impugnatura
  (vincolo/IK in Blender, cotto nell'export).
- Ordine di lavoro: prima spada + scudo completo (base + 6 skill) fatto bene; poi due spade e spadone riusando struttura e tempi.
  Script e pose in Blender vanno scritti già pensando ai 3 stili (parametrici), così le varianti non si rifanno da zero.

## Animazioni fatte — stile spada + scudo (versione 2, approvata 2026-10-05)

30 fps, sul posto, in `assets/3d/characters/warrior/warrior.glb`. Provale nel prototipo con F1-F6.

| Animazione | Durata | Eventi |
|---|---|---|
| `skill_sword_aura` | 1.333 s | on 0.400 s (battito del piede) |
| `skill_berserk` | 1.133 s | on 0.533 s (culmine del salto) |
| `skill_sword_vortex` | 1.200 s | hit 0.533 s (metà giro) · on 0.900 s (frenata, anello a terra) |
| `skill_three_way_slash` | 1.100 s | hit1 0.167 s · hit2 0.400 s · hit3 0.733 s |
| `skill_hiss` | 0.600 s | hit 0.333 s (Godot sposta il warrior tra 0.12 e 0.32 s) |
| `skill_life_force` | 1.400 s | hit 0.900 s |

- Lama nello spazio di `hand.R`: punta (-0.702, 0.025, 0), base (-0.101, 0.025, 0); la lama corre lungo -X dell'osso.
- Vortice: il root gira di 450° in senso antiorario visto dall'alto; il warrior finisce rivolto in avanti. Avanzamento di ~0.8 m a carico di Godot.
- Script in `art/warrior/warrior.blend`: `skill_v2_lib.py` (pose come "intenzioni", stili ss/dual/gs in `STYLES`), `skill_v2_actions.py`,
  `skill_check.py`, `v2_preview.py`. Per gli stili `dual_` e `gs_` restano da definire posizioni di mani e arma (tabella `L_DUAL` segnaposto).

## Animazioni fatte — stile spadone (`gs_`, 2026-10-05)

Arma `Eq_Greatsword` (1.19 m, su `hand.R`): punta (-0.900, 0.025, 0), base (-0.075, 0.025, 0) nello spazio dell'osso.
Seconda spada `Eq_Sword_L` (su `hand.L`): punta (0.702, 0.025, 0), base (0.101, 0.025, 0).

| Animazione | Durata | Eventi |
|---|---|---|
| `gs_idle` | 1.600 s, loop | — |
| `gs_run` | 0.667 s, loop | — |
| `gs_attack1` | 1.133 s | hit 0.500 s (fendente orizzontale) |
| `gs_attack2` | 1.200 s | hit 0.600 s (diagonale dalla spalla destra) |
| `gs_hit` | 0.500 s | — |
| `gs_death` | 1.467 s | — (cade all'indietro con lo spadone in mano, disteso da 1.07 s, testa a 0.34 m) |
| `gs_skill_sword_aura` | 1.400 s | on 0.467 s |
| `gs_skill_berserk` | 1.200 s | on 0.600 s |
| `gs_skill_sword_vortex` | 1.467 s | hit 0.633 s · on 1.067 s |
| `gs_skill_three_way_slash` | 1.500 s | hit1 0.233 · hit2 0.533 · hit3 1.000 s |
| `gs_skill_hiss` | 0.733 s | hit 0.400 s (Godot sposta il warrior tra 0.20 e 0.40 s) |
| `gs_skill_life_force` | 1.600 s | hit 1.067 s |

## Animazioni fatte — stile due spade (`dual_`, 2026-10-05)

`Eq_Sword` su `hand.R` e `Eq_Sword_L` su `hand.L`: punte (∓0.702, 0.025, 0), basi (∓0.101, 0.025, 0).

| Animazione | Durata | Eventi |
|---|---|---|
| `dual_idle` | 1.333 s, loop | — |
| `dual_run` | 0.600 s, loop | — |
| `dual_attack1` | 0.800 s | hit 0.333 s (destra) |
| `dual_attack2` | 0.800 s | hit 0.333 s (sinistra) |
| `dual_hit` | 0.467 s | — |
| `dual_death` | 1.333 s | — (testa a 0.36 m all'ultimo frame) |
| `dual_skill_sword_aura` | 1.200 s | on 0.400 s |
| `dual_skill_berserk` | 1.133 s | on 0.533 s |
| `dual_skill_sword_vortex` | 1.333 s | hit 0.533 s · on 0.900 s (root 440°) |
| `dual_skill_three_way_slash` | 1.100 s | hit1 0.167 · hit2 0.400 · hit3 0.733 s |
| `dual_skill_hiss` | 0.667 s | hit 0.367 s (Godot sposta il warrior tra 0.20 e 0.37 s) |
| `dual_skill_life_force` | 1.400 s | hit 0.933 s |

## Regole comuni per le animazioni (Blender)

- Scheletro `Warrior_Rig`, 30 fps, **sul posto** (niente root motion): spostamenti e avanzamenti li fa Godot nei tempi indicati.
- Nome animazione = `skill_<id>`. Partono e finiscono nella posa di guardia/idle, così si legano alle altre.
- Per ogni animazione servono durata ed **eventi** (secondo esatto): `hit` = momento del colpo, `on` = momento in cui parte l'effetto.
- Serve la posizione della **punta della lama** e della **base della lama** nello spazio dell'osso `hand.R` (per le scie della spada in Godot).

## 1. Aura della Spada — `sword_aura`

- **Gameplay**: buff su se stesso. Finché è attivo, ogni colpo (anche Attacco Base e le altre skill) aggiunge un danno extra fisso.
  *Proposta*: +8 danni per colpo (cresce col livello della skill), durata 30 s, ricarica 25 s, mana 20.
- **Animazione** `skill_sword_aura`, ~1.2 s, no loop: afferra la spada con **due mani** e la porta con gesto deciso davanti al petto,
  lama verticale o leggermente inclinata (0–0.35 s); tiene la posa ~0.5 s (evento `on` a ~0.35 s); torna in guardia.
- **Effetti (Godot)**: alla posa, aura verde-azzurra (ciano) che avvolge tutta la lama + particelle luminose che salgono lente lungo la spada e svaniscono.
  Resta in loop sulla spada per tutta la durata. A livelli alti della skill aura più spessa e brillante, con scintille.
  Deve convivere con il bagliore del potenziamento +7/+8/+9 (strati sovrapposti, non uno al posto dell'altro).

## 2. Estasi da Combattimento (Berserk) — `berserk`

- **Gameplay**: come Grido di Battaglia: +40% attacco, −30% difesa, durata 25 s, ricarica 20 s, mana 20.
  *Proposta*: anche +20% velocità d'attacco e di movimento, coerente con le animazioni più rapide.
- **Animazione** `skill_berserk`, ~1.0 s, no loop: si ferma, contrae il corpo (si raccoglie), gesto aggressivo: alza le braccia / stringe pugni e spada
  (evento `on` al culmine, ~0.55 s), torna in guardia.
- **Effetti (Godot)**: aura rosso-arancio che parte dal torace e si espande a braccia e gambe (vapore di rabbia / fiamme basse), leggera vibrazione del personaggio,
  scie di velocità quando corre. `run` e attacchi accelerati (velocità animazione ~1.3x) per tutta la durata.

## 3. Vortice della Spada — `sword_vortex`

- **Gameplay**: invariato (danno ad area a tutti i nemici vicini).
- **Animazione** `skill_sword_vortex`, ~1.0 s, no loop: breve carica (0–0.15 s), giro di 360° (o un giro e mezzo) su se stesso brandendo la spada
  con forza, braccio teso (0.15–0.8 s), recupero. Evento `hit` a ~0.5 s (metà giro), evento `on` (anello a terra) a fine rotazione ~0.8 s.
  Durante la rotazione Godot fa avanzare il personaggio di ~0.8 m.
- **Effetti (Godot)**: scia circolare molto evidente attorno al personaggio (arco di luce bianco-argento con punta verdognola) — è il punto focale;
  polvere/vento ai piedi; piccolo anello d'impatto a terra alla fine.

## 4. Taglio a Tre Vie — `three_way_slash`

- **Gameplay**: invariato (fino a 3 bersagli, ignora la difesa fisica). Ogni fendente colpisce uno dei bersagli (o lo stesso, se è solo).
- **Animazione** `skill_three_way_slash`, < 1.0 s (~0.9 s), no loop: tre fendenti rapidissimi frontali — 1° orizzontale (evento `hit1` ~0.18 s),
  2° diagonale (`hit2` ~0.40 s), 3° più ampio e potente (`hit3` ~0.65 s), poi posa di recupero.
- **Effetti (Godot)**: una scia di spada distinta per fendente (bianco-argento con alone luminoso) che appare e sparisce in fretta; scintille a ogni impatto.
  Effetto secco, netto, leggibilissimo.

## 5. Sibilare (scatto) — `hiss`

- **Gameplay**: invariato (danno a un bersaglio + stordimento 1.5 s). Lo scatto porta il warrior addosso al bersaglio.
- **Animazione** `skill_hiss`, ~0.5 s, no loop: si abbassa (0–0.12 s), posa di scatto in avanti come un proiettile, colpo di spalla/spada
  (evento `hit` ~0.32 s), recupero. Godot sposta il personaggio verso il bersaglio tra 0.12 e 0.32 s.
- **Effetti (Godot)**: immagini fantasma del personaggio (afterimage) e scie di velocità durante lo scatto; all'impatto piccola onda d'urto + scintille;
  se lo stordimento riesce, stelline/anelli che girano sopra la testa del nemico per tutta la durata.

## 6. Volontà di Vivere — `life_force`

- **Gameplay**: colpo potente frontale ad area; il warrior si cura di una parte del danno inflitto.
  *Proposta*: danno 40–55, fino a 5 bersagli in un cono frontale di ~3 m, cura il 30% del danno totale inflitto, ricarica 15 s, mana 30.
- **Animazione** `skill_life_force`, ~1.4 s, no loop: caricamento (0–0.7 s: si ferma, stringe la spada con due mani o la alza, concentra la forza, leggero tremito),
  poi colpo frontale ampio e potente (evento `hit` ~0.95 s), recupero.
- **Effetti (Godot)**: durante il caricamento corpo e spada brillano sempre di più di luce bianco-gialla; al colpo esplosione di particelle luminose in avanti
  e piccola onda d'urto a terra. L'effetto più "esplosivo" di tutti. Numero verde di cura sopra il warrior.

## Da fare

- [x] Animazioni `skill_*` spada + scudo, versione 2 (la prima era troppo rigida) + tabella durate/eventi
- [x] Modelli arma `Eq_Greatsword` e `Eq_Sword_L`; stile spadone (`gs_`): animazioni base + 6 skill 
- [x] Stile due spade (`dual_`): animazioni base + 6 skill, tabella eventi
- [ ] Gameplay armi: campo `weapon_type`, slot sinistro scudo/seconda spada, blocco con spadone, scelta dello stile in Godot
- [ ] Gameplay: SkillDatabase (nuove skill, rinomina, rimozione Guardia), SkillCastController (danno extra Aura, cura Volontà, velocità Estasi), `data/skills.json`
- [ ] Icone per Aura della Spada, Estasi da Combattimento, Volontà di Vivere (`Icons/Skills/`)
- [ ] Effetti Godot per ogni skill + eventi sincronizzati con le animazioni (Fase 5b del piano)
- [ ] Compatibilità salvataggi: loadout salvati con `guard` / `battle_cry` vanno convertiti
