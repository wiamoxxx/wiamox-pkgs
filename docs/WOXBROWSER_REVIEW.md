# Woxbrowser: feature review and next releases

Reviewed 3 November 2026 against browser 0.2.1, commit
`29cd09a45af0d96ae2df07765bb6dd6bb3bd0af4`. This is a source review and proposed
roadmap, not an assertion that the proposed features have been implemented.
The workshop submodule previously pinned 0.1.0 (`c7574f89`); this change updates
it to the existing published 0.2.1. No browser source or browser version changes.

## What is already available

| Capability | Evidence in the browser repository | Practical limit |
| --- | --- | --- |
| Keyboard navigation, command completion, key reference | config/rc.lua; lib/binds.lua; lib/completion.lua; lib/binds_chrome.lua | Preserve the owner's existing Luakit key bindings. |
| Start page and tutorial | lib/wox_start.lua; tests/async/test_wox.lua | Start page links to a separate tutorial; it is a reference, not interactive practice. |
| Video downloads | lib/wox_external.lua; test_download_video | yt-dlp background launch; destination and completion notice, without managed progress/queue/cancel controls. |
| External video and Firefox fallback | lib/wox_external.lua | External programs handle playback/site compatibility. |
| Ordinary download manager | lib/downloads.lua; lib/downloads_chrome.lua | Shows progress and supports cancel/retry/open. Retry creates a new download; verified byte-range resume is a separate feature. Video jobs do not enter this manager. |
| Session recovery, undo closed tabs, tab search/list | lib/session.lua; lib/undoclose.lua; lib/tabmenu.lua | Recovery autosave defaults to 30 seconds; named workspace management is not enabled by default. |
| Tab groups | lib/tabgroups.lua | Module exists, but its require is commented out in config/rc.lua. This is integration work, not a module to write from scratch. |
| Bookmarks, history, quickmarks, private tabs | lib/bookmarks*.lua; lib/history.lua; lib/binds.lua | Private history is skipped; this does not make external tools or saved files private. |
| Search aliases | lib/window.lua | Google, DuckDuckGo, GitHub, Wikipedia and IMDb exist. Arch/WiamOX shortcuts would extend them. |
| Ad blocking | lib/adblock.lua; lib/adblock_chrome.lua | Bundled EasyList/EasyPrivacy; global/list switches exist. A convenient per-site control panel is missing. |
| Site settings, proxy, website-data clearing | lib/settings.lua; lib/settings_chrome.lua; lib/proxy.lua; lib/clear_data.lua | Powerful existing controls, spread across commands/settings rather than one site panel. |
| Camera/microphone prompts | lib/wox_permissions.lua; widgets/webview.c | Permission state is keyed by host, and camera/microphone share a user-media decision. Notification/location types reach Lua but have no WiamOX prompt handler. |
| PDFs, print and saved pages | lib/webview.lua; lib/viewpdf.lua; lib/binds.lua | Built-in PDF setting exists and defaults on; print, source-save and MHTML-save paths exist. Validate these rather than proposing them as absent. |
| Custom scripts/styles/form filling | lib/userscripts.lua; lib/styles.lua; lib/formfiller.lua | Not equivalent to Firefox/Chrome extensions or an encrypted password manager. |

## Recommended next features

Effort is relative scope, not a delivery estimate: small = chiefly Lua/config/UI;
medium = several modules and lifecycle tests; large = native/API or isolation work.
Keep the default browser look and established keys unless the owner chooses otherwise.

### 1. Managed video downloads — highest product priority, medium to large

Replace fire-and-forget video launches with tracked jobs: queued, downloading,
post-processing, completed, failed and cancelled. Offer percentage/speed/ETA where
reported, destination selection, open file/folder, retry, saved error details and
explicit cancellation. Keep the existing :download-video and ;d entry points.

Use a shared downloads page or a clearly separate Video section. Do not pretend
WebKitDownload can directly manage a yt-dlp subprocess. The existing native spawn
binding provides exit callbacks, not a complete asynchronous job/output API;
review clib/luakit.c before adding nonblocking output and process cancellation.

Acceptance: no frozen UI; multiple jobs remain distinguishable; close-browser
behavior is explicit; cancellation reaches the actual download/post-processing
processes; retry does not overwrite a finished file silently; interrupted partial
files are retained where yt-dlp can resume. Resume is conditional on the remote
server, available format and retained partial files, not a universal promise.

### 2. Video/audio quality chooser — medium, build on tracked jobs

Inspect available formats, then offer best, capped resolution and audio-only,
plus captions where available. Show an estimate only when size data exists.
Detect ffmpeg for separate audio/video merging and audio conversion: the current
PKGBUILD does not explicitly declare it, and gst-libav is not the ffmpeg CLI.
Check the installed yt-dlp runtime requirements as well as its presence. An
optional playlist operation must show item count/space implications and require
selection; retain the current no-playlist default.

Acceptance: missing ffmpeg/format/authentication has a useful explanation; no
silent installation or self-update; unsupported/DRM sites are explained. Defer
browser-cookie sharing until the user explicitly chooses it and its scope is clear.

### 3. Site controls and more precise permissions — high priority, medium

One keyboard-accessible panel for the current origin: camera, microphone,
JavaScript/site preferences, ad blocking, stored data and reset permissions.
Reuse existing settings, clear-data and adblock APIs. Extend the C/Lua boundary
where request-origin or separate resource information is missing.

First tighten permission semantics: scheme/host/port scoping, separate camera and
microphone decisions, requester-frame origin where the engine exposes it, clear
allow-once versus tab-session versus persistent choices. Add notification/location
prompts only with their backend integration and tests; answering a location
permission alone does not establish that a location provider works.

Acceptance: background and navigated-away requests settle correctly, cross-origin
frames cannot inherit an unrelated site's decision, private decisions are not
written to disk and do not outlive the intended private session. Existing host-only
records need an explicit conservative migration rather than broader new grants.

### 4. Interactive keyboard onboarding — high value, small to medium

Keep the existing tutorial, add a short optional practice page for o, f, tab
switching, search and Esc. Show active mode, a persistent Help entry and a small
beginner cheat sheet on the start page. Let users skip/reopen the tour. Track
practice locally without sending analytics. Do not change existing shortcuts.

Acceptance: each exercise verifies the action, works without internet, survives
resizing and teaches how to recover from Insert/Command modes. Custom start.html
and newtab.html overrides should continue to work.

### 5. Named workspaces/tab groups — medium

Enable and qualify the inherited tabgroups module. Add create/rename/switch/move
commands, an optional group indicator, and clear session restoration behavior.
Validate it with undo-close, multiple windows and private tabs before enabling
it by default. A workspace is not a cookie/account-isolation container.

### 6. Reader mode, reading list and useful saved-page controls — medium

Add a clean reading view, readable typography and a local reading list. Reuse
existing page-save/print support instead of duplicating it. Reader extraction
needs a reviewed, licensed library or a deliberately limited implementation;
CSP, dynamic pages and inaccessible documents may prevent extraction.

Acceptance: original page is easy to return to; saved/private behavior is explicit;
no network service is needed; saved-page failures do not claim offline success.

### 7. Bookmark migration and profile backup — medium

Import/export a standard bookmark HTML format with preview, duplicate handling
and rollback/backup of the existing database. Offer a selective settings/bookmarks
backup without cookies, credentials and history by default. Do not copy live
SQLite files naively; use consistent snapshots. No full browser-profile migration
or password import should be implied by bookmark import.

### 8. Per-site adblock controls and filter information — small to medium

Expose temporary and persistent exceptions for a broken site, show bundled-list
age and explain reload versus update. Verify the current parser's exception
semantics before designing the UI. Optional online list refresh should be explicit,
atomic, validated and retain a last-known-good set. The bundled offline defaults
must remain usable. Parsed-rule caching is worthwhile only after measurement and
must invalidate on list/parser-version changes.

### 9. Arch/WiamOX search shortcuts and troubleshooting — small

Add aliases such as aw (ArchWiki), ap (Arch packages), aur and optionally WiamOX
documentation. Keep Google as the owner's default. Add a diagnostics page showing
browser/WebKit/GStreamer versions and availability of mpv, yt-dlp, ffmpeg,
notification service and video decoding. Explain missing components rather than
installing software automatically. Export a redacted report without browsing URLs,
cookies, permission hosts or media-device identifiers by default.

### 10. Media/tab controls and memory management — medium to large

Add an audio indicator and mute action; verify the supported WebKit API and expose
it in C if needed. Idle-tab unloading needs a design for dirty forms, calls,
downloads, playing media and session restoration. Start with a manual unload
command and measured memory improvements. Do not claim the current process_limit
setting limits RAM: config/rc.lua itself says it has no effect since WebKit 2.26.

## Larger work to research before committing to it

- Isolated profiles/containers: distinct cookie/storage contexts, directory layout
  and instance routing; tab groups alone cannot provide isolation.
- Password-manager integration: prefer a reviewed external manager interface;
  the formfiller and HTTP-auth hooks are not a secure password vault. Autofill must
  bind to the intended origin and avoid arbitrary script access to secrets.
- Passkeys, screen sharing and modern web-app compatibility: capability-test the
  installed WebKitGTK/API/portal stack first; a Lua module alone cannot promise them.
- Firefox/Chrome extension support and Widevine streaming: not ordinary Lua
  features. Keep Firefox fallback and document actual compatibility rather than
  promising parity or implementing a second extension platform.
- Browser-to-browser/cloud sync: protocol, authentication, encryption and conflict
  resolution are a separate project. Local import/export should come first.

## Suggested sequence for owner selection

1. Ship the corrected 0.2.1 package; exercise actual YouTube playback/download,
   tutorial and camera/mic on WiamOX. This pin update does not rebuild woxKitchen.
2. Next small release: interactive onboarding, search aliases, diagnostics and
   qualification of tab groups. Reuse what already exists.
3. Next substantial release: tracked video jobs, then quality/audio/caption options.
4. Site permission/control work can be selected as a separate focused release;
   retain conservative defaults until requester-origin tests pass.
5. Reading tools and bookmark migration follow usage feedback. Containers,
   password integration and automatic tab unloading require separate design.

## Validation and publication status

This review checked actual modules, enabled rc.lua requires, native permission
and process interfaces, package dependencies and the existing async tests. It did
not execute the full browser suite or download from YouTube in this environment.
The project's documented build environment is the owner's wiamox-build distrobox;
that environment is unavailable here. No browser code was changed, so a new full
browser build was not needed to update a source pointer and documentation.

- [x] Workshop submodule updated from 0.1.0 to the existing 0.2.1 commit.
- [x] Verify the selected tree's version, runtime modules and tutorial/download tests.
- [ ] On the build machine: scripts/build.sh woxbrowser (add --install if desired).
- [ ] Run the browser's make run-tests in its documented build environment.
- [ ] Verify real playback/downloads, external apps, tutorial and permissions.
- [ ] Rebuild the ISO from the newly published woxKitchen package.
- [ ] Choose proposed features above; none are implemented by this review.
