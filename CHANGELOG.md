# Changelog

All notable changes to OpenNook are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Companion surfaces - host views floated beside the nook. Register one with
  `NookConfiguration.addCompanion(...)` (`NookCompanion`): anchor it below, leading,
  or trailing the chrome with an alignment and spacing (`NookCompanionAnchor`),
  show it in the compact state, the expanded state, or both
  (`NookCompanionVisibility`), and pick its shape and backdrop
  (`NookCompanionShape`, `NookCompanionBackdrop`). Companions render in the nook's
  own panel, so they move with its expand and collapse in the notch, floating, and
  auto layouts and on every display, share its backdrop (Liquid Glass included) and
  palette, share one hover region with it, and never take focus from it or get in
  the way of the global hotkey. Each carries an `opennook.companion.<id>`
  accessibility identifier, and a module's companions leave the surface when it is
  switched away. At the engine level: `Nook.companions` (`NookCompanionSurface`),
  the `nookCompanionVisibility(_:)` / `nookCompanionHidden(_:)` modifiers, and
  `\.nookCompanionIsPresented`.
- Companion styling and sizing. Every companion shares a size with its controls
  (`NookConfiguration.companionSize`, `NookCompanionSize`: small, regular, and large),
  so companions side by side are the same height, a companion beside the compact pill
  is fitted to the pill's height, and a row below the chrome hangs every surface from
  one drop so they line up. A companion is drawn by a style
  (`NookConfiguration.companionStyle`, `NookCompanionStyle`, `AnyNookCompanionStyle`):
  `NookStandardCompanionStyle` adjusts the fill, a fade away from the chrome, an edge,
  a shadow, hover (wash, scale, glow), padding, and height, with the `.standard`,
  `.faded`, `.raised`, and `.plain` presets, and a host can write its own; its shadow
  and glow are cast by the outline (`NookOutlineShadow`), so they show without a
  fill. A companion comes and goes with a presence
  (`NookConfiguration.companionPresence`, `NookCompanionPresence`: fold, fade, slide,
  pop, with its own curve), including when it is added or removed. Each
  companion can set its own style, size, and presence, a `gap` to its neighbour
  separate from its `spacing` to the chrome, and a `rowAlignment` across its row.
  `NookGlyphButtonStyle` (`.buttonStyle(.nookGlyph)`) is a glyph button in the
  chrome's palette at the companion's size, with its size, colors, shape, fill, fade,
  hover, and press adjustable. `NookBackdropView` and `\.nookChromeBackdrop` paint the
  chrome's own material in any shape, and `\.nookCompanionIsHovered` and
  `\.nookCompanionSize` reach companion content.
- `NookCompanionSource` (`NookConfiguration.companionSource`): companions a host
  adds, replaces, moves, and removes while the nook runs, with no configuration
  reload.
- Movable top bar controls: `NookTopBarConfiguration.showsKeepOpenButton` and
  `showsSettingsButton` take the lock or the gear out of the top bar without
  removing the feature, and `NookKeepOpenButton`, `NookSettingsButton`, and the
  `\.nookChromeActions` environment value (`NookChromeActions`) put them anywhere
  else, such as a companion surface.
- Rim glow: `nookRimGlow(_:)` (`NookRimGlowPreferenceKey`) lights a glowing rim
  around the chrome from any compact, expanded, or companion content - the rim's
  counterpart to the ambient color seam, for signaling state such as blue while
  work is running. Styled by `NookConfiguration.rimGlow` (`NookRimGlowStyle`,
  `Nook.rimGlowStyle`), which can also follow the ambient color. Respects Reduce
  Motion, Increase Contrast, and Reduce Transparency.
- Scroll edge fade: `NookConfiguration.scrollEdgeFade` (`NookScrollEdgeFade`,
  `Nook.scrollEdgeFade`) softens scrolling content where it meets the panel's
  edges - Apple's soft scroll edge effect on macOS 26, a gradient mask on
  macOS 15. The built-in Settings screen and the `NookComponents` shelf follow it;
  host scroll views opt in with `nookScrollEdgeFade(axes:)`, or fade on their own
  with `nookScrollEdgeFade(_:axes:)`.
- `Examples/CompanionNook` (`swift run CompanionNook`), and the site guides
  "Companion surfaces" and "Rim glow and edge fade".
- Live configuration: `AppCoordinator.reloadActiveConfiguration()` calls the active
  module's `makeConfiguration()` again and applies the result to the running
  chrome - content, theme, top bar, tokens, width, hooks, companions, rim glow,
  scroll edge fade, `style`, and `transitions` - without a module switch, and
  `AppCoordinator.replaceChromeBehavior(_:)` changes the host's hover behavior and
  backdrop resolver at runtime (`ModuleHost.chromeBehavior` now reads back the live
  value). `NookConfiguration.defaultStyle` names the framework's own chrome shape.
  At the engine level, `Nook.style` is now settable and published, and
  `Nook.hoverBehavior` is settable, so a running chrome restyles in place.
- Notch clearance: `NookTopBarConfiguration.notchClearance` (`NookNotchClearance`)
  keeps the home and Settings content clear of the hardware notch. With the default,
  `.automatic`, the content starts below the notch whether or not the top bar is
  showing, and the top bar grows to fill the band beside the notch when the notch is
  taller than the bar; `.manual` lets the content run up beside the notch.
  `nookNotchAccessories(leading:trailing:)` puts views such as icons beside the notch,
  `NookNotchRow` splits a row around it, and `\.nookNotchCutout` (`NookNotchCutout`)
  tells content where the notch falls in its frame. See "Layout and content insets".
- `Examples/PlaygroundNook` (`swift run PlaygroundNook`): a live customization
  playground. A controls window changes the running nook's appearance, theme, size
  and shape, typography and motion, top bar and notch clearance, companion surfaces,
  rim glow, scroll edge fade, and hover behavior, and exports the result as Swift
  that sets only what differs from the defaults, or as a JSON preset it can open
  again (`--preset <file>`). Companions are composed from items - glyph buttons,
  labels, and the lock and gear - with shared and per-companion size, style, and
  presence, and export as real SwiftUI views. Its settings model and exporters are
  the tested `PlaygroundNookCore` target. New site guide: "Playground".

- Typing in the nook. A click on a text input in the nook always gives the nook the
  keyboard, including after the person has used another app, and the nook hands the
  keyboard back to the app in front when it collapses or hides. To type without a
  click, `AppCoordinator.takeNookKeyboardFocus()` and `releaseNookKeyboardFocus()`
  (with `nookHasKeyboardFocus`), `NookChromeActions.takeKeyboardFocus` and
  `releaseKeyboardFocus` for views, and `Nook.takeKeyboardFocus()`,
  `releaseKeyboardFocus()`, and `hasKeyboardFocus` at the engine level.
  `NookChromeBehavior.keyboard` (`NookKeyboardBehavior`) opts the global shortcut in
  to taking the keyboard when it opens the nook (`shortcutTakesKeyboardFocus`, off by
  default). New site guide: "Typing in the nook".
- Editing shortcuts in text inputs: at launch the framework installs a hidden Edit
  menu (`NookEditMenu`) with Undo, Redo, Cut, Copy, Paste, and Select All when the
  app's main menu has none, so Command-Z, Shift-Command-Z, and Command-X, C, V, and A
  work. `NookKeyboardBehavior.installsEditMenu` turns it off.
- `nookFocusOnAppear(_:)` gives the nook the keyboard and focuses a text input as it
  appears, which setting its `FocusState` from `onAppear`, `task`, or `defaultFocus`
  does not do in the nook.
- `nookKeepsExpanded(whileFocused:)` holds the nook open while a text input has focus
  and the nook has the keyboard, from the same `FocusState` binding the input uses, and
  `\.nookHasKeyboardFocus` tells content whether typing reaches the nook.
- `AppCoordinator.nookWindow` and `Nook.window`: the nook's panel right now, `nil`
  while hidden, for window-level work the framework has no API for.
- Composable Settings. The built-in screen's groups are public views a host's own
  Settings screen can reuse - `NookDisplaySettingsSection`,
  `NookShortcutSettingsSection`, `NookResetSettingsSection`, and
  `NookAboutSettingsSection`, beside `NookAppearanceSettingsSection` - drawn in the
  framework's collapsible `NookSettingsGroup`. `NookConfiguration.settingsGroups`
  (`NookSettingsGroups`) hides individual groups of the built-in screen, and
  `NookChromeActions.resetSettings` runs the reset from host controls.
- The notch fade: `NookChromeBehavior.glassShading = .notchFade` (`NookGlassShading`)
  shades Liquid Glass black where the panel meets the notch, clearing toward the
  bottom (white for light chrome), scaled by Glass strength and replaced by a solid
  fill under Reduce Transparency, with no backdrop resolver. The gradient is
  `NookBackdrop.LiquidGlass.Shading.notchFade(_:strength:)`. Companions inheriting
  the chrome's backdrop get their own even version of it: `Nook.companionBackdrop`,
  `NookChromeBehavior.companionBackdrop` for a host resolver, and
  `NookBackdropMapping.companionBackdrop(...)`.
- PlaygroundNook's Behavior page picks the glass shading (Even or Notch fade), and the
  Swift export and presets carry it.
- `NookHostBranding.menuBarIcon` gives the menu-bar status item an icon other than the
  brand mark, and `NookHostBranding.symbol(_:)` builds a mark or icon from an SF Symbol.
- `AppState.preferenceDefaults` reads the host's launch defaults back, and
  `resetAppearancePreferences()`, `resetHotkey()`, and `resetDisplayPreference()`
  return one preference to them.
- Per-state chrome backdrops. The chrome re-resolves what it paints every time it
  expands and collapses, so the collapsed pill and the expanded panel no longer have
  to share one backdrop. `NookChromeBehavior.backdrop` and `companionBackdrop` now
  receive a `NookBackdropContext` carrying the chrome's `NookState` and its resolved
  `NookChromeForm` beside the appearance state they already got, and
  `NookBackdropMapping.notchBackdrop(...)` / `companionBackdrop(...)` take an optional
  `state:`. A hide re-resolves nothing, so no repaint lands under a panel that is
  fading out.
- `Nook.layoutForm` (`NookChromeForm`, previously internal) is readable and published:
  the layout `presentation` resolved to on the current screen, since `.auto` lands on
  the notch form or the floating one depending on the display.

### Changed

- `NookGlassShading.notchFade` paints the collapsed chrome solid - the flat notch
  color, black or white for light chrome - and fades only the expanded panel.
  Collapsed, a notch-fused panel is the hardware notch's own height with roughly three
  quarters of its width behind the camera, so the fade had nothing to shade there but
  the two small wings either side of it; solid is the look it was after. Companions
  inheriting the chrome follow: they take their own even glass under the expanded fade
  as before, and the chrome's own backdrop while it is collapsed. `.even` (the default)
  is unchanged in every state, so a host that sets no shading renders exactly as before.
- **Breaking:** `NookChromeBehavior.BackdropResolver` and `CompanionBackdropResolver`
  take a single `NookBackdropContext` instead of three arguments. A resolver reads its
  old parameters off the context - `{ preferences, scheme, rt in ... }` becomes
  `{ context in ... }` with `context.preferences`, `context.colorScheme`, and
  `context.reduceTransparency` - and gains `context.state` and `context.form`. Hosts
  that only set `glassShading` are unaffected, and future additions are new properties
  rather than another signature change.
- Appearance preferences are stored field by field. Changing one field persists only
  that field, so every field the person never changed keeps following the host's
  `preferenceDefaults`, including a default a later build changes. Before, changing
  any field (the keep-open lock, say) saved the whole record and froze every other
  field at the default of that moment. A record saved by an earlier build
  (`opennook.appearance.v1`) is migrated once on launch: its fields that match the
  host's current defaults count as never chosen, and the rest are kept, so nobody's
  appearance changes on upgrade. Choices now live under
  `opennook.appearance.choices.v2`.
- "Reset All Settings" (`AppCoordinator.resetAllSettingsToDefaults()`) returns
  appearance, the global shortcut, and the display to the host's `preferenceDefaults`
  and forgets the person's choices. It used to write the framework's own defaults,
  ignoring the host's.
- When the person clicks into another app, a text input in the nook gives up focus,
  so `@FocusState` turns `false` and anything held open by it lets go.
- Inside companion content, `\.nookChromeBackdrop` is the backdrop companions inherit,
  which is the chrome's own unless `Nook.companionBackdrop` is set.
- The GitHub repository moved to [twinkling-reality/opennook](https://github.com/twinkling-reality/opennook) (organization rename from `twinkling-reality`). Update your Swift package URL; GitHub redirects the old `twinkling-reality/opennook` path.


- The top bar's collapsed leading cluster (shown in Settings and while a module
  breadcrumb is active) keeps the host identity glyph - the configured
  `leadingIcon`, or the brand mark when none is set - instead of swapping to a
  bare `chevron.left`. The old chevron sat next to the breadcrumb's
  `chevron.right` separator and misread as browser back/forward buttons; the bar
  now reads as a breadcrumb (`[mark] > Settings`), and the glyph is still the
  click-to-go-back control with the same hover title reveal.
- The notch panel grows downward when a companion surface hangs below the top half
  of the screen. Without companions it keeps its size, and the file-drag region
  stays the top half of the screen either way.
- With the top bar hidden (`topBar.showsTopBar = false`), expanded content now starts
  below the hardware notch instead of beside and under it, where the notch hid the
  middle of it. Set `topBar.notchClearance = .manual` to keep the old layout.

### Fixed

- The nook closes when a hold on it ends after the pointer left: a
  `nookKeepsExpanded` pin, the keep-open lock turned off, or the settle after content
  resizes. It used to stay open until the pointer entered and left again. A nook the
  pointer never left, such as one opened with the shortcut, still stays open.
- Turning the keep-open lock off, opening the nook, or resetting settings no longer
  drops a `nookKeepsExpanded` pin that is still held.
- Recording a new global shortcut in Settings works after the person has been in
  another app: the recorder takes the keyboard it listens with.
- The `NookTopBarConfiguration.showsTopBar` documentation said Settings and the lock
  were unreachable from the chrome with the top bar off; `NookSettingsButton` and
  `NookKeepOpenButton` reach them from a companion or home view.
- Light theme + Liquid Glass no longer turns illegible over dark wallpapers or
  windows. Apple's macOS 26 glass material adapts its light/dark treatment to
  whatever is behind the notch, so neutral glass could flip dark underneath
  forced-light (dark) chrome text. The default mapping now anchors the glass to
  the resolved theme - a white tint plus a white legibility scrim in light, and
  the mirrored black tint in dark - both scaled by the existing Glass strength
  slider. Hosts with a custom backdrop resolver are unaffected.
- `Examples/ActivityNook` now shows its sample activities. It started its demo
  timer in `onActivate()`, which the host calls only on a module switch and never
  for the module it launches with, so the demo sat on "Activity queue idle". The
  module now starts the timer when it is built. The `NookModule.onActivate()`
  documentation and the Multiple modules guide now say that the launch module gets
  no `onActivate()`.
- A `Nook` built with its public initializer - the one `AppCoordinator` uses - now
  ends its layout-resize grace when it leaves the expanded state, as the
  no-compact-content initializer already did. Before, a collapse could leave
  `isLayoutGraceActive` set for the rest of the grace window (about 0.6 s), so the
  coordinator kept reporting the user as engaged (`isUserEngaged`) and held back
  surface claims such as activity-queue takeovers after the user had left.
- The launch smoke check (`AppCoordinator.runLaunchSmokeTest()`, run by
  `Scripts/smoke-examples.sh` and CI) now waits for `AppState.isNookVisible` to
  follow the expanded surface. It read the value once, right as the surface
  expanded, but the value catches up a run-loop pass later, so a few percent of
  runs failed at random.
- The package builds without warnings: `NookExpandedView` uses the current
  `onChange(of:)` overload, and doc comment links that could not resolve (links to
  another module or to internal symbols) are plain code, so the DocC build is
  clean too.

## [0.4.0] - 2026-06-29

### Added

- `NookChromeTypography` - a host-tunable token type for the framework's own
  fonts. Set via `NookConfiguration.typography`; defaults reproduce the framework
  exactly, and the resolved `fontDesign` still cascades over the roles. Restyles
  framework text without forking, the typography counterpart to the existing color
  (`NookResolvedTheme`) and layout (`NookChromeMetrics`) seams. Roles cover the
  top bar, compact pill, and status banner, plus the placeholder home, the
  built-in Settings panel, and the optional `NookComponents` add-ons.
- `NookChromeMetrics` gained the element-level dimensions, corner radii, spacing,
  and emphasis-opacity values that were previously baked into the framework views -
  the chrome (header icons, leading brand mark, compact pill, status banner), the
  placeholder home, the Settings panel (rows, pickers, the shortcut key cap, the
  accent swatches, the disclosure section), and the `NookComponents` shelf,
  activity card, and volume glyph. All new fields default to today's values, so
  the change is additive and non-breaking.

### Changed

- The framework views now read every font, size, radius, spacing, and opacity from
  `NookChromeTypography` / `NookChromeMetrics` instead of inline literals - the
  chrome (top bar, header icons, compact pill, status banner), the placeholder
  home, the built-in Settings panel, and the `NookComponents` add-ons. No visual
  change at the defaults; a host can now restyle any of these surfaces through
  public API only. (A few intentionally-structural literals stay inline: motion
  spring/offset magnitudes, the breadcrumb gradient mask, the fixed severity and
  destructive-action colors, and zero-floor spacers.)
- The GitHub repository moved to [athledev-labs/opennook](https://github.com/athledev-labs/opennook).
  Update your Swift package URL; GitHub redirects the old `glendonC/opennook` path
  for a transition period.

## [0.3.1] - 2026-06-12

### Fixed

- The Liquid Glass surface style now builds on Xcode versions earlier than 26.
  Its `Glass` / `.glassEffect` use (the macOS 26 SDK) is compile-gated behind
  `#if compiler(>=6.2)`, so an earlier toolchain compiles the pre-Tahoe
  approximation instead of failing with "cannot find 'Glass' in scope"; on
  macOS 26 the real material is still used at runtime.
- Cleared a Swift 6 concurrency warning on `NookFilePickerKey.defaultValue` (a
  `@MainActor`-isolated value held in a nonisolated static): the inert default
  picker now has a `nonisolated init`. No behavior change.

## [0.3.0] - 2026-06-12

The chrome-customization release. v0.3.0 opens up the framework chrome through
additive, non-breaking seams - every default still reproduces the demo exactly,
so hosts opt in only where they need to. It also adds a Liquid Glass surface
style, a chrome-derived safe-area for host content, and the module drill-in
breadcrumb. This is the surface downstream hosts have been depending on from
`main`; pin to `0.3.0` instead.

This is still 0.x: the public API is not frozen. Pin to a tag.

### Added

- Liquid Glass surface style - the real macOS 26 `glassEffect` material with a
  layered pre-Tahoe approximation fallback, gated on availability so it cannot
  crash on older systems. Host-configurable like the other surface styles.
- `NookContentInsets` / `NookEdgeInsets` - a chrome-derived safe-area so host
  content can align to the same horizontal edge as the top bar instead of
  double-padding. The per-edge expanded-content inset is configurable.
- `AppState.moduleBreadcrumb` - a drill-in breadcrumb on the host top bar for
  multi-module hosts, with an overflow fade mask constrained to the pre-notch
  region.
- `NookHostConfiguration.moduleSwitcherPlacement` / `NookModuleSwitcherPlacement`
  - choose where a multi-module host surfaces its switcher: `.menuBar` (the
  default - a "Modules" section in the menu-bar item), `.leadingCluster` (a
  compact popup folded into the top bar's leading cluster), or `.none` (cycle /
  per-module hotkeys only). The framework no longer plants switcher chrome in a
  module's expanded surface uninvited.
- `NookConfiguration.style` - host override for the chrome corner radii.
- `NookConfiguration.transitions` - host override for the expand / collapse /
  convert animation curves.
- `NookConfiguration.expandedWidth` and a host-configurable top-bar width mode
  (`.contentColumn`) - control the expanded surface width and keep the top bar
  aligned to the content column.
- `NookConfiguration.setSettings(_:)` / `settings` - inject a custom Settings
  surface in place of the built-in one (still reached via the gear).
- `setTopBarTrailingItems` - host actions placed left of the lock / gear.
- `NookChromeBehavior` - host control over hover side-effects, the cold-launch
  shimmer, and the appearance-to-backdrop mapping.
- `NookChromeLabels`, `NookChromeMetrics`, `NookChromeMotion`, and host status
  severity - localize chrome strings, tune the fixed layout values, retune the
  in-panel springs, and post info / success / warning / error banners.
- `NookPreferenceDefaults` - host-seeded launch defaults for appearance, global
  hotkey, and display target. Seed-only: a value the user changes in Settings
  always wins, and the seed is never persisted.
- `NookHostBranding` brand mark and `NookMarkView` - drop in a custom mark that
  replaces the OpenNook glyph in the top bar, About card, and menu bar; unify
  host identity across the chrome and the menu-bar item.
- `NookAccentPreset` / `accentPreset`, `NookResolvedTheme.accent`, and
  `NookResolvedTheme.fontDesign` - brand the interactive chrome tint and restyle
  the chrome's own typography. Defaults are unchanged.
- `NookAppearanceSettingsSection` - embed the framework's appearance controls
  inside a host-supplied Settings surface.
- Host file picker (`filePicker`) for modules, with file import folded into the
  shelf.
- `AppState` exposed to host-registered home and compact content.
- `NookScreenLocator.resolveIndex(preference:displays:mainIndex:)` and
  `DisplayCandidate` - the multi-display fallback policy as a pure function, now
  unit-tested without a live `NSScreen`.
- CI: an Xcode-version matrix (`latest-stable` required, `latest` non-blocking)
  and a guard so the license-header check can't pass vacuously if the source
  layout moves.

### Changed

- `NookStyle.openingAnimation` / `closingAnimation` / `conversionAnimation` are
  now `public`.
- `NookLayout` and its metrics are now `public`.
- The Settings UI was reworked alongside the expanded chrome-customization
  seams.
- The module switcher is no longer a chrome band at the top of the expanded
  surface. A multi-module host now switches from a "Modules" menu-bar section
  and the cycle / per-module hotkeys by default, leaving the surface entirely
  the module's own; opt into a compact in-surface switcher with
  `NookHostConfiguration.moduleSwitcherPlacement = .leadingCluster`.

### Fixed

- One-shot peripheral feedback cues now auto-clear when finished. Previously the
  overlay's `TimelineView` kept ticking at 60fps forever after a cue (rendering
  only `Color.clear`); the cold-launch greeting shimmer armed this on every
  launch.
- The nook no longer collapses accidentally after an in-surface layout change.
- Top-bar trailing icons now align to the row edge - the cluster is expanded
  before horizontal padding is applied, on a full-width row.
- The breadcrumb fade is constrained to the pre-notch region.
- README: corrected the persistence-prefix guidance - NookKit writes under
  `opennook.*`, not `nook.*` (only the file shelf uses `nook.shelf.*`).
- Layout-grace tests are stable under parallel CI load.

### Docs

- Added a `ChromeNook` example demonstrating the chrome-customization seams.
- Fleshed out guides for theming, multiple modules, the file shelf, the
  activity queue, and the volume glyph.
- Refreshed the README and added an LLM-friendly markdown export of the docs.

## [0.2.0] - 2026-05-23

See the [v0.2.0 release](https://github.com/twinkling-reality/opennook/releases) on
GitHub.

## [0.1.0] - 2026-05-22

Initial public release. See the
[v0.1.0 release](https://github.com/twinkling-reality/opennook/releases) on GitHub.

[Unreleased]: https://github.com/twinkling-reality/opennook/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/twinkling-reality/opennook/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/twinkling-reality/opennook/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/twinkling-reality/opennook/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/twinkling-reality/opennook/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/twinkling-reality/opennook/releases/tag/v0.1.0
