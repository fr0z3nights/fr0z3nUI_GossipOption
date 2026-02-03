[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$GitPushArgs
)

$ErrorActionPreference = 'Stop'

$repoRoot = (git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
if (-not $repoRoot) { throw 'Unable to determine git repo root.' }

# 1) Always take a timestamped backup before pushing
& (Join-Path $PSScriptRoot 'backup.ps1') -Mode all -IncludeUntracked

# 2) Push
& git -C $repoRoot push @GitPushArgs
if ($LASTEXITCODE -ne 0) {
  throw "git push failed (exit $LASTEXITCODE). Backups were NOT cleared." 
}

# 3) Only prune backups after a successful push
& (Join-Path $PSScriptRoot 'clear_backups.ps1')
