# 🧪 ISTRUZIONI: Eseguire Test Bug Bag

## ⚡ Metodo 1: PowerShell Script (PIÙ FACILE)

1. **Chiudi Godot** se è aperto
2. **Apri PowerShell** nella cartella del progetto:
   - Clicca destro sulla cartella del progetto
   - Seleziona "Apri in Terminal" o "Open PowerShell window here"
3. **Esegui lo script**:
   ```powershell
   .\run_test_bag.ps1
   ```
4. Lo script cercherà automaticamente Godot e eseguirà il test
5. **Leggi l'output** - dovrebbe mostrare se il bug è presente o no

---

## 🎮 Metodo 2: Da Godot Editor

### Step 1: Verifica che GUT sia abilitato

1. Apri il progetto in **Godot Editor**
2. Vai in **Project → Project Settings**
3. Clicca sulla tab **Plugins**
4. Assicurati che **Gut** sia **Enabled** (spunta verde)
   - Se non lo vedi, chiudi e riapri Godot

### Step 2: Apri il pannello GUT

1. Nel menu in alto, vai su **Project → Tools → GUT**
2. Si aprirà una finestra con il pannello di test GUT

### Step 3: Seleziona il test

Nel pannello GUT:
1. Cerca il campo **"Select Script"** o **"Test Script"**
2. Clicca sul pulsante **"..."** o **"Select"**
3. Naviga fino a: `res://tests/test_bag_removal_no_space.gd`
4. Selezionalo

### Step 4: Esegui il test

1. Clicca sul pulsante **"Run"** o **"Run Tests"**
2. Il test verrà eseguito e vedrai l'output nella finestra

---

## 📊 Come Interpretare i Risultati

### ✅ Se vedi questo → Bug NON presente (tutto OK)

```
[TEST] ✅ can_remove_bag correctly returns FALSE
[STEP 7] ✅ Bag correctly stayed in slot (not removed)
[STEP 7] ✅ Bag is NOT in inventory (correctly)
[STEP 7] ✅ Grid size unchanged: 6x7
PASSED: test_bag_removal_with_insufficient_space
```

### ❌ Se vedi questo → Bug PRESENTE (da fixare)

```
[STEP 7] ❌ BUG DETECTED: Bag is at position (0, 0) in inventory!
FAILED: Bag should NOT be in inventory
FAILED: Bag should NOT go to position 0,0!
ASSERT FAILED: expected Vector2i(0, 0) != Vector2i(0, 0)
```

---

## 🔍 Debug: Se il test non parte

### Problema: "GUT non trovato nel menu"

1. Chiudi Godot completamente
2. Riapri il progetto
3. Vai in **Project → Project Settings → Plugins**
4. Disabilita e riabilita **Gut**
5. Riprova

### Problema: "File test_bag_removal_no_space.gd non trovato"

Il file esiste in: `tests/test_bag_removal_no_space.gd`

Verifica con:
```powershell
ls tests\test_bag_removal_no_space.gd
```

### Problema: "Errori durante l'esecuzione"

Copia e incolla l'output completo dell'errore - ti aiuto a risolverlo!

---

## 📝 Dopo aver eseguito il test

Una volta che hai l'output del test:

1. **Copia l'output completo** (tutto quello che appare nella console)
2. **Incollalo** nella chat
3. Ti dirò:
   - Se il bug è presente o meno
   - Dove si trova il problema nel codice
   - Come fixarlo

---

## ⚠️ Note Importanti

- **Il test crea items fittizi** - non modificherà il tuo save reale
- **Chiudi il gioco** prima di eseguire il test PowerShell
- Il test richiede **circa 5 secondi** per completarsi
- L'output è **molto verboso** - cerca le parole **PASSED** o **FAILED**

---

## 🆘 Aiuto

Se hai problemi:
1. Prova prima il **Metodo 1** (PowerShell) - è più semplice
2. Se non funziona, prova il **Metodo 2** (Godot Editor)
3. Se nessuno funziona, dimmi quale errore vedi!
