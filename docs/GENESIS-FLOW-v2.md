# Genesis-Init — Detaylı Akış (v2)
> Program dili: İngilizce (universal)
> Bu doküman dili: Türkçe
> Mimari: State Machine + Anti-Crash Input + Step Tracking
> Son güncelleme: 2026-06-25

---

## GENEL PRENSİPLER (Tüm Akışa Uygulanır)

### 1. State Machine Navigasyonu
Her ekran bir "state". Kullanıcı bir seçim yapar → sonraki state'e geçer, veya "geri" der → önceki state'e döner, veya "çıkış" der → onaylı çıkış.

Hata durumunda `throw` YOK. Fonksiyonlar `return` ile state döner:
- `[NextState]` → sonraki adıma geç
- `[SameState]` → geçersiz input, aynı ekranda tekrar sor
- `[PreviousState]` → bir önceki menüye dön
- `[ExitState]` → onaylı çıkış

### 2. Anti-Crash Input Wrapper
Her `Read-Host` çağrısı `Read-ValidatedInput` üzerinden geçer. Validator geçersiz derse crash olmaz, uyarı verir ve tekrar sorar. `Ctrl+C` dışında script'ten çıkış yok.

```
Read-ValidatedInput
  ├── IPv4 validator          → ^(\d{1,3}\.){3}\d{1,3}$ + range 0-255
  ├── Integer validator       → int + min/max range
  ├── Non-empty validator     → trim edildiğinde boş değil
  ├── Choice validator        → verilen listeden biri
  └── Yes/No validator        → Y/N/y/n/yes/no
```

### 3. Step Tracking + Süre + Özet Tablo
Global `$global:GenesisWorkflow.Steps` array. Her workflow adımı:
```
Start-GenesisStep -Name "anonkneti"
  ...adım kodu...
Complete-GenesisStep -Status Success  (veya Failed / Skipped)
```

Workflow sonunda `Show-GenesisSummary` bir tablo basar:
```
+----+------------------------+----------+---------+
| #  | Step                   | Duration | Status  |
+----+------------------------+----------+---------+
| 1  | anonkneti              | 1.2s     | OK      |
| 2  | rfs-setup enrollment   | 0.8s     | OK      |
| 3  | Client whitelist       | 2.4s     | OK      |
| 4  | hs_clients config      | 0.1s     | OK      |
| 5  | cfg-pushnethsm         | 1.1s     | OK      |
+----+------------------------+----------+---------+
Total duration: 5.6s | Status: SUCCESS
```

### 4. Loglama (İngilizce, Ekrana + Dosyaya)
- DEBUG: Sadece dosya (komut satırları, ham çıktılar)
- INFO: Ekran + dosya (normal ilerleme)
- WARN: Ekran (sarı) + dosya
- ERROR: Ekran (kırmızı) + dosya
- STEP: Süre-tracker'a bilgi (görsel bölüm başlıkları)

### 5. Hata Kategorileri
- **Recoverable** → Menüye geri dön, state = PreviousState
- **User Correctable** → Aynı state'te tekrar sor (invalid input, network hatası)
- **Fatal** → Backup restore öner, sonra ExitState

---

## 0. BAŞLANGIÇ — Genesis-Init.ps1

```
[MANUEL ÖN GEREKSİNİM]
  Kullanıcı README'de/console'da uyarılmalı:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        │
        ▼
.\Genesis-Init.ps1 çalıştırıldı
        │  (Tüm yollar $PSScriptRoot bazlı)
        ▼
#Requires -RunAsAdministrator kontrolü
    HAYIR → PowerShell zaten scripti yüklemez, kendi mesajını verir
        │
        ▼
Logger.ps1 dot-source ile yüklenmeye çalışıldı
        │
        ├── FAIL → Try-Catch yakala
        │         Write-Host [ABSOLUTE PATH] kırmızı
        │         "Logger module could not be loaded. Aborting."
        │         exit 1
        │
        ▼ (Logger yüklü)
Engine.ps1 dot-source ile yüklenmeye çalışıldı
        │
        ├── FAIL → Try-Catch yakala
        │         Write-GenesisLog -Level ERROR [ABSOLUTE PATH]
        │         "Engine module could not be loaded. Aborting."
        │         exit 1
        │
        ▼ (Engine yüklü)
Start-GenesisEngine -BaseDir $GenesisRoot
```

---

## 1. ENGINE BOOTSTRAP

```
Start-GenesisEngine
        │
        ▼
Log klasörü hazırla (output\logs\)
        │
        ▼
Initialize-Logger (session header dosyaya)
        │
        ▼
Initialize-Workflow ($global:GenesisWorkflow reset)
        │
        ▼
Admin kontrolü
    HAYIR → ERROR log + Write-Host [red]
            "Administrator privileges required."
            exit 1
        │
        ▼
Backup retention cleanup (session başında)
    output\backups\ altında hardserver.cfg.bak_* dosyaları
    En yeni 10 tanesini tut, kalanları sil
    [ ] Silinen dosyalar INFO log'a yazılsın
        │
        ▼
Genesis banner gösterildi
        │
        ▼
State = MAIN_MENU → State loop başladı
```

---

## STATE LOOP

```
$currentState = MAIN_MENU

while ($currentState -ne EXIT) {
    switch ($currentState) {
        MAIN_MENU         → $currentState = Show-MainMenu
        VENDOR_SELECT     → $currentState = Show-VendorMenu
        ENTRUST_ROLE      → $currentState = Show-EntrustRoleMenu
        RFS_SETUP         → $currentState = Invoke-RfsWorkflow
        CLIENT_SETUP      → $currentState = Invoke-ClientWorkflow
        CONFIRM_EXIT      → $currentState = Confirm-Exit
    }
}

Show-GenesisSummary  (özet tablo)
Write-GenesisLog "Session ended."
```

---

## 2. STATE: MAIN_MENU

```
Ekran:
    ============================================================
      PROJECT GENESIS — INIT v0.2
      HSM Day 0 Provisioning Automation
    ============================================================

    [1] Start Setup
    [2] Exit

    Selection:
        │
        ▼
Choice validator (1, 2)
    Invalid → Warn + tekrar sor (SameState)
        │
        ▼
    [1] → return VENDOR_SELECT
    [2] → return CONFIRM_EXIT
```

---

## 3. STATE: VENDOR_SELECT

```
Ekran:
    ------------------------------------------------------------
      Select HSM Vendor
    ------------------------------------------------------------

    [1] Entrust nShield Connect (network-attached)
    [2] Back to main menu
    [3] Exit

    Selection:
        │
        ▼
Choice validator
    Invalid → Warn + tekrar sor
        │
        ▼
    [1] Entrust seçildi
        │
        ▼
    VENDOR-SPESİFİK ÖN UYARI GÖSTER:
    ┌────────────────────────────────────────────────────────┐
    │ Entrust nShield Connect — Prerequisites                │
    │                                                        │
    │ This script supports the following scenario only:      │
    │   • HSM has a physical IP configured                   │
    │   • Bidirectional TCP/9004 communication is open       │
    │     between server and HSM                             │
    │   • nShield Security World client is installed         │
    │   • NFAST_HOME environment variable is set             │
    │                                                        │
    │ Press Enter to continue or 'B' to go back.             │
    └────────────────────────────────────────────────────────┘
        │
        ▼
    'B' → return VENDOR_SELECT
    Enter → devam
        │
        ▼
    VENDOR MODÜLLERİ YÜKLENDİ (dot-source):
      ├── HardserverConfig.ps1
      │     FAIL → ERROR log + return VENDOR_SELECT
      │
      └── BinaryRunner.ps1
            FAIL → ERROR log + return VENDOR_SELECT
        │
        ▼
    NFAST_HOME env kontrol:
      YOK → WARN log + kullanıcıya sor:
             "NFAST_HOME is not set. Default path will be used:
              C:\Program Files\nCipher\nfast
              Continue with default? (Y/N)"
        N → return VENDOR_SELECT
        Y → $global:GenesisNfastHome = default; devam
        │
        ▼
    BINARY VARLIK KONTROLÜ (toplu):
      Gerekli exe'ler: anonkneti, rfs-setup, cfg-pushnethsm,
                       nethsmenroll, rfs-sync, enquiry, nfkminfo
      Eksik varsa liste ver:
        "The following binaries are missing:
           - <name> at <path>
         nShield client may not be properly installed."
      Kullanıcıya sor: "Continue anyway? (Y/N)"
        N → return VENDOR_SELECT
        Y → devam (o binary'e ihtiyaç duyulunca hata verir)
        │
        ▼
    return ENTRUST_ROLE

    [2] → return MAIN_MENU
    [3] → return CONFIRM_EXIT
```

---

## 4. STATE: ENTRUST_ROLE

```
Ekran:
    ------------------------------------------------------------
      Entrust nShield — Select Server Role
    ------------------------------------------------------------

    [1] RFS Server Setup       (this server acts as RFS)
    [2] Client Server Setup    (this server is a client of RFS)
    [3] Back to vendor selection
    [4] Exit

    Selection:
        │
        ▼
Choice validator
    Invalid → Warn + tekrar sor
        │
        ▼
    [1] → return RFS_SETUP
    [2] → return CLIENT_SETUP
    [3] → return VENDOR_SELECT
    [4] → return CONFIRM_EXIT
```

---

## 5. STATE: RFS_SETUP (Bölüm A)

### A.0 — Ön Uyarı

```
Ekran:
    ============================================================
      RFS Server Setup
    ============================================================

    This workflow will:
      1. Test HSM connectivity via anonkneti (proves TCP/9004 reachability)
      2. Enroll HSM to this RFS server
      3. Whitelist client IPs on RFS
      4. Update hsm-<ESN>\config with client entries
      5. Push the updated config back to HSM

    IMPORTANT NOTES:
      • After this script completes, you must define the RFS IP
        on the HSM front panel (or via HSM config push if RFS IP
        entry exists in hardserver config).
      • For each HSM you want to enroll as RFS target, run this
        script separately. Multi-HSM in one run is not supported yet.

    Continue? (Y/N):
        │
        ▼
    N → return ENTRUST_ROLE
    Y → devam
```

### A.1 — Input Toplama

```
Start-GenesisStep "Collect RFS inputs"
        │
        ▼
HSM IP prompt:
    Read-ValidatedInput -Validator IPv4
    Invalid → "Enter a valid IPv4 address (e.g. 192.168.1.10)"
              tekrar sor (SameState)
        │
        ▼
PRE-FLIGHT CHECK: HSM connectivity
    Write-Host "Testing HSM connectivity via anonkneti..." [cyan]
    Invoke-Anonkneti -HsmIp <ip>
    Süre 10sn'yi geçerse timeout kabul et (Start-Job)
        │
        ├── Timeout / ExitCode != 0 / Parse fail
        │   ERROR log:
        │     "HSM connectivity test failed for <ip>.
        │      Possible causes:
        │        - HSM is not reachable at TCP/9004
        │        - Firewall blocking outbound 9004
        │        - HSM is powered off or misconfigured
        │        - Wrong IP address"
        │   Sor: "Retry with the same IP? (Y/N)"
        │     Y → aynı IP ile tekrar
        │     N → HSM IP prompt'a geri dön (SameState)
        │
        ▼ (Başarılı — ESN + Keyhash elde edildi ve cachelendi)
    Bu ESN ve Keyhash sonraki adımlarda kullanılacak
    (rfs-setup için tekrar anonkneti çağırma yok)
        │
        ▼
Client count prompt:
    Read-ValidatedInput -Validator Integer -Min 0 -Max 20
    Invalid → "Enter a number between 0 and 20"
        │
        ▼
    0 girildi:
      WARN log: "No client will be whitelisted. RFS enrollment
                  will still proceed."
      Sor: "Continue with 0 clients? (Y/N)"
        N → tekrar sor (SameState)
        Y → devam
        │
        ▼
Client IPs döngü (count kadar):
    For i = 1..count:
      Read-ValidatedInput -Validator IPv4 -Prompt "Client $i IP"
      Duplicate check → daha önce girilen listede var mı?
        VAR → WARN + tekrar sor (SameState) "Duplicate IP entered"
        YOK → listeye ekle
        │
        ▼
Client permission prompt (bir kere, tüm client'lar için):
    Ekran:
        Select client permission mode:
        [1] priv        (privileged - recommended for RFS acting as client too)
        [2] unpriv      (unprivileged - recommended for production apps)
        [3] priv_lowport (privileged, low ports only)

        Default: [1]
    Read-ValidatedInput -Validator Choice -Default 1
        │
        ▼
Ntoken var mı? (bir kere, tüm client'lar için):
    Ekran:
        "Do any of these clients use an nToken? (Y/N) [default: N]"
    Read-ValidatedInput -Validator YesNo -Default N
        │
        ├── Y → WARN log + Write-Host:
        │       "nToken support is not automated. You must manually
        │        configure nToken parameters after this script.
        │        The script will continue with standard (no-nToken) flow."
        │       Sor: "Understood, continue? (Y/N)"
        │         N → return ENTRUST_ROLE
        │         Y → devam (standart flow, ntoken_esn boş)
        │
        └── N → devam
        │
        ▼
INPUT ÖZETİ ONAY EKRANI:
    Ekran:
        ------------------------------------------------------------
          Review Setup Parameters
        ------------------------------------------------------------
        HSM IP        : 192.168.202.153
        HSM ESN       : B519-05E0-D947  (from anonkneti)
        HSM Keyhash   : 607341cc6d24...  (from anonkneti)
        Client Count  : 2
        Client IPs    : 192.168.202.100, 192.168.202.101
        Client Perm   : priv
        Uses nToken   : No

        Proceed with setup? (Y/N):
        │
        ▼
    N → tüm input'ları sıfırla, A.1'in başına dön (SameState)
    Y → devam
        │
        ▼
Complete-GenesisStep -Status Success
```

### A.2 — rfs-setup Enrollment

```
Start-GenesisStep "RFS enrollment"
        │
        ▼
rfs-setup.exe --force <HSM_IP> <ESN> <KEYHASH>
    (Anonkneti'den gelen ESN + Keyhash kullanılır)
        │
        ├── ExitCode != 0 → ERROR log:
        │     "RFS enrollment failed with exit code <n>.
        │      STDERR: <stderr>"
        │   Sor: "Retry, Back to inputs, or Abort? (R/B/A)"
        │     R → aynı komutu tekrar dene
        │     B → return RFS_SETUP (A.1'e döner)
        │     A → return ENTRUST_ROLE
        │
        ▼
Complete-GenesisStep -Status Success
INFO log: "RFS enrolled: <HSM_IP> (<ESN>)"
```

### A.3 — Client Whitelist Loop

```
Client count == 0 ise bu bölümü ATLA
        │
        ▼
Start-GenesisStep "Client whitelist"
        │
        ▼
Her client IP için:
    rfs-setup.exe --force --gang-client --write-noauth <Client_IP>
        │
        ├── ExitCode != 0 → ERROR log:
        │     "Whitelist failed for <ClientIP>.
        │      STDERR: <stderr>"
        │   Sor: "Skip this client, Retry, or Abort? (S/R/A)"
        │     S → bu IP'yi atla, kalanlara devam, WARN log
        │     R → aynı IP'yi tekrar dene
        │     A → return ENTRUST_ROLE
        │         (Not: rollback yok — RFS enrollment kaldı,
        │          re-run edildiğinde --force zaten idempotent)
        │
        ▼ (döngü bitti)
Complete-GenesisStep -Status Success
INFO log: "Whitelisted <n> clients"
```

### A.4 — HSM Config (hs_clients) Düzenleme

```
Start-GenesisStep "hs_clients config edit"
        │
        ▼
HSM config path hesapla:
    $hsmConfigPath = %NFAST_KMDATA%\hsm-<ESN>\config
        │
        ▼
Dosya var mı?
    HAYIR → ERROR log:
             "Expected HSM config not found:
              <path>
              rfs-setup should have created this file."
             Sor: "Retry file check, or Abort? (R/A)"
               R → tekrar kontrol
               A → return ENTRUST_ROLE
        │
        EVET
        ▼
Her client IP için Add-HsClientEntry:
        │
        ▼
Dosyayı ASCII olarak oku
        │
        ▼
[hs_clients] section bulundu mu?
    HAYIR → ERROR log:
             "[hs_clients] section not found in config.
              Config may be corrupted or from an unsupported version."
             Sor: "Abort and go back? (Y)"
             Y → return ENTRUST_ROLE
        │
        EVET
        ▼
IP zaten kayıtlı mı? (idempotency)
    EVET → INFO log "Client already registered: <ip>, skipped"
           bu client için A.5'e geç, döngüde sonrakine
        │
        HAYIR
        ▼
Mevcut kayıt var mı bu section'da?
    EVET → önce "-----" (5 tire) separator ekle
    HAYIR → separator YOK, doğrudan kayıt
        │
        ▼
Yeni kayıt yaz:
    addr=<Client_IP>
    clientperm=<seçilen: priv/unpriv/priv_lowport>
    keyhash=0000000000000000000000000000000000000000
    esn=
    (Not: keyhash 40 sıfır — no-auth Day 0 default)
    (Not: esn boş — client tarafı henüz enroll değil,
     nethsmenroll sonrası dolduracak)
        │
        ▼
Dosyayı ASCII olarak yaz (WriteAllLines + ASCII encoding)
        │
        ▼ (döngü bitti)
Complete-GenesisStep -Status Success
```

### A.5 — Config Push (Copy-to-Workdir Stratejisi)

```
Start-GenesisStep "Config push to HSM"
        │
        ▼
DİZİN İZİN SORUNU ÇÖZÜMÜ:
    ProgramData altındaki config dosyasından doğrudan push
    izin sorunu yaratabilir. Onun yerine:
        │
        ▼
Workdir hazırla:
    $pushWorkDir = <Genesis-Init>\output\push-workdir
    Yoksa oluştur
    İçindeki eski dosyaları temizle
        │
        ▼
Config dosyasını workdir'e kopyala:
    Copy-Item $hsmConfigPath $pushWorkDir\config -Force
        │
        ▼
cfg-pushnethsm.exe -a <HSM_IP> "<pushWorkDir>\config"
        │
        ├── ExitCode != 0 → ERROR log:
        │     "Config push failed. Exit code <n>.
        │      STDERR: <stderr>
        │      Possible causes:
        │        - HSM connectivity lost
        │        - Config format invalid
        │        - HSM rejected the change"
        │   Sor: "Retry push, or Abort? (R/A)"
        │     R → workdir'e tekrar kopyala + push
        │     A → return ENTRUST_ROLE
        │
        ▼
Workdir temizlik (opsiyonel — debug için tutulabilir)
        │
        ▼
Complete-GenesisStep -Status Success
INFO log: "Config pushed to HSM <HSM_IP>"
```

### A.6 — Tamamlama Ekranı

```
Ekran:
    ============================================================
      RFS Server Setup COMPLETED
    ============================================================

    HSM       : <HSM_IP> (<ESN>)
    Clients   : <count> whitelisted
                <ip1>, <ip2>, ...

    NEXT STEPS (manual):
      1. Log into the HSM front panel
      2. Set the RFS IP to this server's IP
      3. Save the HSM configuration
      4. Alternatively, if you have SSH access to HSM,
         push the RFS IP entry via cfg-pushnethsm

      (Hardserver service restart is NOT required)

    [1] Setup another HSM (return to Entrust role menu)
    [2] Return to main menu
    [3] Exit

    Selection:
        │
        ▼
    [1] → return ENTRUST_ROLE
    [2] → return MAIN_MENU
    [3] → return CONFIRM_EXIT
```

---

## 6. STATE: CLIENT_SETUP (Bölüm B)

### B.0 — Ön Uyarı

```
Ekran:
    ============================================================
      Client Server Setup
    ============================================================

    This workflow will:
      1. Test RFS connectivity via ICMP ping
      2. Generate/update hardserver.cfg with HSM entries
      3. Enroll this client to each HSM via nethsmenroll
      4. Sync from RFS via rfs-sync
      5. Verify with enquiry + nfkminfo
      6. Create cknfastrc for PKCS#11 loadsharing

    IMPORTANT NOTES:
      • All HSMs enrolled here must belong to the SAME
        Security World.
      • This server can be RFS AND client simultaneously
        (loopback IP for RFS_IP).
      • You'll need to restart the hardserver service manually
        after completion for changes to fully apply.

    Continue? (Y/N):
        │
        ▼
    N → return ENTRUST_ROLE
    Y → devam
```

### B.1 — Input Toplama

```
Start-GenesisStep "Collect Client inputs"
        │
        ▼
RFS Server IP prompt:
    Read-ValidatedInput -Validator IPv4
        │
        ▼
PRE-FLIGHT CHECK: RFS connectivity (ping)
    Write-Host "Testing RFS connectivity via ping..." [cyan]
    Test-Connection -ComputerName <ip> -Count 3 -Quiet
    (Sonucu ekrana göster: her ping için OK/FAIL)
        │
        ├── 0/3 başarı → ERROR log:
        │     "RFS is unreachable at <ip>.
        │      Possible causes:
        │        - RFS server is offline
        │        - Firewall blocks ICMP
        │        - Wrong IP address
        │        - Network routing issue"
        │   Sor: "Retry, Change IP, or Abort? (R/C/A)"
        │     R → tekrar test
        │     C → IP prompt'a dön (SameState)
        │     A → return ENTRUST_ROLE
        │
        ├── 1-2/3 kısmi başarı → WARN log:
        │     "Partial ping success (<n>/3).
        │      RFS may have intermittent connectivity."
        │   Sor: "Continue anyway? (Y/N)"
        │     N → IP prompt'a dön
        │     Y → devam
        │
        └── 3/3 → OK, devam
        │
        ▼
HSM count prompt:
    Ekran uyarısı:
        "How many HSMs to enroll on this client?
         (All HSMs must be in the SAME Security World)"
    Read-ValidatedInput -Validator Integer -Min 1 -Max 10
        │
        ▼
HSM IPs döngü:
    For i = 1..count:
      Read-ValidatedInput -Validator IPv4 -Prompt "HSM $i IP"
      Duplicate check → daha önce girilen listede var mı?
        VAR → WARN + tekrar sor (SameState)
        │
        ▼
      PRE-FLIGHT CHECK: HSM connectivity (anonkneti)
        Write-Host "Testing HSM $i connectivity via anonkneti..." [cyan]
        Invoke-Anonkneti -HsmIp <ip>
        │
        ├── FAIL → ERROR:
        │     (aynı A.1'deki gibi detaylı hata mesajı)
        │   Sor: "Retry, Change IP, Skip this HSM, Abort? (R/C/S/A)"
        │     R → tekrar
        │     C → aynı i için IP prompt'a dön
        │     S → sayıyı azalt, devam
        │     A → return ENTRUST_ROLE
        │
        └── OK → ESN + Keyhash cache'lendi (sonra kullanılmak üzere)
        │
        ▼ (döngü bitti)
INPUT ÖZETİ ONAY:
    ------------------------------------------------------------
      Review Setup Parameters
    ------------------------------------------------------------
    RFS Server    : 192.168.202.100  (ping: 3/3 OK)
    HSM Count     : 2
    HSMs (verified via anonkneti):
      #1 192.168.202.153  ESN: B519-05E0-D947
      #2 192.168.202.154  ESN: DFA8-3AD1-484B

    Proceed with setup? (Y/N):
        │
        ▼
    N → tüm input'ları sıfırla, B.1 başı (SameState)
    Y → devam
        │
        ▼
Complete-GenesisStep -Status Success
```

### B.2 — hardserver.cfg Üretimi

```
Start-GenesisStep "Generate hardserver.cfg"
        │
        ▼
Template dosyası var mı?
    <base>\vendors\entrust\templates\hardserver.cfg.template
        │
        ├── YOK → ERROR log:
        │     "Template file missing: <path>
        │      Cannot generate hardserver.cfg."
        │   Sor: "Retry check, or Abort? (R/A)"
        │     R → tekrar kontrol
        │     A → return ENTRUST_ROLE
        │
        ▼
Output config path:
    %NFAST_KMDATA%\config\config
        │
        ▼
Output var mı?
    YOK → devam (yeni yazılacak)
          UYARI VER:
            "No existing hardserver.cfg found.
             The template used is based on nShield firmware 13.6.15 LTS.
             If your installed version differs, generated config
             may include unsupported directives.
             Continue? (Y/N)"
            N → return ENTRUST_ROLE
            Y → devam
        │
        VAR
        ▼
Detect & Prompt:
    Ekran:
        [!] Existing hardserver.cfg found:
            <path>
        Continuing will BACK UP and OVERWRITE this file.
        Proceed? (Y/N)
        │
        ├── N → INFO log "User canceled config generation"
        │       return CLIENT_SETUP (B.0'a döner) veya ENTRUST_ROLE?
        │       KARAR: ENTRUST_ROLE (workflow iptal)
        │
        ▼ (Y)
Mevcut config yedeklendi:
    output\backups\hardserver.cfg.bak_YYYYMMDD_HHMMSS
    INFO log + full backup path
        │
        ▼
nethsm_imports bloğu üretiliyor:
    Her HSM için _Build-NethsmEntry
        Yazılan alanlar:
            local_module=0
            remote_ip=<IP>
            remote_port=9004
            keyhash=0000000000000000000000000000000000000000
            privileged=0
            privileged_use_high_port=0
        YAZILMAYAN alanlar (boş bırakma yok — satır YOK):
            remote_esn (nethsmenroll dolduracak)
            ntoken_esn (kullanılmıyor)
        │
        ▼
Birden fazla HSM varsa araya "-" separator (tek satır, tek tire)
        │
        ▼
Template placeholder değişimi:
    $templateContent.Replace('{{NETHSM_DYNAMIC_BLOCK}}', $block)
    (String.Replace kullan, [regex]::Escape KULLANMA)
        │
        ▼
Dosya ASCII olarak yazıldı
    [System.IO.File]::WriteAllText + [System.Text.Encoding]::ASCII
        │
        ▼
WARN log:
    "remote_esn will remain empty until nethsmenroll runs.
     This is expected behavior."
        │
        ▼
Complete-GenesisStep -Status Success
```

### B.3 — nethsmenroll Loop

```
Start-GenesisStep "nethsmenroll for all HSMs"
        │
        ▼
Her HSM IP için:
    Ekran:
        ------------------------------------------------------------
          Enrolling HSM $i of $count : <IP>
        ------------------------------------------------------------
        [i] nethsmenroll runs interactively.
            Respond to prompts as they appear.
        │
        ▼
    nethsmenroll.exe --force <HSM_IP>
    (Interactive mode — stdout redirect YOK)
        │
        ▼
    Terminal'e gelen:
        Remote module returned ESN: <ESN>
                            HKNETI: <HASH>
        Is the above correct? (yes/no):
        │
        ▼
    Kullanıcı yanıt:
        │
        ├── "no" → ExitCode != 0
        │   WARN log:
        │     "User responded 'no'. This usually means the returned
        │      ESN or HKNETI doesn't match expectations.
        │      Possible causes:
        │        - Wrong HSM IP was entered
        │        - HSM identity has changed (reinitialized)
        │      This HSM will be skipped."
        │   Sor: "Retry with same IP, Change IP, Skip, or Abort? (R/C/S/A)"
        │     R → tekrar dene
        │     C → aynı i için IP değiştir, anonkneti tekrar
        │     S → bu HSM'i atla, kalanlara devam
        │     A → return ENTRUST_ROLE
        │
        ├── ExitCode != 0 (yes dendi ama başka hata) → ERROR log:
        │     "nethsmenroll failed after 'yes'. STDERR: <text>"
        │   Sor: "Retry, Skip, or Abort? (R/S/A)"
        │
        └── ExitCode == 0 → devam
        │
        ▼
    INFO log: "HSM enrolled: <IP> (ESN <ESN>)"
        │
        ▼ (döngü)
Complete-GenesisStep -Status Success
```

### B.4 — rfs-sync Setup

```
Start-GenesisStep "rfs-sync setup"
        │
        ▼
rfs-sync.exe --setup --no-authenticate <RFS_IP>
    (Ntoken uyarısı Client için de geçerli — B.1 sırasında sorulmadı,
     çünkü Client tarafında ntoken varsa manuel yapılacak. Şimdilik
     default flow --no-authenticate.)

    [ ] İLERİDE: B.1'e "Do you use nToken on this client?" prompt
        eklenmeli. Şu an: WARN log ver:
        "Using --no-authenticate (default, no nToken).
         If this client uses an nToken, manual configuration required."
        │
        ├── ExitCode != 0 → ERROR log:
        │     "rfs-sync --setup failed.
        │      STDERR: <text>
        │      Possible causes:
        │        - RFS not reachable (though ping worked)
        │        - RFS did not whitelist this client's IP
        │        - Authentication mismatch"
        │   Sor: "Retry, or Abort? (R/A)"
        │     R → tekrar dene
        │     A → return ENTRUST_ROLE
        │
        ▼
Complete-GenesisStep -Status Success
```

### B.5 — rfs-sync Update

```
Start-GenesisStep "rfs-sync update"
        │
        ▼
rfs-sync.exe --update
    (Bu komut Security World dosyalarını syncler.)
    STDOUT ekrana YÖNLENDİRİLMELİ — kullanıcı hangi dosyaların
    sync edildiğini görmeli.
    → BinaryRunner'daki wrapper için: -RedirectStandardOutput YOK,
      ekrana bassın, sonuç kodu okunsun
        │
        ├── ExitCode != 0 → ERROR log
        │   Sor: "Retry, or Abort? (R/A)"
        │
        ▼
Complete-GenesisStep -Status Success
```

### B.6 — enquiry Doğrulama

```
Start-GenesisStep "enquiry verification"
        │
        ▼
enquiry.exe (argümansız, splatting fix ile)
        │
        ▼
PARSE STRATEJİSİ (YENİ — kritik):
    1. Çıktıyı "Module #" ile split et
       İlk parça = Server block  → ATLA
       Kalan parçalar = Module #1, Module #2, ...
    2. Her Module block içinde ara:
         - serial number     → ESN
         - mode              → operational olmalı
    3. Cross-check:
         Kaydettiğimiz ESN'ler listesi (B.1'de anonkneti'den cache'lenmiş)
         Enquiry'de görünen ESN'ler
         Her kaydedilen ESN operational olmalı
        │
        ▼
Sonuç:
    Tüm beklenen ESN'ler operational →
        INFO log: "All expected HSMs operational (<n>/<n>)"
        devam
        │
    Bir/birden fazla ESN eksik veya operational değil →
        WARN log:
          "The following HSMs are NOT operational in enquiry:
             - <ESN1>
             - <ESN2>
           Attempting nfkminfo cross-check..."
        (B.7'ye geç, nfkminfo ile onayla)
        │
        ▼
Complete-GenesisStep -Status Success/Warning
```

### B.7 — nfkminfo Cross-Check

```
Start-GenesisStep "nfkminfo cross-check"
        │
        ▼
nfkminfo.exe
        │
        ▼
PARSE STRATEJİSİ:
    Çıktı iki bölüm içerir:
      1. World bloğu (n_modules, state, hknso...)
      2. Module #N blokları (her HSM için ayrı)
         - "Module #" ile başlar, sonra Slot bloğu gelir
         - ARADIĞIMIZ: sadece "Module #N" satırından sonra
           gelen "state 0x2 Usable" satırı
         - Slot blokları içindeki state satırlarına BAKMA
           (Slot #0/Slot #1 farklı state'ler taşır — kart yuvası bilgisi)
    1. "Module #" ile split
    2. İlk parça = World bloğu → ATLA
    3. Her Module parçasında:
         - "Module #N" başlığından sonra ilk "Slot" karşılaşmasına
           kadar olan satırlar = HSM state
         - "state 0x2 Usable" ara (veya state kelimesi sonrası ilk değer)
         - "esn" satırından ESN'i al
        │
        ▼
Sonuç:
    Tüm kaydettiğimiz ESN'ler için state Usable →
        INFO log: "nfkminfo confirms all HSMs Usable"
        │
    Herhangi biri farklı state →
        WARN log:
          "HSM <ESN> state in nfkminfo: <found_state>
           Expected: 0x2 Usable
           Workflow will continue but manual intervention may be needed."
        Sor: "Continue to cknfastrc step? (Y/N)"
          N → return ENTRUST_ROLE
          Y → devam
        │
    nfkminfo çıktısında hiç Module bloğu yok →
        ERROR log:
          "No modules detected by nfkminfo.
           The client may not be properly enrolled."
        Sor: "Continue anyway, or Abort? (C/A)"
        │
        ▼
Complete-GenesisStep
```

### B.8 — cknfastrc Oluşturma

```
Start-GenesisStep "Create cknfastrc"
        │
        ▼
Hedef: $NFAST_HOME\cknfastrc
    (Uzantısız dosya)
        │
        ▼
İçerik SABİT (parametrize edilmiyor):
    CKNFAST_LOADSHARING=1
    CKNFAST_OVERRIDE_SECURITY_ASSURANCES=explicitness;tokenkeys;longterm
        │
        ▼
ASCII olarak yaz (WriteAllText + ASCII)
Mevcut dosya varsa overwrite (idempotent)
        │
        ▼
INFO log: "cknfastrc created: <path>"
    (Verify adımı yok — dosya yazma başarısı encoding hatası vermezse
     yeterli kanıt)
        │
        ▼
Complete-GenesisStep -Status Success
```

### B.9 — Tamamlama Ekranı

```
Show-GenesisSummary (özet tablo — süreleri ve status'ları)
        │
        ▼
Ekran:
    ============================================================
      Client Server Setup COMPLETED
    ============================================================

    Configuration Summary:
      RFS Server         : 192.168.202.100
      Enrolled HSMs      : 2
        - 192.168.202.153  ESN B519-05E0-D947  (operational)
        - 192.168.202.154  ESN DFA8-3AD1-484B  (operational)

      hardserver.cfg     : C:\ProgramData\nCipher\Key Management Data\config\config
        (Backed up to: <backup path>)
      cknfastrc          : C:\Program Files\nCipher\nfast\cknfastrc

    What was configured:
      • HSM entries in [nethsm_imports] section (remote_ip, keyhash,
        privileged flags). ESN was populated by nethsmenroll.
      • rfs-sync established with RFS at 192.168.202.100.
      • Security World files synced from RFS.
      • PKCS#11 loadsharing enabled via cknfastrc:
          CKNFAST_LOADSHARING=1
          CKNFAST_OVERRIDE_SECURITY_ASSURANCES=explicitness;tokenkeys;longterm

    MANDATORY NEXT STEP (manual):
      Restart the nShield hardserver service for the config to fully
      take effect. Run as Administrator:
          Restart-Service -Name "nFast Server"
      (Actual service name may vary; check with:
          Get-Service | Where Name -like "*nfast*")

    OPTIONAL VERIFICATION (manual):
      enquiry  → confirm 'mode operational' under each Module block
      nfkminfo → confirm 'state 0x2 Usable' under each Module block

    [1] Setup another client scenario (return to Entrust role menu)
    [2] Return to main menu
    [3] Exit

    Selection:
        │
        ▼
    [1] → return ENTRUST_ROLE
    [2] → return MAIN_MENU
    [3] → return CONFIRM_EXIT
```

---

## 7. STATE: CONFIRM_EXIT

```
Ekran:
    ------------------------------------------------------------
      Confirm Exit
    ------------------------------------------------------------

    Are you sure you want to exit? (Y/N):
        │
        ▼
    N → return MAIN_MENU
    Y → return EXIT
         (State loop kırılır)
         Show-GenesisSummary çalışır
         Session close log
```

---

## 8. ORTAK BİLEŞENLER

### core/Lang.ps1 — YOK (program hepsi İngilizce)

### core/Validator.ps1 (YENİ)

```
Fonksiyonlar:
  Test-GenesisIPv4         → regex + range check
  Test-GenesisInteger      → cast + min/max
  Test-GenesisChoice       → verilen listede mi
  Test-GenesisYesNo        → Y/N/y/n/yes/no
  Test-GenesisNonEmpty     → trim edilince boş mu

  Read-ValidatedInput      → merkezi wrapper
    Params:
      -Prompt
      -Validator ([scriptblock])
      -ErrorMessage
      -Default (opsiyonel)
      -AllowEmpty (default $false)
```

### core/StepTracker.ps1 (YENİ)

```
Global state:
  $global:GenesisWorkflow = @{
      Steps       = @()
      StartTime   = Get-Date
      CurrentStep = $null
  }

Fonksiyonlar:
  Initialize-Workflow      → global state reset
  Start-GenesisStep -Name  → adım başlat, süre ölçmeye başla
  Complete-GenesisStep -Status Success/Failed/Skipped
                          → süre kaydet, sonuç kaydet
  Show-GenesisSummary      → tablo yazdır
```

### core/MenuNavigation.ps1 (YENİ)

```
Constants (enum yerine string sabitler, PS 5.1 uyumlu):
  $global:GenesisStates = @{
      MAIN_MENU       = 'MAIN_MENU'
      VENDOR_SELECT   = 'VENDOR_SELECT'
      ENTRUST_ROLE    = 'ENTRUST_ROLE'
      RFS_SETUP       = 'RFS_SETUP'
      CLIENT_SETUP    = 'CLIENT_SETUP'
      CONFIRM_EXIT    = 'CONFIRM_EXIT'
      EXIT            = 'EXIT'
  }

Fonksiyonlar:
  Show-MainMenu        → return next state
  Show-VendorMenu      → return next state
  Show-EntrustRoleMenu → return next state
  Confirm-Exit         → return next state
```

### core/Cleanup.ps1 (YENİ)

```
Fonksiyonlar:
  Invoke-BackupRetention -MaxBackups 10
    output\backups\ altında hardserver.cfg.bak_*
    En yeni 10'u tut, kalanları sil
    Silinen dosya sayısını INFO log'a yaz

  Restore-ConfigFromBackup -BackupPath -TargetPath
    (Manuel rollback için kullanılabilir, workflow'da otomatik çağrılmaz)
```

### vendors/entrust/BinaryRunner.ps1 (DEĞİŞECEK)

```
_Invoke-NfastBinary parametreleri:
  -BinaryName
  -Arguments      (default @())
  -Interactive    (switch, default $false)
                  → true ise stdout/stderr redirect YAPMA
                  → false ise temp file redirect (default davranış)
  -TeeToConsole   (switch, default $false)
                  → true ise stdout hem dosyaya hem ekrana

Fonksiyon güncellemeleri:
  Invoke-Anonkneti     → -Interactive $false, -TeeToConsole $false
  Invoke-RfsSetupEnroll → aynı
  Invoke-RfsSetupGangClient → aynı
  Invoke-CfgPushNethsm → aynı
  Invoke-NethsmEnroll  → -Interactive $true (mevcut fix korunur)
  Invoke-RfsSyncSetup  → -Interactive $false, -TeeToConsole $true
                          (Kullanıcı sync progress görmeli)
  Invoke-RfsSyncUpdate → aynı
  Invoke-Enquiry       → -Interactive $false, -TeeToConsole $false
  Invoke-NfkmInfo      → YENİ, aynı pattern
```

### vendors/entrust/HardserverConfig.ps1 (DEĞİŞECEK)

```
_Build-NethsmEntry:
  MEVCUT SORUN: remote_esn ve ntoken_esn boş satır yazılıyor
  YENİ: Değer boşsa satır HİÇ YAZILMASIN
  Uygulama:
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("local_module=$LocalModule")
    $lines.Add("remote_ip=$RemoteIp")
    $lines.Add("remote_port=$RemotePort")
    if ($RemoteEsn) { $lines.Add("remote_esn=$RemoteEsn") }
    $lines.Add("keyhash=$Keyhash")
    $lines.Add("privileged=$Privileged")
    $lines.Add("privileged_use_high_port=$PrivilegedUseHighPort")
    if ($NtokenEsn) { $lines.Add("ntoken_esn=$NtokenEsn") }
    return ($lines -join "`r`n")

Add-HsClientEntry parametreleri:
  ClientPerm artık parametrik (priv/unpriv/priv_lowport)
  (Şu an default 'priv', artık _Get-RfsSetupInputs'tan geliyor)
```

---

## 8.5. EK KARARLAR (Antigravity Context-Building Sonrası)

### Karar 1 — Error Bubbling Kontratı (throw yerine)

`BinaryRunner.ps1` ve `HardserverConfig.ps1` içindeki HİÇBİR public fonksiyon artık
`throw` etmez (iki istisna hariç, aşağıda). Bunun yerine her fonksiyon standart bir
result object döner:

```powershell
[PSCustomObject]@{
    Success      = $true / $false
    ExitCode     = <int, varsa>
    Data         = <başarılıysa üretilen değer — örn. @{ESN=...; Keyhash=...}>
    ErrorMessage = <başarısızsa kullanıcıya gösterilecek insan-okur mesaj>
    ErrorDetail  = <başarısızsa stderr/exception metni — sadece log'a>
}
```

Engine.ps1 tarafında her çağrı şu pattern'i izler:
```powershell
$result = Invoke-Anonkneti -HsmIp $ip
if (-not $result.Success) {
    Write-GenesisLog -Level ERROR -Message $result.ErrorMessage
    # Read-ValidatedInput ile R/C/A veya R/S/A seçimi al, state döndür
}
```

**`throw` SADECE şu iki durumda kalır:**
1. `Genesis-Init.ps1` seviyesinde — Logger.ps1 veya Engine.ps1 fiziksel olarak
   bulunamazsa (workflow henüz başlamadı, dönülecek state yok)
2. Vendor modül dosyaları (BinaryRunner.ps1, HardserverConfig.ps1) dot-source
   sırasında bulunamazsa — bu durum zaten VENDOR_SELECT state'inde try-catch
   ile yakalanıp state'e çevriliyor (§3'e bakınız), fonksiyon içindeki throw
   değil, dot-source çağrısını saran try-catch bunu yönetir.

Bu kontrat Prompt 6 (BinaryRunner refactor) ve Prompt 7 (HardserverConfig refactor)
için bağlayıcıdır. Her iki dosyadaki TÜM public fonksiyonlar bu şekle geçirilecek.

### Karar 2 — Add-HsClientEntry: Aynı IP, Farklı clientperm

Mevcut idempotency kontrolü sadece "IP var mı" bakıyordu. Eksik senaryo: IP zaten
kayıtlı ama farklı bir clientperm ile tekrar eklenmek isteniyor.

**Yeni davranış (upsert mantığı):**
```
IP zaten [hs_clients]'ta kayıtlı mı?
    HAYIR → yeni kayıt ekle (mevcut davranış, değişmedi)
    EVET  → mevcut kaydın clientperm değerini parse et
        │
        ├── Aynı clientperm → INFO log "already registered, no change", skip
        │
        └── Farklı clientperm →
                WARN: "Client <IP> already registered with clientperm=<old>.
                       Requested: clientperm=<new>."
                Read-ValidatedInput -Validator YesNo
                "Update to <new>? (Y/N)"
                  Y → SADECE o kaydın clientperm= satırını güncelle
                      (addr/keyhash/esn satırlarına dokunma, sıra bozulmasın)
                  N → mevcut haliyle bırak, INFO log "kept as-is"
```

Bu, `Add-HsClientEntry`'nin "append-only" değil "upsert" (ekle-veya-güncelle)
fonksiyonuna dönüşmesi demektir. Prompt 7'de bu mantık implement edilecek.

---

## 9. ANTIGRAVITY PROMPTLARI İÇİN MODÜL BÖLÜMLENDİRMESİ

Kod değişikliklerini şu 7 parçaya böleceğiz (Antigravity halüsinasyonunu azaltmak için her prompt tek modül + tek amaç):

```
PROMPT 1: core/Validator.ps1 (YENİ dosya)
          + Read-ValidatedInput wrapper

PROMPT 2: core/StepTracker.ps1 (YENİ dosya)
          + $global:GenesisWorkflow init

PROMPT 3: core/Cleanup.ps1 (YENİ dosya)
          + Invoke-BackupRetention
          + Start-GenesisEngine'de backup cleanup çağrısı

PROMPT 4: core/MenuNavigation.ps1 (YENİ dosya)
          + Show-MainMenu, Show-VendorMenu, Show-EntrustRoleMenu
          + Confirm-Exit
          + $global:GenesisStates sabitleri

PROMPT 5: core/Engine.ps1 (REFACTOR)
          + State loop (linear workflow → state machine)
          + Vendor selection sonrası binary presence check
          + NFAST_HOME env kontrolü

PROMPT 6: vendors/entrust/BinaryRunner.ps1 (REFACTOR)
          + _Invoke-NfastBinary'e -Interactive ve -TeeToConsole
          + Invoke-NfkmInfo YENİ
          + Enquiry parse: Module # split yaklaşımı
          + Anonkneti timeout desteği (Start-Job)

PROMPT 7: vendors/entrust/HardserverConfig.ps1 (REFACTOR)
          + _Build-NethsmEntry: boş field'ları omit et
          + Add-HsClientEntry: ClientPerm parametrik
          + Config push copy-to-workdir stratejisi
```

Her prompt'ta:
- Ne değişecek
- Ne değişmeyecek
- Fonksiyon imzaları (parametreler)
- Hata davranışları
- Test kriterleri
