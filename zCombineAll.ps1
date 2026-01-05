# zCombineAll.ps1
# Combines all .asm and .ps1 files (recursively) into one file
# with clear file boundaries.

$OutputFile = "zFullDump.lst"

# Delete existing output file if present
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile
}

Get-ChildItem -Recurse -Include *.asm, *.ps1 | Sort-Object FullName | ForEach-Object {

    Add-Content $OutputFile ""
    Add-Content $OutputFile "============================================================"
    Add-Content $OutputFile "FILE: $($_.FullName)"
    Add-Content $OutputFile "============================================================"
    Add-Content $OutputFile ""

    Get-Content $_.FullName | Add-Content $OutputFile
}

Write-Host "Done. Output written to $OutputFile"