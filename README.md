# Windows Update Repair

Single-run PowerShell diagnostics and repair for common Windows Update component problems.

> **Testing note:** This was tested by me to be working. User experience may vary.

## Included

`Repair-WindowsUpdate.ps1`

## Usage

Diagnostic mode:

```powershell
.\Repair-WindowsUpdate.ps1
```

Repair mode:

```powershell
.\Repair-WindowsUpdate.ps1 -Repair
```

Preview changes:

```powershell
.\Repair-WindowsUpdate.ps1 -Repair -WhatIf
```

Run from an elevated PowerShell window. Repair mode stops the required update services, preserves the current update caches by renaming them, restarts the services and requests a new scan. It does not restart Windows.

Logs are stored in `C:\ProgramData\WindowsUpdateRepair\Logs`.

Exit code `0` means success, `1` means a fatal error, and `2` means the run completed with warnings.

## Disclaimer

Use this project at your own risk. Results vary by Windows version, policy, update state, permissions and security software. Maintain a current backup and review the generated logs.

## License

MIT
