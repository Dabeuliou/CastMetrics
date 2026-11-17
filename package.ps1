param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$AddonName = "CastsButtonDisplay"
$SourceDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $SourceDir "dist"
}

$TocPath = Join-Path $SourceDir "$AddonName.toc"
if (-not (Test-Path -LiteralPath $TocPath)) {
    Write-Error "Fichier .toc introuvable : $TocPath"
    exit 1
}

# Lit automatiquement le numero de version depuis le .toc
$Version = "dev"
$TocContent = Get-Content -LiteralPath $TocPath
foreach ($Line in $TocContent) {
    if ($Line -match "^##\s*Version:\s*(.+)$") {
        $Version = $Matches[1].Trim()
        break
    }
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$ZipName = "$AddonName-v$Version.zip"
$ZipPath = Join-Path $OutputDir $ZipName

$StagingRoot = Join-Path $env:TEMP ("cbd_package_" + [Guid]::NewGuid().ToString("N"))
$StagingAddonDir = Join-Path $StagingRoot $AddonName
New-Item -ItemType Directory -Path $StagingAddonDir -Force | Out-Null

try {
    # Copie les fichiers de l'addon + README.md dans un sous-dossier CastsButtonDisplay/
    # pour que vos amis n'aient qu'a extraire l'archive dans Interface\AddOns\
    $FilesToPack = Get-ChildItem -LiteralPath $SourceDir -File | Where-Object {
        $_.Extension -in @(".toc", ".lua", ".xml") -or $_.Name -eq "README.md"
    }

    foreach ($File in $FilesToPack) {
        Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $StagingAddonDir $File.Name) -Force
        Write-Host "  [+] $($File.Name)" -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $StagingRoot,
        $ZipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
}
finally {
    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
}

$SizeKB = [Math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1KB, 1)
Write-Host ""
Write-Host "Archive prete a partager ($SizeKB Ko) : $ZipPath" -ForegroundColor Cyan
Write-Host "Installation pour vos amis : extraire le zip dans ...\World of Warcraft\_forever_\Interface\AddOns\" -ForegroundColor Yellow
