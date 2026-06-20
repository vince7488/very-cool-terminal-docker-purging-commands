Write-Host "1. Purge all of Docker [1]"
Write-Host "2. One by one [2]"
$choice = Read-Host "Select option"

if ($choice -eq '1') {
    docker system prune -a --volumes -f
    Write-Host "Complete system wipe done."
} elseif ($choice -eq '2') {
    $runCont = Read-Host "About to purge all unused containers. Proceed? (y/N)"
    if ($runCont -match "^[yY]$") { docker container prune -f }

    $runImg = Read-Host "About to purge all unused images. Proceed? (y/N)"
    if ($runImg -match "^[yY]$") { docker image prune -a -f }

    $runVol = Read-Host "About to clear all unused volumes. Proceed? (y/N)"
    if ($runVol -match "^[yY]$") { docker volume prune -f }

    $runNet = Read-Host "About to clear all unused networks. Proceed? (y/N)"
    if ($runNet -match "^[yY]$") { docker network prune -f }

    $runBld = Read-Host "About to clear all build cache. Proceed? (y/N)"
    if ($runBld -match "^[yY]$") { docker builder prune -a -f }

    Write-Host "All done."
} else {
    Write-Host "Invalid choice. Exiting."
}