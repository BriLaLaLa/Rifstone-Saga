# Come Eseguire il Test per il Bug della Bag

## Test Creato
Ho creato un test GUT completo per riprodurre il bug della rimozione bag:

**File**: `tests/test_bag_removal_no_space.gd`

## Bug Testato
Il test verifica questo scenario:
1. Equipaggi una bag aggiuntiva (oltre alla starter bag)
2. Riempi l'inventario con items oltre la capacità base
3. Provi a rimuovere la bag quando NON c'è spazio per redistribuire gli items
4. **BUG ATTESO**: La bag va in posizione 0,0 e diventa intoccabile

## Come Eseguire il Test

### Opzione 1: Tramite Godot Editor (Consigliato)

1. Apri il progetto in Godot Editor
2. Vai nel menu **Project** → **Tools** → **GUT**
3. Nella finestra GUT che si apre:
   - Clicca su "Select Script"
   - Seleziona `res://tests/test_bag_removal_no_space.gd`
   - Clicca su "Run"

### Opzione 2: Da Command Line

Trova l'eseguibile di Godot sul tuo sistema, poi esegui:

```bash
"C:\Path\To\Godot_v4.x.exe" --path . --headless --script addons/gut/gut_cmdln.gd -gtest=tests/test_bag_removal_no_space.gd
```

Sostituisci `C:\Path\To\Godot_v4.x.exe` con il path reale dell'eseguibile Godot.

### Opzione 3: Tramite PowerShell Script

Crea un file `run_bag_test.ps1` con questo contenuto:

```powershell
# Modifica questo path con il tuo path di Godot
$godotPath = "C:\Program Files\Godot\Godot_v4.3_stable.exe"

# Esegui il test
& $godotPath --path . --headless --script addons/gut/gut_cmdln.gd -gtest=tests/test_bag_removal_no_space.gd

# Aspetta input prima di chiudere
Read-Host "Premi ENTER per chiudere..."
```

Poi esegui: `.\run_bag_test.ps1`

## Output Atteso

### Se il bug è PRESENTE (comportamento attuale)

Vedrai questi messaggi di FALLIMENTO:

```
[STEP 7] ❌ BUG DETECTED: Bag is at position (0, 0) in inventory!
FAILED: Bag should NOT go to position 0,0!
FAILED: Bag should NOT be in inventory
```

Il test dovrebbe **FALLIRE** perché il bug esiste.

### Se il bug è RISOLTO (comportamento corretto)

Vedrai questi messaggi di SUCCESSO:

```
[STEP 7] ✅ Bag correctly stayed in slot (not removed)
[STEP 7] ✅ Bag is NOT in inventory (correctly)
[STEP 7] ✅ Grid size unchanged: 6x7
All tests PASSED
```

## Test Inclusi

Il file contiene 2 test:

1. **test_bag_removal_with_insufficient_space()**
   - Test principale che ricrea esattamente il bug descritto
   - Verifica che la bag NON venga rimossa
   - Verifica che la bag NON vada in posizione 0,0
   - Verifica che gli items rimangano al loro posto

2. **test_can_remove_bag_calculation()**
   - Test isolato per verificare il calcolo di `can_remove_bag()`
   - Verifica che ritorni `true` quando c'è spazio
   - Verifica che ritorni `false` quando NON c'è spazio

## Debug

Se vuoi vedere output dettagliato durante il test, apri `test_bag_removal_no_space.gd` e controlla i messaggi `print()`.

Il test stampa:
- Ogni step eseguito
- Stato della griglia (rows, cols, slots)
- Posizioni degli items
- Risultati di `can_remove_bag()`
- Posizione della bag prima e dopo il tentativo di rimozione

## Prossimi Step

1. **Esegui il test** per confermare che il bug viene riprodotto
2. **Analizza l'output** per vedere dove fallisce
3. **Confronta** con il comportamento atteso

Se il test fallisce (mostrando il bug), possiamo usare l'output per identificare esattamente dove nel codice si verifica il problema e creare una fix.
