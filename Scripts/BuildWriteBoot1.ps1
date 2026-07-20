<# 
BuildWriteBoot1.ps1
Creates a 1.44MB floppy image, formats it as FAT, writes Boot1.bin to boot sector
(offset 0), then verifies 0x55AA signature at bytes 510-511.
Stops on any error/unexpected condition.
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

function Invoke-ImDisk([string]$ArgumentString) {
  $cmd = Get-Command "imdisk.exe" -ErrorAction SilentlyContinue
  if ($null -eq $cmd -or -not $cmd.Source) {
    throw "imdisk.exe not found in PATH. Try: C:\Windows\System32\imdisk.exe"
  }

  $tmpOut = Join-Path $env:TEMP ("imdisk_out_{0}.txt" -f ([guid]::NewGuid().ToString("N")))
  $tmpErr = Join-Path $env:TEMP ("imdisk_err_{0}.txt" -f ([guid]::NewGuid().ToString("N")))

  try {
    $p = Start-Process -FilePath $cmd.Source `
                       -ArgumentList $ArgumentString `
                       -NoNewWindow -Wait -PassThru `
                       -RedirectStandardOutput $tmpOut `
                       -RedirectStandardError  $tmpErr

    $outText = ""
    if (Test-Path $tmpOut) { $outText += (Get-Content $tmpOut -Raw) }
    if (Test-Path $tmpErr) { $outText += (Get-Content $tmpErr -Raw) }

    return @{
      ExitCode = $p.ExitCode
      Output   = $outText.TrimEnd()
    }
  }
  finally {
    Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
  }
}

try {
  # ---- Config ----
  $ImagePath = Join-Path $RepoRoot "floppy.img"
  $BootPath  = Join-Path $RepoRoot "Boot1.bin"
  $ExpectedImageSize = 1474560
  $ExpectedBootSize  = 512

  Write-Host "[1/8] Starting..."

  # ---- Preconditions ----
  Write-Host "[2/8] Checking Boot1.bin exists and is exactly 512 bytes..."
  if (-not (Test-Path -LiteralPath $BootPath -PathType Leaf)) {
    Fail "Boot file not found: $BootPath"
  }

  $bootInfo = Get-Item -LiteralPath $BootPath
  if ($bootInfo.Length -ne $ExpectedBootSize) {
    Fail "Boot file size is $($bootInfo.Length) bytes; expected $ExpectedBootSize bytes."
  }

  # ---- Create / overwrite floppy.img ----
  Write-Host "[3/8] Creating $ExpectedImageSize-byte floppy image (overwriting if it exists)..."
  if (Test-Path -LiteralPath $ImagePath) {
    Remove-Item -LiteralPath $ImagePath -Force
  }

  $fsutilArgs = @("file", "createnew", $ImagePath, $ExpectedImageSize)
  $p = Start-Process -FilePath "fsutil.exe" -ArgumentList $fsutilArgs -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) {
    Fail "fsutil failed (exit code $($p.ExitCode)). Run PowerShell as Administrator."
  }

  # ---- Verify image size ----
  Write-Host "[4/8] Verifying floppy.img size..."
  $imgInfo = Get-Item -LiteralPath $ImagePath
  if ($imgInfo.Length -ne $ExpectedImageSize) {
    Fail "Image size is $($imgInfo.Length) bytes; expected $ExpectedImageSize bytes."
  }

  # ---- Format FAT filesystem ----
  Write-Host "[5/8] Mounting and formatting floppy.img as FAT..."
  $mountArgStr = '-a -t file -f "{0}" -m "#:" -o rw,fd' -f $ImagePath
  $mount = Invoke-ImDisk $mountArgStr
  if ($mount.ExitCode -ne 0) {
    Write-Host "----- ImDisk mount output begin -----"
    if ($mount.Output) { Write-Host $mount.Output } else { Write-Host "(no output)" }
    Write-Host "------ ImDisk mount output end ------"
    Fail "Error creating virtual floppy disk (imdisk exit code $($mount.ExitCode))."
  }

  $Drive = $null
  foreach ($line in ($mount.Output -split "`r?`n")) {
    if ($line -match "Created device\s+\d+:\s+([A-Z]:)\s+->") {
      $Drive = $Matches[1]
      break
    }
  }
  if (-not $Drive) {
    Write-Host "----- ImDisk mount output begin -----"
    if ($mount.Output) { Write-Host $mount.Output } else { Write-Host "(no output)" }
    Write-Host "------ ImDisk mount output end ------"
    Fail "Mounted, but could not determine assigned drive letter from ImDisk output."
  }

  try {
    Start-Sleep -Milliseconds 300

    $formatArgs = @($Drive, "/FS:FAT", "/V:ASMOSX86", "/Q", "/Y")
    $format = Start-Process -FilePath "format.com" -ArgumentList $formatArgs -NoNewWindow -Wait -PassThru
    if ($format.ExitCode -ne 0) {
      Fail "format.com failed for $Drive (exit code $($format.ExitCode))."
    }
    if (-not (Test-Path "$Drive\")) {
      Fail "Formatted drive $Drive is not accessible."
    }
  }
  finally {
    Write-Host "[6/8] Unmounting formatted floppy image..."
    if ($Drive) {
      $det = Invoke-ImDisk ('-d -m "{0}"' -f $Drive)
      if ($det.ExitCode -ne 0) {
        Write-Host "----- ImDisk detach output begin -----"
        if ($det.Output) { Write-Host $det.Output } else { Write-Host "(no output)" }
        Write-Host "------ ImDisk detach output end ------"
        Fail "Could not detach $Drive after formatting."
      }
    }
  }

  # ---- Write Boot1.bin to boot sector ----
  Write-Host "[7/8] Writing Boot1.bin to boot sector (offset 0, 512 bytes)..."
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
  Write-Host "[8/8] Verifying boot signature (55 AA)..."
  $imgBytes = [System.IO.File]::ReadAllBytes($ImagePath)
  $sig = '{0:X2} {1:X2}' -f $imgBytes[510], $imgBytes[511]

  if (($imgBytes[510] -ne 0x55) -or ($imgBytes[511] -ne 0xAA)) {
    Fail "Invalid boot signature at 510-511: $sig"
  }

  Write-Host "SUCCESS: floppy.img created, formatted as FAT, boot sector written, signature verified ($sig)."
  Write-Host "Image: $ImagePath"
  Wait-ForKey
}
catch {
  Write-Error ("ERROR: " + $_.Exception.Message) -ErrorAction Continue
  Wait-ForKey
  exit 1
}
