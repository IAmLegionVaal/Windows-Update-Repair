# Windows Update Repair

Single-run PowerShell diagnostics and repair for common Windows Update component problems.

> **Testing note:** This was tested by me to be working. User experience may vary.

## One-click use

1. Download and extract the repository.
2. Double-click `Run-OneClick.bat`.
3. Approve the Windows administrator prompt.
4. The launcher stops the required services, preserves the existing update caches by renaming them, restores the services and requests a new scan. There is no menu.
5. Review the exit code and logs in `C:\ProgramData\WindowsUpdateRepair\Logs`.

## Included

`Repair-WindowsUpdate.ps1`

## PowerShell usage

```powershell
.\Repair-WindowsUpdate.ps1
.\Repair-WindowsUpdate.ps1 -Repair
.\Repair-WindowsUpdate.ps1 -Repair -WhatIf
```

The default script mode records update services, recent update events, installed hotfixes and pending-restart indicators. Repair mode does not restart Windows automatically.

Exit code `0` means success, `1` means a fatal error and `2` means the run completed with warnings.

Results vary by Windows version, policy, update state, permissions and security software. Maintain a current backup and review the generated logs.

MIT License.
