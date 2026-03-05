# Script per eseguire il test del bug della bag

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   TEST BUG RIMOZIONE BAG" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Trova Godot automaticamente nelle posizioni comuni
$godotPaths = @(
    "C:\Program Files\Godot\Godot_v4.3_stable.exe",
    "C:\Program Files\Godot\Godot_v4.2_stable.exe",
    "C:\Program Files\Godot\Godot_v4.5_stable.exe",
    "C:\Godot\Godot_v4.3_stable.exe",
    "C:\Godot\Godot_v4.2_stable.exe",
    "C:\Godot\Godot_v4.5_stable.exe",
    "$env:LOCALAPPDATA\Godot\Godot_v4.3_stable.exe",
    "$env:LOCALAPPDATA\Godot\Godot_v4.2_stable.exe",
    "$env:LOCALAPPDATA\Godot\Godot_v4.5_stable.exe"
)

$godotExe = $null

# Cerca Godot
foreach ($path in $godotPaths) {
    if (Test-Path $path) {
        $godotExe = $path
        Write-Host "✅ Godot trovato: $godotExe" -ForegroundColor Green
        break
    }
}

# Se non trovato, cerca in tutte le directory Godot
if (-not $godotExe) {
    Write-Host "⚠️  Cercando Godot nelle posizioni comuni..." -ForegroundColor Yellow

    $possibleDirs = @(
        "C:\Program Files\Godot",
        "C:\Godot",
        "$env:LOCALAPPDATA\Godot"
    )

    foreach ($dir in $possibleDirs) {
        if (Test-Path $dir) {
            $found = Get-ChildItem -Path $dir -Filter "Godot*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $godotExe = $found.FullName
                Write-Host "✅ Godot trovato: $godotExe" -ForegroundColor Green
                break
            }
        }
    }
}

# Se ancora non trovato, chiedi all'utente
if (-not $godotExe) {
    Write-Host ""
    Write-Host "❌ Godot non trovato automaticamente!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Inserisci il path completo dell'eseguibile Godot:" -ForegroundColor Yellow
    Write-Host "Esempio: C:\Program Files\Godot\Godot_v4.3_stable.exe" -ForegroundColor Gray
    Write-Host ""
    $godotExe = Read-Host "Path Godot"

    if (-not (Test-Path $godotExe)) {
        Write-Host ""
        Write-Host "❌ File non trovato: $godotExe" -ForegroundColor Red
        Write-Host ""
        Read-Host "Premi ENTER per uscire"
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Eseguendo test..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Esegui il test
$testPath = "tests/test_bag_removal_no_space.gd"

& "$godotExe" --path . --headless --script addons/gut/gut_cmdln.gd -gtest=$testPath

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test completato!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Leggi l'output sopra per vedere i risultati." -ForegroundColor Yellow
Write-Host ""

Read-Host "Premi ENTER per chiudere"
