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
$signToolCmd = Join-Path $PSScriptRoot 'sign-tool.cmd'

if (-not (Test-Path -LiteralPath $signToolCmd)) {
    '@powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sign-file.ps1" %1' | Set-Content -LiteralPath $signToolCmd -Encoding ASCII
}

$installerScriptCandidates = @(
    (Join-Path $projectRoot 'installer\QRScan.iss'),
    (Join-Path $projectRoot 'installer\ATomixQRScan.iss')
)
$installerScript = $installerScriptCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $installerScript) {
    throw "Script Inno Setup non trovato in installer\"
}

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

$innoCompilerCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
)
$innoCompilerCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$innoCompiler = if ($innoCompilerCommand) { $innoCompilerCommand.Source } else { $null }
if (-not $innoCompiler) {
    $innoCompiler = $innoCompilerCandidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
}
if (-not $innoCompiler) {
    throw 'Inno Setup 6 non è installato. Installa Inno Setup 6 per creare il file di setup .exe.'
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

# Rimuove l'attributo di sola lettura dai file generati per evitare problemi di permessi con Windows
Get-ChildItem -LiteralPath $appImage -Recurse | ForEach-Object {
    if (-not $_.PSIsContainer -and $_.IsReadOnly) {
        $_.IsReadOnly = $false
    }
}

# Firma digitale per l'eseguibile dell'app
if (Test-Path -LiteralPath $signScript) {
    Write-Host "Firma digitale del launcher dell'applicazione ($imageExecutable)..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $signScript $imageExecutable
}

# Compilazione installer con Inno Setup e firma automatica
Push-Location (Split-Path -Parent $installerScript)
try {
    $innoArgs = @('/Qp')
    if (Test-Path -LiteralPath $signToolCmd) {
        $innoArgs += '/DUseSignTool'
        $innoArgs += "/Sciaodev_sign=$signToolCmd `$f"
    }
    $innoArgs += (Split-Path $installerScript -Leaf)

    & $innoCompiler @innoArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup non è riuscito a creare l'installer (codice $LASTEXITCODE)."
    }
} finally {
    Pop-Location
}

$setupPath = Join-Path $outputDirectory "QRScan-Setup-$appVersion.exe"
if (-not (Test-Path -LiteralPath $setupPath)) {
    throw "Installer .exe non generato: $setupPath"
}

# Rimuove l'attributo di sola lettura e Mark-of-the-Web
Set-ItemProperty -LiteralPath $setupPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
Unblock-File -LiteralPath $setupPath -ErrorAction SilentlyContinue

Write-Host "Installer pronto: $setupPath" -ForegroundColor Green
Get-Item -LiteralPath $setupPath | Select-Object Name, Length, LastWriteTime
Get-AuthenticodeSignature -FilePath $setupPath | Format-List Status, StatusMessage, SignerCertificate
