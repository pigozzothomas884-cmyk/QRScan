# QR Scan

Applicazione desktop Java per generare codici QR in tempo reale e leggerli
con il pulsante "Scansiona dallo schermo" oppure aprendo un'immagine.

## Requisiti

- JDK 17 o successivo
- Maven 3.6 o successivo
- Inno Setup 6, per creare l'installer Windows
- Windows con supporto alle icone nell'area di notifica per usare il menu tray

## Avvio

Dalla cartella del progetto:

```powershell
mvn clean package
java -jar target\qr-scan-1.0.0.jar
```

Il JAR prodotto include ZXing e non richiede un classpath aggiuntivo.

## Installer Windows

Il logo PNG in `src\main\resources\QRScanLogo.png` viene usato nell'app.
Lo script lo converte in un'icona Windows per l'eseguibile; il file
`src\main\resources\InstallerIcon.ico` resta l'icona del setup. Per creare l'installer,
installa JDK 17 o successivo e Inno Setup 6, poi esegui dalla cartella del
progetto:

```powershell
mvn clean verify
.\packaging\build-installer.ps1 -JavaHome 'C:\percorso\al\jdk-17'
```

Lo script crea un'app standalone con runtime incluso e genera
`dist\QRScan-Setup-1.0.0.exe`. Prima di confezionare l'installer,
verifica che `runtime\bin\jimage.dll` sia una libreria JDK valida e, in
caso contrario, la ricopia dal JDK usato per la build per evitare il classico
errore `Unable to load jimage library` sul sistema target. L'installazione è
per l'utente corrente e non richiede privilegi amministrativi.

Windows mostra **CiaoDev** come editore nei metadati del setup e dell'applicazione.
Lo script firma digitalmente l'eseguibile dell'app, il disinstallatore e l'installer finale
con il certificato di firma codice CiaoDev e include parametri ottimizzati
(compressione standard anti-falsi positivi, metadati completi di versione, rimozione
del Mark of the Web) per evitare avvisi di blocco da parte di Windows Defender e SmartScreen.

Per abilitare la verifica crittografica permanente e azzerare ogni avviso su questo PC:
```powershell
.\packaging\install-certificate.ps1
```
