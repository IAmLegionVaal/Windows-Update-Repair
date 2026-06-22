<#
.SYNOPSIS
Diagnoses and repairs common Windows Update component problems.

.DESCRIPTION
The default run records update services, recent update events and pending
restart indicators. Use -Repair to stop update services, preserve the existing
update caches by renaming them, and restart the services. No restart occurs.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Repair,
    [string]$LogRoot = "$env:ProgramData\WindowsUpdateRepair\Logs"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$runPath = Join-Path $LogRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
$serviceNames = @('bits','wuauserv','cryptsvc','msiserver')
$warnings = New-Object System.Collections.Generic.List[string]
$transcript = $false

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-Diagnostics {
    Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption,Version,BuildNumber,LastBootUpTime |
        Export-Csv (Join-Path $runPath 'OperatingSystem.csv') -NoTypeInformation

    Get-Service -Name $serviceNames -ErrorAction SilentlyContinue |
        Select-Object Name,Status,StartType |
        Export-Csv (Join-Path $runPath 'UpdateServices.csv') -NoTypeInformation

    Get-HotFix -ErrorAction SilentlyContinue |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 50 HotFixID,Description,InstalledBy,InstalledOn |
        Export-Csv (Join-Path $runPath 'RecentHotfixes.csv') -NoTypeInformation

    try {
        Get-WinEvent -FilterHashtable @{
            LogName='System'
            ProviderName='Microsoft-Windows-WindowsUpdateClient'
            StartTime=(Get-Date).AddDays(-14)
        } -MaxEvents 200 -ErrorAction Stop |
            Select-Object TimeCreated,Id,LevelDisplayName,Message |
            Export-Csv (Join-Path $runPath 'WindowsUpdateEvents.csv') -NoTypeInformation
    }
    catch {
        $warnings.Add("Update event collection: $($_.Exception.Message)")
    }

    [pscustomobject]@{
        ComponentBasedServicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    } | ConvertTo-Json | Out-File (Join-Path $runPath 'PendingRestart.json') -Encoding UTF8
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if (-not (Test-Admin)) { throw 'Run PowerShell as Administrator.' }

    New-Item -Path $runPath -ItemType Directory -Force | Out-Null
    Start-Transcript -Path (Join-Path $runPath 'Transcript.txt') -Force | Out-Null
    $transcript = $true

    Save-Diagnostics

    if ($Repair -and $PSCmdlet.ShouldProcess('Windows Update components','Reset update caches and restart services')) {
        foreach ($name in $serviceNames) {
            $service = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($service -and $service.Status -ne 'Stopped') {
                try { Stop-Service -Name $name -Force -ErrorAction Stop }
                catch { $warnings.Add("Could not stop $name: $($_.Exception.Message)") }
            }
        }

        $suffix = Get-Date -Format 'yyyyMMdd_HHmmss'
        $cachePaths = @(
            "$env:SystemRoot\SoftwareDistribution",
            "$env:SystemRoot\System32\catroot2"
        )

        foreach ($cache in $cachePaths) {
            if (Test-Path $cache) {
                $backupName = (Split-Path $cache -Leaf) + ".backup_$suffix"
                try { Rename-Item -Path $cache -NewName $backupName -ErrorAction Stop }
                catch { $warnings.Add("Could not preserve $cache: $($_.Exception.Message)") }
            }
        }

        foreach ($name in @('cryptsvc','bits','wuauserv','msiserver')) {
            try { Start-Service -Name $name -ErrorAction Stop }
            catch { $warnings.Add("Could not start $name: $($_.Exception.Message)") }
        }

        try { Start-Process -FilePath 'UsoClient.exe' -ArgumentList 'StartScan' -WindowStyle Hidden }
        catch { $warnings.Add("Update scan trigger: $($_.Exception.Message)") }

        Save-Diagnostics
    }

    $warnings | Out-File (Join-Path $runPath 'Warnings.txt') -Encoding UTF8
    if ($transcript) { Stop-Transcript | Out-Null; $transcript = $false }

    if ($warnings.Count -gt 0) {
        Write-Host "[WARN] Completed with $($warnings.Count) warning(s). Logs: $runPath" -ForegroundColor Yellow
        exit 2
    }

    Write-Host "[OK] Completed. Logs: $runPath" -ForegroundColor Green
    exit 0
}
catch {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
    Write-Error $_.Exception.Message
    exit 1
}
