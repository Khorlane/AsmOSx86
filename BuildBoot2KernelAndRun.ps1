<# BuildBoot2KernelAndRun.ps1
PowerShell equivalent of BuildBoot2KernelAndRun.bat
- Builds Boot2
- Builds Kernel
- Calls BuildCopy.ps1 instead of DOSBox
- Pauses at the same points
- Launches Bochs
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  [void][System.Console]::ReadKey($true)
}

function Fail($msg) {
  Write-Error $msg -ErrorAction Continue
  Wait-ForKey
  exit 1
}

try {
  Write-Host ""
  Write-Host "------------------"
  Write-Host "- Assemble Boot2 -"
  Write-Host "------------------"

  # call BuildBoot2.bat noexit -> BuildBoot2.ps1 noexit
  & .\BuildBoot2.ps1 noexit
  if (-not $?) {
    throw "BuildBoot2.ps1 failed."
  }

  Write-Host ""
  Write-Host "-------------------"
  Write-Host "- Assemble Kernel -"
  Write-Host "-------------------"

  # call BuildKernel.bat noexit -> BuildKernel.ps1 noexit
  & .\BuildKernel.ps1 noexit
  if (-not $?) {
    throw "BuildKernel.ps1 failed."
  }

  Write-Host ""
  Write-Host "--------------------------------------"
  Write-Host "- Copy Boot2 and Kernel to Boot Disk -"
  Write-Host "--------------------------------------"

  # Replaces DOSBox copy step
  & .\BuildCopy.ps1
  if (-not $?) {
    throw "BuildCopy.ps1 failed."
  }

  Clear-Host
  Write-Host ""
  Write-Host "--------------------------"
  Write-Host "- Boot Disk prep is done -"
  Write-Host "--------------------------"
  Write-Host ""
  Wait-ForKey

  Clear-Host
  Write-Host ""
  Write-Host "--------------------------------"
  Write-Host "- Boot up AsmOSx86 using Bochs -"
  Write-Host "--------------------------------"
  Wait-ForKey

  $BochsExe = "C:\Program Files\Bochs-2.8\bochs.exe"
  $BochsCfg = "C:\Projects\AsmOSx86\AsmOSx86.bxrc"

  if (-not (Test-Path -LiteralPath $BochsExe -PathType Leaf)) {
    Fail "Bochs executable not found: $BochsExe"
  }
  if (-not (Test-Path -LiteralPath $BochsCfg -PathType Leaf)) {
    Fail "Bochs config not found: $BochsCfg"
  }

  & $BochsExe -q -f $BochsCfg
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
    throw "Bochs exited with code $LASTEXITCODE."
  }
}
catch {
  Fail ("ERROR: " + $_.Exception.Message)
}