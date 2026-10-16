# Castles, path mapping and linking

[Documentation index](README.md#documentation) · [Command reference](commands.md)

## Layout and discovery

A castle is normally a Git working tree immediately under `<resolved-home>/.homesick/repos/<name>`. Without a manifest, managed entries are under its literal `home/` directory. For example:

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

This table describes an ordinary castle. A root-level `homepsick.json` can declare additional source roots, conditions and named destinations; it is configuration, not a linked file. Such a castle can omit `home/`. See [manifest roots and destinations](manifests.md) for complete layouts and examples.

The home root is [resolved from the environment](configuration.md#home-and-path-overrides). There is no separate registry: placing a repository directory in `repos/` makes it discoverable. Clone and init create that placement. To reuse an existing checkout without cloning, arrange it at that location yourself after reviewing its links and uncommitted work; moving a checkout can invalidate existing relative links. Alternatively use `New-HomepsickCastle -Clone -GitUrl <absolute-local-path> -Batch` to create a separate clone. A clone transfers committed history, not uncommitted working-copy changes or local-only configuration.

Automatic discovery enumerates immediate directories, including hidden ones, and accepts either an existing `.git` entry (directory or file) or a successful `git rev-parse --is-inside-work-tree` result of `true`. It does not recursively search arbitrary locations or require `home/`. Keep the storage tree outside another repository: the Git probe can otherwise inherit that ancestor working tree and misidentify a plain directory. Explicit `Get-HomepsickCastle -CastleName` only requires that the named directory exist.

Castle names reject blank values, `.` and `..`, slash and backslash, and the current platform's invalid filename characters. They are not arbitrary paths or patterns. Use names valid on every target OS and avoid names differing only by case.

## Which entries are managed

[Get-HomepsickTrackedFile](../src/Private/Get-HomepsickTrackedFile.ps1) reads `git ls-files --stage -z`. Legacy enumeration selects an ordinal, case-sensitive `home/` prefix; the shared planner can enumerate the full repository for manifest roots, whose source prefixes are also case-sensitive. Untracked or ignored-only files are not linked. Newly staged entries count before commit. In manifest castles, a selected tracked source missing from the working copy is an error before linking; ordinary castles retain their legacy possibility of creating a broken link.

Hidden and ordinary names use the same rule: dot prefixes have no special selection meaning. Spaces are supported when you quote shell arguments. Newline-containing names are currently omitted by the parser despite its use of NUL-separated Git output; avoid them. Tracked filenames are literal: extension suffixes do not select an OS, and file contents are not rendered as templates. Conditions select manifest root entries; environment expansion applies only to declared destination paths.

For ordinary directories, links are created for individual tracked leaves, with real parent directories created as needed. Empty directories are not represented by Git or recreated by this traversal. Multiple castles can therefore populate distinct files in the same destination directory. A Git-tracked symbolic link is linked as an entry, producing a link to the castle's link. Relative targets inside a cloned castle are not rewritten during enable; they resolve from their source location in the castle. Manifest source symlinks must resolve to existing files inside the castle; relative targets containing `../` are supported when their final target satisfies that rule. Source directory symlinks are rejected.

Git submodule entries (mode `160000`) are traversed recursively with their path prefix retained. Tracked leaves in initialized submodules beneath `home/` or a selected manifest source root use that root's mapping. Clone uses `--recursive`; update uses `submodule update --init --recursive` after a successful pull. Initialize missing submodules with Git before linking. Merely having an empty submodule directory is not evidence that it is initialized; the traversal tests directory existence, not submodule validity.

## Manifest roots and the link plan

An existing `home/` is an implicit manifest root targeting home with priority 0. An explicit `home` entry configures it without adding a second implicit copy. Other entries declare `source`, `target`, optional `into`, conditions and optional priority overrides. The same source may map to different destinations under mutually exclusive conditions; source roots must not contain one another.

Conditions use AND across fields and OR within arrays. Default scores add only explicitly declared fields; a one-element array scores like its scalar. An integer `priority` replaces that score. For each destination file within the castle, the highest score wins and lower candidates are shadowed. Equal highest scores and file/ancestor destination overlaps are errors before linking; manifest order never breaks ties. See the [priority table](manifests.md#priority-within-a-castle).

```powershell
$plan = Get-HomepsickLinkPlan -CastleName personal
$plan.Entries | Format-Table Entry, Source, Selected, Priority, Reasons -Wrap
$plan.Candidates | Format-Table SourcePath, DestinationPath, Priority, Status, ExistingState -Wrap
$plan.Errors | Format-Table Code, Entries, Message -Wrap
```

Preview and execution use the same resolver. Inspect `Allowed` and `Conflicts` as well as `IsValid`: ordinary collisions are conflicts, while invalid paths and actual ties make the plan invalid. Named external destinations require both manifest `outsideHome: true` and runtime `-AllowOutsideHome`. Destination variables and `.`/`..` are resolved before authorization and file arbitration; they cannot bypass containment or parent-symlink checks.

## Linking and conflicts

Links normally use a relative target from the destination's parent to the source in the castle. This makes editing the destination edit the source working copy. It does not copy or commit content. Moving the castle or changing the relative arrangement of home and storage can break the links.

`Enable-HomepsickCastle` operates on each destination leaf:

| Existing destination | Behavior |
| --- | --- |
| Absent | Create parent directories and a symbolic link |
| Symbolic link whose normalized target path equals the source | Leave alone, with an optional verbose message |
| Regular file | Conflict: skip, prompt or replace according to switches |
| Real directory at a file/link destination | Conflict: left for review, including with `-Force`; never recursively deleted |
| Other symbolic link, including a broken one | Same conflict policy; replacement removes the link entry |
| Manifest link verified against another current mapping in the same castle | Managed link: update to the winning source, subject to `ShouldProcess` |
| Correctly targeted link whose source has disappeared | Legacy behavior leaves it alone; a selected missing manifest source is a preflight error |

The equality check normalizes target paths; it does not compare content or resolve arbitrary chains of links. Manifest checks use native OS path comparison and validate source symlinks separately. The no-manifest execution path retains PowerShell's case-insensitive target equality, even on Linux; a wrong case-only target can be accepted there. Inspect and repair that legacy case manually.

Verified managed links can change winners without the ordinary collision prompt. Ownership is inferred from the current target and declared source/destination relationship; there is no ownership database. Inactive roots can establish that relationship too, except an inactive environment destination remains unread unless an active entry shares its named target. Links from other castles use the ordinary conflict policy. See [managed-link safeguards](manifests.md#linking-and-external-destinations).

For ordinary file/link conflicts, policy applies in this order; real directories always remain intact:

1. `-Skip` skips any existing conflict, including with `-Force`.
2. `-Batch` skips conflicts unless `-Force` is present.
3. Without either policy, an interactive replacement prompt is shown unless `-Force` is present.
4. Replacement passes `ShouldProcess`, removes only the conflicting file or symbolic-link entry, then creates the new link. Removing a directory symbolic link does not remove its referent.

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

There is no global castle priority or ownership database. Within a manifest castle, candidates use the rules above; between different castles, the same destination remains an ordinary conflict. With explicitly ordered commands:

```powershell
Enable-HomepsickCastle -CastleName personal -Batch
Enable-HomepsickCastle -CastleName work -Batch
```

The first command creates missing links. The second skips a different link at the same path. If both calls use `-Force`, the later castle can replace the earlier link. The earlier castle's source is left intact, but the destination now points elsewhere. All-castle operations use directory enumeration order without declaring a priority contract; do not depend on that order to choose a winner. Select castles explicitly or give them distinct destinations.

Within a normal castle Git tree, the same exact path cannot simultaneously represent a file and its own subtree. Still, case-only names can collide on case-insensitive filesystems, and an unresolved Git index can contain multiple stages for one path. The shared planner deduplicates stages of the same working-copy source; it does not resolve Git merge conflicts. Resolve Git conflicts and case collisions before enabling.

An **ancestor conflict** differs from a leaf conflict. If the castle has `home/.config/tool/settings` but the destination `.config` is a regular file, `-Force` does not replace that ancestor. Manifest plans reject blocking files, symlink parents and reparse points before linking, then recheck immediately before writes. Ordinary no-manifest linking retains its older ancestor handling: directory creation may fail or a parent symlink may redirect writes. Preserve and reorganize blocking paths manually; the extra manifest safeguards do not change legacy path semantics.

## Adding, removing and stale links

`Add-HomepsickFile` moves existing destination entries into an applicable source root, links them back and stages them. Ordinary castles store home files under `home/`; manifest castles reverse selected destination/`into` mappings, requiring `-Root` when storage choices are ambiguous. Directory inputs are traversed into leaves; ignored paths and existing castle paths are skipped. It does not import an entire directory as a single ordinary directory link. See the [full command contract](commands.md#add-homepsickfile).

There is no unlink or cleanup command. Enable never removes a destination merely because its source was removed from the index. Pulling a deletion or rename can leave a broken old link; enabling afterward creates eligible new links but does not clean the old path. Removing a castle directory has the same problem for all its links.

To stop managing files while preserving their content, copy the resolved data to a separate regular file, verify it, remove only the confirmed link and restore the data before untracking or archiving the source. A [worked retirement example](getting-started.md#stop-managing-a-file-or-castle) explains the order. Keep your own backups: homepsick has no restore history beyond whatever you commit in Git.
