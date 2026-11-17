<#
.SYNOPSIS
Installa il certificato CiaoDev Code Signing nelle Autorità di certificazione radice attendibili (Root)
e negli Autori attendibili (TrustedPublisher) per abilitare la verifica completa in Windows.
#>

$cerPath = Join-Path $PSScriptRoot 'CiaoDev.cer'

if (-not (Test-Path -LiteralPath $cerPath)) {
    throw "File certificato non trovato: $cerPath"
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "Installazione certificato CiaoDev nello store di macchina (LocalMachine)..." -ForegroundColor Cyan
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
    Write-Host "Certificato CiaoDev installato con successo a livello di sistema (LocalMachine)!" -ForegroundColor Green
} else {
    Write-Host "Installazione certificato CiaoDev nello store utente (CurrentUser)..." -ForegroundColor Cyan
    Write-Host "Nota: Se Windows mostra un avviso di sicurezza, clicca 'Sì' per confermare l'installazione." -ForegroundColor Yellow
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null
    Write-Host "Certificato CiaoDev installato con successo nello store utente (CurrentUser)!" -ForegroundColor Green
}
