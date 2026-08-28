<#
.SYNOPSIS
    Detects whether Azure Data Studio is installed and running the required minimum version.
.DESCRIPTION
    Scans the standard Windows uninstall registry keys for Azure Data Studio installations
    and reports whether at least one compliant instance exists with no outdated instance
    remaining. Intended for use as an endpoint-management detection script (exit 0 = compliant,
    exit 1 = not compliant).
.EXAMPLE
    ./Detect-AzureDataStudio.ps1
.NOTES
    NAME: Detect-AzureDataStudio.ps1
#>

# ------------------------------------ End of Help description block ---------------------------------------

Set-StrictMode -Version Latest

# ======================================== FUNCTIONS =======================================================

# ----------------------------------------------------------------------------------------------------------
function Get-InstalledAppData {
    <# -----------------------------------------------------------------------------------------------------
        .SYNOPSIS
            Get installed instances of Azure Data Studio by traversing the uninstall registry keys.
        .DESCRIPTION
            Runs detection across the 64-bit and 32-bit (Wow6432Node) uninstall registry keys and
            returns any entries whose DisplayName matches "Azure Data Studio".
        .EXAMPLE
            Get-InstalledAppData
    --------------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param ()

    $RegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $Results = foreach ($Path in $RegistryPaths) {
        Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | ForEach-Object {
            $DisplayName = $_.GetValue('DisplayName')

            # Filter for Azure Data Studio during collection
            if ($DisplayName -match 'Azure Data Studio') {
                [pscustomobject]@{
                    GUID            = $_.PSChildName
                    DisplayName     = $DisplayName
                    DisplayVersion  = $_.GetValue('DisplayVersion')
                    UninstallString = $_.GetValue('UninstallString')
                }
            }
        }
    }
    return $Results
} # End of Get-InstalledAppData function
# ----------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------
function Test-ADSCompliance {
    <# ------------------------------------------------------------------------------------------------
        .SYNOPSIS
            Determines whether Azure Data Studio is compliant with the required minimum version.
        .DESCRIPTION
            Compares each detected installation against the required minimum version. Returns $true
            only if at least one compliant instance exists AND no outdated instance remains.
        .PARAMETER InstallData
            Array of applications detected by Get-InstalledAppData.
        .PARAMETER MinimumVersion
            The minimum acceptable version string, e.g. "1.52.0".
        .EXAMPLE
            Test-ADSCompliance -InstallData $InstallData -MinimumVersion '1.52.0'
    ---------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$InstallData,

        [Parameter(Mandatory = $true)]
        [string]$MinimumVersion
    )

    if (-not $InstallData -or @($InstallData).Count -eq 0) {
        return $false
    }

    $RequiredVersion = [version]$MinimumVersion
    $HasCompliant    = $false
    $HasOutdated     = $false

    foreach ($Instance in $InstallData) {
        $ParsedVersion = $null
        if (-not [version]::TryParse($Instance.DisplayVersion, [ref]$ParsedVersion)) {
            # Skip entries with an unparsable version string rather than throwing
            Write-Verbose "Could not parse version '$($Instance.DisplayVersion)' for '$($Instance.DisplayName)'; skipping."
            continue
        }

        if ($ParsedVersion -ge $RequiredVersion) { $HasCompliant = $true }
        else { $HasOutdated = $true }
    }

    return ($HasCompliant -and -not $HasOutdated)
} # End of Test-ADSCompliance function
# ----------------------------------------------------------------------------------------------------------

# ============================================ MAIN ========================================================

# ------------------------------- Variables -------------------------------
$MinimumVersion = '1.52.0'
# -------------------------------------------------------------------------

try {
    $InstallData = Get-InstalledAppData

    if (Test-ADSCompliance -InstallData $InstallData -MinimumVersion $MinimumVersion) {
        Write-Output 'Installed'
        exit 0
    }
    else {
        Write-Output 'Not-Installed'
        exit 1
    }
}
catch {
    # Fail safe: treat unexpected errors as non-compliant rather than crashing the detection run
    Write-Output 'Not-Installed'
    exit 1
}
# End of Detect-AzureDataStudio.ps1
# ----------------------------------------------------------------------------------------------------------
