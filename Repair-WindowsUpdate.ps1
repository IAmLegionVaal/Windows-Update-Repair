#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Repair,
    [ValidateNotNullOrEmpty()][string]$LogRoot = "$env:ProgramData\WindowsUpdateRepair\Logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$runPath = Join-Path $LogRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
$serviceNames = @('bits','wuauserv','cryptsvc','msiserver')
$warnings = New-Object System.Collections.Generic.List[string]
$transcriptStarted = $false

function Add-WarningRecord([string]$Message) {
    $script:warnings.Add($Message)
    Write-Warning $Message
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ServiceSnapshot {
    foreach ($name in $serviceNames) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) {
            [pscustomobject]@{
                Name = $service.Name
                WasRunning = ($service.Status -eq 'Running')
                StartType = [string]$service.StartType
            }
        }
        else {
            Add-WarningRecord "Service '$name' is unavailable."
        }
    }
}

function Restore-ServiceSnapshot([object[]]$Snapshot) {
    foreach ($item in $Snapshot) {
        try {
            $service = Get-Service -Name $item.Name -ErrorAction Stop
            if ($item.WasRunning -and $service.Status -ne 'Running') {
                Start-Service -Name $item.Name -ErrorAction Stop
            }
            elseif (-not $item.WasRunning -and $service.Status -eq 'Running') {
                Stop-Service -Name $item.Name -Force -ErrorAction Stop
            }
        }
        catch {
            Add-WarningRecord "Could not restore '$($item.Name)' runtime state: $($_.Exception.Message)"
        }
    }
}

function Save-Diagnostics([string]$Prefix) {
    Get-Service -Name $serviceNames -ErrorAction SilentlyContinue |
        Select-Object Name,Status,StartType |
        Export-Csv (Join-Path $runPath "${Prefix}_Services.csv") -NoTypeInformation -Encoding UTF8

    Get-HotFix -ErrorAction SilentlyContinue |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 50 HotFixID,Description,InstalledBy,InstalledOn |
        Export-Csv (Join-Path $runPath "${Prefix}_Hotfixes.csv") -NoTypeInformation -Encoding UTF8

    $pendingRename = $false
    try {
        $value = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction Stop
        $pendingRename = $null -ne $value.PendingFileRenameOperations
    }
    catch {}

    [pscustomobject]@{
        ComponentServicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        PendingFileRename = $pendingRename
    } | ConvertTo-Json | Out-File (Join-Path $runPath "${Prefix}_PendingRestart.json") -Encoding UTF8
}

function Invoke-UpdateScan {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $started = Get-Date
        $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
        $resultCode = [int]$result.ResultCode
        $warningCount = if ($null -ne $result.Warnings) { [int]$result.Warnings.Count } else { 0 }
        $succeeded = ($resultCode -eq 2 -and $warningCount -eq 0)

        [pscustomobject]@{
            Method = 'Windows Update Agent COM API'
            StartedAt = $started
            CompletedAt = Get-Date
            ResultCode = [string]$result.ResultCode
            PendingUpdates = [int]$result.Updates.Count
            WarningCount = $warningCount
            Succeeded = $succeeded
        } | ConvertTo-Json | Out-File (Join-Path $runPath 'UpdateScan.json') -Encoding UTF8

        switch ($resultCode) {
            2 {
                if ($warningCount -gt 0) {
                    Add-WarningRecord "Update scan completed with $warningCount warning(s). Review UpdateScan.json."
                }
            }
            3 {
                Add-WarningRecord 'Update scan succeeded with errors; the result set may be incomplete.'
            }
            default {
                Add-WarningRecord "Update scan returned result code $($result.ResultCode)."
            }
        }
    }
    catch {
        Add-WarningRecord "Synchronous update scan failed: $($_.Exception.Message)"
    }
}

try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if (-not (Test-Admin)) { throw 'Run PowerShell as Administrator.' }

    New-Item $runPath -ItemType Directory -Force | Out-Null
    Start-Transcript -Path (Join-Path $runPath 'Transcript.txt') -Force | Out-Null
    $transcriptStarted = $true
    Save-Diagnostics Before

    if ($Repair -and $PSCmdlet.ShouldProcess('Windows Update components','Reset caches and run a synchronous scan')) {
        $snapshot = @(Get-ServiceSnapshot)
        try {
            foreach ($item in $snapshot) {
                $service = Get-Service -Name $item.Name
                if ($service.Status -ne 'Stopped') {
                    Stop-Service -Name $item.Name -Force -ErrorAction Stop
                    $service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
                }
            }

            $suffix = Get-Date -Format 'yyyyMMdd_HHmmss'
            foreach ($cache in @("$env:SystemRoot\SoftwareDistribution","$env:SystemRoot\System32\catroot2")) {
                if (Test-Path -LiteralPath $cache) {
                    $target = "${cache}.backup_${suffix}"
                    if (Test-Path -LiteralPath $target) { throw "Backup already exists: $target" }
                    Move-Item -LiteralPath $cache -Destination $target -ErrorAction Stop
                }
            }

            foreach ($name in @('cryptsvc','bits','wuauserv')) {
                if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
                    Start-Service -Name $name -ErrorAction Stop
                }
            }
            Invoke-UpdateScan
        }
        finally {
            Restore-ServiceSnapshot $snapshot
        }
        Save-Diagnostics After
    }

    $warnings | Out-File (Join-Path $runPath 'Warnings.txt') -Encoding UTF8
    Stop-Transcript | Out-Null
    $transcriptStarted = $false

    if ($warnings.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    if ($transcriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    Write-Error $_.Exception.Message
    exit 1
}
