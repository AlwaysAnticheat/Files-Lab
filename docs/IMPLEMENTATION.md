# Implementation notes

## Upstream code

`worse_query.m` requests and consumes a sandbox extension through the container-manager query flow. `pathleak.m` enumerates inode values with `fsgetpath` and filters direct children by a literal prefix. These upstream implementations retain their original notices.

## Browser integration

`FileAccess` serializes exploit calls because they share an App Group cache/symlink location. Discovery verifies directory reads before presenting containers. Temporary discovery handles are released; active browsing scopes are retained across navigation and tab changes.

`BrowserModel` coordinates discovery, bounded directory caching, and favorites. `ActivityLog` publishes separately from browser state and persists bounded structured history using a background queue.

`FolderOrdering` handles view-independent sorting/filtering. Folder navigation uses SwiftUI NavigationStack/NavigationLink history. Search is a native UISearchBar outside the scrolling collection.

## Canonical paths

Discovery uses `/private/var/...`: the literal prefix must match the paths returned by `fsgetpath`. A positive extension handle does not establish that a protected parent directory can be listed; discovery opens specific container paths.

## Configuration

The project declares the placeholder `APP_GROUP_IDENTIFIER = group.com.example.FilesLab`. It feeds both the entitlement and the generated `FilesLabAppGroup` Info.plist value. Each developer must configure their own valid team, bundle identifier, group, and profile.

## Validation

The public source snapshot compiles for generic physical iOS without signing. Folder discovery and a child/parent listing round trip were also checked on a physical development device during implementation. Those local logs are intentionally excluded from the public repository. UI screenshots use Debug-only sample data. Preview/sharing coverage is not exhaustive across every file type.


## File changes

File operations run on the same serial queue as extension acquisition. Copying stages a new item beside its destination; replacing a file uses atomic rename, preserving the original if preparing the replacement fails. Replacing a directory is rejected. The UI confirms permanent deletion and existing-file replacement, and keeps security-scoped import access alive while a conflict decision is pending.

Directory entries preserve a symbolic link's own path separately from its browse target. Deleting or renaming a link therefore acts on the link, not the target. Successful mutations invalidate directory caches, refresh known container counts, and update or remove affected favorites.

The explicit Configuration/Info.plist carries FilesLabAppGroup; its value is expanded from APP_GROUP_IDENTIFIER. This is necessary because the generated-plist build did not emit the arbitrary custom key from an INFOPLIST_KEY setting alone. Missing or placeholder group configuration produces an actionable error.

The core fixture suite passed locally and on a physical development device. A separate attempt to create a disposable fixture in another application cache was refused by iOS; editing should not be inferred from browsing success. No existing files in that external cache were changed.


The recursive-copy guard canonicalizes the existing destination parent before comparing paths. On iOS, resolving a not-yet-created destination leaf can leave /var unresolved while the existing source resolves to /private/var; a naive prefix comparison then misses a recursive copy. Regression checks cover copying into both the source itself and an existing descendant.


## File operation progress

Copies use a coordinated source read and 1 MiB chunks, reporting actual bytes written. The temporary file remains beside the destination until the complete copy is ready; replacement then uses an atomic rename so a failed copy leaves the original in place. Folder deletion enumerates entries before modification and deletes children before their parent, reporting completed/total items. Move stages and copies the destination first, then removes the source; a failed source removal is reported without deleting the new copy. The operation status is published separately from browser state and updates are throttled on the main actor. One top progress card shows bytes or item counts with an action-specific icon. List and grid row changes use bounded SwiftUI transitions. If a deletion fails partway through, the folder is reloaded and the actual OS error is shown.
