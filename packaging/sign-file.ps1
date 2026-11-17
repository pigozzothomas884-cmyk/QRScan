param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "File da firmare non trovato: $FilePath"
}

# Rimuove l'attributo di sola lettura se presente
Set-ItemProperty -LiteralPath $FilePath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

# Cerca il certificato CiaoDev nello store utente o macchina
$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -like "*CN=CiaoDev*" -and $_.HasPrivateKey } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    Write-Host "Certificato CiaoDev non trovato. Creazione nuovo certificato Code Signing..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=CiaoDev, O=CiaoDev, C=IT" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature `
        -FriendlyName "CiaoDev Code Signing" `
        -NotAfter (Get-Date).AddYears(5)

    try {
        $pubStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("TrustedPublisher", "CurrentUser")
        $pubStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $pubStore.Add($cert)
        $pubStore.Close()
    } catch {
        # Non bloccante se lo store TrustedPublisher non è accessibile
    }
}

# Tenta la firma con timestamp RFC 3161; fallback senza timestamp se offline
$timestampServers = @(
    'http://timestamp.digicert.com',
    'http://timestamp.sectigo.com'
)

$signed = $false
foreach ($ts in $timestampServers) {
    try {
        $res = Set-AuthenticodeSignature -FilePath $FilePath -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $ts -ErrorAction Stop
        if ($res.SignerCertificate) {
            $signed = $true
            break
        }
    } catch {
        # Riprova con il prossimo server o fallback
    }
}

if (-not $signed) {
    Set-AuthenticodeSignature -FilePath $FilePath -Certificate $cert -HashAlgorithm SHA256 -ErrorAction Stop | Out-Null
}

# Rimuove il Mark of the Web (Zone.Identifier) per evitare il blocco SmartScreen per file scaricato/non sicuro
Unblock-File -LiteralPath $FilePath -ErrorAction SilentlyContinue

Write-Host "Firmato con successo: $FilePath [Autore: $($cert.Subject)]" -ForegroundColor Green
