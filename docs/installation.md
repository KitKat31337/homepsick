# Installation and loading

[Documentation index](README.md#documentation) · [Getting started](getting-started.md)

## Prerequisites

Use PowerShell 7.4 or later and a current Git on `PATH`:

```powershell
$PSVersionTable.PSVersion
Get-Command git -CommandType Application
git --version
```

The [manifest](../src/Homepsick.psd1) declares the PowerShell minimum but no Git minimum or runtime module dependencies. Bash, Ruby, homeshick, homesick, Pester and a GitHub account are not runtime requirements. Network access and credentials are needed only for the Git remotes and submodules you use. Local cloning works without a hosted service.

The module can load without Git, but creation explicitly rejects a missing `git`; operations that execute Git will otherwise fail when starting the process. Symbolic link permission is needed for linking and tracking, not for importing or listing ordinary castle directories.

## Install from this repository

There is no package installation or publication workflow in this repository, and these instructions do not assume a PowerShell Gallery package exists. Use the project's actual source URL:

```powershell
$installPath = Join-Path $HOME 'src/homepsick'
git clone https://github.com/KitKat31337/homepsick.git $installPath
Import-Module (Join-Path $installPath 'src/Homepsick.psd1')
```

The checkout can live elsewhere; substitute its absolute path. The parent `src` location is just a suggested installation directory. Choose an unused checkout path; clone will not update an existing checkout. Installation writes that checkout, and import changes only the current PowerShell process.

An extracted source archive also works if the complete `src/` tree is preserved. From any existing checkout or extracted tree:

```powershell
Import-Module ./src/Homepsick.psd1
```

Importing [Homepsick.psm1](../src/Homepsick.psm1) directly is supported by the loader and used by the current tests:

```powershell
Import-Module ./src/Homepsick.psm1
```

Prefer the manifest: it supplies the version, minimum PowerShell version and explicit export list. Direct `.psm1` import bypasses that metadata; it does not make older PowerShell versions supported. Do not dot-source the individual public files or the module loader as an installation method. Public functions depend on private helpers and the `HomepsickCastle` class assembled by the module. There is no standalone `homepsick.ps1` executable or `homepsick` command.

Verify the import:

```powershell
Get-Module Homepsick | Select-Object Name, Version, Path
Get-Command -Module Homepsick
Get-Help New-HomepsickCastle -Full
```

The manifest version is currently `0.2.0`. Eight functions and no aliases are exported.

## Load in future sessions

`$PROFILE.CurrentUserCurrentHost` is PowerShell's platform- and host-specific profile path. Do not hardcode a Windows Documents directory or a Unix shell's `.profile` file. Inspect the path, create its parent if needed, and edit that profile without overwriting existing content:

```powershell
$profilePath = $PROFILE.CurrentUserCurrentHost
$profilePath
New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType File -Path $profilePath | Out-Null
}
```

Add this line once to that file if you used the suggested checkout location:

```powershell
Import-Module (Join-Path $HOME 'src/homepsick/src/Homepsick.psd1')
```

Creating and editing the profile changes a user-owned file, not system configuration. The import executes in future sessions of that host; use `$PROFILE.CurrentUserAllHosts` instead if you deliberately want every PowerShell host to load it. Profiles are not loaded with `pwsh -NoProfile`. Import the module manually to use it immediately. No refresh, pull or linking operation runs merely from importing it.

On Windows, inspect `Get-ExecutionPolicy -List` if execution is blocked. Organizational policy may take precedence. For a trusted downloaded archive, inspect the affected files and use `Unblock-File` only on files you trust if the block is a download marker. No repository instruction requires an unrestricted or bypass policy. Link permissions are a separate issue; see [Windows troubleshooting](platforms-and-troubleshooting.md#windows-symbolic-link-permission-errors).

## Update an installation

Review local changes first, then fast-forward the **module checkout**:

```powershell
git -C $installPath status --short
git -C $installPath pull --ff-only
Remove-Module Homepsick
Import-Module (Join-Path $installPath 'src/Homepsick.psd1')
```

If `$installPath` is no longer defined, set it to the original checkout path. If the checkout has local changes or cannot fast-forward, resolve that in Git before updating. A fresh PowerShell process is safest after class-definition changes: PowerShell classes can remain in an existing session after module removal. Avoid repeatedly forcing imports of changed class definitions.

This updates homepsick itself. `Update-HomepsickCastle` updates castles and does not update a module checkout installed elsewhere.

## Unload and uninstall

```powershell
Remove-Module Homepsick
```

This removes the module's exported commands and its registered `HomepsickCastle` type accelerator from the current session. It does not remove profile entries, the source checkout, castles or home-directory links. Previously created objects and loaded class definitions may remain until the session ends.

To stop future loading, remove the import line you added to your profile. After reviewing and preserving local changes, remove the installation checkout manually if desired. Leave `<home>/.homesick/repos` intact unless you separately intend to retire its castles. Deleting a castle while home-directory links still point into it leaves broken links; follow the [file and castle retirement workflow](getting-started.md#stop-managing-a-file-or-castle) first. There is no `Uninstall-Homepsick`, unlink or castle-removal command.
