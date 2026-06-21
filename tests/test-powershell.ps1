$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$ScriptPath = Join-Path $RootDir "windows/docker-purge.ps1"
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("docker-purge-tests-" + [guid]::NewGuid().ToString("N"))
$FakeDocker = Join-Path $TempDir "docker.ps1"
$LogFile = Join-Path $TempDir "docker.log"

New-Item -ItemType Directory -Path $TempDir | Out-Null

$fakeDockerContent = @'
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DockerArgs
)

($DockerArgs -join " ") | Add-Content -LiteralPath $env:DOCKER_PURGE_TEST_LOG

$cmd = if ($DockerArgs.Count) { $DockerArgs[0] } else { "" }
$rest = if ($DockerArgs.Count -gt 1) { @($DockerArgs[1..($DockerArgs.Count - 1)]) } else { @() }
$restText = $rest -join " "

switch ($cmd) {
    "context" {
        "test-context"
    }
    "system" {
        "TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE"
        "Images          2         0         120MB     120MB (100%)"
        "Containers      1         0         1kB       1kB (100%)"
        "Local Volumes   1         0         20MB      20MB (100%)"
        "Build Cache     1         0         15MB      15MB"
    }
    "ps" {
        if ($restText -eq "-q") {
            "abc123"
        } elseif ($restText -like "*status=exited*") {
            "NAMES`tIMAGE`tSTATUS"
            "old-app`talpine`tExited"
        } else {
            "NAMES`tIMAGE`tSTATUS`tPORTS"
            "live-app`tnginx`tUp 5 minutes`t80/tcp"
        }
    }
    "images" {
        "REPOSITORY`tTAG`tIMAGE ID`tSIZE"
        "nginx`tlatest`timg123`t80MB"
    }
    "volume" {
        if ($restText -like "ls*") {
            "VOLUME NAME`tDRIVER`tSCOPE"
            "sample-volume`tlocal`tlocal"
        } elseif ($restText -like "prune*") {
            "Deleted volumes"
        } else {
            Write-Error "Unexpected volume command: $restText"
            exit 42
        }
    }
    "network" {
        if ($restText -like "ls*") {
            "NAME`tDRIVER`tSCOPE"
            "sample-network`tbridge`tlocal"
        } elseif ($restText -like "prune*") {
            "Deleted networks"
        } else {
            Write-Error "Unexpected network command: $restText"
            exit 42
        }
    }
    "builder" {
        if ($restText -eq "du") {
            "ID          RECLAIMABLE     SIZE"
            "cache123    true            15MB"
        } elseif ($restText -like "prune*") {
            "Deleted build cache"
        } else {
            Write-Error "Unexpected builder command: $restText"
            exit 42
        }
    }
    "stop" {
        $rest
    }
    "container" {
        "Deleted containers"
    }
    "image" {
        "Deleted images"
    }
    default {
        Write-Error "Unexpected docker command: $cmd $restText"
        exit 42
    }
}
'@

Set-Content -LiteralPath $FakeDocker -Value $fakeDockerContent -Encoding UTF8

function Invoke-PurgeScript {
    param(
        [string]$InputText,
        [string[]]$Arguments = @()
    )

    Set-Content -LiteralPath $LogFile -Value "" -NoNewline

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.Environment["DOCKER_PURGE_TEST_LOG"] = $LogFile
    $psi.Environment["DOCKER_PURGE_DOCKER_BIN"] = $FakeDocker
    $psi.Environment["NO_COLOR"] = "1"

    foreach ($arg in @("-NoProfile", "-File", $ScriptPath) + $Arguments) {
        [void]$psi.ArgumentList.Add($arg)
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    $process.StandardInput.Write($InputText)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "Script failed with exit code $($process.ExitCode). STDOUT: $stdout STDERR: $stderr"
    }

    return $stdout
}

function Get-DockerLog {
    if (-not (Test-Path -LiteralPath $LogFile)) {
        return @()
    }

    return @(Get-Content -LiteralPath $LogFile | Where-Object { $_ })
}

function Assert-OutputContains {
    param(
        [string]$Output,
        [string]$Needle
    )

    if (-not $Output.Contains($Needle)) {
        throw "Expected output to contain: $Needle"
    }
}

function Assert-OutputHasNoAnsi {
    param([string]$Output)

    if ($Output.Contains([char]27)) {
        throw "Expected output to contain no ANSI escape sequences."
    }
}

function Assert-LogContains {
    param([string]$Needle)
    $log = Get-DockerLog
    if ($Needle -notin $log) {
        throw "Expected docker log to contain '$Needle'. Actual log: $($log -join ' | ')"
    }
}

function Assert-LogNotContains {
    param([string]$Needle)
    $log = Get-DockerLog
    if ($Needle -in $log) {
        throw "Expected docker log not to contain '$Needle'. Actual log: $($log -join ' | ')"
    }
}

function Assert-LogOrder {
    param(
        [string]$Before,
        [string]$After
    )

    $log = Get-DockerLog
    $beforeIndex = [array]::IndexOf($log, $Before)
    $afterIndex = [array]::IndexOf($log, $After)

    if ($beforeIndex -lt 0 -or $afterIndex -lt 0 -or $beforeIndex -ge $afterIndex) {
        throw "Expected '$Before' to appear before '$After'. Actual log: $($log -join ' | ')"
    }
}

try {
    $output = Invoke-PurgeScript -InputText "" -Arguments @("-Preview", "-NoColor")
    Assert-OutputContains $output "Preview complete. No Docker resources were changed."
    Assert-OutputContains $output "test-context"
    Assert-OutputHasNoAnsi $output
    Assert-LogNotContains "stop abc123"
    Assert-LogNotContains "container prune -f"
    Assert-LogNotContains "image prune -a -f"
    Assert-LogNotContains "volume prune -a -f"
    Assert-LogNotContains "network prune -f"
    Assert-LogNotContains "builder prune -a -f"

    $output = Invoke-PurgeScript -InputText "1`nPURGE`n" -Arguments @("-NoColor")
    Assert-LogContains "stop abc123"
    Assert-LogContains "container prune -f"
    Assert-LogContains "image prune -a -f"
    Assert-LogContains "volume prune -a -f"
    Assert-LogContains "network prune -f"
    Assert-LogContains "builder prune -a -f"
    Assert-LogOrder "ps --format table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" "stop abc123"
    Assert-LogOrder "stop abc123" "container prune -f"
    Assert-OutputContains $output "Complete Docker purge done."

    $output = Invoke-PurgeScript -InputText "2`ny`ny`ny`ny`ny`ny`n" -Arguments @("-NoColor")
    Assert-LogContains "stop abc123"
    Assert-LogContains "container prune -f"
    Assert-LogContains "image prune -a -f"
    Assert-LogContains "volume prune -a -f"
    Assert-LogContains "network prune -f"
    Assert-LogContains "builder prune -a -f"
    Assert-OutputContains $output "Selected Docker purge steps done."

    "PowerShell mocked tests passed."
} finally {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
