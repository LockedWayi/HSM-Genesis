# Project Genesis — Genesis-Init

Interactive bootstrap automation for Entrust nShield Connect (network-attached) HSM Day 0 provisioning.

---

## 1. Purpose

Day 0 provisioning of nShield Connect HSMs involves repetitive, error-prone manual steps: running CLI binaries in sequence, copy-pasting ESN/keyhash values between terminal output and config files, hand-editing `hardserver.cfg` with strict syntax rules, and tracking which servers have been enrolled where.

Genesis-Init automates this into a single interactive script. The engineer runs one command, answers a series of prompts, and the script performs the correct sequence of binary calls, config edits, and validations — with backups, idempotency checks, and clear error recovery at every step.

**Current platform: Windows Server, PowerShell 5.1.**
**Planned platform: Linux (separate implementation, not a port — see Section 9).**

---

## 2. Design Principles

These are non-negotiable and should be preserved across all future changes:

1. **Dot-source, single-directory packaging.** No PowerShell modules, no `$env:PSModulePath` dependency. The entire project is a folder that can be zipped, copied to a server, and run — including in air-gapped environments.

2. **No credential storage.** Day 0 provisioning as designed here requires no passwords, PINs, or tokens to be entered or persisted. If a future requirement needs credentials, this must be treated as a deliberate architectural addition, not bolted on.

3. **Detect & Prompt idempotency.** Before overwriting any existing config, the script detects it, shows the user what will happen, and requires explicit confirmation. Nothing is silently overwritten.

4. **No crash on bad input.** Every user input goes through a validator. Invalid input re-prompts; it never throws an unhandled exception or exits the process.

5. **State machine navigation, not linear script.** The user can go back to a previous menu, retry a failed step, skip an optional step, or abort — without the whole script dying. `throw` is reserved for genuinely unrecoverable conditions (missing core files at startup); workflow-level errors return to a previous state instead.

6. **ASCII encoding for all nShield config files.** `hardserver.cfg` and any `hsm-<ESN>\config` file must be written with `[System.Text.Encoding]::ASCII` via `[System.IO.File]::WriteAllText`/`WriteAllLines`. `Out-File`/`Set-Content` are avoided because they can introduce BOM or UTF-16, which nShield's config parser rejects.

7. **String.Replace, not regex, for template substitution.** `[regex]::Replace` combined with `[regex]::Escape` corrupts CRLF sequences into literal `\r\n` text in the output. Plain `.Replace()` is used instead.

8. **English only, program-wide.** All console output, log messages, and code comments are in English. This is a deliberate simplicity choice over building an i18n layer for a single-vendor tool. (See `GENESIS-FLOW-v2.md` for the one exception under discussion.)

9. **Global scope for cross-module state.** PowerShell dot-sourcing does not share `$script:`-scoped variables across separately dot-sourced files reliably. All cross-module state uses `$global:Genesis*` naming (e.g. `$global:GenesisNfastHome`, `$global:GenesisLogFile`) to avoid ambiguity.

---

## 3. Directory Structure

The repository root contains one subdirectory per platform implementation.
**All paths in this document and in every modification prompt are given
relative to `windows/`** (the current, active implementation) unless stated
otherwise — e.g. "core/Engine.ps1" means `windows/core/Engine.ps1` on disk.

```
Genesis-Init/                                   # Repository root
├── windows/                                     # Active implementation (this document's scope)
│   ├── Genesis-Init.ps1                        # Entry point — the only file the user runs directly
│   │
│   ├── core/
│   │   ├── Logger.ps1                          # Write-GenesisLog, Write-GenesisSection
│   │   ├── Engine.ps1                          # Orchestration: module loading, state machine, workflows
│   │   ├── Validator.ps1                       # Read-ValidatedInput + validators
│   │   ├── StepTracker.ps1                     # [PLANNED] Start/Complete-GenesisStep, Show-GenesisSummary
│   │   ├── MenuNavigation.ps1                  # [PLANNED] State constants, menu display functions
│   │   └── Cleanup.ps1                         # [PLANNED] Backup retention
│   │
│   ├── vendors/
│   │   └── entrust/
│   │       ├── BinaryRunner.ps1                # nfast binary wrappers (anonkneti, rfs-setup, etc.)
│   │       ├── HardserverConfig.ps1            # Template rendering, surgical hs_clients editing
│   │       └── templates/
│   │           └── hardserver.cfg.template     # Base config with {{NETHSM_DYNAMIC_BLOCK}} placeholder
│   │
│   └── output/
│       ├── logs/                                # genesis_YYYYMMDD.log (timestamped, ASCII)
│       ├── backups/                             # hardserver.cfg.bak_YYYYMMDD_HHMMSS
│       └── push-workdir/                        # [PLANNED] Staging area for cfg-pushnethsm
│
├── linux/                                       # [NOT STARTED] Future parallel implementation — see §9
│
├── README.md                                    # This file
└── GENESIS-FLOW-v2.md                           # Authoritative step-by-step flow specification
```

`[PLANNED]` marks files that do not exist yet as of this writing and are the subject of the upcoming modification prompts. `README.md` and `GENESIS-FLOW-v2.md` live at the repository root, not inside `windows/`, since they describe (or will describe) both implementations.

---

## 4. What Each Existing File Does

**Genesis-Init.ps1**
Entry point. Requires Administrator (`#Requires -RunAsAdministrator`). Resolves `$PSScriptRoot`, dot-sources `core/Logger.ps1` then `core/Engine.ps1`, calls `Start-GenesisEngine`. Contains no business logic itself.

**core/Logger.ps1**
`Write-GenesisLog -Level <DEBUG|INFO|WARN|ERROR> -Message <string>` — writes to console (color-coded) and to `output/logs/genesis_YYYYMMDD.log` (ASCII, timestamped). `Write-GenesisSection -Title <string>` — prints a visual section header for readability during long runs. `Initialize-Logger` sets up the log file and writes a session header. State is held in `$global:GenesisLogFile` / `$global:GenesisLogInitialized`.

**core/Engine.ps1**
Currently: admin check, dot-source loading of vendor modules (`HardserverConfig.ps1`, `BinaryRunner.ps1`), a simple role menu (RFS / Client), and two workflow functions `_Invoke-RfsServerSetup` / `_Invoke-ClientServerSetup` that call into `BinaryRunner.ps1` and `HardserverConfig.ps1` in sequence. This is the file being refactored into a state machine per `GENESIS-FLOW-v2.md`.

**vendors/entrust/BinaryRunner.ps1**
Wraps every nfast CLI binary used in the workflows: `anonkneti`, `rfs-setup`, `cfg-pushnethsm`, `nethsmenroll`, `rfs-sync`, `enquiry`. The core primitive is `_Invoke-NfastBinary`, which runs a binary via `Start-Process`, redirects stdout/stderr to temp files (unless the binary needs interactive stdin, e.g. `nethsmenroll`), and returns exit code + captured output. Public wrapper functions parse specific outputs (e.g. `Invoke-Anonkneti` extracts ESN and Keyhash via regex).

**vendors/entrust/HardserverConfig.ps1**
Two responsibilities:
1. `New-EntrustHardserverConfig` — renders `hardserver.cfg` from the template, filling in `{{NETHSM_DYNAMIC_BLOCK}}` with one or more HSM entries (multi-entry separator: a single `-` line between entries, per nShield config syntax).
2. `Add-HsClientEntry` — surgically edits an existing HSM-side config (`hsm-<ESN>\config`) to add a client entry under `[hs_clients]`, using a `-----` (5-hyphen) separator convention observed in production. Does not touch any other section of the file.

**vendors/entrust/templates/hardserver.cfg.template**
A real production `hardserver.cfg`, spliced so the `[nethsm_imports]` section's field definitions are replaced with a single `{{NETHSM_DYNAMIC_BLOCK}}` placeholder. All other sections are untouched from the original.

---

## 5. The Two Supported Roles

### RFS (Remote File System) Server Setup
This server acts as the RFS for one or more HSMs. Workflow: verify HSM reachability (`anonkneti`), enroll the HSM to this RFS (`rfs-setup --force`), whitelist client IPs (`rfs-setup --gang-client --write-noauth`), edit the HSM's own config to register those clients (`Add-HsClientEntry`), and push the updated config back to the HSM (`cfg-pushnethsm`).

### Client Server Setup
This server is a client of an existing RFS. Workflow: verify RFS reachability (ping), generate/update this server's own `hardserver.cfg` with the HSM(s) it needs to talk to, enroll to each HSM (`nethsmenroll --force`, interactive), sync Security World files from RFS (`rfs-sync --setup` then `--update`), verify HSM state (`enquiry`, then `nfkminfo` as cross-check), and enable PKCS#11 loadsharing (`cknfastrc`).

Full step-by-step detail, including every decision branch, error message, and recovery path, is specified in **`GENESIS-FLOW-v2.md`** — that document is authoritative for exact behavior; this README is the map, not the territory.

---

## 6. Known Constraints From Production Testing

These were discovered by testing against real hardware and must not be regressed:

| Constraint | Why |
|---|---|
| `remote_esn` and `ntoken_esn` lines must be **omitted entirely** when empty, not written as `field=` | nShield's config parser enforces "if present, exactly 14 characters" for ESN fields. An empty value fails validation with `empty string (length must be between 14 and 14)`. |
| Multi-entry sections need exactly one `-` line between entries (`[nethsm_imports]`) | nShield config syntax rule, confirmed against the real config file header. |
| Multi-entry client blocks in HSM-side config use `-----` (5 hyphens) | Observed convention in the production `hs_clients` section — different separator than `[nethsm_imports]`. |
| `hardserver.cfg` must be generated **before** running `nethsmenroll`, not after | `nethsmenroll` reads the existing config; if it's missing or malformed, enrollment fails. Order matters. |
| `nethsmenroll` must run without stdout/stderr redirection | It can prompt interactively ("Is the above correct? (yes/no):"). Redirecting output hides the prompt and the process hangs waiting for stdin. |
| `Start-Process -ArgumentList` must not receive an empty array | Passing `@()` throws a parameter validation error. Use splatting to omit `-ArgumentList` entirely when there are no arguments (e.g. `enquiry` takes none). |
| Template substitution must use `.Replace()`, not `[regex]::Replace` + `[regex]::Escape` | The escape step converts real CRLF bytes into the literal text `\r\n`, which gets written to disk as-is and breaks the config parser. |
| `enquiry` output parsing must skip the "Server:" block and only inspect "Module #N:" blocks | The Server block describes the driver host, not the HSM. Searching the whole output for `mode operational` can produce false positives/negatives. |
| `nfkminfo` output: only the `state` line immediately following `Module #N` (before any `Slot` sub-block) is relevant | `Slot #0` / `Slot #1` blocks have their own `state` lines describing smartcard/softcard slots, not the module itself. |

---

## 7. Bugs Fixed During Development (Reference Only)

| Symptom | Root Cause | Fix |
|---|---|---|
| `_Invoke-ClientServerSetup` not recognized | `$null = . $file` broke function registration in nested dot-source context | Removed `$null =`, use plain `. $file` |
| Cross-module variables invisible | `$script:` scope doesn't cross separately dot-sourced files reliably | Promoted to `$global:Genesis*` |
| `nethsmenroll` hung indefinitely | stdout redirected, hiding an interactive yes/no prompt | Removed redirection for this binary specifically |
| "entry already exists" on second run | Missing `--force` flag | Added `--force` |
| `hardserver.cfg` contained literal `\r\n` text | `[regex]::Escape()` on the replacement string | Switched to `String.Replace()` |
| `nethsmenroll`: "bad integer" | Stale malformed config from the bug above, read before the fix took effect | Fixed at the source; re-run regenerates a clean file |
| `nethsmenroll`: "empty string (length must be between 14 and 14)" | `remote_esn=` written with no value instead of omitted | **Fix pending** — see `GENESIS-FLOW-v2.md` §8, `_Build-NethsmEntry` |
| `_Invoke-NfastBinary` failed on `enquiry` (no args) | `Start-Process -ArgumentList @()` throws | Splatting: only add `-ArgumentList` key when `$Arguments.Count -gt 0` |

---

## 8. Current State vs. Target State

As of this writing, `core/Engine.ps1` implements a **linear** two-role workflow (see Section 4). It works end-to-end on real hardware for both roles, with the one pending fix noted above.

`GENESIS-FLOW-v2.md` specifies a **target architecture** that is not yet implemented:
- State machine navigation (menu → vendor select → role select → workflow, with back/retry/abort at every step)
- Centralized input validation (`core/Validator.ps1`, currently absent)
- Step timing and a summary table at the end of each run (`core/StepTracker.ps1`, currently absent)
- Backup retention (keep newest 10, currently absent)
- Pre-flight connectivity checks (`anonkneti` for HSM reachability, ping for RFS reachability) before collecting the rest of the inputs
- Config push via a staging directory instead of pushing directly from `%ProgramData%` (permission safety)
- `nfkminfo` as a cross-check after `enquiry`

The migration from current state to target state is being done as a series of scoped, file-specific modification prompts (see Section 10) rather than one large rewrite, specifically to keep an AI coding agent's changes auditable and to minimize hallucinated modifications to unrelated code.

---

## 9. Out of Scope (For Now)

- **Linux implementation.** Will be a separate, parallel implementation (bash), not a PowerShell-to-bash port. Directory structure will mirror this one under a `linux/` root. Not started yet.
- **nToken automation.** If a client uses an nToken, the script warns and defers to manual configuration. Full automation of nToken-based enrollment is not planned in the current phase.
- **Multi-HSM RFS setup in a single run.** The RFS workflow currently handles one HSM per run. If multiple HSMs need to become RFS targets, the script is re-run per HSM (it's idempotent, so this is safe).
- **i18n / localization.** Program is English-only by design (see Section 2, principle 8).

---

## 10. How Changes Are Made to This Project

Modifications are given to an AI coding agent (Antigravity) as a sequence of scoped prompts, each of which:
1. Names the exact file(s) to be changed
2. States what changes and what must NOT change
3. Gives exact function signatures where new functions are introduced
4. Specifies error-handling behavior precisely (this project does not tolerate silent `throw`-and-crash for recoverable errors)
5. References `GENESIS-FLOW-v2.md` for the authoritative behavior spec rather than re-deriving it

The first prompt given to the agent is always a **context-building prompt** — it reads every file in the project and this README, and confirms its understanding, before any code is touched. See `PROMPT-0-CONTEXT.md`.

---

## 11. Prerequisites to Run

- Windows Server, PowerShell 5.1+
- Administrator privileges
- Entrust nShield Security World client software installed
- `NFAST_HOME` environment variable set (or default path `C:\Program Files\nCipher\nfast` must be correct)
- Network path to target HSM(s) open on TCP/9004 (bidirectional)
- Execution policy allowing script execution:
  ```powershell
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
  ```

Run with (from inside the `windows/` directory):
```powershell
cd windows
.\Genesis-Init.ps1
```
