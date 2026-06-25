# Windows Update Repair

Single-run PowerShell diagnostics and repair for common Windows Update component problems.

## One-click use

1. Download and extract the repository.
2. Double-click `Run-OneClick.bat`.
3. Approve the administrator prompt.
4. Review logs under `C:\ProgramData\WindowsUpdateRepair\Logs`.

The launcher runs repair mode directly. Use `-WhatIf` from PowerShell when a preview is required.

## Repair behavior

The script:

1. Captures the current runtime state and startup type of BITS, Windows Update, Cryptographic Services and Windows Installer.
2. Stops available update services.
3. Preserves `SoftwareDistribution` and `catroot2` by renaming them to timestamped backup paths.
4. Starts only the services required for scan validation.
5. Runs a synchronous Windows Update Agent search and writes `UpdateScan.json`.
6. Restores each captured service to its original running/stopped state in a `finally` block.
7. Does not change any service startup type.

The operating system may subsequently trigger-start update services as part of normal Windows servicing. The script does not force every service to remain running.

## Usage

Diagnostics only:

```powershell
.\Repair-WindowsUpdate.ps1
```

Repair:

```powershell
.\Repair-WindowsUpdate.ps1 -Repair
```

Preview:

```powershell
.\Repair-WindowsUpdate.ps1 -Repair -WhatIf
```

## Results

The log directory includes before/after service state, recent hotfixes, pending-restart indicators, scan results, warnings and a transcript.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Completed without warnings |
| `1` | Fatal execution or validation error |
| `2` | Completed with one or more warnings |

A scan warning can indicate policy, proxy, service or Windows Update Agent issues and must not be treated as a confirmed successful scan.

## Validation

A Windows GitHub Actions workflow parses every `.ps1` file with PowerShell's native parser and runs PSScriptAnalyzer with error-severity findings treated as failures.

## License

MIT License.
