param(
    [string]$JavaHome = $env:JAVA_HOME
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$appVersion = '1.0.0'
$jarPath = Join-Path $projectRoot "target\qr-scan-$appVersion.jar"
$iconPath = Join-Path $projectRoot 'src\main\resources\InstallerIcon.ico'
$logoPath = Join-Path $projectRoot 'src\main\resources\QRScanLogo.png'
$appIconPath = Join-Path $projectRoot 'target\QRScanApp.ico'
$appImageInput = Join-Path $projectRoot 'target\jpackage-input'
$appImageOutput = Join-Path $projectRoot 'target\installer-app'
$signScript = Join-Path $PSScriptRoot 'sign-file.ps1'

if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    $jpackageCommand = Get-Command jpackage.exe -ErrorAction SilentlyContinue
    if ($jpackageCommand) {
        $JavaHome = Split-Path (Split-Path $jpackageCommand.Source -Parent) -Parent
    }
}

if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    throw 'Serve un JDK 17 o successivo. Imposta JAVA_HOME o passa -JavaHome.'
}

$jpackagePath = Join-Path $JavaHome 'bin\jpackage.exe'
if (-not (Test-Path -LiteralPath $jpackagePath)) {
    throw "jpackage.exe non trovato in $jpackagePath. Indica il percorso di un JDK, non di un JRE."
}

if (-not (Test-Path -LiteralPath $jarPath)) {
    throw "JAR dell'app non trovato: $jarPath. Compila prima il progetto con mvn clean verify."
}

if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Logo ICO dell'installer non trovato: $iconPath"
}

if (-not (Test-Path -LiteralPath $logoPath)) {
    throw "Logo PNG dell'app non trovato: $logoPath"
}

$logoBytes = [System.IO.File]::ReadAllBytes($logoPath)
Add-Type -AssemblyName System.Drawing
$logoImage = [System.Drawing.Image]::FromStream([System.IO.MemoryStream]::new($logoBytes))
try {
    if ($logoImage.Width -ne 256 -or $logoImage.Height -ne 256) {
        throw "Il logo PNG deve essere 256x256 pixel: $logoPath"
    }
} finally {
    $logoImage.Dispose()
}

$iconStream = [System.IO.File]::Open(
    $appIconPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write)
try {
    $iconWriter = [System.IO.BinaryWriter]::new($iconStream)
    $iconWriter.Write([UInt16]0)
    $iconWriter.Write([UInt16]1)
    $iconWriter.Write([UInt16]1)
    $iconWriter.Write([byte]0)
    $iconWriter.Write([byte]0)
    $iconWriter.Write([byte]0)
    $iconWriter.Write([byte]0)
    $iconWriter.Write([UInt16]1)
    $iconWriter.Write([UInt16]32)
    $iconWriter.Write([UInt32]$logoBytes.Length)
    $iconWriter.Write([UInt32]22)
    $iconWriter.Write($logoBytes)
    $iconWriter.Dispose()
} finally {
    $iconStream.Dispose()
}

$outputDirectory = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

if (Test-Path -LiteralPath $appImageInput) {
    Remove-Item -LiteralPath $appImageInput -Recurse -Force
}
New-Item -ItemType Directory -Path $appImageInput | Out-Null
Copy-Item -LiteralPath $jarPath -Destination $appImageInput

$appImage = Join-Path $appImageOutput 'QR Scan'
if (Test-Path -LiteralPath $appImage) {
    Remove-Item -LiteralPath $appImage -Recurse -Force
}

# 1. Creazione dell'app-image standalone
Write-Host "Creazione dell'app standalone con jpackage..." -ForegroundColor Cyan
try {
    Push-Location $projectRoot
    & $jpackagePath `
        --type app-image `
        --dest $appImageOutput `
        --input $appImageInput `
        --name 'QR Scan' `
        --main-jar (Split-Path $jarPath -Leaf) `
        --main-class 'com.atomix.qrscan.Main' `
        --app-version $appVersion `
        --vendor 'CiaoDev' `
        --copyright 'Copyright (C) 2026 CiaoDev' `
        --description 'Generatore e lettore di codici QR' `
        --icon $appIconPath
    if ($LASTEXITCODE -ne 0) {
        throw "jpackage non è riuscito a creare l'app standalone (codice $LASTEXITCODE)."
    }
} finally {
    Pop-Location
}

$imageExecutable = Join-Path $appImageOutput 'QR Scan\QR Scan.exe'
if (-not (Test-Path -LiteralPath $imageExecutable)) {
    throw "Launcher nativo dell'app non generato: $imageExecutable"
}

$jimageRuntimePath = Join-Path $appImage 'runtime\bin\jimage.dll'
$jdkJimagePath = Join-Path $JavaHome 'bin\jimage.dll'
if (-not (Test-Path -LiteralPath $jdkJimagePath)) {
    throw "jimage.dll non trovato nel JDK: $jdkJimagePath"
}

if ((Test-Path -LiteralPath $jimageRuntimePath) -and (Get-Item -LiteralPath $jimageRuntimePath).Length -lt 32768) {
    Copy-Item -LiteralPath $jdkJimagePath -Destination $jimageRuntimePath -Force
}

if (-not (Test-Path -LiteralPath $jimageRuntimePath) -or (Get-Item -LiteralPath $jimageRuntimePath).Length -lt 32768) {
    throw "Il runtime JDK generato non contiene un jimage.dll valido: $jimageRuntimePath"
}

# Rimuove l'attributo di sola lettura dai file generati
Get-ChildItem -LiteralPath $appImage -Recurse | ForEach-Object {
    if (-not $_.PSIsContainer -and $_.IsReadOnly) {
        $_.IsReadOnly = $false
    }
}

# Firma digitale per l'eseguibile dell'app
if (Test-Path -LiteralPath $signScript) {
    Write-Host "Firma digitale del launcher ($imageExecutable)..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $signScript $imageExecutable
}

# 2. Creazione della versione Portable (.zip)
$portableZipPath = Join-Path $outputDirectory "QRScan-Portable-$appVersion.zip"
Write-Host "Creazione pacchetto Portable ZIP ($portableZipPath)..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $portableZipPath) {
    Remove-Item -LiteralPath $portableZipPath -Force
}
Compress-Archive -Path "$appImage" -DestinationPath $portableZipPath -Force
Write-Host "Pacchetto Portable ZIP pronto: $portableZipPath" -ForegroundColor Green

# 3. Creazione del pacchetto nativo Windows Installer (.msi) con jpackage
Write-Host "Creazione pacchetto nativo Windows Installer (.msi)..." -ForegroundColor Cyan
$wixFound = (Get-Command candle.exe, light.exe -ErrorAction SilentlyContinue)
if (-not $wixFound) {
    # Cerca nelle posizioni standard di WiX Toolset
    $wixPaths = @(
        'C:\Program Files (x86)\WiX Toolset v3.11\bin',
        'C:\Program Files\WiX Toolset v3.11\bin',
        (Join-Path $env:LOCALAPPDATA 'Programs\WiX Toolset v3.11\bin')
    )
    foreach ($wp in $wixPaths) {
        if (Test-Path $wp) {
            $env:PATH = "$wp;$env:PATH"
            $wixFound = $true
            break
        }
    }
}

if ($wixFound) {
    try {
        Push-Location $projectRoot
        & $jpackagePath `
            --type msi `
            --app-image $appImage `
            --dest $outputDirectory `
            --name 'QR Scan' `
            --app-version $appVersion `
            --vendor 'CiaoDev' `
            --description 'Generatore e lettore di codici QR' `
            --win-menu `
            --win-shortcut `
            --win-dir-chooser `
            --win-per-user-install
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Pacchetto MSI generato con successo in $outputDirectory" -ForegroundColor Green
            $msiFile = Get-ChildItem -Path $outputDirectory -Filter "*.msi" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($msiFile -and (Test-Path -LiteralPath $signScript)) {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $signScript $msiFile.FullName
            }
        } else {
            Write-Warning "jpackage MSI ha restituito il codice $LASTEXITCODE."
        }
    } catch {
        Write-Warning "Impossibile generare l'MSI: $_"
    } finally {
        Pop-Location
    }
} else {
    Write-Host "WiX Toolset non presente in locale (l'MSI verra' generato su GitHub Actions dove WiX e' preinstallato)." -ForegroundColor Yellow
}

Write-Host "Build completata con successo!" -ForegroundColor Green
Get-ChildItem -LiteralPath $outputDirectory | Select-Object Name, Length, LastWriteTime
