<# 
BootSectorWrite.ps1
Creates a 1.44MB floppy image, verifies size, writes Boot1.bin to boot sector (offset 0),
then verifies 0x55AA signature at bytes 510-511. Stops on any error/unexpected condition.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  [void][System.Console]::ReadKey($true)
}

function Fail([string]$Message) {
  Write-Error $Message
  Wait-ForKey
  exit 1
}

try {
  # ---- Config ----
  $ImagePath = Join-Path (Get-Location) "floppy.img"
  $BootPath  = Join-Path (Get-Location) "Boot1.bin"
  $ExpectedImageSize = 1474560
  $ExpectedBootSize  = 512

  Write-Host "[1/6] Starting..."

  # ---- Preconditions ----
  Write-Host "[2/6] Checking Boot1.bin exists and is exactly 512 bytes..."
  if (-not (Test-Path -LiteralPath $BootPath -PathType Leaf)) {
    Fail "Boot file not found: $BootPath"
  }

  $bootInfo = Get-Item -LiteralPath $BootPath
  if ($bootInfo.Length -ne $ExpectedBootSize) {
    Fail "Boot file size is $($bootInfo.Length) bytes; expected $ExpectedBootSize bytes."
  }

  # ---- Create / overwrite floppy.img ----
  Write-Host "[3/6] Creating $ExpectedImageSize-byte floppy image (overwriting if it exists)..."
  if (Test-Path -LiteralPath $ImagePath) {
    Remove-Item -LiteralPath $ImagePath -Force
  }

  $args = @("file", "createnew", $ImagePath, $ExpectedImageSize)
  $p = Start-Process -FilePath "fsutil.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) {
    Fail "fsutil failed (exit code $($p.ExitCode)). Run PowerShell as Administrator."
  }

  # ---- Verify image size ----
  Write-Host "[4/6] Verifying floppy.img size..."
  $imgInfo = Get-Item -LiteralPath $ImagePath
  if ($imgInfo.Length -ne $ExpectedImageSize) {
    Fail "Image size is $($imgInfo.Length) bytes; expected $ExpectedImageSize bytes."
  }

  # ---- Write Boot1.bin to boot sector ----
  Write-Host "[5/6] Writing Boot1.bin to boot sector (offset 0, 512 bytes)..."
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

  # ---- Verify signature ----
  Write-Host "[6/6] Verifying boot signature (55 AA)..."
  $imgBytes = [System.IO.File]::ReadAllBytes($ImagePath)
  $sig = '{0:X2} {1:X2}' -f $imgBytes[510], $imgBytes[511]

  if (($imgBytes[510] -ne 0x55) -or ($imgBytes[511] -ne 0xAA)) {
    Fail "Invalid boot signature at 510-511: $sig"
  }

  Write-Host "SUCCESS: floppy.img created, boot sector written, signature verified ($sig)."
  Write-Host "Image: $ImagePath"
  Wait-ForKey
}
catch {
  Write-Error ("ERROR: " + $_.Exception.Message) -ErrorAction Continue
  Wait-ForKey
  exit 1
}