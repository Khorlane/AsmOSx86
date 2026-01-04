<# AsmOSx86Run.ps1
PowerShell equivalent of AsmOSx86Run.bat
- Clears screen
- Prompts user
- Launches Bochs
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  [void][System.Console]::ReadKey($true)
}

Clear-Host
Write-Host ""
Write-Host "--------------------------------"
Write-Host "- Boot up AsmOSx86 using Bochs -"
Write-Host "--------------------------------"
Wait-ForKey

$BochsExe = "C:\Program Files\Bochs-2.8\bochs.exe"
$BochsCfg = "C:\Projects\AsmOSx86\AsmOSx86.bxrc"

if (-not (Test-Path -LiteralPath $BochsExe -PathType Leaf)) {
  Write-Error "Bochs executable not found: $BochsExe"
  Wait-ForKey
  exit 1
}

if (-not (Test-Path -LiteralPath $BochsCfg -PathType Leaf)) {
  Write-Error "Bochs config not found: $BochsCfg"
  Wait-ForKey
  exit 1
}

& $BochsExe -q -f $BochsCfg

# Exit code 1 = user powered off Bochs (acceptable)
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
  Write-Error "Bochs exited with code $LASTEXITCODE."
  Wait-ForKey
  exit 1
}

exit 0