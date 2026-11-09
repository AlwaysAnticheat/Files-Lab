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
