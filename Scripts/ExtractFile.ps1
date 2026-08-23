<#
ExtractFile.ps1
Extracts one file from the AsmOSx86 raw ASMF floppy image.

Usage:
  .\ExtractFile.ps1 LOG.TXT
  .\ExtractFile.ps1 DATA.TXT C:\Temp\Data.txt
#>

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Name,

  [Parameter(Mandatory = $false, Position = 1)]
  [string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function ConvertTo-ManifestName([string]$FileName) {
  $base = [IO.Path]::GetFileNameWithoutExtension($FileName).ToUpperInvariant()
  $ext = [IO.Path]::GetExtension($FileName).TrimStart('.').ToUpperInvariant()
  return ($base.PadRight(8).Substring(0, 8) + $ext.PadRight(3).Substring(0, 3))
}

function Read-UInt16Le([byte[]]$Buffer, [int]$Offset) {
  return [BitConverter]::ToUInt16($Buffer, $Offset)
}

function Read-UInt32Le([byte[]]$Buffer, [int]$Offset) {
  return [BitConverter]::ToUInt32($Buffer, $Offset)
}

$Image = Join-Path $RepoRoot "floppy.img"
$BytesPerSector = 512
$ManifestSector = 1
$ManifestEntryOffset = 16
$ManifestEntrySize = 32

if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) {
  throw "Missing floppy image: $Image"
}

if (-not $OutPath) {
  $OutDir = Join-Path $RepoRoot "Extracted"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $OutPath = Join-Path $OutDir ([IO.Path]::GetFileName($Name).ToUpperInvariant())
}

$imageBytes = [System.IO.File]::ReadAllBytes($Image)
$manifestOffset = $ManifestSector * $BytesPerSector
$sig = [System.Text.Encoding]::ASCII.GetString($imageBytes, $manifestOffset, 4)
if ($sig -ne "ASMF") {
  throw "ASMF manifest signature was '$sig', expected ASMF."
}

$entryCount = Read-UInt16Le $imageBytes ($manifestOffset + 6)
$targetName = ConvertTo-ManifestName $Name
$found = $false
$startSector = 0
$byteSize = 0

for ($i = 0; $i -lt $entryCount; $i++) {
  $entryOffset = $manifestOffset + $ManifestEntryOffset + ($i * $ManifestEntrySize)
  $entryName = [System.Text.Encoding]::ASCII.GetString($imageBytes, $entryOffset, 11)
  if ($entryName -eq $targetName) {
    $startSector = Read-UInt32Le $imageBytes ($entryOffset + 12)
    $byteSize = Read-UInt32Le $imageBytes ($entryOffset + 16)
    $found = $true
    break
  }
}

if (-not $found) {
  throw "File not found in ASMF manifest: $Name"
}

$fileOffset = [int]$startSector * $BytesPerSector
$bytes = New-Object byte[] $byteSize
[Array]::Copy($imageBytes, $fileOffset, $bytes, 0, $byteSize)

if ([IO.Path]::GetFileName($Name).ToUpperInvariant() -eq "LOG.TXT") {
  $last = $bytes.Length - 1
  while ($last -ge 0 -and $bytes[$last] -eq 0) {
    $last--
  }
  if ($last -lt 0) {
    $bytes = New-Object byte[] 0
  }
  else {
    $trimmed = New-Object byte[] ($last + 1)
    [Array]::Copy($bytes, 0, $trimmed, 0, $last + 1)
    $bytes = $trimmed
  }
}

[System.IO.File]::WriteAllBytes($OutPath, $bytes)
Write-Host ("Extracted {0} bytes to {1}" -f $bytes.Length, $OutPath)
