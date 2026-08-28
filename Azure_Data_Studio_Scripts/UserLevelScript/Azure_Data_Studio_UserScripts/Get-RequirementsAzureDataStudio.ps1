<#
.SYNOPSIS
    Determines whether the Azure Data Studio detect/remediate pair should run on this device.
.DESCRIPTION
    Checks whether any instance of Azure Data Studio is installed. Used as the "requirements"
    gate script so that detection/remediation only runs on devices where the app is present.
.EXAMPLE
    ./Get-RequirementsAzureDataStudio.ps1
.NOTES
    NAME: Get-RequirementsAzureDataStudio.ps1
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

# ============================================ MAIN ========================================================

try {
    $InstallData = Get-InstalledAppData

    if (@($InstallData).Count -gt 0) {
        Write-Output 'Required'
        exit 0
    }
    else {
        Write-Output 'Not Required'
        exit 1
    }
}
catch {
    # Fail safe: if detection itself errors out, don't claim the requirement is met
    Write-Output 'Not Required'
    exit 1
}
# End of Get-RequirementsAzureDataStudio.ps1
# ----------------------------------------------------------------------------------------------------------
