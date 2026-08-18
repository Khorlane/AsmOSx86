<# BuildPrograms.ps1
Assembles Prog1.asm, Prog2.asm, and Prog3.asm into flat binaries.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

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
  Set-Location $RepoRoot
  foreach ($prog in @("Prog1", "Prog2", "Prog3")) {
    Write-Host "nasm -f bin $prog.asm -o $prog.bin -l $prog.lst"
    & nasm -f bin "$prog.asm" -o "$prog.bin" -l "$prog.lst"
    if ($LASTEXITCODE -ne 0) {
      throw "nasm failed with exit code $LASTEXITCODE."
    }
  }
  Wait-ForKey
  exit 0
}
catch {
  Write-Error ("ERROR: " + $_.Exception.Message)
  Wait-ForKey
  exit 1
}
