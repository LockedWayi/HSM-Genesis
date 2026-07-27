# HSM-Genesis

**Multi-vendor HSM Day 0 Provisioning Automation**

Interactive PowerShell automation that turns the repetitive, error-prone manual steps of HSM Day 0 provisioning — running vendor CLI binaries in the correct order, copy-pasting identity values between terminals, hand-editing strict-syntax config files — into a single guided workflow with validation, backups, idempotency checks, and error recovery at every step.

Built on a vendor-plugin architecture: core engine (state machine, validation, logging, step tracking) is vendor-agnostic; each vendor lives under `vendors/<name>/` with its own binary wrappers and config logic.

```
'##::::'##::'######::'##::::'##:::::'######:::'########:'##::: ##:'########::'######::'####::'######::
 ##:::: ##:'##... ##: ###::'###::::'##... ##:: ##.....:: ###:: ##: ##.....::'##... ##:. ##::'##... ##:
 ##:::: ##: ##:::..:: ####'####:::: ##:::..::: ##::::::: ####: ##: ##::::::: ##:::..::: ##:: ##:::..::
 #########:. ######:: ## ### ##:::: ##::'####: ######::: ## ## ##: ######:::. ######::: ##::. ######::
 ##.... ##::..... ##: ##. #: ##:::: ##::: ##:: ##...:::: ##. ####: ##...:::::..... ##:: ##:::..... ##:
 ##:::: ##:'##::: ##: ##:.:: ##:::: ##::: ##:: ##::::::: ##:. ###: ##:::::::'##::: ##:: ##::'##::: ##:
 ##:::: ##:. ######:: ##:::: ##::::. ######::: ########: ##::. ##: ########:. ######::'####:. ######::
..:::::..:::......:::..:::::..::::::......::::........::..::::..::........:::......:::....:::......:::
```

---

## Supported Vendors

| Vendor  | Model Family                                     | Status                          |
|---------|--------------------------------------------------|---------------------------------|
| Entrust | nShield Connect (network-attached)               | ✅ Implemented, hardware-tested |
| Thales  | Luna Network HSM (Password-based authentication) | 🔜 Planned                      |


New vendors are added as self-contained modules under `vendors/` without touching the core engine.

---

## What It Does — Entrust nShield Connect

Two supported server roles, selected interactively at runtime:

### RFS Server Setup
Configures the machine as the Remote File System (RFS) for one or more nShield Connect HSMs:

1. HSM reachability pre-flight (`anonkneti`) — captures ESN and KNETI keyhash
2. RFS enrollment (`rfs-setup --force`)
3. Client IP whitelisting (`rfs-setup --gang-client --write-noauth`)
4. Waits for the HSM to export its config after the RFS IP is entered on the HSM front panel (guided manual step)
5. Surgical `[hs_clients]` edit on the HSM-side config — if there are existing entries doest not overwrite them, other sections are left untouched, adds new clients. privileged/unprivileged connection mode selection
6. Pushes the modified config back to the HSM (`cfg-pushnethsm`)
7. Verifies the Security World status (`nfkminfo` HKNSO check)

### Client Server Setup
Configures the machine as a crypto client of an existing RFS:

1. RFS reachability check (ping)
2. Per-HSM reachability pre-flight (`anonkneti`)
3. Per-HSM privileged/unprivileged connection mode selection
4. HSM enrollment (`nethsmenroll --force [-p]`, interactive — `[nethsm_imports]` is written by the binary itself, surgically)
5. Security World sync from RFS (`rfs-sync --force --setup`, then `--update`)
6. Connection verification (`enquiry`) and module state cross-check (`nfkminfo`)
7. Security World initialization check (HKNSO hash)
8. PKCS#11 configuration (`cknfastrc` with loadsharing)

Every step supports retry / change input / skip / abort without crashing the session. A timing summary table is printed at the end of each run.

---

## Requirements

| Requirement                   | Detail                                                                   |
|-------------------------------|--------------------------------------------------------------------------|
| OS (tested)                   | Windows Server 2019, Windows 11 Pro 25H2                                 |
| PowerShell                    | 5.1 (ships with both of the above)                                       |
| Privileges                    | Administrator (enforced via `#Requires -RunAsAdministrator`)             |
| Vendor software               | Entrust nShield Security World client software installed                 |
| Tested client versions        | 13.6.11, 13.6.12, 13.6.15                                                |
| Environment                   | `NFAST_HOME` set (or default `C:\Program Files\nCipher\nfast` valid)     |
| Network                       | TCP/9004 open bidirectionally between this server and the HSM(s)         |

**On other Security World client versions:** the tool edits config files by locating section headers (`[hs_clients]`, `[nethsm_imports]`) and works at the section level, so versions that keep the same section names and `syntax-version=1` config format are expected to work — but only the versions listed above have been verified against real hardware. No guarantee is made for untested versions.

---

## Installation
No installer, no modules, no dependencies. The project is a self-contained folder — designed for air-gapped environments.

1. Download or clone the repository
2. Copy the `windows/` folder to the target server
3. Open an elevated PowerShell session

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd windows
.\Genesis-Init.ps1
```

---

## Project Structure

```
windows/
├── Genesis-Init.ps1              # Entry point — the only file you run
├── core/                         # Vendor-agnostic engine
│   ├── Logger.ps1                # Timestamped console + file logging
│   ├── Validator.ps1             # Anti-crash input validation (IPv4, int, choice, Y/N)
│   ├── StepTracker.ps1           # Step timing + end-of-run summary table
│   ├── Cleanup.ps1               # Backup retention (newest 10 kept)
│   ├── MenuNavigation.ps1        # State machine states + menu screens
│   └── Engine.ps1                # Orchestration: state machine + workflows
├── vendors/                      # One folder per vendor — plugin model
│   └── entrust/
│       ├── BinaryRunner.ps1      # nfast binary wrappers with structured result objects
│       ├── HardserverConfig.ps1  # Surgical config editing (hs_clients)
│       └── templates/
└── output/                       # Created automatically on first run
    ├── logs/                     # genesis_YYYYMMDD.log
    ├── backups/                  # Timestamped config backups
    └── push-workdir/             # Staging area for config push operations
```

---

## Design Principles

1. **Vendor-plugin architecture** — the core engine knows nothing vendor-specific; each vendor module is self-contained under `vendors/`.
2. **Dot-source, single-directory packaging** — zip, copy, run. No `PSModulePath`, no installation.
3. **No credential storage** — Day 0 provisioning as implemented requires no passwords, PINs, or tokens.
4. **Detect & Prompt idempotency** — nothing is silently overwritten; existing config is detected, backed up, and confirmed.
5. **Surgical config editing** — only the targeted section is modified; all other sections, comments, and existing entries are preserved byte-for-byte.
6. **No crash on bad input** — every input goes through a validator; invalid input re-prompts.
7. **State machine navigation** — back / retry / skip / abort at every step, without killing the session.
8. **ASCII encoding for all vendor config writes** — HSM config parsers commonly reject BOM/UTF-16.
9. **Structured result objects** — every binary wrapper returns `{Success, ExitCode, Data, ErrorMessage, ErrorDetail}`; workflow functions never throw for recoverable errors.

---

## Known Config Constraints — Entrust nShield

Hard-won rules from testing against real hardware, encoded into the tool:

- `remote_esn=` / `ntoken_esn=` must be **omitted entirely** when empty — the parser enforces exactly 14 characters if the field is present
- `[nethsm_imports]` multi-entry separator is a single `-` line; `[hs_clients]` uses `-----`
- `nethsmenroll` requires unredirected stdout/stderr (interactive ESN/keyhash confirmation)
- `rfs-sync --setup` requires `--force` to suppress its overwrite confirmation prompt
- The HSM only exports its config to the RFS **after** the RFS IP is entered on the HSM front panel (`System > System configuration > Remote file system`) — the RFS workflow waits for this

---

## Out of Scope

- **Security World creation** (Entrust) — a manual ceremony requiring an Administrator Card Set; the tool checks and reports world status but never creates one
- **nToken-based client authentication** — detected and deferred to manual configuration
- **Linux** — planned as a separate parallel implementation, not started
- Post-Day-0 configuration (NTP, remote syslog, SNMP, CodeSafe)

---

## Disclaimer

This tool is developed and tested in a **lab environment**. It modifies HSM-related configuration files and executes enrollment commands against live HSMs. Before using it in a production environment:

- Test the full workflow in a non-production environment first
- Verify backups exist and are restorable
- Review every prompt before confirming

**Use at your own risk. The author accepts no liability for misconfiguration, data loss, or service disruption resulting from the use of this software.** This project is not affiliated with, endorsed by, or supported by Entrust, Thales, or any HSM vendor. All product names and marks are property of their respective owners.

---

## License

﻿MIT License

Copyright (c) 2026 LockedWayi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
---

*created by LockedWayi*
