<# 
BuildCopy.ps1
Copies Boot2.bin, Kernel.bin, and optional user programs to floppy.img using ImDisk.
- Mounts using first free drive letter (#:) to avoid conflicts.
- Copies BOOT2.BIN, KERNEL.BIN, and optional PROG*.BIN files to the FAT12 root.
- Verifies files exist via DIR-style listing.
- Verifies copied files remain below sector 512.
- Unmounts robustly: dismount/remove drive letter, retry detach, then force detach if needed.
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

function Fail([string]$msg) {
  Write-Error $msg -ErrorAction Continue
  Wait-ForKey
  exit 1
}

function Invoke-ImDisk([string]$ArgumentString) {
  # Invokes imdisk.exe and returns: @{ ExitCode=int; Output=string }

  $cmd = Get-Command "imdisk.exe" -ErrorAction SilentlyContinue
  if ($null -eq $cmd -or -not $cmd.Source) {
    throw "imdisk.exe not found in PATH. Try: C:\Windows\System32\imdisk.exe"
  }
  $imdiskExe = $cmd.Source

  $tmpOut = Join-Path $env:TEMP ("imdisk_out_{0}.txt" -f ([guid]::NewGuid().ToString("N")))
  $tmpErr = Join-Path $env:TEMP ("imdisk_err_{0}.txt" -f ([guid]::NewGuid().ToString("N")))

  try {
    $p = Start-Process -FilePath $imdiskExe `
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

function Get-Fat12Entry([byte[]]$ImageBytes, [int]$FatBase, [int]$Cluster) {
  $fatOffset = $Cluster + [int][math]::Floor($Cluster / 2)
  $entryOffset = $FatBase + $fatOffset

  if (($Cluster % 2) -eq 0) {
    return [int](([int]$ImageBytes[$entryOffset]) -bor ((([int]$ImageBytes[$entryOffset + 1]) -band 0x0F) -shl 8))
  }

  return [int](((([int]$ImageBytes[$entryOffset]) -shr 4) -band 0x0F) -bor (([int]$ImageBytes[$entryOffset + 1]) -shl 4))
}

function ConvertTo-FatName83([string]$FileName) {
  $name = [IO.Path]::GetFileNameWithoutExtension($FileName).ToUpperInvariant()
  $ext = [IO.Path]::GetExtension($FileName).TrimStart('.').ToUpperInvariant()

  return ($name.PadRight(8).Substring(0, 8) + $ext.PadRight(3).Substring(0, 3))
}

function Find-Fat12RootEntry([byte[]]$ImageBytes, [string]$FileName) {
  $BytesPerSector = 512
  $RootStartSector = 19
  $RootEntrySize = 32
  $RootEntryCount = 224
  $targetName = ConvertTo-FatName83 $FileName
  $rootBase = $RootStartSector * $BytesPerSector

  for ($entryIndex = 0; $entryIndex -lt $RootEntryCount; $entryIndex++) {
    $entryOffset = $rootBase + ($entryIndex * $RootEntrySize)
    if ($ImageBytes[$entryOffset] -eq 0x00) {
      break
    }
    if ($ImageBytes[$entryOffset] -eq 0xE5) {
      continue
    }
    if (($ImageBytes[$entryOffset + 11] -band 0x18) -ne 0) {
      continue
    }

    $entryName = [System.Text.Encoding]::ASCII.GetString($ImageBytes, $entryOffset, 11)
    if ($entryName -eq $targetName) {
      return $entryOffset
    }
  }

  return -1
}

function Test-Fat12FileBelowCustomArea([byte[]]$ImageBytes, [string]$FileName) {
  $BytesPerSector = 512
  $FatBase = 512
  $FirstDataSector = 33
  $CustomFsStartSector = 512
  $Fat12Eoc = 0xFF8
  $entryOffset = Find-Fat12RootEntry $ImageBytes $FileName

  if ($entryOffset -lt 0) {
    throw "FAT12 validation could not find $FileName in root directory."
  }

  $cluster = [int]$ImageBytes[$entryOffset + 26] -bor (([int]$ImageBytes[$entryOffset + 27]) -shl 8)
  $fileSize = [int]$ImageBytes[$entryOffset + 28] `
            -bor (([int]$ImageBytes[$entryOffset + 29]) -shl 8) `
            -bor (([int]$ImageBytes[$entryOffset + 30]) -shl 16) `
            -bor (([int]$ImageBytes[$entryOffset + 31]) -shl 24)
  $bytesLeft = $fileSize
  $maxSector = 0

  while ($bytesLeft -gt 0) {
    if ($cluster -lt 2) {
      throw "FAT12 validation found bad cluster $cluster in $FileName."
    }

    $sector = $FirstDataSector + ($cluster - 2)
    if ($sector -ge $CustomFsStartSector) {
      throw "$FileName uses cluster $cluster at sector $sector, inside the custom storage area."
    }
    if ($sector -gt $maxSector) {
      $maxSector = $sector
    }

    $bytesLeft -= $BytesPerSector
    if ($bytesLeft -le 0) {
      break
    }

    $cluster = Get-Fat12Entry $ImageBytes $FatBase $cluster
    if ($cluster -ge $Fat12Eoc) {
      throw "FAT12 validation reached end-of-chain early in $FileName."
    }
  }

  Write-Host ("  {0}: max sector {1}" -f $FileName, $maxSector)
}

function Test-CopiedFilesBelowCustomArea([string]$ImagePath, [string[]]$FileNames) {
  Write-Host "Validating copied files stay below sector 512..."
  $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)

  foreach ($fileName in $FileNames) {
    Test-Fat12FileBelowCustomArea $imageBytes $fileName
  }
}

try {
  Write-Host "Running: $PSCommandPath"

  $Image  = Join-Path $RepoRoot "floppy.img"
  $Boot2  = Join-Path $RepoRoot "Boot2.bin"
  $Kernel = Join-Path $RepoRoot "Kernel.bin"
  $Prog1  = Join-Path $RepoRoot "Prog1.bin"
  $Prog2  = Join-Path $RepoRoot "Prog2.bin"
  $Prog3  = Join-Path $RepoRoot "Prog3.bin"
  $CopiedFiles = @("BOOT2.BIN", "KERNEL.BIN")

  Write-Host "[1/5] Verifying files..."
  foreach ($f in @($Image, $Boot2, $Kernel)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
      Fail "Missing required file: $f"
    }
  }

  Write-Host "[2/5] Mounting floppy.img as first free drive letter..."
  $mountArgStr = '-a -t file -f "{0}" -m "#:" -o rw,fix' -f $Image
  $mount = Invoke-ImDisk $mountArgStr

  if ($mount.ExitCode -ne 0) {
    Write-Host "----- ImDisk mount output begin -----"
    if ($mount.Output) { Write-Host $mount.Output } else { Write-Host "(no output)" }
    Write-Host "------ ImDisk mount output end ------"
    Fail "Error creating virtual disk (imdisk exit code $($mount.ExitCode))."
  }

  # Determine assigned drive letter from output: "Created device 2: F: -> ..."
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

  Write-Host "Mounted as $Drive"

  try {
    Start-Sleep -Milliseconds 300

    if (-not (Test-Path "$Drive\")) {
      Fail "Mounted drive $Drive is not accessible."
    }

    Write-Host "[3/5] Copying files to $Drive..."
    Remove-Item "$Drive\PROG1.EXE", "$Drive\PROG2.EXE", "$Drive\PROG3.EXE" -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $Boot2  -Destination "$Drive\BOOT2.BIN"  -Force
    Copy-Item -LiteralPath $Kernel -Destination "$Drive\KERNEL.BIN" -Force
    foreach ($prog in @($Prog1, $Prog2, $Prog3)) {
      if (Test-Path -LiteralPath $prog -PathType Leaf) {
        $progName = [IO.Path]::GetFileName($prog).ToUpperInvariant()
        Copy-Item -LiteralPath $prog -Destination (Join-Path "$Drive\" $progName) -Force
        $CopiedFiles += $progName
      }
    }

    Write-Host "[4/5] Verifying files on $Drive (DIR)..."
    if (-not (Test-Path "$Drive\BOOT2.BIN"))  { Fail "BOOT2.BIN not found on $Drive after copy." }
    if (-not (Test-Path "$Drive\KERNEL.BIN")) { Fail "KERNEL.BIN not found on $Drive after copy." }

    Get-ChildItem "$Drive\" | Out-Host
  }
  finally {
    Write-Host "[5/5] Unmounting $Drive..."

    # Best-effort: dismount volume and remove drive letter first (often releases locks)
    try { & mountvol $Drive /p | Out-Null } catch { }

    # Normal detach retries
    $detached = $false
    $forcedDetachUsed = $false
    $lastOut = ""

    for ($i = 1; $i -le 2; $i++) {
      $det = Invoke-ImDisk ('-d -m "{0}"' -f $Drive)
      $lastOut = $det.Output
      if ($det.ExitCode -eq 0) {
        $detached = $true
        break
      }
      Start-Sleep -Milliseconds 250
    }

    # Last resort: force detach
    if (-not $detached) {
      Write-Warning "Normal detach failed; forcing detach (-D)..."
      $forcedDetachUsed = $true
      $fdet = Invoke-ImDisk ('-D -m "{0}"' -f $Drive)
      $lastOut = $fdet.Output
      if ($fdet.ExitCode -eq 0) {
        $detached = $true
      }
    }

    if ($detached -and $forcedDetachUsed) {
      Write-Host "Force detach successful"
    }

    if (-not $detached) {
      Write-Host "----- ImDisk detach output begin -----"
      if ($lastOut) { Write-Host $lastOut } else { Write-Host "(no output)" }
      Write-Host "------ ImDisk detach output end ------"
      Write-Warning "Could not detach $Drive (still in use). The image is already updated."
    }
  }

  Test-CopiedFilesBelowCustomArea $Image $CopiedFiles

  Write-Host "SUCCESS: Boot2.bin, Kernel.bin, and optional user programs copied to floppy.img via FAT12."
  Wait-ForKey
  exit 0
}
catch {
  Fail ("ERROR: " + $_.Exception.Message)
}
