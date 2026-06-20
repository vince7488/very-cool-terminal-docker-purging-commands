$script:AnsiReset = "$([char]27)[0m"
$script:Magenta = "35"
$script:White = "37"
$script:Gray = "90"
$script:Yellow = "33"
$script:BrightCyan = "96"
$script:BrightGreen = "38;2;0;255;0"
$script:DiskUsageColor = "38;2;180;255;180"
$script:PurgePromptColor = "91"

function Format-Ansi {
    param(
        [string]$Text,
        [string]$Code
    )

    return "$([char]27)[$($Code)m$Text$script:AnsiReset"
}

function Write-AnsiLine {
    param(
        [string]$Text,
        [string]$Code
    )

    Write-Host (Format-Ansi $Text $Code)
}

function Write-Ansi {
    param(
        [string]$Text,
        [string]$Code
    )

    Write-Host -NoNewline (Format-Ansi $Text $Code)
}

function Read-AnsiPrompt {
    param(
        [string]$Prompt,
        [string]$Code
    )

    Write-Ansi $Prompt $Code
    return Read-Host
}

function Read-YesNoPrompt {
    param(
        [string]$Prompt
    )

    Write-Ansi $Prompt $script:BrightGreen
    Write-Ansi " (y/N)" $script:Yellow
    Write-Host -NoNewline " "
    return Read-Host
}

function Read-PurgeConfirmation {
    Write-Host ""
    Write-Host ""

    $skull = @(
        "          .-.",
        "         (o o)",
        "         | O |",
        "          |=|",
        "      ___/| |\___",
        "     /   /   \   \",
        "    /___/     \___\"
    )

    foreach ($line in $skull) {
        Write-AnsiLine $line $script:PurgePromptColor
    }

    Write-Host ""
    Write-Ansi "Type PURGE to run every prune command without more prompts: " $script:PurgePromptColor
    return Read-Host
}

function Show-DockerUsage {
    Write-Host ""
    $usage = docker system df 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($usage) {
            $usage | ForEach-Object { Write-Error $_.ToString() }
        }
        throw "Unable to read Docker disk usage. Is Docker running?"
    }

    $lines = @("Docker disk usage:") + @($usage | ForEach-Object { $_.ToString() })
    $maxLength = 0
    foreach ($line in $lines) {
        if ($line.Length -gt $maxLength) {
            $maxLength = $line.Length
        }
    }

    $separator = "=" * ($maxLength + 1)
    Write-AnsiLine $separator $script:DiskUsageColor
    foreach ($line in $lines) {
        Write-AnsiLine $line.PadRight($separator.Length) $script:DiskUsageColor
    }
    Write-AnsiLine $separator $script:DiskUsageColor
}

function Invoke-DockerPrune {
    param(
        [string]$Description,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host $Description
    docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed."
    }
}

function Stop-RunningContainers {
    $containerIds = docker ps -q
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list running containers."
    }

    if (-not $containerIds) {
        Write-Host ""
        Write-Host "No running containers to stop."
        return
    }

    Write-Host ""
    Write-Host "Stopping all running containers..."
    docker stop $containerIds
    if ($LASTEXITCODE -ne 0) {
        throw "Stopping running containers failed."
    }
}

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI was not found. Install Docker or add it to PATH."
    }

    Write-AnsiLine "~*~*--=== A ROBUST, COMPLETE DOCKER PURGE SCRIPT ===--*~*~" $script:Magenta
    Write-AnsiLine "by Vernard Mercader (https://github.com/vince7488)" $script:White
    Write-Host ""
    Write-AnsiLine "*WAW, very convenient much!*" $script:Gray
    Write-Host ""
    Write-AnsiLine "These commands are destructive. Option 1 stops all running containers, kills all stopped containers, strips all unreferenced images, clears unused networks, removes unused named and anonymous volumes, and clears the build cache. Data residing in unused volumes will be permanently erased. Proceed with caution." $script:Yellow
    Write-Host ""
    Write-Host ""
    Write-AnsiLine "1. Purge all unused Docker resources [1]" $script:BrightCyan
    Write-AnsiLine "2. One by one [2]" $script:BrightCyan
    $choice = Read-AnsiPrompt "Select option: " $script:BrightCyan

    if ($choice -eq '1') {
        Show-DockerUsage

        $confirm = Read-PurgeConfirmation
        if ($confirm -cne 'PURGE') {
            Write-Host "Confirmation did not match. Exiting."
            exit 0
        }

        Stop-RunningContainers
        Invoke-DockerPrune "Purging stopped containers..." @('container', 'prune', '-f')
        Invoke-DockerPrune "Purging unused images..." @('image', 'prune', '-a', '-f')
        Invoke-DockerPrune "Purging unused named and anonymous volumes..." @('volume', 'prune', '-a', '-f')
        Invoke-DockerPrune "Purging unused networks..." @('network', 'prune', '-f')
        Invoke-DockerPrune "Purging build cache..." @('builder', 'prune', '-a', '-f')

        Show-DockerUsage
        Write-Host ""
        Write-Host "Complete Docker purge done."
    } elseif ($choice -eq '2') {
        $ranAny = $false
        Show-DockerUsage

        $runStop = Read-YesNoPrompt "About to stop all running containers. Proceed?"
        if ($runStop -match "^[yY]$") {
            Stop-RunningContainers
            $ranAny = $true
        }

        $runCont = Read-YesNoPrompt "About to purge all stopped containers. Proceed?"
        if ($runCont -match "^[yY]$") {
            Invoke-DockerPrune "Purging stopped containers..." @('container', 'prune', '-f')
            $ranAny = $true
        }

        $runImg = Read-YesNoPrompt "About to purge all unused images. Proceed?"
        if ($runImg -match "^[yY]$") {
            Invoke-DockerPrune "Purging unused images..." @('image', 'prune', '-a', '-f')
            $ranAny = $true
        }

        $runVol = Read-YesNoPrompt "About to clear all unused named and anonymous volumes. Proceed?"
        if ($runVol -match "^[yY]$") {
            Invoke-DockerPrune "Purging unused named and anonymous volumes..." @('volume', 'prune', '-a', '-f')
            $ranAny = $true
        }

        $runNet = Read-YesNoPrompt "About to clear all unused networks. Proceed?"
        if ($runNet -match "^[yY]$") {
            Invoke-DockerPrune "Purging unused networks..." @('network', 'prune', '-f')
            $ranAny = $true
        }

        $runBld = Read-YesNoPrompt "About to clear all build cache. Proceed?"
        if ($runBld -match "^[yY]$") {
            Invoke-DockerPrune "Purging build cache..." @('builder', 'prune', '-a', '-f')
            $ranAny = $true
        }

        if ($ranAny) {
            Show-DockerUsage
            Write-Host ""
            Write-Host "Selected Docker purge steps done."
        } else {
            Write-Host "No prune commands selected."
        }
    } else {
        Write-Host "Invalid choice. Exiting."
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
