[CmdletBinding()]
param(
  # Optional override for where backups are stored.
  # Default is: <AddonDev>\z Backup\fr0z3nUI_Backups\<addonName>
  [string]$BackupRoot,

  # Retention window. Backups older than this are deleted.
  # Set to 0 to delete everything.
  [int]$KeepDays = 7
)

$ErrorActionPreference = 'Stop'

$repoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
if (-not $repoRoot) { throw 'Unable to determine git repo root.' }

$addonName = Split-Path -Leaf $repoRoot
$addonDevRoot = Split-Path -Parent $repoRoot
$defaultBackupRoot = Join-Path $addonDevRoot ('z Backup\\fr0z3nUI_Backups\\' + $addonName)

$backupRoot = if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $defaultBackupRoot } else { $BackupRoot }
if (-not (Test-Path -LiteralPath $backupRoot)) {
  Write-Host 'No backups folder present.'
  exit 0
}

$cutoff = if ($KeepDays -le 0) { [DateTime]::MinValue } else { (Get-Date).AddDays(-1 * $KeepDays) }

$children = Get-ChildItem -LiteralPath $backupRoot -Force
$toDelete = @()

foreach ($c in $children) {
  # Only consider timestamped snapshot folders (avoid accidentally deleting other helper files)
  if (-not $c.PSIsContainer) { continue }

  # Prefer parsing snapshot folder name: YYYYMMDD_HHMMSS
  $snapshotTime = $null
  if ($c.Name -match '^(\d{8})_(\d{6})$') {
    $snapshotTime = [DateTime]::ParseExact($c.Name, 'yyyyMMdd_HHmmss', $null)
  } else {
    # Fallback to filesystem write time if the folder isn't in the expected format
    $snapshotTime = $c.LastWriteTime
  }

  if ($snapshotTime -lt $cutoff) {
    $toDelete += $c
  }
}

foreach ($c in $toDelete) {
  $attempts = 0
  while ($true) {
    try {
      Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction Stop
      break
    } catch {
      $attempts++
      if ($attempts -ge 8) {
        Write-Warning "Failed to remove: $($c.FullName)"
        Write-Warning $_
        break
      }
      Start-Sleep -Milliseconds 250
    }
  }
}

if ($KeepDays -le 0) {
  Write-Host "Deleted all backups (best-effort): $backupRoot"
} else {
  Write-Host "Pruned backups older than $KeepDays day(s) (best-effort): $backupRoot"
}
