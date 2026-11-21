param(
    [ValidateSet("all", "retail", "forever")]
    [string]$Target = "all",
    [string]$RetailAddOnsDir = "E:\World of Warcraft\_retail_\Interface\AddOns",
    [string]$ForeverAddOnsDir = "E:\World of Warcraft\_forever_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"

$AddonName = "CastMetrics"
$LegacyAddonName = "CastsButtonDisplay"
$SourceDir = $PSScriptRoot

$Destinations = @()
if ($Target -in @("all", "retail")) {
    $Destinations += @{ Label = "Retail"; Path = $RetailAddOnsDir }
}
if ($Target -in @("all", "forever")) {
    $Destinations += @{ Label = "WoW Forever"; Path = $ForeverAddOnsDir }
}

$FilesToCopy = Get-ChildItem -LiteralPath $SourceDir -File | Where-Object {
    $_.Extension -in @(".toc", ".lua", ".xml")
}

$DeployedCount = 0

foreach ($Dest in $Destinations) {
    $AddOnsDir = $Dest.Path
    if (-not (Test-Path -LiteralPath $AddOnsDir)) {
        Write-Warning "[$($Dest.Label)] Dossier ignore (introuvable) : $AddOnsDir"
        continue
    }

    $LegacyDir = Join-Path $AddOnsDir $LegacyAddonName
    if (Test-Path -LiteralPath $LegacyDir) {
        Write-Warning "[$($Dest.Label)] Ancien dossier '$LegacyAddonName' detecte : supprimez-le pour eviter les doublons ($LegacyDir)"
    }

    $TargetDir = Join-Path $AddOnsDir $AddonName
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir | Out-Null
    }

    # Nettoie les anciens fichiers .lua / .toc / .xml pour eviter les fichiers orphelins
    Get-ChildItem -LiteralPath $TargetDir -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @(".toc", ".lua", ".xml")
    } | Remove-Item -Force

    Write-Host "[$($Dest.Label)] Deploiement vers : $TargetDir" -ForegroundColor Cyan
    foreach ($File in $FilesToCopy) {
        Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $TargetDir $File.Name) -Force
        Write-Host "  [OK] $($File.Name)" -ForegroundColor Green
    }

    $DeployedCount++
}

if ($DeployedCount -eq 0) {
    Write-Error "Aucun dossier AddOns cible n'a ete trouve."
    exit 1
}

Write-Host ""
Write-Host "En jeu, tapez /reload pour recharger $AddonName." -ForegroundColor Yellow
