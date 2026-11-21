param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$AddonName = "CastMetrics"
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
    # Copie les fichiers de l'addon + README.md (en conservant les sous-dossiers comme Locales\)
    # pour que vos amis n'aient qu'a extraire l'archive dans Interface\AddOns\
    $FilesToPack = Get-ChildItem -LiteralPath $SourceDir -Recurse -File | Where-Object {
        ($_.Extension -in @(".toc", ".lua", ".xml") -or $_.Name -eq "README.md") -and
        $_.FullName -notmatch "[\\/](?:\.git|\.vscode|dist|tests)[\\/]"
    }

    foreach ($File in $FilesToPack) {
        $RelativePath = $File.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
        $DestFile = Join-Path $StagingAddonDir $RelativePath
        $DestParent = Split-Path -Path $DestFile -Parent
        if (-not (Test-Path -LiteralPath $DestParent)) {
            New-Item -ItemType Directory -Path $DestParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $File.FullName -Destination $DestFile -Force
        Write-Host "  [+] $RelativePath" -ForegroundColor Green
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
Write-Host "Installation pour vos amis : extraire le zip dans ...\World of Warcraft\_retail_\Interface\AddOns\ (ou _forever_)" -ForegroundColor Yellow
