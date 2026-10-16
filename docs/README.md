# homepsick documentation

[Project README](../README.md)

homepsick manages Git-backed collections of home-directory configuration files from PowerShell. Each collection is a **castle**: a repository under `<home>/.homesick/repos/<castle>` whose `home/` directory mirrors the paths to manage. homepsick links Git-tracked files into your home directory, so editing a linked file edits the castle's working copy.

It follows the layout and core workflows of [homeshick](https://github.com/andsens/homeshick), the Bash tool related to the Ruby-based [homesick](https://github.com/technicalpickles/homesick). It provides a PowerShell module with eight commands; it does not implement every workflow of those tools. See the [compatibility comparison](homeshick-compatibility.md).

## Requirements

- PowerShell **7.4 or later**, as declared by the module manifest. Windows PowerShell 5.1 is outside that contract.
- Git available as `git` on `PATH`. The project does not establish a minimum Git version; use a current Git supporting `git -C` and `git branch --show-current`.
- A filesystem and account that can create symbolic links. On Windows, check link permissions before tracking files.

The repository's CI runs Pester on `ubuntu-latest` and `windows-latest`. Linux examples were exercised during this documentation work with PowerShell 7.6.6 and Git 2.56.0. Windows was not retested locally; macOS has no CI coverage or task-local validation. See [platform support and troubleshooting](platforms-and-troubleshooting.md).

## Install and try it

Run these commands in PowerShell. This installs a source checkout under your home directory and imports it into the **current session**. No Gallery installation or administrator access is required for the module itself.

```powershell
$installPath = Join-Path $HOME 'src/homepsick'
git clone https://github.com/KitKat31337/homepsick.git $installPath
Import-Module (Join-Path $installPath 'src/Homepsick.psd1')
Get-Command -Module Homepsick
```

Obtain a castle using a trusted Git URL or absolute local repository path. The prompt below asks for your own repository; there is no bundled sample castle.

```powershell
$castleSource = Read-Host 'Trusted castle Git URL or absolute local path'
$castle = New-HomepsickCastle -Clone -GitUrl $castleSource -Batch
Get-HomepsickCastle
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
git -C $castle.CastlePath status --short
Get-HomepsickCastleStatus -CastleName $castle.CastleName

# Preview missing links; preserve conflicting destinations.
Enable-HomepsickCastle -CastleName $castle.CastleName -Batch -WhatIf
Enable-HomepsickCastle -CastleName $castle.CastleName -Batch -Verbose
```

`-Batch` skips existing conflicting paths. The interactive link command offers replacement; `-Force` permits removal of conflicting files or whole directories **without a backup**. Read [linking and conflicts](castles-and-linking.md) before replacing anything.

To maintain the castle:

```powershell
git -C $castle.CastlePath diff
Update-HomepsickCastle -CastleName $castle.CastleName -Batch
Enable-HomepsickCastle -CastleName $castle.CastleName -Batch
```

**Git synchronization and linking are separate operations.** Pull updates the castle's working copy. Existing links expose changed content immediately; new paths require links. `Update-HomepsickCastle -Link` only runs linking when its pull detects added or renamed paths under `home/`, so an explicit `Enable-HomepsickCastle` is the reliable way to relink. Commit and push using Git directly.

To start your own castle instead, follow [getting started and everyday workflows](getting-started.md).

## Documentation

| Guide | Contents |
| --- | --- |
| [Installation](installation.md) | Source installation, imports, profiles, updates, unloading and removal |
| [Getting started](getting-started.md) | Create, clone, track, commit, synchronize, use multiple castles and stop managing files |
| [Command reference](commands.md) | Every exported command, syntax, outputs, prompts and side effects |
| [Castles and linking](castles-and-linking.md) | Discovery, path mapping, tracked files, submodules, collisions and cleanup |
| [Configuration](configuration.md) | Home discovery, fixed paths, Git settings, defaults and absent features |
| [Platforms and troubleshooting](platforms-and-troubleshooting.md) | Support evidence, permissions, diagnostics and known limitations |
| [Homeshick compatibility](homeshick-compatibility.md) | Shared layouts, workflow equivalents and behavioral differences |
| [Development](development.md) | Architecture, local development, tests, CI and maintainer considerations |

For contributor setup, tests and CI, see the [development guide](development.md). Distributed under the [MIT license](../LICENSE).
