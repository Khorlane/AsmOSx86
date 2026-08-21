<#
BuildCopy.ps1
Writes the AsmOSx86 raw floppy manifest and packed boot/runtime files.
- Sector 0 is Boot.bin and is written by BuildWriteBoot.ps1.
- Sector 1 is the AsmOSx86 file manifest.
- Sector 2 and onward contain KERNEL.BIN and optional runtime files.
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
  Write-Error $Message -ErrorAction Continue
  Wait-ForKey
  exit 1
}

function ConvertTo-ManifestName([string]$FileName) {
  $base = [IO.Path]::GetFileNameWithoutExtension($FileName).ToUpperInvariant()
  $ext = [IO.Path]::GetExtension($FileName).TrimStart('.').ToUpperInvariant()
  return ($base.PadRight(8).Substring(0, 8) + $ext.PadRight(3).Substring(0, 3))
}

function Write-UInt16Le([byte[]]$Buffer, [int]$Offset, [int]$Value) {
  $bytes = [BitConverter]::GetBytes([UInt16]$Value)
  [Array]::Copy($bytes, 0, $Buffer, $Offset, 2)
}

function Write-UInt32Le([byte[]]$Buffer, [int]$Offset, [UInt32]$Value) {
  $bytes = [BitConverter]::GetBytes($Value)
  [Array]::Copy($bytes, 0, $Buffer, $Offset, 4)
}

function Write-ImageBytes([System.IO.FileStream]$Stream, [int]$Sector, [byte[]]$Bytes) {
  $BytesPerSector = 512
  $sectorCount = [int][Math]::Ceiling($Bytes.Length / $BytesPerSector)
  $paddedBytes = New-Object byte[] ($sectorCount * $BytesPerSector)
  [Array]::Copy($Bytes, $paddedBytes, $Bytes.Length)
  $null = $Stream.Seek($Sector * $BytesPerSector, [System.IO.SeekOrigin]::Begin)
  $Stream.Write($paddedBytes, 0, $paddedBytes.Length)
  return $sectorCount
}

try {
  $Image  = Join-Path $RepoRoot "floppy.img"
  $Kernel = Join-Path $RepoRoot "Kernel.bin"
  $Prog1  = Join-Path $RepoRoot "Prog1.bin"
  $Prog2  = Join-Path $RepoRoot "Prog2.bin"
  $Prog3  = Join-Path $RepoRoot "Prog3.bin"
  $Prog4  = Join-Path $RepoRoot "Prog4.bin"
  $Data   = Join-Path $RepoRoot "Data.txt"
  $BytesPerSector = 512
  $ManifestSector = 1
  $FirstFileSector = 2
  $ImageSectors = 2880
  $ManifestEntryOffset = 16
  $ManifestEntrySize = 32

  Write-Host "Running: $PSCommandPath"
  Write-Host "[1/4] Verifying files..."
  foreach ($f in @($Image, $Kernel)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
      Fail "Missing required file: $f"
    }
  }

  $files = @(
    @{ Name = "KERNEL.BIN"; Path = $Kernel }
  )

  foreach ($prog in @($Prog1, $Prog2, $Prog3, $Prog4)) {
    if (Test-Path -LiteralPath $prog -PathType Leaf) {
      $files += @{ Name = [IO.Path]::GetFileName($prog).ToUpperInvariant(); Path = $prog }
    }
  }
  if (Test-Path -LiteralPath $Data -PathType Leaf) {
    $files += @{ Name = "DATA.TXT"; Path = $Data }
  }

  if ($files.Count -gt 15) {
    Fail "Manifest supports at most 15 files in this first version."
  }

  Write-Host "[2/4] Planning packed file layout..."
  $nextSector = $FirstFileSector
  foreach ($file in $files) {
    $info = Get-Item -LiteralPath $file.Path
    $sectorCount = [int][Math]::Ceiling($info.Length / $BytesPerSector)
    if ($sectorCount -lt 1) {
      Fail "$($file.Name) is empty."
    }
    $file["Size"] = [UInt32]$info.Length
    $file["StartSector"] = [UInt32]$nextSector
    $file["SectorCount"] = [UInt32]$sectorCount
    $nextSector += $sectorCount
    Write-Host ("  {0,-10} sector {1,4} count {2,4} bytes {3}" -f $file.Name, $file.StartSector, $file.SectorCount, $file.Size)
  }

  if ($nextSector -gt $ImageSectors) {
    Fail "Packed files require sector $($nextSector - 1), beyond the 1.44MB image."
  }

  Write-Host "[3/4] Writing manifest and file bodies..."
  $manifest = New-Object byte[] $BytesPerSector
  $sig = [System.Text.Encoding]::ASCII.GetBytes("ASMF")
  [Array]::Copy($sig, 0, $manifest, 0, 4)
  Write-UInt16Le $manifest 4 1
  Write-UInt16Le $manifest 6 $files.Count

  for ($i = 0; $i -lt $files.Count; $i++) {
    $entryOffset = $ManifestEntryOffset + ($i * $ManifestEntrySize)
    $manifestName = [System.Text.Encoding]::ASCII.GetBytes((ConvertTo-ManifestName $files[$i].Name))
    [Array]::Copy($manifestName, 0, $manifest, $entryOffset, 11)
    Write-UInt32Le $manifest ($entryOffset + 12) $files[$i].StartSector
    Write-UInt32Le $manifest ($entryOffset + 16) $files[$i].Size
    Write-UInt32Le $manifest ($entryOffset + 20) $files[$i].SectorCount
  }

  $fs = $null
  try {
    $fs = [System.IO.File]::Open(
      $Image,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )

    $null = $fs.Seek($ManifestSector * $BytesPerSector, [System.IO.SeekOrigin]::Begin)
    $fs.Write($manifest, 0, $manifest.Length)

    foreach ($file in $files) {
      $bytes = [System.IO.File]::ReadAllBytes($file.Path)
      $writtenSectors = Write-ImageBytes $fs $file.StartSector $bytes
      if ($writtenSectors -ne $file.SectorCount) {
        Fail "Internal write mismatch for $($file.Name)."
      }
    }

    $fs.Flush()
  }
  finally {
    if ($fs) { $fs.Close() }
  }

  Write-Host "[4/4] Verifying manifest signature..."
  $imageBytes = [System.IO.File]::ReadAllBytes($Image)
  $actualSig = [System.Text.Encoding]::ASCII.GetString($imageBytes, $ManifestSector * $BytesPerSector, 4)
  if ($actualSig -ne "ASMF") {
    Fail "Manifest signature was '$actualSig', expected ASMF."
  }

  Write-Host "SUCCESS: raw AsmOSx86 floppy image populated."
  Wait-ForKey
  exit 0
}
catch {
  Fail ("ERROR: " + $_.Exception.Message)
}
