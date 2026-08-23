<# BuildBoot.ps1
Assembles Boot.asm into the 512-byte boot sector binary.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$DidPushLocation = $false

function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  try {
    [void][System.Console]::ReadKey($true)
  }
  catch {
    Write-Host "(No interactive console available; continuing.)"
  }
}

try {
  Push-Location $RepoRoot
  $DidPushLocation = $true

  Write-Host ""
  Write-Host "------------------"
  Write-Host "- Assemble Boot -"
  Write-Host "------------------"
  Write-Host ""

  # Delete outputs (ignore if missing)
  Remove-Item ".\Boot.bin", ".\Boot.lst" -Force -ErrorAction SilentlyContinue

  # Assemble
  Write-Host "nasm -f bin Boot.asm -o Boot.bin -l Boot.lst"
  & nasm -f bin Boot.asm -o Boot.bin -l Boot.lst

  if ($LASTEXITCODE -ne 0) {
    throw "nasm failed with exit code $LASTEXITCODE."
  }

  if ($args.Count -lt 1 -or $args[0] -ne 'noexit') {
    Write-Host ""
    Wait-ForKey
  }

  # Equivalent of: if x%1 == xexit exit
  if ($args.Count -ge 1 -and $args[0] -eq 'exit') {
    exit 0
  }
}
catch {
  Write-Error ("ERROR: " + $_.Exception.Message) -ErrorAction Continue
  Wait-ForKey
  exit 1
}
finally {
  if ($DidPushLocation) {
    Pop-Location
  }
}
