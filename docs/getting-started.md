# Getting started and everyday workflows

[Documentation index](README.md#documentation) · [Installation](installation.md) · [Command reference](commands.md)

These examples run in PowerShell after importing homepsick. `$HOME` is assumed to match the [resolved destination home](configuration.md#home-and-path-overrides). Use a temporary home first if you want to experiment. Tracking moves originals, and forced linking can delete conflicts without backups.

## Create your first castle

```powershell
$castle = New-HomepsickCastle -CastleName personal
$castle | Select-Object CastleName, CastlePath, CastleSymRoot
```

This creates a local Git repository with an empty `home/` directory. It does not commit anything, set an identity or add a remote. The initial branch follows your Git configuration.

To create a harmless example file, first ensure the path is unused:

```powershell
$examplePath = Join-Path $HOME '.homepsick-example'
if (Get-Item -LiteralPath $examplePath -Force -ErrorAction SilentlyContinue) {
    throw 'Choose an unused example path.'
}
Set-Content -LiteralPath $examplePath -Value 'my first managed file'
Add-HomepsickFile -CastleName personal -Path $examplePath -WhatIf
Add-HomepsickFile -CastleName personal -Path $examplePath
```

The original moves to `personal/home/.homepsick-example`, its home path becomes a relative symbolic link, and Git stages the source. Inspect both the managed inventory and Git changes:

```powershell
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
Get-Item -LiteralPath $examplePath -Force | Select-Object FullName, LinkType, Target
git -C $castle.CastlePath status --short
git -C $castle.CastlePath diff --cached
```

`Get-HomepsickCastle` lists castles, not their file contents. `Get-HomepsickCastleStatus` summarizes comparison with an upstream; a new local castle is `Uncheckable` until it has one. Neither substitutes for `git status` and `git diff`.

## Commit and synchronize

Run Git directly to commit and push. Git needs an appropriate identity and any signing credentials configured for this repository. Review the staged diff before committing configuration files, especially credentials and machine-specific paths.

```powershell
git -C $castle.CastlePath diff --cached
git -C $castle.CastlePath commit -m 'feat: track example configuration'
```

To publish to a repository you own, create that remote repository using your hosting service, then set its URL. The commands below perform the push when run; supply your own remote and review before executing:

```powershell
$remoteUrl = Read-Host 'Git URL of your empty remote repository'
git -C $castle.CastlePath remote add origin $remoteUrl
$branch = (git -C $castle.CastlePath branch --show-current).Trim()
git -C $castle.CastlePath push --set-upstream origin $branch
```

There are no homepsick commit, push or remote-management commands. Pulling and linking never publish your local changes.

## Add an existing castle

Use a trusted Git URL, GitHub `owner/repo` shorthand, or an absolute local path:

```powershell
$source = Read-Host 'Castle Git URL or absolute local repository path'
$castle = New-HomepsickCastle -Clone -GitUrl $source -Batch
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
git -C $castle.CastlePath status --short
Enable-HomepsickCastle -CastleName $castle.CastleName -Batch -WhatIf
Enable-HomepsickCastle -CastleName $castle.CastleName -Batch -Verbose
```

Clone derives the castle name from the source basename and fails if the destination exists. It clones submodules recursively but does not link with `-Batch` alone. `-Link -Batch` combines cloning with creation of eligible missing links; inspecting first is useful for an unfamiliar castle. A repository without `home/` can still supply files through a manifest. Use `Get-HomepsickLinkPlan -CastleName $castle.CastleName` to inspect resolved destinations and conflicts, including external candidates that require opt-in. [Existing local checkout placement](castles-and-linking.md#layout-and-discovery) requires no separate registration.

## Add another managed file

For an existing file or directory in your home:

```powershell
Add-HomepsickFile -CastleName personal -Path "$HOME/.config/my tool" -WhatIf
Add-HomepsickFile -CastleName personal -Path "$HOME/.config/my tool"
```

Use a path that actually exists. Quote paths containing spaces. Directory tracking processes eligible leaves, including hidden files, leaving directories in place. Ignored files and existing castle destinations are skipped. It stages accepted entries but does not commit them.

Alternatively, add a new file directly under the castle's `home/` tree, stage it with Git, then run enable. An untracked source file is not linked, and an empty directory is not sufficient.

## Add a manifest for shared settings

An ordinary castle needs no migration. To add platform-specific placement, keep its `home/` tree and add `homepsick.json` alongside it. The following uses the existing `personal` castle, checks that both new paths are unused, and maps one shared source to Windows or Linux home locations:

```powershell
$castle = Get-HomepsickCastle -CastleName personal
$manifestPath = Join-Path $castle.CastlePath 'homepsick.json'
$settingsPath = Join-Path $castle.CastlePath 'editor_settings'
if ((Get-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue) -or
    (Get-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue)) {
    throw 'Review the existing manifest or source before adapting this example.'
}
New-Item -ItemType Directory -Path $settingsPath | Out-Null
Set-Content -LiteralPath (Join-Path $settingsPath 'settings.json') -Value '{}'
@'
{
  "version": 1,
  "roots": [
    { "source": "editor_settings", "target": "home", "into": "AppData/Roaming/Editor", "when": { "os": "windows" } },
    { "source": "editor_settings", "target": "home", "into": ".config/editor", "when": { "os": "linux" } }
  ]
}
'@ | Set-Content -LiteralPath $manifestPath
git -C $castle.CastlePath add -- homepsick.json editor_settings/settings.json
Test-HomepsickManifest -CastleName personal | Format-List IsValid, Errors, Warnings
$plan = Get-HomepsickLinkPlan -CastleName personal
$plan.Entries | Format-Table Entry, Selected, Priority, Reasons -Wrap
$plan.Winners | Format-Table SourcePath, DestinationPath, ExistingState
Enable-HomepsickCastle -CastleName personal -Batch -WhatIf
Enable-HomepsickCastle -CastleName personal -Batch
```

Existing `home/` stays an implicit root at priority 0. The matching editor root scores 100 for its explicit OS condition. Adding another file with `Add-HomepsickFile` may require `-Root editor_settings`: both the implicit home mapping and the editor mapping can contain its destination, and priority does not choose where to store a new file. Review and commit the staged manifest/settings using the earlier Git workflow.

The [manifest guide](manifests.md) covers Windows 11 Pro, Windows Server Datacenter, Ubuntu 24.04, priority overrides, external destinations and `%NAME%`/`$NAME`/`${NAME}` expansion. Environment variables expand only for selected destinations. External writes require both `outsideHome: true` and `-AllowOutsideHome`; inspect with the read-only plan before enabling them. No scripts or configuration-file contents are evaluated.

## Review and save edits

Edits through a home-directory link appear in the castle's working tree:

```powershell
$castle = Get-HomepsickCastle -CastleName personal
git -C $castle.CastlePath status --short
git -C $castle.CastlePath diff
# Stage only the files you intend to save.
git -C $castle.CastlePath add -- home/.homepsick-example
git -C $castle.CastlePath diff --cached
git -C $castle.CastlePath commit -m 'fix: adjust example configuration'
git -C $castle.CastlePath push
```

The last command requires an upstream. Use your actual managed paths, and review submodules separately if their working copies changed. A superproject records a submodule commit; it does not commit or push changes inside that submodule for you.

## Pull on another machine and relink

On another machine, install the module and clone your castle first. On subsequent visits:

```powershell
$castle = Get-HomepsickCastle -CastleName personal
git -C $castle.CastlePath status --short
Get-HomepsickCastleStatus -CastleName personal
Update-HomepsickCastle -CastleName personal -Batch
Enable-HomepsickCastle -CastleName personal -Batch -Verbose
```

Review or commit local changes before pulling; Git can reject or conflict with them. Plain `git pull` follows your configured merge/rebase policy. Existing links reveal updated content immediately. Enable handles new destinations but does not remove stale links after source renames or deletions.

`Update-HomepsickCastle -Link -Batch` can combine the steps after a qualifying changed-HEAD diff. Ordinary castles require added/renamed `home/` paths; manifest castles also recognize manifest changes and modifications, deletions or submodule-pointer changes in roots selected before or after pull. Skipped-root-only changes do not trigger relinking. It does not run linking unconditionally. Use explicit enable to repair missing links or after directly adding/staging files, changing machine facts/environment, switching branches or restoring a checkout. Forward `-AllowOutsideHome` when you intend to authorize declared external destinations.

For an occasional age-based update:

```powershell
Invoke-HomepsickCastleRefresh -CastleName personal -Days 7 -Pull -Batch
Enable-HomepsickCastle -CastleName personal -Batch
```

Refresh is based on `FETCH_HEAD` modification time, not a remote comparison. It does not install a background task. `-Batch` without `-Pull` performs no stale-castle update.

## Use multiple castles

```powershell
Get-HomepsickCastle
foreach ($name in @('personal', 'work')) {
    Enable-HomepsickCastle -CastleName $name -Batch -Verbose
}
Get-HomepsickCastleStatus -All
```

The named castles must already exist. Distinct files can share ordinary destination directories. If both castles target the same path, the second command above skips the first link. Manifest conditions and priorities apply within each castle; there is no priority setting between castles. `Enable-HomepsickCastle` with no name applies to all discovered castles, and its enumeration order is not a precedence contract. See [collisions](castles-and-linking.md#collisions-and-ordering).

## Stop managing a file or castle

There is no unlink command. Do not delete the source before preserving data you want to keep. For a **working file link** in the example castle, the following verifies that it points directly to the expected source, copies its content, and replaces only that link with a regular file:

```powershell
$castle = Get-HomepsickCastle -CastleName personal
$path = Join-Path $HOME '.homepsick-example'
$sourcePath = Join-Path $castle.CastleSymRoot '.homepsick-example'
$item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
if ($item.LinkType -ne 'SymbolicLink') { throw 'Expected a symbolic link.' }
$target = [IO.Path]::GetFullPath([IO.Path]::Combine(
    (Split-Path -Parent $path), @($item.Target)[0]))
if ($target -cne $sourcePath) { throw 'Inspect the unexpected link target first.' }
$savedPath = $path + '.saved-' + [guid]::NewGuid()
Copy-Item -LiteralPath $path -Destination $savedPath -ErrorAction Stop
Get-Item -LiteralPath $savedPath -Force | Select-Object FullName, LinkType, Length
Get-Content -LiteralPath $savedPath
```

Verify that the saved file is regular and contains the expected content. The `git rm` step below assumes the castle source has been committed and is unmodified. Review and commit any intended source changes first; Git will refuse removal of staged or locally modified content rather than discard it. Then:

```powershell
Remove-Item -LiteralPath $path -Force -ErrorAction Stop
Move-Item -LiteralPath $savedPath -Destination $path -ErrorAction Stop
git -C $castle.CastlePath rm -- home/.homepsick-example
git -C $castle.CastlePath diff --cached
```

Removing the source from Git stops future linking after you commit the removal. Commit and push when you want that removal synchronized. Other machines still need their old links retired manually. Leaving the source tracked means a future forced enable can replace your restored regular file.

This example applies to a working file link, not a directory link, broken link or arbitrary chain. Preserve directories separately and inspect their resolved contents before removing any link. To remove a castle, retire all links you want to keep, inspect untracked and uncommitted data and submodules, then archive the repository outside `.homesick/repos` or remove it manually. Removing only the module leaves castles and links in place; removing only a castle leaves broken links. Nothing automatically removes empty destination directories.
