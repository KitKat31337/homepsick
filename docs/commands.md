# Public command reference

[Documentation index](README.md#documentation) · [Everyday workflows](getting-started.md)

The module manifest exports exactly the ten functions below, with **no public aliases**. There is no umbrella `homepsick` command. Private helpers and internal result classes are implementation details. This page describes every exported command. Run `Get-Command -Module Homepsick -Syntax` or `Get-Help <command> -Full` after importing the module for metadata, parameter help and examples.

Syntax uses `[]` for optional arguments and `<...>` for values. All commands accept PowerShell common parameters such as `-Verbose` and `-ErrorAction`; only the commands explicitly showing `-WhatIf` and `-Confirm` implement `ShouldProcess`. Only `Add-HomepsickFile -Path` accepts pipeline input, by value. Castle names are scalar strings, not arrays or pipeline selections.

| Command | Purpose |
| --- | --- |
| [New-HomepsickCastle](#new-homepsickcastle) | Create or clone a castle |
| [Get-HomepsickCastle](#get-homepsickcastle) | Discover castles and inspect their managed entries |
| [Add-HomepsickFile](#add-homepsickfile) | Move files into a castle, link them back and stage them |
| [Enable-HomepsickCastle](#enable-homepsickcastle) | Link winning tracked files to selected destinations |
| [Test-HomepsickManifest](#test-homepsickmanifest) | Validate declarations and selected file resolution without writes |
| [Get-HomepsickLinkPlan](#get-homepsicklinkplan) | Preview facts, selected roots, winners, ties and conflicts |
| [Get-HomepsickCastleStatus](#get-homepsickcastlestatus) | Compare local and upstream Git state |
| [Update-HomepsickCastle](#update-homepsickcastle) | Pull changes and update submodules |
| [Invoke-HomepsickCastleRefresh](#invoke-homepsickcastlerefresh) | Update castles according to fetch age |
| [Enter-HomepsickCastle](#enter-homepsickcastle) | Enter the castle repository directory |

## Scope, prompts and errors

Enable, status, update and refresh have two parameter sets: `-CastleName <string>` for one castle, or optional `-All` for all discovered castles. **Omitting both also selects all castles.** Combining `-All` and `-CastleName` is invalid. There is no wildcard expansion or multi-name parameter; loop explicitly for a subset.

`-Batch` suppresses the homepsick interaction at the places documented below. It does not suppress Git authentication, all possible Git interactions, or PowerShell `ShouldProcess` confirmations imposed by `-Confirm` or `$ConfirmPreference`.

`ShouldContinue` prompts (link offers, conflicts and refresh offers) are separate from `ShouldProcess`: `-Confirm:$false` does not answer them. A plain link `-WhatIf` may still ask about an existing conflict before reaching `ShouldProcess`. Use `-Batch -WhatIf` to preview missing links, or `-Force -WhatIf` to preview replacements without deleting anything.

Missing named castles and invalid names throw. Git failures normally throw with command, repository and captured error output; some probes deliberately tolerate failures. Filesystem cmdlets can emit nonterminating errors under normal PowerShell preferences. For automation, use `-ErrorAction Stop` and inspect the resulting files and Git state after a failure. Multi-castle and multi-file operations are not transactions and can leave earlier successful changes in place.

Manifest validation and planning are read only. Errors include codes and root identifiers such as `roots[2]`; linking rejects an invalid whole-castle plan before creating that castle's links. Ordinary existing destination conflicts are reported separately and use the conflict policy below. See [manifest conditions, destinations and priorities](manifests.md).

## New-HomepsickCastle

Create an empty Git castle or clone a repository into the fixed castle storage location.

```text
New-HomepsickCastle -CastleName <string> [-WhatIf] [-Confirm] [<CommonParameters>]
New-HomepsickCastle -Clone -GitUrl <string> [-Link] [-Batch] [-AllowOutsideHome] [-WhatIf] [-Confirm] [<CommonParameters>]
```

- **Init:** `-CastleName` is required. Creates the repository directory, runs `git init`, and creates `home/`. It does not add a remote, stage files or create an initial commit.
- **Clone:** both `-Clone` and `-GitUrl` are required. Accepts Git-supported HTTPS/SSH URLs and local paths. A string matching `owner/repo` with an owner made of letters, digits or hyphens and a repository made of letters, digits, underscores, dots or hyphens, without a trailing `.git`, becomes `https://github.com/owner/repo.git`. Use an absolute path for local sources to avoid shorthand ambiguity and Git's `-C` relative-path context.
- The clone name is the final component after `/`, `\` or `:`, with trailing separators and one trailing `.git` removed. There is no clone-name override; `-CastleName` cannot be combined with clone parameters. An existing destination, including a broken symbolic link, causes an error. Choose a different source basename or arrange the checkout manually rather than expecting overwrite or registration.
- Clone runs `git clone --recursive`. A failed clone attempts to remove only its newly created destination. A repository without either `home/` or selected manifest content contributes no links.
- Without switches, an ordinary clone with `home/` offers to link. A manifest clone builds the shared plan and offers linking when there are winning candidates, even without `home/`; an invalid plan is reported and linking rejects it. `-Batch` suppresses the initial offer. `-Link` requests linking; `-Link -Batch` creates eligible missing links and skips conflicts. There is no forwarded `-Force`.
- Clone-only `-AllowOutsideHome` forwards authorization for destinations declared with `outsideHome: true`. Without it, external candidates remain skipped; home candidates can still link. Neither declaration nor opt-in grants filesystem permissions.
- `-WhatIf` prevents directory creation and clone/init, but Git availability, the name and the destination are checked first. `-Confirm` controls the outer operation; it is separate from linking prompts.

**Input:** no pipeline input. **Output:** one `HomepsickCastle` after successful creation, or no object when `ShouldProcess` declines. Subsequent link failures may leave the clone present.

```powershell
New-HomepsickCastle -CastleName personal
New-HomepsickCastle -Clone -GitUrl 'https://github.com/KitKat31337/homepsick.git' -Batch
```

The second example clones this project's source as a repository named `homepsick`; it has no castle `home/` tree, so it does not install dotfiles. For a real dotfile castle, supply your own trusted repository URL.

## Get-HomepsickCastle

List discovered castles or retrieve a named castle object.

```text
Get-HomepsickCastle [[-CastleName] <string>] [<CommonParameters>]
```

Without a name, returns zero or more `HomepsickCastle` objects for immediate repository directories under `<home>/.homesick/repos`, including hidden directories. With a name, returns one object if that directory exists; this explicit lookup checks directory existence, **not** Git validity or the presence of `home/`. No `-All`, pipeline input, link changes or remote access. Discovery may execute local Git probes.

| Object member | Meaning |
| --- | --- |
| `CastleName` | Name supplied or discovered |
| `CastlePath` | Repository path calculated at construction |
| `CastleSymRoot` | `<CastlePath>/home` |
| `Exists()` | Whether `CastlePath` is a directory, not a repository-integrity test |
| `GitOrigin()` | Origin URL, or an empty string when absent or the directory is missing |
| `ItemsToLink()` | Git-index inventory for ordinary castles; shared-plan winners for manifest castles, with destinations/priorities; throws for an invalid manifest plan; empty if the castle directory is missing |
| `Update()` | Pull and submodule update as described under update below; no structured output, prompts or relinking |

The public type accelerator `[HomepsickCastle]` is registered on import. Its one-string constructor calculates paths but does not create or register a castle; the parameterless constructor throws. Prefer the commands for ordinary use. Object methods have no `-WhatIf` or `-Confirm` parameters.

```powershell
Get-HomepsickCastle | Select-Object CastleName, CastlePath
$castle = Get-HomepsickCastle -CastleName personal
$castle.GitOrigin()
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
```

## Add-HomepsickFile

Move existing destination entries into a castle, stage them in Git and link them back. This **moves originals**; review a dry run and preserve important files first.

```text
Add-HomepsickFile [-CastleName] <string> [-Path] <string[]> [[-Root] <string>] [[-MachineFacts] <IDictionary>] [-AllowOutsideHome] [-WhatIf] [-Confirm] [<CommonParameters>]
```

`-CastleName` and `-Path` are required. `-Path` accepts filesystem paths or pipeline strings by value; there is no property-name binding or wildcard expansion. Relative paths resolve against the current PowerShell location. Each path must exist.

Without a manifest, files must be lexically inside the resolved home, excluding home itself, and are stored under `home/`. This legacy containment check does not resolve parent symlinks. With a manifest, paths must fall beneath applicable destination/`into` mappings. `-Root` selects a source directory or `roots[n]` identifier when several mappings qualify, regardless of their priority; otherwise `AmbiguousTrackingRoot` is an error. A manifest castle can omit `home/`.

`-AllowOutsideHome` authorizes tracking from an external destination already declared with `outsideHome: true`. `-MachineFacts` supplies a complete synthetic selection context; omitted facts are unavailable. Destination variables and filesystem rules still use the actual process and OS.

For an ordinary directory, recursively processes files and symbolic links, including hidden entries, excluding descendants whose full path contains a `.git/` component. Empty directories are not tracked; the original directory structure remains. A symbolic link is handled as an entry rather than recursively importing its target. A relative symbolic link's target is rebased when it is relocated into the castle so it still refers to the original absolute location. This can make it machine-specific.

If the corresponding castle path already exists, skips it with a verbose message, even if it is not Git-tracked or the home file differs. Git-ignored paths are left untouched with a warning. There is no `-Force`, replacement prompt or overwrite option for these skips.

For each accepted entry, creates castle parent directories, moves the entry and stages the chosen source path. Manifest tracking rebuilds the shared plan after staging, then links the actual winner; `-Root` chooses storage and does not override file priority. Initialized submodules use their own indexes. No commit or push occurs.

Manifest tracking validates source/destination parents, portable relative paths and storage boundaries before moving files. A failed entry attempts to restore its original file/link and prior index stages while preserving unrelated staged work. Previously completed entries remain changed, and filesystem failures can also prevent restoration. Rollback is per entry, not an all-input transaction or backup.

**Output:** no success objects; warnings and verbose messages as applicable. `-WhatIf` still validates inputs and checks ignore rules, but does not move, link or stage. `-Confirm` applies per entry.

```powershell
Add-HomepsickFile -CastleName personal -Path "$HOME/.gitconfig" -WhatIf
Add-HomepsickFile -CastleName personal -Path "$HOME/.gitconfig", "$HOME/.config/my tool"
@("$HOME/.example", "$HOME/.another") | Add-HomepsickFile -CastleName personal
Add-HomepsickFile -CastleName personal -Path "$HOME/.config/editor/settings.json" -Root editor_settings -WhatIf
```

The final example assumes the manifest maps `editor_settings` into `.config/editor`. See [manifest tracking](manifests.md#track-files-into-roots) for ambiguous mappings, external paths and rollback examples.

## Enable-HomepsickCastle

Create symbolic links for winning tracked entries under `home/` or selected manifest roots. It neither fetches nor stages anything.

```text
Enable-HomepsickCastle [-All] [-Force] [-Skip] [-Batch] [-AllowOutsideHome] [-MachineFacts <IDictionary>] [-WhatIf] [-Confirm] [<CommonParameters>]
Enable-HomepsickCastle -CastleName <string> [-Force] [-Skip] [-Batch] [-AllowOutsideHome] [-MachineFacts <IDictionary>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

Without a manifest or `home/`, there are no candidates. Initialized submodules contribute tracked entries recursively. The shared plan resolves manifest conditions and within-castle priorities before any links are created. Actual highest-priority ties and file/ancestor destination overlaps are errors. Static `PotentialTie` warnings remain available in validation/preview without being repeated during unambiguous linking.

`-MachineFacts` replaces detected facts completely; omitted facts stay unavailable. `-AllowOutsideHome` permits writes only to external destinations declared with `outsideHome: true`. Without opt-in those winners are skipped with a warning, including under `-Force`. Ordinary parent directories are created as needed. Already-correct links remain, and verified managed links can switch to another winner in the same manifest castle, subject to `ShouldProcess`.

Real directory conflicts always remain for review, including under `-Force`. For an ordinary conflicting file or symbolic link, including another castle's link:

1. `-Skip` always preserves it, even with `-Force`.
2. `-Batch` preserves it unless `-Force` is set.
3. Otherwise, `-Force` permits replacement without a conflict prompt; without `-Force`, asks `ShouldContinue`.
4. Approved replacement still passes `ShouldProcess`, then removes the individual entry and creates the link. No recursive directory deletion occurs. **Individual replacements have no backup or rollback.**

`-Force` does not repair a regular file blocking an ancestor directory or bypass filesystem permissions. See [collision behavior](castles-and-linking.md#collisions-and-ordering).

**Input:** no pipeline input. **Output:** no success objects; routine per-file details use `-Verbose`. `-WhatIf` prevents removal, parent creation and link creation. It may still prompt unless combined with `-Batch` or `-Force` as explained above. `-Confirm` applies to each changed destination.

```powershell
Enable-HomepsickCastle -CastleName personal -Batch -Verbose
Enable-HomepsickCastle -CastleName personal -Force -WhatIf
Enable-HomepsickCastle -All -Skip
Enable-HomepsickCastle -CastleName personal -AllowOutsideHome -Batch -WhatIf
```

## Test-HomepsickManifest

Validate a castle's optional manifest, source paths and selected file resolution without modifying files.

```text
Test-HomepsickManifest -CastleName <string> [-MachineFacts <IDictionary>] [<CommonParameters>]
Test-HomepsickManifest -RepositoryPath <string> [-MachineFacts <IDictionary>] [<CommonParameters>]
```

Exactly one of installed `-CastleName` or arbitrary `-RepositoryPath` is required. `-MachineFacts` replaces detection for condition checks and actual file ties; it does not emulate another filesystem or provide environment variables. Without a manifest the command validates the ordinary link plan and reports `HasManifest = false`.

**Input:** no pipeline input. **Output:** an object with `RepositoryPath`, `HasManifest`, `IsValid`, `Errors` and `Warnings`, rather than a boolean. Each diagnostic has `Severity`, `Code`, `Entries` and `Message`. Errors make `IsValid` false; warnings alone do not. Checks include schema/version, invalid or duplicate declarations, incompatible conditions, unsafe paths, selected missing tracked files, actual priority ties and destination overlaps. Missing root directories, roots without tracked linkable files and potential overlaps can produce warnings. Existing ordinary destination conflicts are inspected with the link-plan command instead.

No `-WhatIf`, `-Confirm` or external opt-in is needed for this read-only command. Missing variables matter only for selected targets. An external destination without runtime opt-in can still validate; an external selected mapping without its required declaration cannot.

```powershell
$validation = Test-HomepsickManifest -CastleName personal
$validation | Format-List HasManifest, IsValid
$validation.Errors | Format-Table Code, Entries, Message -Wrap
Test-HomepsickManifest -RepositoryPath ./dotfiles -MachineFacts @{
    os = 'linux'; distro = 'ubuntu'; distroVersion = '24.04'; distroLike = @('debian')
}
```

The repository example assumes an existing local castle checkout. See [schema and validation](manifests.md#validate-and-preview) for complete diagnostics and canonical conditions.

## Get-HomepsickLinkPlan

Inspect the same selection and resolution used by enable and manifest tracking, without creating links or changing the Git index.

```text
Get-HomepsickLinkPlan -CastleName <string> [-MachineFacts <IDictionary>] [-AllowOutsideHome] [<CommonParameters>]
Get-HomepsickLinkPlan -RepositoryPath <string> [-MachineFacts <IDictionary>] [-AllowOutsideHome] [<CommonParameters>]
```

Choose one installed castle or repository path. `-AllowOutsideHome` marks explicitly declared external winners as authorized in the preview; it never writes. `-MachineFacts` replaces detected facts, including the host, so unspecified fields cannot match. Selected environment variables and paths still resolve on the executing host. Selecting Windows facts on Linux can therefore produce an `InvalidDestination` for a drive path, even though its conditions match.

| Result member | Meaning |
| --- | --- |
| `MachineFacts`, `FactNotes` | Normalized facts and detection/unavailability notes |
| `Entries` | Selected and skipped roots, reasons, destination paths and calculated/overridden priorities |
| `Candidates`, `Winners`, `Shadowed`, `Ties` | Tracked sources, resolved destination files and within-castle decisions |
| `Conflicts` | Existing file/link/directory conflicts or blocked paths; inspect `ExistingState` and `Reason` |
| `Errors`, `Warnings`, `IsValid` | Structured diagnostics and whole-plan validity |
| `RepositoryPath`, `HasManifest`, `RootMappings` | Repository identity and source/destination mappings used for ownership checks |

**Input:** no pipeline input. **Output:** one structured plan. There is no `-WhatIf` or `-Confirm`; the command is always read only. `IsValid` does not mean every winner is writable: inspect `Allowed` for external opt-in and `Conflicts` for existing destinations. Equal highest-priority files are errors, never resolved by manifest order. Priorities apply within a castle, not between castles.

```powershell
$plan = Get-HomepsickLinkPlan -CastleName personal
$plan.MachineFacts
$plan.Entries | Format-Table Entry, Source, Selected, Priority, Reasons -Wrap
$plan.Candidates | Format-Table SourcePath, DestinationPath, Priority, Status, ExistingState, Reason -Wrap
Get-HomepsickLinkPlan -CastleName personal -MachineFacts @{
    os = 'windows'; windowsRelease = '11'; windowsEdition = 'pro'
}
```

## Get-HomepsickCastleStatus

Compare local `HEAD` with its live upstream branch without fetching, pulling, linking or changing the index/worktree.

```text
Get-HomepsickCastleStatus [-All] [<CommonParameters>]
Get-HomepsickCastleStatus -CastleName <string> [<CommonParameters>]
```

Reads the current branch's upstream and configured remote, then uses `git ls-remote --heads`. This can require network access and authentication. Returns one `PSCustomObject` per castle with `CastleName`, `Status`, `Upstream` (the upstream name or tolerated probe output) and `Path`.

| Status | Exact decision |
| --- | --- |
| `Uncheckable` | No resolvable upstream, or no parseable live remote branch hash, including tolerated remote failures |
| `Current` | Remote hash equals `HEAD`, and `git status --porcelain` is empty |
| `Modified` | Remote hash equals `HEAD`, and porcelain status has changes, including untracked files |
| `Ahead` | Hashes differ, remote object is present locally, and merge base equals remote hash |
| `Behind` | Hashes differ and merge base equals local hash, **or the remote object is absent locally** |
| `Diverged` | Hashes differ, remote object is present locally, and neither merge-base equality holds |

This is a summary, not a full Git diagnosis: unknown remote objects are labeled `Behind` even if histories actually diverged. Dirty working trees do not get an additional flag when status is `Ahead`, `Behind`, `Diverged` or `Uncheckable`. `git status` and `git diff` are still necessary. Missing branch metadata, unusual upstream configurations or unexpected Git errors can also make the check fail.

**Input:** no pipeline input. No `-WhatIf`, `-Confirm`, `-Force` or `-Batch`; it has no homepsick prompts.

```powershell
Get-HomepsickCastleStatus
git -C (Get-HomepsickCastle -CastleName personal).CastlePath status --short
```

## Update-HomepsickCastle

Pull from the current branch's upstream, then initialize/update submodules recursively to recorded commits.

```text
Update-HomepsickCastle [-All] [-Link] [-Batch] [-AllowOutsideHome] [-WhatIf] [-Confirm] [<CommonParameters>]
Update-HomepsickCastle -CastleName <string> [-Link] [-Batch] [-AllowOutsideHome] [-WhatIf] [-Confirm] [<CommonParameters>]
```

`HomepsickCastle.Update()` checks for an upstream. With none, skips both pull and submodule update and writes a verbose message. Otherwise runs plain `git pull` followed by `git submodule update --init --recursive`; it does not push, commit, stash, reset, choose a merge strategy or pull each submodule's branch tip independently. Git's policy, credentials and conflict behavior apply. A successful pull followed by a failed submodule update is a partial update, not a rollback.

The command records `HEAD` before and after. With no manifest before or after pull, linking remains gated on added/renamed `home/` paths across a changed `HEAD`. If either revision uses a manifest, it compares all changed paths against `homepsick.json` and the source roots selected before or after pull. Modifications, deletions and submodule-pointer changes in those roots qualify; skipped-root-only changes do not. Adding or removing the manifest qualifies too.

`-Link` then invokes linking for the entire castle, not just changed paths. `-Batch` suppresses the initial offer; `-Link -Batch` links with conflict skipping. `-AllowOutsideHome` forwards authorization for declared external destinations. Neither `-Force` nor `-Skip` is forwarded or accepted, and this command has no `-MachineFacts` parameter.

Content changes follow existing links immediately. Deletions and renames can leave stale links; updated submodules and an unchanged `HEAD` may require explicit enable. Even `-Link` does not repair missing links when its diff gate is not satisfied.

**Input:** no pipeline input. **Output:** no success objects; Git output is captured rather than streamed. `-WhatIf` prevents pulling, submodule changes and linking. `-Confirm` applies to each castle's update; interactive linking decisions remain separate. Review `git status` first and run enable separately for a predictable relink.

```powershell
Update-HomepsickCastle -CastleName personal -Batch
Enable-HomepsickCastle -CastleName personal -Batch
Update-HomepsickCastle -All -Link -Batch
Update-HomepsickCastle -CastleName personal -Link -AllowOutsideHome -Batch -WhatIf
```

## Invoke-HomepsickCastleRefresh

Conditionally pull castles based on the last fetch timestamp, rather than checking live remote state.

```text
Invoke-HomepsickCastleRefresh [-All] [-Days <int>] [-Pull] [-Batch] [-Link] [-AllowOutsideHome] [<CommonParameters>]
Invoke-HomepsickCastleRefresh -CastleName <string> [-Days <int>] [-Pull] [-Batch] [-Link] [-AllowOutsideHome] [<CommonParameters>]
```

`-Days` defaults to **7**, accepts integers 0–36500 inclusive, and measures elapsed UTC time. Resolves `FETCH_HEAD` with `git rev-parse --git-path FETCH_HEAD`. If that file exists and its `LastWriteTimeUtc` is **strictly newer** than `UtcNow.AddDays(-Days)`, skips the castle as fresh. Equality or absence makes it stale. `-Days 0` normally treats any past fetch as stale, but a future-dated marker is still fresh.

- A stale castle with `-Pull` calls update immediately, forwarding `-Link`, `-Batch` and `-AllowOutsideHome`.
- Without `-Pull`, an interactive stale castle prompts to pull. Accepting calls update, forwarding `-Link` and `-AllowOutsideHome`.
- Declining the prompt touches an existing `FETCH_HEAD` timestamp to now, deferring another reminder. If the marker is absent, none is created.
- `-Batch` without `-Pull` silently leaves stale castles alone, without touching the marker. `-Link` alone does not request a pull.

There is no scheduler: nothing runs unless you invoke this command. A recent timestamp does not prove synchronization; an external fetch or a declined prompt can make a behind castle appear fresh. Pull and link behavior, including the link diff gate, is inherited from update.

**Input:** no pipeline input. **Output:** no success objects; `-Verbose` reports fresh castles and nested update details. **No `-WhatIf`, `-Confirm`, `-Force` or `-Skip`.** Refresh can modify repository content and timestamps.

```powershell
Invoke-HomepsickCastleRefresh -CastleName personal -Days 7 -Pull -Batch
Invoke-HomepsickCastleRefresh -Days 0 -Pull -Link -Batch
```

## Enter-HomepsickCastle

Change the current PowerShell location to the castle repository root, not its `home/` subdirectory.

```text
Enter-HomepsickCastle [-CastleName] <string> [<CommonParameters>]
```

`-CastleName` is required. Uses a literal path and checks that the named castle directory exists. Does not validate Git, modify files, push a location stack entry or start a new shell. No pipeline input, success objects, `-WhatIf` or `-Confirm`.

```powershell
Push-Location
try {
    Enter-HomepsickCastle -CastleName personal
    git status --short
}
finally {
    Pop-Location
}
```
