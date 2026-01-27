<# 
Copy1.ps1
Copies Boot2.bin and Kernel.bin to floppy.img using ImDisk.
- Mounts using first free drive letter (#:) to avoid conflicts.
- Copies BOOT2.BIN and KERNEL.BIN to the FAT12 root.
- Verifies files exist via DIR-style listing.
- Unmounts robustly: dismount/remove drive letter, retry detach, then force detach if needed.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  [void][System.Console]::ReadKey($true)
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

try {
  Write-Host "Running: $PSCommandPath"

  $Image  = Join-Path (Get-Location) "floppy.img"
  $Boot2  = Join-Path (Get-Location) "Boot2.bin"
  $Kernel = Join-Path (Get-Location) "Kernel.bin"

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
    Copy-Item -LiteralPath $Boot2  -Destination "$Drive\BOOT2.BIN"  -Force
    Copy-Item -LiteralPath $Kernel -Destination "$Drive\KERNEL.BIN" -Force

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

  Write-Host "SUCCESS: Boot2.bin and Kernel.bin copied to floppy.img via FAT12."
  Wait-ForKey
  exit 0
}
catch {
  Fail ("ERROR: " + $_.Exception.Message)
}