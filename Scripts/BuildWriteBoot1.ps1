<#
BuildWriteBoot1.ps1
Creates a blank 1.44MB floppy image, writes Boot1.bin to sector 0, and verifies
the 0x55AA boot signature at bytes 510-511.
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

function Fail([string]$Message) {
  Write-Error $Message
  Wait-ForKey
  exit 1
}

try {
  $ImagePath = Join-Path $RepoRoot "floppy.img"
  $BootPath  = Join-Path $RepoRoot "Boot1.bin"
  $ExpectedImageSize = 1474560
  $ExpectedBootSize  = 512

  Write-Host "[1/5] Checking Boot1.bin exists and is exactly 512 bytes..."
  if (-not (Test-Path -LiteralPath $BootPath -PathType Leaf)) {
    Fail "Boot file not found: $BootPath"
  }

  $bootInfo = Get-Item -LiteralPath $BootPath
  if ($bootInfo.Length -ne $ExpectedBootSize) {
    Fail "Boot file size is $($bootInfo.Length) bytes; expected $ExpectedBootSize bytes."
  }

  Write-Host "[2/5] Creating blank $ExpectedImageSize-byte floppy image..."
  if (Test-Path -LiteralPath $ImagePath) {
    Remove-Item -LiteralPath $ImagePath -Force
  }

  $fsutilArgs = @("file", "createnew", $ImagePath, $ExpectedImageSize)
  $p = Start-Process -FilePath "fsutil.exe" -ArgumentList $fsutilArgs -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) {
    Fail "fsutil failed (exit code $($p.ExitCode)). Run PowerShell as Administrator."
  }

  Write-Host "[3/5] Verifying floppy.img size..."
  $imgInfo = Get-Item -LiteralPath $ImagePath
  if ($imgInfo.Length -ne $ExpectedImageSize) {
    Fail "Image size is $($imgInfo.Length) bytes; expected $ExpectedImageSize bytes."
  }

  Write-Host "[4/5] Writing Boot1.bin to boot sector..."
  $bootBytes = [System.IO.File]::ReadAllBytes($BootPath)
  $fs = $null
  try {
    $fs = [System.IO.File]::Open(
      $ImagePath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
    $null = $fs.Seek(0, [System.IO.SeekOrigin]::Begin)
    $fs.Write($bootBytes, 0, $ExpectedBootSize)
    $fs.Flush()
  }
  finally {
    if ($fs) { $fs.Close() }
  }

  Write-Host "[5/5] Verifying boot signature..."
  $imgBytes = [System.IO.File]::ReadAllBytes($ImagePath)
  $sig = '{0:X2} {1:X2}' -f $imgBytes[510], $imgBytes[511]
  if (($imgBytes[510] -ne 0x55) -or ($imgBytes[511] -ne 0xAA)) {
    Fail "Invalid boot signature at 510-511: $sig"
  }

  Write-Host "SUCCESS: blank AsmOSx86 floppy image created and Boot1 written ($sig)."
  Write-Host "Image: $ImagePath"
  Wait-ForKey
}
catch {
  Write-Error ("ERROR: " + $_.Exception.Message) -ErrorAction Continue
  Wait-ForKey
  exit 1
}
