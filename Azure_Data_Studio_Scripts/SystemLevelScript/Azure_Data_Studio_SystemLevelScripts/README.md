# Azure Data Studio – Version Compliance Scripts

PowerShell scripts to detect, gate, and remediate outdated installations of **Azure Data
Studio** on Windows endpoints. Written for use with an endpoint management platform's
Detect / Require / Remediate model (e.g. SCCM Configuration Item, Intune Proactive
Remediation, or an equivalent orchestrator).

| Script | Role | Runs as |
|---|---|---|
| `Get-RequirementsAzureDataStudio.ps1` | Requirement gate — decides whether this device is in scope | System / Admin |
| `Detect-AzureDataStudio.ps1` | Detection — reports whether the device is compliant | System / Admin |
| `Remediate-AzureDataStudio.ps1` | Remediation — upgrades and cleans up outdated installs | **System / Admin (required)** |

---

## How it fits together

1. **Requirement** — `Get-RequirementsAzureDataStudio.ps1` checks whether Azure Data Studio
   is installed at all. If it isn't, the device is out of scope and the pair below never runs.
2. **Detection** — `Detect-AzureDataStudio.ps1` checks whether the installed version meets
   the minimum required version. Exit `0` = compliant, exit `1` = not compliant.
3. **Remediation** — `Remediate-AzureDataStudio.ps1` runs only on non-compliant devices. It
   silently upgrades any outdated instance, confirms a compliant version is actually present
   afterward, and only then removes the leftover outdated install.

All three scripts share the same detection logic (`Get-InstalledAppData`), which walks the
64-bit and 32-bit (`Wow6432Node`) `Uninstall` registry keys under `HKLM` and returns any
entry whose `DisplayName` matches `Azure Data Studio`.

---

## Requirements

- Windows 10/11, PowerShell 5.1 or later
- **Administrative / SYSTEM context.** `HKLM:\...\Uninstall` is readable by standard users,
  but the remediation script installs and uninstalls software and must run elevated.
- Supported architectures: **AMD64 (x64)** and **ARM64**. x86 is not supported and will be
  logged as "Unsupported architecture."
- The remediation script expects the version-matched installers to sit alongside it in the
  same folder as the script (`$PSScriptRoot`):
  - `azuredatastudio-windows-setup-<version>.exe` (x64)
  - `azuredatastudio-windows-arm64-setup-<version>.exe` (ARM64)

---

## Updating the target version

Each script defines the required version in one place near the top of the `MAIN` section:

```powershell
$AppList = @{ 'ADS' = '1.52.0' }
```

To roll out a new Azure Data Studio release:

1. Update the version string in **all three** scripts (`Get-RequirementsAzureDataStudio.ps1`
   doesn't use it, but `Detect-` and `Remediate-` must match).
2. Drop the new installer executable(s) next to `Remediate-AzureDataStudio.ps1`, named to
   match the version in `$AppList['ADS']`.
3. Remove or archive the old installer(s) once rollout is confirmed, to keep the package small.

---

## Exit codes

| Script | Exit 0 | Exit 1 |
|---|---|---|
| `Get-RequirementsAzureDataStudio.ps1` | Azure Data Studio found — remediation is applicable | Not found — out of scope |
| `Detect-AzureDataStudio.ps1` | Compliant version installed | Not installed or below minimum version |
| `Remediate-AzureDataStudio.ps1` | Remediation logic completed without a script-level error* | An unhandled error occurred during remediation |

\* A `0` exit from the remediation script means it *ran* to completion, not necessarily that
every install/uninstall step succeeded — check the log file or event log for per-step results
(see below).

---

## Logging

- **Transcript log:** `Remediate-AzureDataStudio.ps1` writes a timestamped log file to
  `%TEMP%\RemediateAzureDataStudio_<timestamp>.log` on each run, including per-instance
  update/removal results and exit codes.
- **Event log:** the remediation script also writes to a custom Windows event log named
  `AppRemediation`, under source `AzureDataStudio-Remediation`:

  | Event ID | Type | Meaning |
  |---|---|---|
  | 50001 | Information | Remediation ran; message includes update/removal summary |
  | 50002 | Information | No Azure Data Studio installation found |
  | 50003 | Error | Remediation failed with an unhandled exception |

---

## Behavior notes

- **Running-process check:** if `azuredatastudio.exe` is currently running, remediation is
  **skipped for that run** rather than forcing an update — this avoids interrupting the user
  and avoids installer failures from locked files. It will be retried on the next scheduled run.
- **Safe removal ordering:** the remediation script never removes an outdated install unless
  it first confirms a version meeting the minimum is present on the device. This prevents a
  failed/partial update from leaving a device with no working installation.
- **Version parsing:** installed versions that don't parse as a standard `[version]` (e.g. a
  malformed or non-standard build string) are logged and treated conservatively (as outdated /
  non-compliant) rather than crashing the script.

---

## Known limitations / things to validate before broad rollout

- Only AMD64 and ARM64 are handled; x86 devices will be logged as unsupported and left as-is.
- The remediation script assumes Azure Data Studio's Inno Setup–style silent switches
  (`/VERYSILENT /NORESTART /MERGETASKS=!runcode` for install, `/VERYSILENT` for uninstall).
  Confirm these still match the vendor's installer if you jump multiple major versions.
- No PowerShell environment was available to execute these scripts end-to-end before delivery
  — validate in a test ring (including the requirement/detect/remediate cycle and log output)
  before wide deployment.

---

## File list

```
Get-RequirementsAzureDataStudio.ps1   # Requirement gate
Detect-AzureDataStudio.ps1            # Compliance detection
Remediate-AzureDataStudio.ps1         # Update + cleanup
README.md                             # This file
```
