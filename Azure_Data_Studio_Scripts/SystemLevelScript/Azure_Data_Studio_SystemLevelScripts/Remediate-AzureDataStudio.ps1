<#
.SYNOPSIS
    Updates Azure Data Studio to the required version and removes any leftover outdated
    installations, only after the update is confirmed successful.
.DESCRIPTION
    Detects installed Azure Data Studio instances, silently upgrades any that are below the
    required minimum version, verifies a compliant version is present afterward, and only then
    removes outdated instances. Skips remediation entirely while Azure Data Studio is running,
    to avoid interrupting the user or failing on a locked file.
.EXAMPLE
    ./Remediate-AzureDataStudio.ps1
.NOTES
    NAME: Remediate-AzureDataStudio.ps1
#>

# ------------------------------------ End of Help description block ---------------------------------------

Set-StrictMode -Version Latest

# ======================================== FUNCTIONS =======================================================

# ----------------------------------------------------------------------------------------------------------
function Write-LogEvent {
    <# ----------------------------------------------------------------------------------------------------------
    .SYNOPSIS
        Write a log entry to the Windows Application-style custom event log used for this remediation.
    .DESCRIPTION
        Creates the event log/source if it does not already exist, then writes the requested entry.
    .PARAMETER Source
        Which operation is causing the log to be written.
    .PARAMETER EventID
        Event ID to log.
    .PARAMETER Message
        Message to log.
    .PARAMETER Type
        Entry type: Error, Warning, Information, SuccessAudit, or FailureAudit.
    .EXAMPLE
        Write-LogEvent -Source "AzureDataStudio-Remediation" -EventID 50001 -Type "Information" -Message "Update completed."
    ------------------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [int32]$EventID,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Error', 'Warning', 'Information', 'SuccessAudit', 'FailureAudit')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $LogName = 'AppRemediation'

    try {
        if (-not ([System.Diagnostics.EventLog]::Exists($LogName) -and [System.Diagnostics.EventLog]::SourceExists($Source))) {
            New-EventLog -Source $Source -LogName $LogName -ErrorAction SilentlyContinue
            Limit-EventLog -LogName $LogName -MaximumSize 15360KB -ErrorAction SilentlyContinue
        }
        Write-EventLog -LogName $LogName -Source $Source -EventID $EventID -EntryType $Type -Message $Message
    }
    catch {
        # Event log writes are best-effort; don't let a logging failure abort remediation
        Write-Verbose "Failed to write to event log '$LogName': $($_.Exception.Message)"
    }
} # End of Write-LogEvent function
# ----------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------
function Write-LogInfo {
    <# ---------------------------------------------------------------------------
    .SYNOPSIS
        Write a timestamped line to the run's transcript log file and to the verbose stream.
    .PARAMETER Message
        Message to log.
    .EXAMPLE
        Write-LogInfo -Message "Update completed."
    ------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $Now              = Get-Date -Format G
    $FormattedMessage = "[$Now] $Message"

    Write-Verbose -Message $FormattedMessage
    Add-Content -Path $script:LogFilePath -Value $FormattedMessage
} # End of Write-LogInfo function
# ----------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------
function Write-LogException {
    <# ---------------------------------------------------------------------------
    .SYNOPSIS
        Log an exception with the function and line number where it occurred.
    .PARAMETER ErrorRecord
        The caught error record (pass $_ from the catch block).
    .PARAMETER FunctionName
        Name of the function/scope where execution failed.
    .EXAMPLE
        Write-LogException -ErrorRecord $_ -FunctionName $FuncName
    ------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    $Line             = $ErrorRecord.InvocationInfo.ScriptLineNumber
    $Now              = Get-Date -Format G
    $FormattedMessage = "[$Now] Exception in $FunctionName (line $Line): $($ErrorRecord.Exception.Message)"

    Write-Verbose -Message $FormattedMessage
    Add-Content -Path $script:LogFilePath -Value $FormattedMessage
} # End of Write-LogException function
# ----------------------------------------------------------------------------------------------------------

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
function Get-OutdatedInstances {
    <# -----------------------------------------------------------------------------------------------------
        .SYNOPSIS
            Filters a set of detected installations down to those below the required version.
        .PARAMETER InstallData
            Array of applications detected by Get-InstalledAppData.
        .PARAMETER RequiredVersion
            [version] object representing the minimum acceptable version.
        .EXAMPLE
            Get-OutdatedInstances -InstallData $InstallData -RequiredVersion ([version]'1.52.0')
    --------------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$InstallData,

        [Parameter(Mandatory = $true)]
        [version]$RequiredVersion
    )

    $InstallData | Where-Object {
        $ParsedVersion = $null
        if ([version]::TryParse($_.DisplayVersion, [ref]$ParsedVersion)) {
            $ParsedVersion -lt $RequiredVersion
        }
        else {
            Write-LogInfo -Message "Could not parse version '$($_.DisplayVersion)' for '$($_.DisplayName)'; treating as outdated."
            $true
        }
    }
} # End of Get-OutdatedInstances function
# ----------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------
function Test-CompliantVersionPresent {
    <# -----------------------------------------------------------------------------------------------------
        .SYNOPSIS
            Returns $true if at least one detected installation meets the required version.
        .PARAMETER InstallData
            Array of applications detected by Get-InstalledAppData.
        .PARAMETER RequiredVersion
            [version] object representing the minimum acceptable version.
        .EXAMPLE
            Test-CompliantVersionPresent -InstallData $InstallData -RequiredVersion ([version]'1.52.0')
    --------------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$InstallData,

        [Parameter(Mandatory = $true)]
        [version]$RequiredVersion
    )

    foreach ($Instance in $InstallData) {
        $ParsedVersion = $null
        if ([version]::TryParse($Instance.DisplayVersion, [ref]$ParsedVersion) -and $ParsedVersion -ge $RequiredVersion) {
            return $true
        }
    }
    return $false
} # End of Test-CompliantVersionPresent function
# ----------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------
function Update-AzureDataStudio {
    <# -----------------------------------------------------------------------------------------------------
    .SYNOPSIS
        Silently upgrade any outdated Azure Data Studio instances to the required version.
    .DESCRIPTION
        Picks the correct architecture-specific installer, verifies it exists, runs it silently,
        and records the exit code for each attempt so callers can confirm success before acting
        on the result.
    .PARAMETER InstallData
        Array of applications to evaluate for update.
    .PARAMETER AppList
        Hashtable containing the required version of the application, keyed "ADS".
    .EXAMPLE
        Update-AzureDataStudio -InstallData $InstallData -AppList $AppList
    --------------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$InstallData,

        [Parameter(Mandatory = $true)]
        [hashtable]$AppList
    )

    # ------------------- Variables -----------------
    $ScriptPath      = $PSScriptRoot
    $RequiredVersion = [version]$AppList['ADS']
    # Use the true native OS architecture even if this script runs under a 32-bit PowerShell host
    $Arch            = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $InstallerMap    = @{
        'AMD64' = Join-Path -Path $ScriptPath -ChildPath 'azuredatastudio-windows-setup-1.52.0.exe'
        'ARM64' = Join-Path -Path $ScriptPath -ChildPath 'azuredatastudio-windows-arm64-setup-1.52.0.exe'
    }
    $Result = @()
    # ------------------------------------------------

    $OutdatedInstances = Get-OutdatedInstances -InstallData $InstallData -RequiredVersion $RequiredVersion

    if (-not $OutdatedInstances) {
        return @('Azure Data Studio is already running the required version.')
    }

    if (-not $InstallerMap.ContainsKey($Arch)) {
        Write-LogInfo -Message "Unsupported architecture: $Arch"
        return @("Unsupported architecture: $Arch")
    }

    $InstallerPath = $InstallerMap[$Arch]

    if (-not (Test-Path -Path $InstallerPath -PathType Leaf)) {
        Write-LogInfo -Message "Installer not found at '$InstallerPath'."
        return @("Installer not found at '$InstallerPath'.")
    }

    foreach ($Instance in $OutdatedInstances) {
        Write-LogInfo -Message "Upgrading $($Instance.DisplayName) $($Instance.DisplayVersion) -> $($AppList['ADS']) using $Arch installer."

        try {
            $Process = Start-Process -FilePath $InstallerPath -ArgumentList '/VERYSILENT /NORESTART /MERGETASKS=!runcode' -Wait -NoNewWindow -PassThru

            if ($Process.ExitCode -eq 0) {
                $Result += "$($Instance.DisplayName) $($Instance.DisplayVersion) -> $($AppList['ADS']): Success"
                Write-LogInfo -Message "Update completed successfully (exit code 0)."
            }
            else {
                $Result += "$($Instance.DisplayName) $($Instance.DisplayVersion) -> $($AppList['ADS']): Failed (exit code $($Process.ExitCode))"
                Write-LogInfo -Message "Update FAILED with exit code $($Process.ExitCode)."
            }
        }
        catch {
            $Result += "$($Instance.DisplayName) $($Instance.DisplayVersion) -> $($AppList['ADS']): Failed to launch installer - $($_.Exception.Message)"
            Write-LogInfo -Message "Failed to launch installer: $($_.Exception.Message)"
        }
    }

    return $Result
} # End of Update-AzureDataStudio function
# ----------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------
function Remove-AzureDataStudio {
    <# -----------------------------------------------------------------------------------------------------
    .SYNOPSIS
        Remove outdated Azure Data Studio instances.
    .DESCRIPTION
        Runs each outdated instance's registered uninstall string silently and records the exit
        code of each attempt.
    .PARAMETER InstallData
        Array of applications to evaluate for removal.
    .PARAMETER AppList
        Hashtable containing the required version of the application, keyed "ADS".
    .EXAMPLE
        Remove-AzureDataStudio -InstallData $InstallData -AppList $AppList
    --------------------------------------------------------------------------------------------------------
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$InstallData,

        [Parameter(Mandatory = $true)]
        [hashtable]$AppList
    )

    $RequiredVersion   = [version]$AppList['ADS']
    $OutdatedInstances = Get-OutdatedInstances -InstallData $InstallData -RequiredVersion $RequiredVersion
    $Result            = @()

    if (-not $OutdatedInstances) {
        return @('No outdated Azure Data Studio version found to remove.')
    }

    foreach ($Instance in $OutdatedInstances) {
        if ([string]::IsNullOrWhiteSpace($Instance.UninstallString)) {
            Write-LogInfo -Message "No uninstall string found for $($Instance.DisplayName) $($Instance.DisplayVersion); skipping."
            $Result += "$($Instance.DisplayName) $($Instance.DisplayVersion): Skipped - no uninstall string"
            continue
        }

        $UninstallExe = $Instance.UninstallString.Trim('"')

        if (-not (Test-Path -Path $UninstallExe -PathType Leaf)) {
            Write-LogInfo -Message "Uninstaller not found at '$UninstallExe' for $($Instance.DisplayName) $($Instance.DisplayVersion); skipping."
            $Result += "$($Instance.DisplayName) $($Instance.DisplayVersion): Skipped - uninstaller not found"
            continue
        }

        Write-LogInfo -Message "Uninstalling $($Instance.DisplayName) $($Instance.DisplayVersion)."

        try {
            $Process = Start-Process -FilePath $UninstallExe -ArgumentList '/VERYSILENT' -Wait -NoNewWindow -PassThru

            if ($Process.ExitCode -eq 0) {
                $Result += "Uninstalled $($Instance.DisplayName) $($Instance.DisplayVersion): Success"
                Write-LogInfo -Message "Uninstall completed successfully (exit code 0)."
            }
            else {
                $Result += "Uninstalled $($Instance.DisplayName) $($Instance.DisplayVersion): Failed (exit code $($Process.ExitCode))"
                Write-LogInfo -Message "Uninstall FAILED with exit code $($Process.ExitCode)."
            }
        }
        catch {
            $Result += "$($Instance.DisplayName) $($Instance.DisplayVersion): Failed to launch uninstaller - $($_.Exception.Message)"
            Write-LogInfo -Message "Failed to launch uninstaller: $($_.Exception.Message)"
        }
    }

    return $Result
} # End of Remove-AzureDataStudio function
# ----------------------------------------------------------------------------------------------------------

# ============================================== MAIN ======================================================

# ------------------------------- Variables -------------------------------
$LogSource       = 'AzureDataStudio-Remediation'
$AppList         = @{ 'ADS' = '1.52.0' }
$RequiredVersion = [version]$AppList['ADS']
$Timestamp       = (Get-Date -Format o) -replace ':', '.'

$script:LogFilePath = Join-Path -Path $env:TEMP -ChildPath "RemediateAzureDataStudio_$Timestamp.log"
$ExitCode            = 0   # assume success
# -------------------------------------------------------------------------

New-Item -Path $script:LogFilePath -ItemType File -Force | Out-Null

try {
    Write-LogInfo -Message 'Script execution started.'

    $RunningProcess = Get-Process -Name 'azuredatastudio' -ErrorAction SilentlyContinue

    if ($null -eq $RunningProcess) {
        $InstallData = Get-InstalledAppData

        if ($InstallData) {
            $UpdateResult  = Update-AzureDataStudio -InstallData $InstallData -AppList $AppList
            $RefreshedData = Get-InstalledAppData

            # Only remove outdated instances once we've confirmed a compliant version is actually
            # present, so a failed/partial update never leaves the device with no working install.
            if (Test-CompliantVersionPresent -InstallData $RefreshedData -RequiredVersion $RequiredVersion) {
                $RemoveResult = Remove-AzureDataStudio -InstallData $RefreshedData -AppList $AppList
            }
            else {
                $RemoveResult = @('Skipped removal of outdated version(s): no compliant version confirmed after update attempt.')
                Write-LogInfo -Message $RemoveResult[0]
            }

            $Summary = "Update status: $($UpdateResult -join ' | ') -- Removal status: $($RemoveResult -join ' | ')"
            Write-LogInfo -Message $Summary
            Write-LogEvent -Source $LogSource -EventID 50001 -Type 'Information' -Message $Summary
        }
        else {
            Write-LogInfo -Message 'No Azure Data Studio installation found on the device.'
            Write-LogEvent -Source $LogSource -EventID 50002 -Type 'Information' -Message 'No Azure Data Studio installation found on the device.'
        }
    }
    else {
        Write-LogInfo -Message 'Azure Data Studio is currently running; remediation skipped for this run to avoid interrupting the user.'
    }
}
catch {
    # Flag a failure
    $ExitCode = 1

    $FunctionName = $MyInvocation.MyCommand.Name
    Write-LogException -ErrorRecord $_ -FunctionName $FunctionName
    Write-LogEvent -Source $LogSource -EventID 50003 -Type 'Error' -Message "Remediation failed in ${FunctionName}: $($_.Exception.Message)"
}
finally {
    Write-LogInfo -Message 'Script execution completed.'
}

exit $ExitCode
# end of Remediate-AzureDataStudio.ps1
# ----------------------------------------------------------------------------------------------------------
