param(
    [string]$AddOnsDir = "E:\World of Warcraft\_forever_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

$AddonName = "CastsButtonDisplay"
$SourceDir = $PSScriptRoot
$TargetDir = Join-Path $AddOnsDir $AddonName

if (-not (Test-Path -LiteralPath $AddOnsDir)) {
    Write-Error "Le dossier cible n'existe pas : $AddOnsDir"
    exit 1
}

if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
}

# Nettoie les anciens fichiers .lua / .toc / .xml pour eviter les fichiers orphelins apres un renommage
Get-ChildItem -LiteralPath $TargetDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -in @(".toc", ".lua", ".xml")
} | Remove-Item -Force

# Copie uniquement les fichiers de l'addon depuis la racine du projet
$FilesToCopy = Get-ChildItem -LiteralPath $SourceDir -File | Where-Object {
    $_.Extension -in @(".toc", ".lua", ".xml")
}

foreach ($File in $FilesToCopy) {
    Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $TargetDir $File.Name) -Force
    Write-Host "  [OK] $($File.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Deploiement termine vers : $TargetDir" -ForegroundColor Cyan
Write-Host "En jeu, tapez /reload pour recharger l'addon." -ForegroundColor Yellow
