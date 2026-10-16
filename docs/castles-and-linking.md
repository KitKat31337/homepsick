# Castles, path mapping and linking

[Documentation index](README.md#documentation) · [Command reference](commands.md)

## Layout and discovery

A castle is normally a Git working tree immediately under `<resolved-home>/.homesick/repos/<name>`, with managed entries under its literal `home/` directory. For example:

```text
<home>/.homesick/repos/personal/
├── .git/
├── .gitignore
├── README.md
└── home/
    ├── .gitconfig
    ├── .config/
    │   └── my tool/
    │       └── settings.json
    └── scripts/
        └── hello.ps1
```

| Tracked source relative to the castle | Destination |
| --- | --- |
| `home/.gitconfig` | `<home>/.gitconfig` |
| `home/.config/my tool/settings.json` | `<home>/.config/my tool/settings.json` |
| `home/scripts/hello.ps1` | `<home>/scripts/hello.ps1` |
| `README.md`, `.gitignore`, root configuration files | No destination |

The home root is [resolved from the environment](configuration.md#home-and-path-overrides). There is no separate registry: placing a repository directory in `repos/` makes it discoverable. Clone and init create that placement. To reuse an existing checkout without cloning, arrange it at that location yourself after reviewing its links and uncommitted work; moving a checkout can invalidate existing relative links. Alternatively use `New-HomepsickCastle -Clone -GitUrl <absolute-local-path> -Batch` to create a separate clone. A clone transfers committed history, not uncommitted working-copy changes or local-only configuration.

Automatic discovery enumerates immediate directories, including hidden ones, and accepts either an existing `.git` entry (directory or file) or a successful `git rev-parse --is-inside-work-tree` result of `true`. It does not recursively search arbitrary locations or require `home/`. Keep the storage tree outside another repository: the Git probe can otherwise inherit that ancestor working tree and misidentify a plain directory. Explicit `Get-HomepsickCastle -CastleName` only requires that the named directory exist.

Castle names reject blank values, `.` and `..`, slash and backslash, and the current platform's invalid filename characters. They are not arbitrary paths or patterns. Use names valid on every target OS and avoid names differing only by case.

## Which entries are managed

[Get-HomepsickTrackedFile](../src/Private/Get-HomepsickTrackedFile.ps1) reads `git ls-files --stage -z`. It selects entries with an ordinal, case-sensitive `home/` prefix. Untracked or ignored-only files are not linked. Newly staged entries count before commit. A tracked file that is missing from the working copy can still be listed and linked, producing a broken link.

Hidden and ordinary names use the same rule: dot prefixes have no special selection meaning. Spaces are supported when you quote shell arguments. Newline-containing names are currently omitted by the parser despite its use of NUL-separated Git output; avoid them. The tool does not expand variables in tracked names, transform extensions, render templates or select files by OS.

For ordinary directories, links are created for individual tracked leaves, with real parent directories created as needed. Empty directories are not represented by Git or recreated by this traversal. Multiple castles can therefore populate distinct files in the same destination directory. A Git-tracked symbolic link is linked as an entry, producing a link to the castle's link. Relative targets inside a cloned castle are not rewritten during enable; they resolve from their source location in the castle.

Git submodule entries (mode `160000`) are traversed recursively with their path prefix retained. Tracked leaves in initialized submodules beneath `home/` map to corresponding home-relative paths. Clone uses `--recursive`; update uses `submodule update --init --recursive` after a successful pull. Initialize missing submodules with Git before linking. Merely having an empty submodule directory is not evidence that it is initialized; the traversal tests directory existence, not submodule validity.

## Linking and conflicts

Links normally use a relative target from the destination's parent to the source in the castle. This makes editing the destination edit the source working copy. It does not copy or commit content. Moving the castle or changing the relative arrangement of home and storage can break the links.

`Enable-HomepsickCastle` operates on each destination leaf:

| Existing destination | Behavior |
| --- | --- |
| Absent | Create parent directories and a symbolic link |
| Symbolic link whose normalized target path equals the source | Leave alone, with an optional verbose message |
| Regular file | Conflict: skip, prompt or replace according to switches |
| Real directory at a file/link destination | Conflict: replacement removes it recursively, including its contents |
| Other symbolic link, including a broken one | Same conflict policy; replacement removes the link entry |
| Correctly targeted link whose source has disappeared | Considered already linked; enable does not restore the missing source |

The equality check normalizes the target path with `GetFullPath`; it does not compare content or resolve arbitrary chains of links. It currently uses PowerShell's case-insensitive string equality even on Linux. A link to a different source path that differs only by case can be incorrectly accepted; inspect and repair that link manually.

Conflict policy, in order:

1. `-Skip` skips any existing conflict, including with `-Force`.
2. `-Batch` skips conflicts unless `-Force` is present.
3. Without either policy, an interactive replacement prompt is shown unless `-Force` is present.
4. Replacement passes `ShouldProcess`, removes the old entry with `Remove-Item -Force -Recurse`, then creates the new link.

**Replacement has no backup, recycle-bin handling or rollback.** If link creation fails after removal, the old destination has already gone. Review and preserve conflicting data before approving replacement. `-Force` does not grant link permissions or make the operation atomic.

```powershell
# Preview creation while preserving conflicts.
Enable-HomepsickCastle -CastleName personal -Batch -WhatIf

# Inspect proposed replacements without a homepsick conflict prompt.
Enable-HomepsickCastle -CastleName personal -Force -WhatIf

# Create missing links and report skipped conflicts.
Enable-HomepsickCastle -CastleName personal -Batch -Verbose
```

`-WhatIf` prevents modifications but does not skip all validation or necessarily suppress `ShouldContinue` prompts. `-Confirm:$false` also does not answer conflict prompts. See [command prompt behavior](commands.md#scope-prompts-and-errors).

## Collisions and ordering

There is no ownership database, candidate selection, precedence score or castle priority. Two sources mapping to the same destination are ordinary conflicts. With explicitly ordered commands:

```powershell
Enable-HomepsickCastle -CastleName personal -Batch
Enable-HomepsickCastle -CastleName work -Batch
```

The first command creates missing links. The second skips a different link at the same path. If both calls use `-Force`, the later castle can replace the earlier link. The earlier castle's source is left intact, but the destination now points elsewhere. All-castle operations use directory enumeration order without declaring a priority contract; do not depend on that order to choose a winner. Select castles explicitly or give them distinct destinations.

Within a normal castle Git tree, the same exact path cannot simultaneously represent a file and its own subtree. Still, case-only names can collide on case-insensitive filesystems, and an unresolved Git index can contain multiple stages for one path. The traversal neither deduplicates those stages nor handles merge conflicts as a selection mechanism. Resolve Git conflicts and case collisions before enabling.

An **ancestor conflict** differs from a leaf conflict. If the castle has `home/.config/tool/settings` but the destination `.config` is a regular file, the command only checks the leaf `settings`; directory creation fails, even with `-Force`. It does not offer to replace the blocking ancestor. Preserve and reorganize that file manually. Existing parent directory symlinks can redirect where links are created; inspect them first, especially if they lead outside home. Homepsick does not enforce a resolved-path containment boundary.

## Adding, removing and stale links

`Add-HomepsickFile` moves existing home entries into a castle, links them back and stages them. Directory inputs are traversed into leaves; ignored paths and existing castle paths are skipped. It does not import an entire directory as a single ordinary directory link. See the [full command contract](commands.md#add-homepsickfile).

There is no unlink or cleanup command. Enable never removes a destination merely because its source was removed from the index. Pulling a deletion or rename can leave a broken old link; enabling afterward creates eligible new links but does not clean the old path. Removing a castle directory has the same problem for all its links.

To stop managing files while preserving their content, copy the resolved data to a separate regular file, verify it, remove only the confirmed link and restore the data before untracking or archiving the source. A [worked retirement example](getting-started.md#stop-managing-a-file-or-castle) explains the order. Keep your own backups: homepsick has no restore history beyond whatever you commit in Git.
