# VERY COOL, TERMINAL-BASED, DOCKER PURGING COMMANDS

by [Vernard](https://vernard.net)

These scripts provide an interactive wrapper for Docker's native prune commands. They preview Docker state, show the active Docker
context, and clear unused Docker assets safely and quickly.

## Warnings and Disclaimers

These commands are destructive. Option 1 stops all running containers, kills all stopped containers, strips all unreferenced images,
clears unused networks, removes unused named and anonymous volumes, and clears the build cache. Data residing in unused volumes will be
permanently erased. Proceed with caution. After pruning images, you may need to pull them again later, which can take time and may count
against registry pull limits such as Docker Hub rate limits.

### Prerequisites

**macOS and Linux**: Make the shell script executable. Run `chmod +x ./mac-linux/docker-purge.sh` in your terminal.

**Windows**: PowerShell blocks unsigned scripts by default. You need to bypass this restriction for your active session. Run
`Set-ExecutionPolicy Bypass -Scope Process` before executing the script.

### Usage

Run the script from wherever you place it. If you keep the repository structure, use the commands below.

#### macOS and Linux:

```shell
./mac-linux/docker-purge.sh
```

Preview only, with no destructive changes:

```shell
./mac-linux/docker-purge.sh --preview
```

The same mode is also available as:

```shell
./mac-linux/docker-purge.sh --dry-run
```

Disable terminal colors:

```shell
NO_COLOR=1 ./mac-linux/docker-purge.sh
```

![Docker purge demonstration](./assets/pica-pica/dc__maclinux_01.webp)

![Docker purge demonstration](./assets/pica-pica/dc__maclinux_02.webp)

![Docker purge demonstration](./assets/pica-pica/dc__maclinux_03.webp)

![Docker purge demonstration](./assets/pica-pica/dc__maclinux_04.webp)

![Docker purge demonstration](./assets/pica-pica/dc__maclinux_05.webp)

![Docker purge demonstration](./assets/pica-pica/dc__maclinux_06.webp)

#### Windows:

```shell
.\windows\docker-purge.ps1
```

Preview only, with no destructive changes:

```powershell
.\windows\docker-purge.ps1 -Preview
```

The same mode is also available as:

```powershell
.\windows\docker-purge.ps1 -DryRun
```

Disable terminal colors:

```powershell
$env:NO_COLOR = '1'
.\windows\docker-purge.ps1
```

![Docker purge demonstration](./assets/pica-pica/dc__win_01.webp)

![Docker purge demonstration](./assets/pica-pica/dc__win_02.webp)

![Docker purge demonstration](./assets/pica-pica/dc__win_03.webp)

![Docker purge demonstration](./assets/pica-pica/dc__win_04.webp)

![Docker purge demonstration](./assets/pica-pica/dc__win_05.webp)

![Docker purge demonstration](./assets/pica-pica/dc__win_06.webp)

---

## What This Does

| Behavior | Included? |
| --- | --- |
| Shows the active Docker context before destructive actions | Yes |
| Shows Docker disk usage before and after cleanup | Yes |
| Shows running containers before stopping them | Yes |
| Stops running containers when confirmed or when complete purge is confirmed | Yes |
| Removes stopped containers | Yes |
| Removes unused images, including unreferenced tagged images | Yes |
| Removes unused named and anonymous volumes | Yes |
| Removes unused custom networks | Yes |
| Removes build cache | Yes |
| Removes Docker Desktop, Docker Engine, contexts, credentials, or plugins | No |
| Removes active project files from your filesystem | No |
| Runs destructive commands in preview mode | No |

## Under the Hood

The script offers three paths.

All paths show Docker context and preview details before cleanup so you can see which Docker environment is targeted and what Docker sees.

### Option 1: Complete Wipe

This shows the Docker disk usage preview, requires you to type `PURGE`, then runs the full purge sequence without more prompts:

1. Stop all running containers
1. Prune stopped containers
1. Prune unused images
1. Prune unused named and anonymous volumes
1. Prune unused networks
1. Prune the build cache

#### Option 2: Step-by-Step

This isolates the teardown process. It prompts for a yes or no confirmation before stopping running containers, then running individual
prune commands for containers, images, volumes, networks, and the build cache.

### Option 3: Preview Only

This shows Docker context, disk usage, running containers, stopped containers, images, volumes, custom networks, and build cache without
changing anything.

You can also run preview mode directly:

```shell
./mac-linux/docker-purge.sh --preview
```

```shell
./mac-linux/docker-purge.sh --dry-run
```

```powershell
.\windows\docker-purge.ps1 -Preview
```

```powershell
.\windows\docker-purge.ps1 -DryRun
```

## Testing and CI

The repository includes mocked tests. They fake the Docker CLI and verify the scripts call the expected commands without touching real
Docker resources.

```shell
bash tests/test-bash.sh
```

```powershell
pwsh -NoProfile -File tests/test-powershell.ps1
pwsh -NoProfile -File tests/check-readme-assets.ps1
```

GitHub Actions runs Bash syntax checks, ShellCheck, PowerShell parser checks, PSScriptAnalyzer, mocked behavior tests, and README image
asset validation.

---

Just saying... This really is the be-all and end-all Docker clearing script.

## License

This project is licensed under the MIT License. See the LICENSE file for details.
