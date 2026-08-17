# Test-IntelChipsetVersion.ps1

A PowerShell detection script that checks whether Intel Chipset Device Software is installed on a Windows device and whether the installed version meets or exceeds a defined minimum version.

## Platform

**Windows only.**

This script relies on:
- The Windows Registry (`HKLM:\SOFTWARE\...\Uninstall` and `HKLM:\SOFTWARE\Wow6432Node\...\Uninstall`)
- Windows-specific .NET classes (`Net.ServicePointManager`, `Net.SecurityProtocolType`)

It will **not** run on PowerShell Core on Linux or macOS, since the Registry provider and these .NET classes are unavailable outside Windows.

**Requirements:**
- Windows PowerShell 5.1+ or PowerShell 7+ on Windows
- Local administrative rights are typically required to read `HKLM` registry hives in restricted environments

## What it does

The script scans both 64-bit and 32-bit (Wow6432Node) uninstall registry paths for any entry matching "Intel" and "Chipset" in the display name. It compares the installed version against an expected minimum version (`10.1.20020.8623` by default) and outputs `Installed` if a matching, compliant version is found.

## Usage

```powershell
.\Detect-IntelChipsetVersion.ps1
```

Intended for use as a **detection script** in endpoint management / compliance workflows (e.g., Intune proactive remediation, SCCM configuration items, or similar deployment and compliance tooling).

## Output

- Writes `Installed` to output if a compliant version is found
- No output if the software is missing or the installed version is below the expected minimum

## Customization

Update the `$expectedVersion` variable in the script to match the minimum version you want to enforce in your environment.

## Disclaimer

This script is provided as-is for reference and automation purposes. Review and test in a non-production environment before deploying at scale.
