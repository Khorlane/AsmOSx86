# zCombineAll.ps1
# Combines .asm files and README.md into one file.
# Optionally includes .ps1 files when -IncludePs1 is specified.
# Excludes Boot1.asm and Boot2.asm.
# Now also includes *.md files in the Doc folder.

param (
    [switch]$IncludePs1,
    [switch]$asm,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

function Show-Usage {
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  zCombineAll.ps1 [-IncludePs1] [-asm]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -IncludePs1    Include *.ps1 files in the output"
    Write-Host "  -asm           Only include *.asm files"
    Write-Host ""
}

# Reject invalid parameters
if ($ExtraArgs.Count -gt 0) {
    Write-Error "Invalid parameter(s): $($ExtraArgs -join ' ')"
    Show-Usage
    exit 1
}

$OutputFile = "AsmOSx86_FullDump.lst"

# Remove existing output file if present
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile
}

if ($asm) {
    # Only include .asm files, excluding Boot1.asm and Boot2.asm
    $files = Get-ChildItem -Recurse -File |
        Where-Object {
            $_.Extension -eq ".asm" -and
            $_.Name -inotmatch '^Boot[12]\.asm$'
        } |
        Sort-Object FullName
} else {
    $files = Get-ChildItem -Recurse -File |
        Where-Object {
            (
                $_.Extension -eq ".asm" -or
                ($IncludePs1 -and $_.Extension -eq ".ps1") -or
                $_.Name -ieq "README.md" -or
                ($_.Extension -eq ".md" -and $_.DirectoryName -match "\\Doc($|\\)")
            ) -and
            $_.Name -inotmatch '^Boot[12]\.asm$'
        } |
        Sort-Object FullName
}

foreach ($file in $files) {
    Add-Content $OutputFile ""
    Add-Content $OutputFile "============================================================"
    Add-Content $OutputFile "FILE: $($file.FullName)"
    Add-Content $OutputFile "============================================================"
    Add-Content $OutputFile ""

    Get-Content $file.FullName | Add-Content $OutputFile
}

Write-Host "Done. Output written to $OutputFile"