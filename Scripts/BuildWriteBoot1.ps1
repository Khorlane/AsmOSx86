<# 
BuildWriteBoot1.ps1
Creates a 1.44MB floppy image, formats it as FAT, writes Boot1.bin to boot sector
(offset 0), then verifies 0x55AA signature at bytes 510-511.
Marks sectors 512-2879 as bad FAT12 clusters for future AsmOSx86 storage.
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

function Set-Fat12Entry([byte[]]$ImageBytes, [int]$FatBase, [int]$Cluster, [int]$Value) {
  $fatOffset = $Cluster + [int][math]::Floor($Cluster / 2)
  $entryOffset = $FatBase + $fatOffset

  if (($Cluster % 2) -eq 0) {
    $ImageBytes[$entryOffset] = [byte]($Value -band 0xFF)
    $ImageBytes[$entryOffset + 1] = [byte](($ImageBytes[$entryOffset + 1] -band 0xF0) -bor (($Value -shr 8) -band 0x0F))
  }
  else {
    $ImageBytes[$entryOffset] = [byte](($ImageBytes[$entryOffset] -band 0x0F) -bor (($Value -shl 4) -band 0xF0))
    $ImageBytes[$entryOffset + 1] = [byte](($Value -shr 4) -band 0xFF)
  }
}

function Get-Fat12Entry([byte[]]$ImageBytes, [int]$FatBase, [int]$Cluster) {
  $fatOffset = $Cluster + [int][math]::Floor($Cluster / 2)
  $entryOffset = $FatBase + $fatOffset

  if (($Cluster % 2) -eq 0) {
    return [int](([int]$ImageBytes[$entryOffset]) -bor ((([int]$ImageBytes[$entryOffset + 1]) -band 0x0F) -shl 8))
  }

  return [int](((([int]$ImageBytes[$entryOffset]) -shr 4) -band 0x0F) -bor (([int]$ImageBytes[$entryOffset + 1]) -shl 4))
}

function Reserve-CustomFat12Area([string]$ImagePath) {
  $BytesPerSector = 512
  $Fat1Sector = 1
  $Fat2Sector = 10
  $FirstDataSector = 33
  $CustomStartSector = 512
  $CustomEndSector = 2879
  $BadClusterValue = 0xFF7

  $firstCluster = ($CustomStartSector - $FirstDataSector) + 2
  $lastCluster = ($CustomEndSector - $FirstDataSector) + 2
  $fat1Base = $Fat1Sector * $BytesPerSector
  $fat2Base = $Fat2Sector * $BytesPerSector
  $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)

  foreach ($cluster in $firstCluster..$lastCluster) {
    Set-Fat12Entry $imageBytes $fat1Base $cluster $BadClusterValue
    Set-Fat12Entry $imageBytes $fat2Base $cluster $BadClusterValue
  }

  [System.IO.File]::WriteAllBytes($ImagePath, $imageBytes)

  $verifyBytes = [System.IO.File]::ReadAllBytes($ImagePath)
  foreach ($cluster in @($firstCluster, ($firstCluster + 1), $lastCluster)) {
    $fat1Value = Get-Fat12Entry $verifyBytes $fat1Base $cluster
    $fat2Value = Get-Fat12Entry $verifyBytes $fat2Base $cluster
    if (($fat1Value -ne $BadClusterValue) -or ($fat2Value -ne $BadClusterValue)) {
      throw ("FAT12 custom-area reservation failed at cluster {0}: FAT1={1:X3}, FAT2={2:X3}" -f $cluster, $fat1Value, $fat2Value)
    }
  }
}

try {
  # ---- Config ----
  $ImagePath = Join-Path $RepoRoot "floppy.img"
  $BootPath  = Join-Path $RepoRoot "Boot1.bin"
  $ExpectedImageSize = 1474560
  $ExpectedBootSize  = 512

  Write-Host "[1/9] Starting..."

  # ---- Preconditions ----
  Write-Host "[2/9] Checking Boot1.bin exists and is exactly 512 bytes..."
  if (-not (Test-Path -LiteralPath $BootPath -PathType Leaf)) {
    Fail "Boot file not found: $BootPath"
  }

  $bootInfo = Get-Item -LiteralPath $BootPath
  if ($bootInfo.Length -ne $ExpectedBootSize) {
    Fail "Boot file size is $($bootInfo.Length) bytes; expected $ExpectedBootSize bytes."
  }

  # ---- Create / overwrite floppy.img ----
  Write-Host "[3/9] Creating $ExpectedImageSize-byte floppy image (overwriting if it exists)..."
  if (Test-Path -LiteralPath $ImagePath) {
    Remove-Item -LiteralPath $ImagePath -Force
  }

  $fsutilArgs = @("file", "createnew", $ImagePath, $ExpectedImageSize)
  $p = Start-Process -FilePath "fsutil.exe" -ArgumentList $fsutilArgs -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) {
    Fail "fsutil failed (exit code $($p.ExitCode)). Run PowerShell as Administrator."
  }

  # ---- Verify image size ----
  Write-Host "[4/9] Verifying floppy.img size..."
  $imgInfo = Get-Item -LiteralPath $ImagePath
  if ($imgInfo.Length -ne $ExpectedImageSize) {
    Fail "Image size is $($imgInfo.Length) bytes; expected $ExpectedImageSize bytes."
  }

  # ---- Format FAT filesystem ----
  Write-Host "[5/9] Mounting and formatting floppy.img as FAT..."
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
    Write-Host "[6/9] Unmounting formatted floppy image..."
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

  # ---- Reserve custom storage area ----
  Write-Host "[7/9] Marking sectors 512-2879 as bad FAT12 clusters..."
  Reserve-CustomFat12Area $ImagePath

  # ---- Write Boot1.bin to boot sector ----
  Write-Host "[8/9] Writing Boot1.bin to boot sector (offset 0, 512 bytes)..."
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
  Write-Host "[9/9] Verifying boot signature (55 AA)..."
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
