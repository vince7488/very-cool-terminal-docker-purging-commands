$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$readmePath = Join-Path $rootDir "README.md"
$readme = Get-Content -LiteralPath $readmePath -Raw
$imageMatches = [regex]::Matches($readme, '!\[[^\]]*\]\(([^)]+)\)')

if ($imageMatches.Count -eq 0) {
    throw "README.md does not contain any image links."
}

foreach ($match in $imageMatches) {
    $target = $match.Groups[1].Value
    if ($target -match '^(https?:)?//') {
        continue
    }

    $normalized = $target -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $fullPath = Join-Path $rootDir $normalized
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "README image target does not exist: $target"
    }
}

"README image asset check passed."
