# Repository map

What lives where in this repository, file by file. The conceptual tour of the
same modules is [Introduction](https://opennook.dev/start/introduction/) on the
docs site; this page is for reading the source.

| Directory | What it holds |
| --- | --- |
| `Sources/NookSurface/` | The notch window itself (MIT, forked from DynamicNotchKit) |
| `Sources/NookKit/` | The app chrome built on the surface |
| `Sources/NookComponents/` | Opt-in add-ons: shelf, activities, volume |
| `Sources/NookApp/` | The library entry point shared by both launch surfaces |
| `Sources/NookExecutable/` | The SPM trampoline behind `swift run Nook` |
| `App/` | The Xcode app-target trampoline, `Info.plist`, entitlements template |
| `Examples/` | Twelve example hosts, built on public API only |
| `Scripts/` | Build, format, coverage, and capture scripts |
| `site/` | The Astro + Starlight source of [opennook.dev](https://opennook.dev) |
| `docs/` | This page and the [README media](images/README.md) |

## `NookSurface` - the notch window

The low-level chrome: the notch-shaped panel itself, its shape geometry,
hover behavior, expand/compact lifecycle, the translucent backdrop, and the
shimmer feedback overlay. This is a trimmed, renamed fork of
[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) and is licensed
MIT (see [Licensing](../README.md#licensing)).

You usually don't edit `NookSurface` - you drive it through `NookKit`.

## `NookKit` - the app chrome

Everything built on top of `NookSurface` to make it feel like an app:

- `App/AppCoordinator.swift` - lifecycle (show / hide / toggle, keep-open,
  reset settings); binds the notch backdrop to appearance preferences.
- `App/AppState.swift` - `viewMode`, `appearancePreferences`, visibility
  flags. Add your product state alongside these.
- `App/AppServices.swift` - an empty dependency container. Add your services
  (clipboard, networking, persistence) here so view initializers stay put.
- `App/NookAppearancePreferences.swift` - persisted theme / surface style /
  haptics, with forwards-compatible `Codable` decoding.
- `App/Views/NookExpandedView.swift` - the framework chrome shell (top bar +
  Settings) that hosts the home view **you register** via `NookConfiguration`.
- `App/Views/NookTopBar.swift` - home glyph + lock (keep-open) + gear.
- `App/Views/Compact/CompactViews.swift` - the left/right slots flanking the
  physical notch when collapsed.
- `App/Views/Settings/` - Appearance, Display, Hotkey, and Data panels.
- `App/Views/Shared/` - reusable settings primitives.
- `System/HotkeyController.swift` - a Carbon-based global hotkey.

## `NookComponents` - optional add-ons

Opt-in components built on the layers above - depend on this product only when
you want one. It is not pulled in by `NookApp`.

- `Shelf/` - a file shelf: drop files onto the notch, they collect in a
  persistent `ShelfStore`, and you can drag them back out. Render it with
  `NookShelfView` and wire `ShelfStore.accept` into `NookConfiguration.onFileDrop`.
  See `Examples/ShelfNook` and
  [File shelf](https://opennook.dev/guides/file-shelf/).
- `Activities/` - a priority live-activity queue: `NookActivityQueue` collects
  transient activities, orders them by priority, coalesces duplicates, and
  presents each by briefly taking over the expanded surface. Bind it via
  `NookConfiguration.onReady` and render with `NookActivityHost`. The queue
  yields the surface whenever the user is engaging it. See
  `Examples/ActivityNook` and
  [Activity queue](https://opennook.dev/guides/activity-queue/).
- `Volume/` - an ambient volume glyph: `SystemVolumeObserver` tracks the default
  output device's volume and mute via public CoreAudio APIs; `NookVolumeIndicator`
  renders it as a compact-slot glyph. It shows the level - it does not intercept
  or replace Apple's volume HUD. See `Examples/VolumeNook` and
  [Volume glyph](https://opennook.dev/guides/volume-glyph/).

## The demo app

- `Sources/NookApp/NookApp.swift` - the library entry point shared by both
  launch surfaces; sets up the `NSApplication`, the coordinator, and a
  menu-bar fallback.
- `Sources/NookExecutable/main.swift` - a three-line SPM trampoline so
  `swift run Nook` works.
- `App/main.swift` + `App/Info.plist` - the Xcode app-target trampoline and
  bundle metadata, for producing a real signed `.app`.

`Nook.xcodeproj` is generated from `project.yml` by
`Scripts/regenerate-xcodeproj.sh` and is gitignored. Both launch surfaces
compile the same SwiftPM modules, so behavior cannot drift between them.

## See also

- [README](../README.md) - install, the minimal example, the module list
- [Examples](https://opennook.dev/guides/examples/) - every app under `Examples/`
- [API reference](https://opennook.dev/reference/api/) - the public surface
- [Shipping](https://opennook.dev/guides/shipping/) - bundle identity,
  persistence keys, entitlements, notarization
