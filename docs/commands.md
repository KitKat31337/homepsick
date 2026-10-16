# Public command reference

[Documentation index](README.md#documentation) · [Everyday workflows](getting-started.md)

The manifest exports exactly the eight functions below, with **no public aliases**. There is no umbrella `homepsick` command. Private helpers are implementation details. This page provides the complete descriptions and examples for every exported command. Run `Get-Command -Module Homepsick -Syntax` or `Get-Help <command> -Full` after importing the module to inspect its current metadata; built-in help is limited to the existing source synopses and generated syntax.

Syntax uses `[]` for optional arguments and `<...>` for values. All commands accept PowerShell common parameters such as `-Verbose` and `-ErrorAction`; only the commands explicitly showing `-WhatIf` and `-Confirm` implement `ShouldProcess`. Only `Add-HomepsickFile -Path` accepts pipeline input, by value. Castle names are scalar strings, not arrays or pipeline selections.

| Command | Purpose |
| --- | --- |
| [New-HomepsickCastle](#new-homepsickcastle) | Create or clone a castle |
| [Get-HomepsickCastle](#get-homepsickcastle) | Discover castles and inspect their managed entries |
| [Add-HomepsickFile](#add-homepsickfile) | Move files into a castle, link them back and stage them |
| [Enable-HomepsickCastle](#enable-homepsickcastle) | Link tracked castle files into home |
| [Get-HomepsickCastleStatus](#get-homepsickcastlestatus) | Compare local and upstream Git state |
| [Update-HomepsickCastle](#update-homepsickcastle) | Pull changes and update submodules |
| [Invoke-HomepsickCastleRefresh](#invoke-homepsickcastlerefresh) | Update castles according to fetch age |
| [Enter-HomepsickCastle](#enter-homepsickcastle) | Enter the castle repository directory |

## Scope, prompts and errors

Enable, status, update and refresh have two parameter sets: `-CastleName <string>` for one castle, or optional `-All` for all discovered castles. **Omitting both also selects all castles.** Combining `-All` and `-CastleName` is invalid. There is no wildcard expansion or multi-name parameter; loop explicitly for a subset.

`-Batch` suppresses the homepsick interaction at the places documented below. It does not suppress Git authentication, all possible Git interactions, or PowerShell `ShouldProcess` confirmations imposed by `-Confirm` or `$ConfirmPreference`.

`ShouldContinue` prompts (link offers, conflicts and refresh offers) are separate from `ShouldProcess`: `-Confirm:$false` does not answer them. A plain link `-WhatIf` may still ask about an existing conflict before reaching `ShouldProcess`. Use `-Batch -WhatIf` to preview missing links, or `-Force -WhatIf` to preview replacements without deleting anything.

Missing named castles and invalid names throw. Git failures normally throw with command, repository and captured error output; some probes deliberately tolerate failures. Filesystem cmdlets can emit nonterminating errors under normal PowerShell preferences. For automation, use `-ErrorAction Stop` and inspect the resulting files and Git state after a failure. Multi-castle and multi-file operations are not transactions and can leave earlier successful changes in place.

## New-HomepsickCastle

Create an empty Git castle or clone a repository into the fixed castle storage location.

```text
New-HomepsickCastle -CastleName <string> [-WhatIf] [-Confirm] [<CommonParameters>]
New-HomepsickCastle -Clone -GitUrl <string> [-Link] [-Batch] [-WhatIf] [-Confirm] [<CommonParameters>]
```

- **Init:** `-CastleName` is required. Creates the repository directory, runs `git init`, and creates `home/`. It does not add a remote, stage files or create an initial commit.
- **Clone:** both `-Clone` and `-GitUrl` are required. Accepts Git-supported HTTPS/SSH URLs and local paths. A string matching `owner/repo` with an owner made of letters, digits or hyphens and a repository made of letters, digits, underscores, dots or hyphens, without a trailing `.git`, becomes `https://github.com/owner/repo.git`. Use an absolute path for local sources to avoid shorthand ambiguity and Git's `-C` relative-path context.
- The clone name is the final component after `/`, `\` or `:`, with trailing separators and one trailing `.git` removed. There is no clone-name override; `-CastleName` cannot be combined with clone parameters. An existing destination, including a broken symbolic link, causes an error. Choose a different source basename or arrange the checkout manually rather than expecting overwrite or registration.
- Clone runs `git clone --recursive`. A failed clone attempts to remove only its newly created destination. A repository without `home/` can be cloned and listed but contributes no links.
- Without switches, a clone with `home/` offers to link. `-Batch` suppresses that offer. `-Link` requests linking; `-Link -Batch` creates missing links and skips conflicts. There is no forwarded `-Force`.
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
| `ItemsToLink()` | Array of objects with `RelativePath` and `SourcePath`, derived from the Git index; an empty array if the castle directory is missing |
| `Update()` | Pull and submodule update as described under update below; no structured output, prompts or relinking |

The public type accelerator `[HomepsickCastle]` is registered on import. Its one-string constructor calculates paths but does not create or register a castle; the parameterless constructor throws. Prefer the commands for ordinary use. Object methods have no `-WhatIf` or `-Confirm` parameters.

```powershell
Get-HomepsickCastle | Select-Object CastleName, CastlePath
$castle = Get-HomepsickCastle -CastleName personal
$castle.GitOrigin()
$castle.ItemsToLink() | Format-Table RelativePath, SourcePath
```

## Add-HomepsickFile

Move existing home-directory entries into a castle, create links back and stage them in Git. This **moves originals**; review a dry run and preserve important files first.

```text
Add-HomepsickFile [-CastleName] <string> [-Path] <string[]> [-WhatIf] [-Confirm] [<CommonParameters>]
```

Both arguments are required. `-Path` accepts one or more filesystem paths or pipeline strings by value; there is no property-name binding or wildcard expansion. Relative paths resolve against the current PowerShell location. Each path must exist and be lexically inside the resolved home, excluding home itself. This is not a security boundary resolving parent symlinks.

For an ordinary directory, recursively processes files and symbolic links, including hidden entries, excluding descendants whose full path contains a `.git/` component. Empty directories are not tracked; the original directory structure remains. A symbolic link is handled as an entry rather than recursively importing its target. A relative symbolic link's target is rebased when it is relocated into the castle so it still refers to the original absolute location. This can make it machine-specific.

If the corresponding castle path already exists, skips it with a verbose message, even if it is not Git-tracked or the home file differs. Git-ignored paths are left untouched with a warning. There is no `-Force`, replacement prompt or overwrite option for these skips.

For each accepted entry, creates castle parent directories, moves the entry, creates a relative symbolic link at the original path and runs `git add -- home/<relative-path>`. No commit or push. The code attempts to restore the current original on a terminating link/staging error; this is not a complete filesystem or index transaction, and previously processed entries remain changed. Do not rely on rollback as a backup.

**Output:** no success objects; warnings and verbose messages as applicable. `-WhatIf` still validates inputs and checks ignore rules, but does not move, link or stage. `-Confirm` applies per entry.

```powershell
Add-HomepsickFile -CastleName personal -Path "$HOME/.gitconfig" -WhatIf
Add-HomepsickFile -CastleName personal -Path "$HOME/.gitconfig", "$HOME/.config/my tool"
@("$HOME/.example", "$HOME/.another") | Add-HomepsickFile -CastleName personal
```

## Enable-HomepsickCastle

Create relative symbolic links for tracked entries under `home/`. It neither fetches nor stages anything.

```text
Enable-HomepsickCastle [-All] [-Force] [-Skip] [-Batch] [-WhatIf] [-Confirm] [<CommonParameters>]
Enable-HomepsickCastle -CastleName <string> [-Force] [-Skip] [-Batch] [-WhatIf] [-Confirm] [<CommonParameters>]
```

Missing `home/` trees are skipped with verbose output. Initialized submodules contribute tracked entries recursively. Ordinary parent directories are created as needed. An already-correct link is left alone. For any other existing leaf destination, including a directory or broken link:

1. `-Skip` always preserves it, even with `-Force`.
2. `-Batch` preserves it unless `-Force` is set.
3. Otherwise, `-Force` permits replacement without a conflict prompt; without `-Force`, asks `ShouldContinue`.
4. Approved replacement still passes `ShouldProcess`, then uses `Remove-Item -Force -Recurse` before creating the link. **There is no backup or rollback; a directory's contents can be deleted.**

`-Force` does not repair a regular file blocking an ancestor directory or bypass filesystem permissions. See [collision behavior](castles-and-linking.md#collisions-and-ordering).

**Input:** no pipeline input. **Output:** no success objects; routine per-file details use `-Verbose`. `-WhatIf` prevents removal, parent creation and link creation. It may still prompt unless combined with `-Batch` or `-Force` as explained above. `-Confirm` applies to each changed destination.

```powershell
Enable-HomepsickCastle -CastleName personal -Batch -Verbose
Enable-HomepsickCastle -CastleName personal -Force -WhatIf
Enable-HomepsickCastle -All -Skip
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
Update-HomepsickCastle [-All] [-Link] [-Batch] [<CommonParameters>]
Update-HomepsickCastle -CastleName <string> [-Link] [-Batch] [<CommonParameters>]
```

`HomepsickCastle.Update()` checks for an upstream. With none, skips both pull and submodule update and writes a verbose message. Otherwise runs plain `git pull` followed by `git submodule update --init --recursive`; it does not push, commit, stash, reset, choose a merge strategy or pull each submodule's branch tip independently. Git's policy, credentials and conflict behavior apply. A successful pull followed by a failed submodule update is a partial update, not a rollback.

The command records `HEAD` before and after. Only if both are present, differ, and `git diff --name-only --diff-filter=AR <before> <after> -- home` reports added or renamed paths does it offer linking or honor `-Link`. Renames depend on Git's diff detection. `-Link` then invokes linking for the entire castle, not just new paths. `-Batch` suppresses the offer; `-Link -Batch` links with conflict skipping. Neither `-Force` nor `-Skip` is forwarded or accepted.

Content changes follow existing links immediately. Deletions and renames can leave stale links; updated submodules and an unchanged `HEAD` may require explicit enable. Even `-Link` does not repair missing links when its diff gate is not satisfied.

**Input:** no pipeline input. **Output:** no success objects; Git output is captured rather than streamed. There is **no `-WhatIf` or `-Confirm`**. Review `git status` first and run enable separately for a predictable relink.

```powershell
Update-HomepsickCastle -CastleName personal -Batch
Enable-HomepsickCastle -CastleName personal -Batch
Update-HomepsickCastle -All -Link -Batch
```

## Invoke-HomepsickCastleRefresh

Conditionally pull castles based on the last fetch timestamp, rather than checking live remote state.

```text
Invoke-HomepsickCastleRefresh [-All] [-Days <int>] [-Pull] [-Batch] [-Link] [<CommonParameters>]
Invoke-HomepsickCastleRefresh -CastleName <string> [-Days <int>] [-Pull] [-Batch] [-Link] [<CommonParameters>]
```

`-Days` defaults to **7**, accepts integers 0–36500 inclusive, and measures elapsed UTC time. Resolves `FETCH_HEAD` with `git rev-parse --git-path FETCH_HEAD`. If that file exists and its `LastWriteTimeUtc` is **strictly newer** than `UtcNow.AddDays(-Days)`, skips the castle as fresh. Equality or absence makes it stale. `-Days 0` normally treats any past fetch as stale, but a future-dated marker is still fresh.

- A stale castle with `-Pull` calls update immediately, forwarding `-Link` and `-Batch`.
- Without `-Pull`, an interactive stale castle prompts to pull. Accepting calls update, forwarding `-Link`.
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
