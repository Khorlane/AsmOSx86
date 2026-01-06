# zCombineAll.ps1
# Combines all .asm, .ps1, and README.md files (recursively) into one file
# with clear file boundaries, for review and archival purposes.
#
# Excludes Boot1.asm and Boot2.asm (kernel focus)

$OutputFile = "AsmOSx86_FullDump.lst"

# Remove existing output file if present
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile
}

Get-ChildItem -Recurse -File |
    Where-Object {
        (
            $_.Extension -in @(".asm", ".ps1") -or
            $_.Name -ieq "README.md"
        ) -and
        $_.Name -inotmatch '^Boot[12]\.asm$'
    } |
    Sort-Object FullName |
    ForEach-Object {

        Add-Content $OutputFile ""
        Add-Content $OutputFile "============================================================"
        Add-Content $OutputFile "FILE: $($_.FullName)"
        Add-Content $OutputFile "============================================================"
        Add-Content $OutputFile ""

        Get-Content $_.FullName | Add-Content $OutputFile
    }

Write-Host "Done. Output written to $OutputFile"