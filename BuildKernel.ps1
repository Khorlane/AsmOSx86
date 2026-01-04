<# BuildKernel.ps1
Assembles Kernel.asm -> Kernel.bin / Kernel.lst
- If called with "noexit", do NOT pause (for chained scripts)
- If called with "exit", exit at the end (legacy behavior)
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
  Write-Host "-------------------"
  Write-Host "- Assemble Kernel -"
  Write-Host "-------------------"
  Write-Host ""

  Remove-Item ".\Kernel.bin", ".\Kernel.lst" -Force -ErrorAction SilentlyContinue

  Write-Host "nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst"
  & nasm -f bin Kernel.asm -o Kernel.bin -l Kernel.lst

  if ($LASTEXITCODE -ne 0) {
    throw "nasm failed with exit code $LASTEXITCODE."
  }

  Write-Host ""

  # Skip pause when chained
  if (!($args.Count -ge 1 -and $args[0] -eq 'noexit')) {
    Wait-ForKey
  }

  # Legacy behavior
  if ($args.Count -ge 1 -and $args[0] -eq 'exit') {
    exit 0
  }
}
catch {
  Write-Error ("ERROR: " + $_.Exception.Message) -ErrorAction Continue
  Wait-ForKey
  exit 1
}