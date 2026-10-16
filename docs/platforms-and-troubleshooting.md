# Platform support and troubleshooting

[Documentation index](README.md#documentation) · [Link behavior](castles-and-linking.md)

## What is tested

| Platform or version | Evidence and limits |
| --- | --- |
| Windows | Historical project use; current CI matrix includes `windows-latest` with hosted `pwsh`. No Windows execution was performed during this documentation task. A CI definition alone does not establish that every Windows configuration passes. |
| Linux | Current CI matrix includes `ubuntu-latest`. All nine existing Pester tests passed during this task on the Ubuntu development VM with PowerShell 7.6.6 and Git 2.56.0; additional temporary-home examples and edge cases were exercised. |
| macOS | No CI job and no task-local test. The implementation uses PowerShell/.NET filesystem APIs, but that is not macOS verification. |
| PowerShell 7.4 | Declared minimum in the manifest. CI uses the runner's installed `pwsh`, without a 7.4-specific matrix; this task did not run 7.4 itself. |
| Windows PowerShell 5.1 | Outside the manifest's minimum version; do not use it. |

See the [workflow](../.github/workflows/test.yml) and [test suite](../tests/Parity.Tests.ps1). Hosted runner versions can change. CI does not cover macOS, network shares, all Windows link privileges, arbitrary filesystem providers or every filesystem's case behavior. The runtime has no separate OS adapters or privilege-elevation mechanism.

## Platform differences to plan for

- **Links:** homepsick uses `New-Item -ItemType SymbolicLink`, not hard links, copies or Windows junctions as a fallback. Windows needs the relevant symbolic-link permission. Developer Mode can permit non-elevated creation on supported Windows configurations; organizational policy can still apply. See Microsoft's [New-Item documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item#example-7-create-a-symbolic-link-to-a-file-or-folder). Do not make an elevated shell your routine dotfile-management environment.
- **Case and names:** Linux filesystems commonly distinguish case; Windows and macOS volumes often do not. Use consistent, portable names and avoid case-only differences. Selection requires the exact `home/` prefix, and the already-linked comparison has a [case-sensitivity defect](castles-and-linking.md#linking-and-conflicts).
- **Paths:** .NET constructs platform separators; there are no Windows-only destination mappings. A file intended for PowerShell's profile must occupy the correct relative path for that host. Filename legality, path length and filesystem link support remain platform constraints. Quote spaces and use literal-path inspection.
- **Home:** `$env:HOME` takes precedence over the .NET user profile. It can differ from PowerShell's `$HOME`. Both storage and destinations move together when it is overridden; see [configuration](configuration.md).
- **Profiles:** use `$PROFILE.CurrentUserCurrentHost` or `$PROFILE.CurrentUserAllHosts` rather than fixed Windows or Unix paths. Windows PowerShell and PowerShell 7, and different hosts, can use different profiles. See [profile integration](installation.md#load-in-future-sessions) and Microsoft's [profile reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles).
- **Git checkout:** homepsick delegates tracked-symlink checkout, line endings, executable modes and submodule behavior to Git. In particular, inspect Git's `core.symlinks` and the resulting source entry when a Unix symlink is checked out as ordinary text on Windows. Enabling homepsick does not reconstruct that source symlink or normalize application configuration across OSes.

## Import fails or commands are missing

**Likely causes:** wrong checkout path, old PowerShell, incomplete `src/`, execution policy, or an already registered class accelerator.

```powershell
$PSVersionTable.PSVersion
Test-Path -LiteralPath ./src/Homepsick.psd1
Test-ModuleManifest ./src/Homepsick.psd1
Import-Module ./src/Homepsick.psd1 -Verbose -ErrorAction Stop
Get-Command -Module Homepsick
```

Use PowerShell 7.4+, import the full tree through the manifest and inspect the first error. Import into a fresh `pwsh -NoProfile` session to isolate profile interference. If `HomepsickCastle` is already registered by a loaded copy, remove that module normally or start a fresh process; do not overwrite an unrelated accelerator. On Windows inspect `Get-ExecutionPolicy -List` and trusted-download markers before changing any policy. There is no install-time execution-policy change in homepsick.

## Git is not found or an operation fails

**Likely causes:** no application named `git` on `PATH`, remote authentication or transport restrictions, missing upstream, or a Git conflict.

```powershell
Get-Command git -CommandType Application
git --version
$castle = Get-HomepsickCastle -CastleName personal
git -C $castle.CastlePath status
git -C $castle.CastlePath branch -vv
git -C $castle.CastlePath remote -v
```

Review remote URLs before sharing output; they can contain private details. Make Git work directly in the repository before retrying homepsick. A newly generated castle has no upstream, so update intentionally skips it. Configure the intended remote/upstream using Git after an initial commit. Do not reset or delete the checkout to solve an authentication or merge problem.

## Windows symbolic-link permission errors

**Likely cause:** the current account/session cannot create symbolic links, or the filesystem disallows them. `-Force` cannot grant privileges.

Before tracking originals, try a link between disposable files:

```powershell
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('homepsick-link-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $probeRoot | Out-Null
Set-Content -LiteralPath (Join-Path $probeRoot 'target.txt') -Value 'test'
New-Item -ItemType SymbolicLink -Path (Join-Path $probeRoot 'link.txt') -Target 'target.txt' -ErrorAction Stop
Get-Item -LiteralPath (Join-Path $probeRoot 'link.txt') -Force | Select-Object LinkType, Target
```

This writes only temporary data and leaves it for inspection. Check Developer Mode or the relevant privilege with your administrator if the probe fails. Do not weaken execution policy to fix link privileges; they are separate mechanisms. If tracking already failed, inspect the original path, castle path and `git status` before retrying, since rollback is not a transaction.

## A destination is skipped or a directory cannot be created

**Likely causes:** a conflicting destination was preserved by batch/skip mode, or an ancestor is a file.

```powershell
$path = Join-Path $HOME '.config/my tool/settings.json'
Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue | Format-List FullName, Attributes, LinkType, Target
Get-Item -LiteralPath (Split-Path -Parent $path) -Force -ErrorAction SilentlyContinue
Enable-HomepsickCastle -CastleName personal -Batch -Verbose
Enable-HomepsickCastle -CastleName personal -Force -WhatIf
```

Inspect every relevant ancestor if necessary. Preserve existing content separately, then choose whether to keep it or replace it. Approved leaf replacement deletes conflicts with no backup; replacing a directory deletes its contents. An ancestor file must be reorganized manually. If another castle owns the path, choose which source to use; there is no priority setting.

## Files do not appear after clone, pull or enable

**Likely causes:** no tracked `home/` entries, batch clone without linking, update's conditional link gate, uninitialized submodules, or skipped conflicts.

```powershell
$castle = Get-HomepsickCastle -CastleName personal
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
git -C $castle.CastlePath ls-files -- home
git -C $castle.CastlePath status --short
git -C $castle.CastlePath submodule status --recursive
Enable-HomepsickCastle -CastleName personal -Batch -Verbose
```

Stage intended files beneath literal `home/`; root files and untracked files do not map. Initialize trusted submodules with `git -C $castle.CastlePath submodule update --init --recursive` when needed. An update without a qualifying addition/rename does not run enable, even with `-Link`. Git synchronization changes source content; enable creates the destination links. Newline-containing filenames currently cannot be selected by the parser.

## A link is broken or points to unexpected content

**Likely causes:** a moved/deleted source, a deleted or archived castle, an absent submodule, a wrong castle selected in a collision, a machine-specific source symlink, or the case-only target-comparison defect.

```powershell
$path = Join-Path $HOME '.example'
Get-Item -LiteralPath $path -Force | Format-List FullName, LinkType, Target
$castle = Get-HomepsickCastle -CastleName personal
git -C $castle.CastlePath status --short
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
```

`Get-Item -Force` can inspect a link whose target is gone; do not use only `Test-Path` to decide whether a link entry exists. Resolve a relative target from the link's parent and inspect the target itself. Restore an unintentionally missing source from your own Git history or backups. If the source was intentionally removed, retire the stale link manually. Enabling does not clean stale links or restore missing source files. Inspect and replace a wrong link deliberately; `-Force` may still skip a case-only wrong target because of the equality defect.

## Status says Current, Behind or Uncheckable unexpectedly

`Current` means local `HEAD` matches the live upstream hash and porcelain status is empty; it does not mean the home links are present or correct. `Uncheckable` can hide a failed remote query as well as a missing upstream. `Behind` is also used when the remote object has not been fetched locally, so it does not prove a fast-forward is possible.

Inspect `git status`, `git branch -vv` and your remote connectivity. If needed, run a deliberate `git fetch` followed by `git status -sb` or `git log --oneline --left-right 'HEAD...@{upstream}'` in the castle. Fetch changes local remote refs and the freshness marker; it does not link files. Resolve divergence with Git before pulling.

## Refresh does nothing or keeps prompting

`-Batch` alone does not pull; use `-Pull -Batch` for a deliberate unattended update. A recent `FETCH_HEAD` is fresh even if remote commits exist, and declining an interactive prompt updates an existing marker's timestamp. A missing marker is always stale until a fetch/pull creates it; declining does not create one. Check its location with `git -C $castle.CastlePath rev-parse --git-path FETCH_HEAD` and inspect its UTC timestamp. No recurring refresh job is installed by homepsick.
