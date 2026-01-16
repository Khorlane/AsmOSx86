# zExpand.ps1
# Reads Kernel.asm and expands each %include by inlining the referenced file.
# Writes the result to Kernel.All.asm

$inputFile = "Kernel.asm"
$outputFile = "Kernel.All.asm"

# Read all lines from Kernel.asm
$lines = Get-Content $inputFile

# Prepare output array
$output = @()

foreach ($line in $lines) {
    if ($line -match '^\s*%include\s+"([^"]+)"') {
        $includePath = $Matches[1]
        if (Test-Path $includePath) {
            $output += "; ===== Begin include: $includePath ====="
            $output += Get-Content $includePath
            $output += "; ===== End include: $includePath ====="
        } else {
            $output += "; ===== Missing include: $includePath ====="
        }
    } else {
        $output += $line
    }
}

# Write the expanded output to Kernel.All.asm
Set-Content $outputFile $output

Write-Host "Expanded includes written to $outputFile"