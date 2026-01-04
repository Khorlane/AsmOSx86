<# BuildKernelAndRun.ps1
PowerShell equivalent of BuildKernelAndRun.bat
- Calls BuildKernel.ps1
- Calls BuildCopy.ps1 (replaces DOSBox copy step)
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

  # Launch Bochs
  $BochsExe = "C:\Program Files\Bochs-2.8\bochs.exe"
  $BochsCfg = "C:\Projects\AsmOSx86\AsmOSx86.bxrc"

  if (-not (Test-Path -LiteralPath $BochsExe -PathType Leaf)) {
    Fail "Bochs executable not found: $BochsExe"
  }
  if (-not (Test-Path -LiteralPath $BochsCfg -PathType Leaf)) {
    Fail "Bochs config not found: $BochsCfg"
  }

  & $BochsExe -q -f $BochsCfg

  # Optional: treat exit code 1 as "user powered off" (quiet)
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
    throw "Bochs exited with code $LASTEXITCODE."
  }
}
catch {
  Fail ("ERROR: " + $_.Exception.Message)
}