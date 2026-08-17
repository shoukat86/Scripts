<#
.SYNOPSIS
    This script detects if the version of Intel Chipset Device Software installed on the device is the latest version.
.DESCRIPTION
    This script is designed exclusively for Windows environments. 
    It queries the Windows Registry (HKLM Uninstall keys) to detect whether Intel Chipset Device Software is installed and whether the installed version meets or exceeds the expected minimum version. 
    It is intended for use with Windows-based endpoint management and detection workflows (e.g., Intune, SCCM, or similar deployment tools) and will not run on non-Windows platforms, as it relies on the Windows Registry provider and .NET Framework classes unavailable outside Windows.
.EXAMPLE
    ./Detect-IntelChipset.ps1
.NOTES
    NAME: Detect-IntelChipsetVersion.ps1
    CREATION DATE: 03/2025
    LAST UPDATE: 03/2025
#>
# ------------------------------------ End of Help description block ---------------------------------------
# ======================================== FUNCTIONS =======================================================
# ----------------------------------------------------------------------------------------------------------
Set-StrictMode -Version latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# ======================================== FUNCTIONS =======================================================
# ----------------------------------------------------------------------------------------------------------
function Get-CheckChipsetInstall 
{
    <#
    .SYNOPSIS
        Checks to see if Intel Chipset is installed
    .DESCRIPTION
        Runs detection across the registries and file paths to capture all instances of Intel Chipset Device Software application
    .EXAMPLE
        Get-CheckChipsetInstall
    #>
    # Variables
    $results = @()
    $registryPaths = @(
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    # Extract all registries under HKLM uninstall path
    foreach ($path in $registryPaths) 
    {
        Get-ChildItem -Path $path | ForEach-Object {
            $obj = [PSCustomObject]@{
                GUID            = $_.PSChildName
                DisplayName     = $_.GetValue("DisplayName")
                DisplayVersion  = $_.GetValue("DisplayVersion")
                InstallLocation = $_.GetValue("InstallLocation")
                UninstallString = $_.GetValue("UninstallString")
                Is32bit         = if ($path -match "Wow6432Node") { "Yes" } else { "No" }
            }
            if ($obj.DisplayName -match "Intel" -and $obj.DisplayName -match "Chipset") 
            {
                $results += $obj
            }
        }
    }
    return $results
}
# ----------------------------------------------------------------------------------------------------------
# ============================================ MAIN ===================================================
# Call the function and display the results of installed versions (for verification)
$installedVersions = Get-CheckChipsetInstall
$expectedVersion = "10.1.20020.8623"
if ($installedVersions) 
{
    $foundMatch = $false
    foreach ($installed in $installedVersions) 
    {
        if ([version]$installed.DisplayVersion -ge [version]$expectedVersion) 
        {
            $foundMatch = $true
            break;
        }
    }
    if ($foundMatch) 
    {
        Write-Output "Installed"
    }
}
#exit $LASTEXITCODE
#end Detect-IntelChipset.ps1
