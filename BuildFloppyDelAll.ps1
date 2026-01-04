<# 
FloppyDelAll.ps1
Deletes all files from floppy.img (equivalent to DEL *.*) with confirmation.
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

$Image = Join-Path (Get-Location) "floppy.img"
$Drive = "A:"

Write-Host "[1/5] Verifying floppy.img..."
if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) {
  Fail "Missing floppy image: $Image"
}

Write-Host ""
Write-Host "About to delete ALL files on floppy.img (equivalent to DEL *.*)"
$resp = Read-Host "Are you sure (Y/N)"
if ($resp.ToUpperInvariant() -ne 'Y') {
  Write-Host "Aborted."
  Wait-ForKey
  exit 0
}

Write-Host "[2/5] Mounting floppy.img as $Drive..."
& imdisk -a -t file -f $Image -m $Drive -o rw,fd
if ($LASTEXITCODE -ne 0) {
  Fail "ImDisk mount failed (exit code $LASTEXITCODE)."
}

try {
  Start-Sleep -Milliseconds 250

  if (-not (Test-Path "$Drive\")) {
    Fail "Mounted drive $Drive is not accessible."
  }

  Write-Host "[3/5] Deleting all files from $Drive..."
  $files = Get-ChildItem "$Drive\" -File
  if ($files.Count -eq 0) {
    Write-Host "    (No files to delete)"
  } else {
    Remove-Item $files.FullName -Force
  }

  Write-Host ""
  Write-Host "Directory listing after delete:"
  Get-ChildItem "$Drive\" | Out-Host
}
finally {
  Write-Host "[4/5] Unmounting $Drive..."
  & imdisk -d -m $Drive | Out-Null
}

Write-Host "[5/5] Done."
Write-Host "SUCCESS: All files deleted from floppy.img."
Wait-ForKey