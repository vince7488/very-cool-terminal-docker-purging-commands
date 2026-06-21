param(
    [switch]$Preview,
    [switch]$DryRun,
    [switch]$NoColor,
    [switch]$Help
)

$script:UseColor = -not ($NoColor -or $env:NO_COLOR)
$script:DockerBin = if ($env:DOCKER_PURGE_DOCKER_BIN) { $env:DOCKER_PURGE_DOCKER_BIN } else { "docker" }

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

    if (-not $script:UseColor) {
        return $Text
    }

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

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  .\docker-purge.ps1 [-Preview|-DryRun] [-NoColor] [-Help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Preview   Show Docker context, disk usage, containers, images, volumes, networks, and build cache without deleting anything."
    Write-Host "  -DryRun    Alias-style preview mode. No Docker resources are changed."
    Write-Host "  -NoColor   Disable ANSI colors. You can also set NO_COLOR=1."
    Write-Host "  -Help      Show this help text."
}

function Invoke-DockerCommand {
    param(
        [string[]]$Arguments
    )

    $output = & $script:DockerBin @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { $_.ToString() })
    }
}

function Assert-DockerAvailable {
    if (-not (Get-Command $script:DockerBin -ErrorAction SilentlyContinue)) {
        throw "Docker CLI was not found. Install Docker or add it to PATH."
    }
}

function Write-PreviewBlock {
    param(
        [string]$Title,
        [string[]]$Lines
    )

    $body = @($Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $body.Count) {
        $body = @("(none)")
    }

    $displayLines = @($Title) + $body
    $maxLength = 0
    foreach ($line in $displayLines) {
        if ($line.Length -gt $maxLength) {
            $maxLength = $line.Length
        }
    }

    $separator = "=" * ($maxLength + 1)
    Write-AnsiLine $separator $script:DiskUsageColor
    foreach ($line in $displayLines) {
        Write-AnsiLine $line.PadRight($separator.Length) $script:DiskUsageColor
    }
    Write-AnsiLine $separator $script:DiskUsageColor
}

function Show-DockerOutputBlock {
    param(
        [string]$Title,
        [string[]]$Arguments
    )

    Write-Host ""
    $result = Invoke-DockerCommand -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        if ($result.Output) {
            $result.Output | ForEach-Object { Write-Error $_ }
        }
        throw "Unable to read $Title"
    }

    Write-PreviewBlock $Title $result.Output
}

function Show-DockerPreview {
    Show-DockerOutputBlock "Docker context:" @("context", "show")
    Show-DockerOutputBlock "Docker disk usage:" @("system", "df")
    Show-DockerOutputBlock "Running containers:" @("ps", "--format", "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}")
    Show-DockerOutputBlock "Stopped containers:" @("ps", "-a", "--filter", "status=exited", "--format", "table {{.Names}}\t{{.Image}}\t{{.Status}}")
    Show-DockerOutputBlock "Images:" @("images", "--format", "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}")
    Show-DockerOutputBlock "Volumes:" @("volume", "ls", "--format", "table {{.Name}}\t{{.Driver}}\t{{.Scope}}")
    Show-DockerOutputBlock "Custom networks:" @("network", "ls", "--filter", "type=custom", "--format", "table {{.Name}}\t{{.Driver}}\t{{.Scope}}")
    Show-DockerOutputBlock "Build cache:" @("builder", "du")
}

function Invoke-DockerPrune {
    param(
        [string]$Description,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host $Description
    $result = Invoke-DockerCommand -Arguments $Arguments
    $result.Output | ForEach-Object { Write-Host $_ }
    if ($result.ExitCode -ne 0) {
        throw "$Description failed."
    }
}

function Stop-RunningContainers {
    $result = Invoke-DockerCommand -Arguments @("ps", "-q")
    if ($result.ExitCode -ne 0) {
        $result.Output | ForEach-Object { Write-Error $_ }
        throw "Unable to list running containers."
    }

    $containerIds = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $containerIds.Count) {
        Write-Host ""
        Write-Host "No running containers to stop."
        return
    }

    Write-Host ""
    Write-Host "Stopping all running containers..."
    $stopResult = Invoke-DockerCommand -Arguments (@("stop") + $containerIds)
    $stopResult.Output | ForEach-Object { Write-Host $_ }
    if ($stopResult.ExitCode -ne 0) {
        throw "Stopping running containers failed."
    }
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

function Show-Intro {
    Write-AnsiLine "~*~*--=== A ROBUST, COMPLETE DOCKER PURGE SCRIPT ===--*~*~" $script:Magenta
    Write-AnsiLine "by Vernard Mercader (https://github.com/vince7488)" $script:White
    Write-Host ""
    Write-AnsiLine "*WAW, very convenient much!*" $script:Gray
    Write-Host ""
    Write-AnsiLine "These commands are destructive. Option 1 stops all running containers, kills all stopped containers, strips all unreferenced images, clears unused networks, removes unused named and anonymous volumes, and clears the build cache. Data residing in unused volumes will be permanently erased. Proceed with caution." $script:Yellow
    Write-Host ""
}

try {
    if ($Help) {
        Show-Usage
        exit 0
    }

    Assert-DockerAvailable
    Show-Intro

    if ($Preview -or $DryRun) {
        Show-DockerPreview
        Write-Host ""
        Write-Host "Preview complete. No Docker resources were changed."
        exit 0
    }

    Write-Host ""
    Write-AnsiLine "1. Purge all unused Docker resources [1]" $script:BrightCyan
    Write-AnsiLine "2. One by one [2]" $script:BrightCyan
    Write-AnsiLine "3. Preview only [3]" $script:BrightCyan
    $choice = Read-AnsiPrompt "Select option: " $script:BrightCyan

    if ($choice -eq "1") {
        Show-DockerPreview

        $confirm = Read-PurgeConfirmation
        if ($confirm -cne "PURGE") {
            Write-Host "Confirmation did not match. Exiting."
            exit 0
        }

        Stop-RunningContainers
        Invoke-DockerPrune "Purging stopped containers..." @("container", "prune", "-f")
        Invoke-DockerPrune "Purging unused images..." @("image", "prune", "-a", "-f")
        Invoke-DockerPrune "Purging unused named and anonymous volumes..." @("volume", "prune", "-a", "-f")
        Invoke-DockerPrune "Purging unused networks..." @("network", "prune", "-f")
        Invoke-DockerPrune "Purging build cache..." @("builder", "prune", "-a", "-f")

        Show-DockerPreview
        Write-Host ""
        Write-Host "Complete Docker purge done."
    } elseif ($choice -eq "2") {
        $ranAny = $false
        Show-DockerPreview

        $runStop = Read-YesNoPrompt "About to stop all running containers. Proceed?"
        if ($runStop -match "^[yY]$") {
            Stop-RunningContainers
            $ranAny = $true
        }

        $runCont = Read-YesNoPrompt "About to purge all stopped containers. Proceed?"
        if ($runCont -match "^[yY]$") {
            Invoke-DockerPrune "Purging stopped containers..." @("container", "prune", "-f")
            $ranAny = $true
        }

        $runImg = Read-YesNoPrompt "About to purge all unused images. Proceed?"
        if ($runImg -match "^[yY]$") {
            Invoke-DockerPrune "Purging unused images..." @("image", "prune", "-a", "-f")
            $ranAny = $true
        }

        $runVol = Read-YesNoPrompt "About to clear all unused named and anonymous volumes. Proceed?"
        if ($runVol -match "^[yY]$") {
            Invoke-DockerPrune "Purging unused named and anonymous volumes..." @("volume", "prune", "-a", "-f")
            $ranAny = $true
        }

        $runNet = Read-YesNoPrompt "About to clear all unused networks. Proceed?"
        if ($runNet -match "^[yY]$") {
            Invoke-DockerPrune "Purging unused networks..." @("network", "prune", "-f")
            $ranAny = $true
        }

        $runBld = Read-YesNoPrompt "About to clear all build cache. Proceed?"
        if ($runBld -match "^[yY]$") {
            Invoke-DockerPrune "Purging build cache..." @("builder", "prune", "-a", "-f")
            $ranAny = $true
        }

        if ($ranAny) {
            Show-DockerPreview
            Write-Host ""
            Write-Host "Selected Docker purge steps done."
        } else {
            Write-Host "No prune commands selected."
        }
    } elseif ($choice -eq "3") {
        Show-DockerPreview
        Write-Host ""
        Write-Host "Preview complete. No Docker resources were changed."
    } else {
        Write-Host "Invalid choice. Exiting."
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
