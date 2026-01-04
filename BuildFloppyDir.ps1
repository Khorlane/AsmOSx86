function Wait-ForKey {
  Write-Host ""
  Write-Host "Press any key to continue..."
  [void][System.Console]::ReadKey($true)
}

# Mount read-only (file-backed, floppy emulation)
& imdisk -a -t file -f ".\floppy.img" -m A: -o ro,fd
if ($LASTEXITCODE -ne 0) {
  Write-Host "ImDisk mount failed (exit code $LASTEXITCODE)."
  Wait-ForKey
  exit 1
}

try {
  # Give Windows a moment to materialize the drive letter
  Start-Sleep -Milliseconds 250

  Write-Host ""
  Write-Host "Directory listing of A:"
  Get-ChildItem A:\

  Wait-ForKey
}
finally {
  & imdisk -d -m A: | Out-Null
}