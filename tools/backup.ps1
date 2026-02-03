[CmdletBinding()]
param(
  [ValidateSet('all','changed')]
  [string]$Mode = 'all',

  [string[]]$Paths,

  [switch]$IncludeUntracked,

  # Optional override for where backups are stored.
  # Default is: <AddonDev>\z Backup\fr0z3nUI_Backups\<addonName>
  [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
if (-not $repoRoot) { throw 'Unable to determine git repo root.' }

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$addonName = Split-Path -Leaf $repoRoot
$addonDevRoot = Split-Path -Parent $repoRoot
$defaultBackupRoot = Join-Path $addonDevRoot ('z Backup\\fr0z3nUI_Backups\\' + $addonName)

$backupRoot = if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $defaultBackupRoot } else { $BackupRoot }
$backupDir = Join-Path $backupRoot $timestamp

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Copy-RelativeFile {
  param(
    [Parameter(Mandatory=$true)][string]$AbsolutePath
  )

  $relative = Resolve-Path -LiteralPath $AbsolutePath | ForEach-Object {
    $_.Path.Substring($repoRoot.Length).TrimStart('\\','/')
  }

  $destPath = Join-Path $backupDir $relative
  $destFolder = Split-Path -Parent $destPath
  New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
  Copy-Item -LiteralPath $AbsolutePath -Destination $destPath -Force
}

# Determine which files to back up
$files = @()

if ($Paths -and $Paths.Count -gt 0) {
  foreach ($p in $Paths) {
    $abs = Join-Path $repoRoot $p
    if (-not (Test-Path -LiteralPath $abs)) { throw "Path not found: $p" }
    $item = Get-Item -LiteralPath $abs
    if ($item.PSIsContainer) {
      $files += Get-ChildItem -LiteralPath $item.FullName -File -Recurse
    } else {
      $files += $item
    }
  }
} elseif ($Mode -eq 'changed') {
  $changed = git -C $repoRoot status --porcelain=v1
  foreach ($line in $changed) {
    # Porcelain format: XY<space>path (ignore renames for now)
    $path = $line.Substring(3).Trim()
    if (-not $path) { continue }
    if ($path -match '->') { $path = ($path -split '->')[-1].Trim() }
    $abs = Join-Path $repoRoot $path
    if (Test-Path -LiteralPath $abs) {
      $files += Get-Item -LiteralPath $abs
    }
  }
} else {
  $tracked = git -C $repoRoot ls-files
  foreach ($path in $tracked) {
    if (-not $path) { continue }

    $abs = Join-Path $repoRoot $path
    if (Test-Path -LiteralPath $abs) {
      $files += Get-Item -LiteralPath $abs
    }
  }

  if ($IncludeUntracked) {
    $untracked = git -C $repoRoot ls-files --others --exclude-standard
    foreach ($path in $untracked) {
      if (-not $path) { continue }

      $abs = Join-Path $repoRoot $path
      if (Test-Path -LiteralPath $abs) {
        $files += Get-Item -LiteralPath $abs
      }
    }
  }
}

$files = $files | Sort-Object -Property FullName -Unique

foreach ($f in $files) {
  if ($f -and (Test-Path -LiteralPath $f.FullName)) {
    Copy-RelativeFile -AbsolutePath $f.FullName
  }
}

$meta = [ordered]@{
  timestamp = $timestamp
  repoRoot  = $repoRoot
  addonName = $addonName
  backupRoot = $backupRoot
  mode      = $Mode
  includeUntracked = [bool]$IncludeUntracked
  paths     = $Paths
  head      = (git -C $repoRoot rev-parse HEAD).Trim()
  status    = (git -C $repoRoot status --porcelain=v1)
  fileCount = $files.Count
}

$metaPath = Join-Path $backupDir '_manifest.json'
$meta | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $metaPath -Encoding UTF8

Write-Host "Backup created: $backupDir"
