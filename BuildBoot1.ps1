<# BuildBoot1.ps1
PowerShell equivalent of BuildBoot1.bat
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  [void][System.Console]::ReadKey($true)
}

try {
  Write-Host ""
  Write-Host "------------------"
  Write-Host "- Assemble Boot1 -"
  Write-Host "------------------"
  Write-Host ""

  # Delete outputs (ignore if missing)
  Remove-Item ".\Boot1.bin", ".\Boot1.lst" -Force -ErrorAction SilentlyContinue

  # Assemble
  Write-Host "nasm -f bin Boot1.asm -o Boot1.bin -l Boot1.lst"
  & nasm -f bin Boot1.asm -o Boot1.bin -l Boot1.lst

  if ($LASTEXITCODE -ne 0) {
    throw "nasm failed with exit code $LASTEXITCODE."
  }

  Write-Host ""
  Wait-ForKey

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