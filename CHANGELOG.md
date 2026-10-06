# Changelog

All notable changes to OpenNook are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Widgets and boards. A module offers small views of itself as `NookWidget`s
  (`NookConfiguration.addWidget(_:)`, or a `NookWidgetSource` for widgets that come and
  go), each with the sizes it supports (`NookWidgetSize`: small, medium, large, wide, or
  any span). `NookWidgetGrid` lays widgets out on a column grid in any home. A board
  (`NookBoardConfiguration`, `NookHostConfiguration.registerBoard(_:)`) is a module whose
  home is a grid of every loaded module's widgets, each drawn in its own module's scope;
  people reorder, resize, show, and hide them in the board's Settings, and the layout is
  saved per board (`NookWidgetPlacement`). New tokens: `widget.gap`, `widget.rowHeight`,
  `widget.board.maxHeight`, `widget.card.cornerRadius`, `widget.card.padding`,
  `widget.card.background.color`, `widget.card.border.color`, and
  `motion.widgetLayout`. New labels: `NookChromeLabels.Widgets`. New site guide: "Widgets
  and boards".

- Live activities, modeled on the Dynamic Island. Any loaded module starts a
  `NookLiveActivity` (compact leading and trailing views, a minimal view, and optionally a
  peek and an expanded view) through its own `NookLiveActivities`
  (`NookLiveActivitiesKey`, `\.nookLiveActivities`). The host's `NookActivityCenter` orders
  them by priority, alert, and recency: the first holds the pill's compact slots, and the
  next show their minimal views in capsules beside it (`NookActivityPolicy`, one capsule by
  default, `NookHostConfiguration.activityPolicy`). An activity can alert by peeking or
  opening the nook (`NookLiveActivity.Alert`), as a surface claim, so it never interrupts
  someone using the nook; from a background module only a high priority alert takes the
  surface. Opening from an activity's peek shows its expanded view under a breadcrumb.
  Activities are transient or ongoing, update in place as their views read module state,
  and end when their module unloads. `NookModuleDescriptor.loadsAtLaunch` builds a resident
  module at launch so it can run activities before it is shown. ShowcaseNook's `compact`
  scene now runs as two activities. New site guide: "Live activities".

- A peek between the compact pill and the full nook. The pill grows down into a short
  region under the notch that shows a module's peek view (`NookConfiguration.setPeek(_:)`),
  and the full nook opens on a click or once the pointer has rested on it. People choose
  in Settings, in a new "Open on hover" row: at once (the default, as before), peek first,
  or off, with a wait before anything happens, a separate wait for other displays, and a
  dwell before the peek opens the nook (`NookAppearancePreferences.openOnHover`,
  `hoverDelay`, `externalDisplayHoverDelay`, `peekDwell`). `NookChromeBehavior.hoverIntent`
  fixes the behavior in code and hides those rows. A surface claim can peek instead of
  opening (`NookSurfaceClaim.presentation`, `.peek`), and
  `NookSurfacePresenting.endTransientPresentation(_:after:)` ends a claim on a schedule that
  moves with each call, which is what a HUD needs. The engine has the same pieces
  (`Nook.peekContent`, `peek(on:)`, `endPeek()`, `isPeeking`, `NookHoverIntent`), and the
  peek's look is themeable (`shape.peek.*`, `transition.peek`, `motion.peek.enter`,
  `motion.peek.exit`). With nothing set, the nook opens and looks exactly as before. New site
  guide: "Hover and peek".

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
- Engine-level visual seams in `NookSurface`, every one defaulting to the look it
  replaces:
  - Backdrops: `NookBackdrop.gradient(_:)` (`NookBackdrop.GradientFill`: linear,
    radial, elliptical, angular), `.meshGradient(_:)` (a SwiftUI `MeshGradient`), and
    `.custom(_:)` (`NookBackdrop.Custom`, a host view identified by an id). Under
    Reduce Transparency gradients and meshes paint every color opaque, and a custom
    backdrop is told through its context. `Vibrancy.darkenColor`, and on
    `LiquidGlass` the `variant` (`.regular` or `.clear` glass on macOS 26),
    `fallbackMaterial`, `highlightColor`, and `rimWidth` of the pre-Tahoe
    approximation.
  - Shape: `NookStyle` gains `compactTopCornerRadius` / `compactBottomCornerRadius`
    (6 and 14), `floatingExpandedTopCornerRadius` /
    `floatingExpandedBottomCornerRadius` / `floatingCompactCornerRadius` (`nil` for
    the historical floating radii), and `outline` (`NookOutline`), which draws the
    chrome's path from its form and animated radii. `NookShape` is public, and chrome
    content reads the live one as `\.nookChromeShape`.
  - Transitions: `NookTransitionConfiguration.compactContentTransition` and
    `expandedContentTransition` (`NookContentTransition`: blur, scale, fade).
  - `Nook.chromeShadow` (`NookChromeShadow`): a shadow cast by the chrome's outline,
    off by default.
  - Feedback: `NookFeedbackStyle` (color, band gradient, line widths, glow, blend
    mode) through `Nook.playFeedback(_:style:duration:repeats:)`, and a
    `NookFeedback.pulse` effect.
  - `Nook.ambientWash` (`NookAmbientWash`) shapes the ambient color wash;
    `NookAmbientColorBackground(color:wash:)` paints it.
  - `NookStandardCompanionStyle.Hover.washColor` (white by default).
  - `Nook.hoverHaptic` (`NookHoverHaptic`) picks the hover haptic pattern.
- A replaceable top bar. `NookTopBarConfiguration.content` (`setContent(_:)`, or
  `NookConfiguration.setTopBar(_:)`) draws a host bar in place of the framework's,
  handed a `NookTopBarContext`: the title, view mode, breadcrumb, keep-open state, the
  modules (`NookTopBarContext.ModuleSwitcher`, for a host that put switching in the top
  bar), and `toggleKeepOpen()`, `toggleSettings()`, and `goBack()`, which do what the
  framework bar's lock, gear, and leading glyph do.
- Top-bar glyphs: `NookTopBarConfiguration.symbols` (`NookChromeSymbols`,
  `\.nookChromeSymbols`) names the lock in both states, the gear, the breadcrumb
  separator, an optional back glyph, and the module switcher's chevron and check.
  `NookKeepOpenButton` and `NookSettingsButton` draw the same glyphs.
  `NookTopBarConfiguration.leadingIconView` (`setLeadingIcon(_:)`) draws any view as the
  leading icon.
- Every string the framework draws is a label. `NookChromeLabels` gained the
  `topBar`, `settings`, `appearance`, `display`, `shortcut`, `menuBar`, and
  `components` groups and `placeholderMessage`: the Settings group titles, rows,
  captions, hints, and accessibility text, the module switcher's tooltip, the menu-bar
  item, the placeholder home, and the `NookComponents` shelf and volume glyph. Strings
  that carry a value are `{name}` templates (`NookChromeLabels.fill(_:_:)`). Labels are
  not part of theme files.
- `NookChromeMotion.settingsDisclosure`, `moduleSwitch`, and `activityCard`, with theme
  tokens `motion.settingsDisclosure`, `motion.moduleSwitch`, and `motion.activityCard`.
  The Settings groups (`NookSettingsGroup`) and `NookActivityHost` read their curve from
  the chrome; the defaults are the curves they hardcoded.

- Chrome themes. `NookTheme` describes the chrome's whole look as data - knobs
  (`accent`, `radius`, `scale`, `fontDesign`, `fontWidth`, `motion`, `soundVolume`),
  semantic tokens (color roles including `color.surface`, `color.hoverWash`, and the
  status colors `color.destructive`, `color.warning`, `color.success`; spacing, radius,
  and type scales; springs; the chrome's shape; content transitions with delay and
  stagger; ambient wash; shadow; sounds), and a component token for every
  `NookChromeMetrics`, `NookChromeTypography`, and `NookChromeMotion` field, each
  defaulting from the semantic tier. `NookTheme.standard` reproduces the framework's
  look value for value. Set one with `NookConfiguration.chromeTheme`,
  `NookHostConfiguration.chromeTheme`, or `NookApp.main(theme:home:)`; per-module
  themes are applied when a module's content reaches the surface.
- Theme files. `NookThemeCoder` reads and writes `{"format": "opennook.theme",
  "version": 1, ...}` with stable dotted token ids, references (`"{radius.lg}"`,
  `"accent"`), renames, range checks, and reported issues (`NookThemeIssue`,
  `NookThemeError`). `NookTheme(contentsOf:)` loads one.
- Live themes. `NookThemeSource` follows a theme replaced in code or a watched theme
  file (`NookThemeSource.watching(fileAt:)`), through
  `NookConfiguration.chromeThemeSource` or `NookHostConfiguration.chromeThemeSource`.
- Theme backdrops per surface style (`NookThemeBackdrops`, `NookBackdropDescription`):
  solid, vibrancy, Liquid Glass, linear, radial, elliptical, angular, and mesh
  gradients, and named custom views the host registers in
  `NookConfiguration.themeBackdrops`.
- Theme pins: a theme's `palette`, `surface`, `backdropStrength`, and
  `allowsUserAccent` override the person's choice without changing it, and the
  built-in Settings hides the pinned controls.
- `NookResolvedTheme` gained `hoverWash`, `destructive`, `warning`, and `success`
  (with the colors the chrome already used as defaults), and the environment gained
  `\.nookTheme`, `\.nookThemeTokens`, and `\.nookChromeColors`.
- `AppCoordinator.playFeedback(_:duration:repeats:)` plays a peripheral cue in the
  theme's `feedback.tint`.
- Choreography. The surface plays the theme's `motion.content.exit` when content
  leaves and holds expanded content back for `motion.content.enterDelay` after the
  chrome starts growing, each transition on its own curve when it names one. At the
  engine level: `NookContentTransition.animation` and `.delay`, and
  `NookTransitionConfiguration.expandedContentRemoval` and `.compactContentRemoval`
  (`nil` leaves the way content arrived, as before). The framework top bar arrives
  `motion.header.delay` after the content, and `nookStaggered(index:)` cascades a
  host's rows in `motion.stagger` apart. Every timing defaults to 0, so nothing moves
  differently until a theme asks.
- Sounds. A theme's `sound.open`, `sound.close`, `sound.hover`, `sound.feedback`,
  `sound.alert` (an error or warning status, a granted `.urgent` claim), and
  `sound.finish` (a success status) play on those chrome events, at the sound's
  volume times the theme's `soundVolume`, loaded once when the theme is applied and
  able to overlap. `AppCoordinator.playSound(_:)` and `NookChromeActions.playSound`
  play any of them on demand, `sound.peek` included. Settings shows a "Sounds" row
  while the theme has sounds and `allowsUserSoundToggle` is on
  (`NookChromeLabels.shortcut.soundsTitle`, `soundsOn`, `soundsOff`), saved as
  `NookAppearancePreferences.soundsEnabled` (on by default); while it is off nothing
  plays. A theme without sounds, the default, plays and loads nothing.
  `NookSoundSpec.Source` is now `Hashable`.
- `NookGlyphButtonStyle.washColor`.
- The playground builds its Theme page as a `NookTheme`, adds corner, scale, and
  motion knobs and the new color roles, exports the theme as Swift
  (`configuration.chromeTheme`) or as a theme file, and the assistant can propose the
  new fields. Presets keep format version 1.
- A read-only view of the theme token registry for tools: `NookTokenDescriptor`
  (`all`, `named(_:)`; each token's `kind`, `tier`, `defaultValue`, `scaling`, `unit`,
  and `group`), `NookTokenValue` with `NookThemeTokens.value(for:)` and
  `setValue(_:for:)` to read and write an override by id, `NookThemeTokens: Codable`
  as one flat object keyed by id, and `NookTheme.resolvedValue(for:in:)`
  (`NookResolvedTokenValue`) for what a token resolves to.
- The playground edits everything a theme can express. A new Tokens page under
  Advanced lists every token from the registry, grouped by id prefix and searchable,
  with its resolved value, whether it is overridden, an editor for its kind (colors
  as one color, a dark and light pair, the accent, or another token; numbers;
  fonts; animations; content transitions; sounds; shadows), and a reset per token.
  The Theme page adds the font width, a backdrop per material (solid, frosted,
  Liquid Glass with its variant, fallback material, highlight, and rim, and linear,
  radial, elliptical, angular, and mesh gradients with a stop editor), the theme's
  glass shading, and a Theme File card for the name, pins, sound volume, and what
  the person may change. The Effects page casts the chrome's shadow, and the Top Bar
  page sets the lock, gear, separator, and back symbols and the Settings group
  titles. Overrides are stored as theme token overrides, so they reach the nook, the
  Swift export, the preset (`settings.theme.tokens`, left out when empty; presets
  keep format version 1), and Copy Theme. The assistant can propose token overrides
  by id, checked against the registry, and theme backdrops.

- Sample theme files in `Examples/Themes`: Dusk (a linear gradient), Aurora (a mesh
  gradient), and Ember (a radial glow), each with its own accent, labels, type, and
  chrome shadow. `ShowcaseNook --theme <file>` paints any scene with one and follows
  the file as it is saved, and the agenda's day takes a theme's accent. A test loads
  every sample, so none can drift into reporting issues. The README and the Theming
  guide show the agenda scene in each, recorded live by
  `docs/images/record-themes.sh`.

### Changed

- `NookActivityQueue` keeps the nook open between consecutive cards: the next card takes
  over the same surface claim when the presenter can move a claim's end
  (`NookSurfacePresenting.endTransientPresentation(_:after:)`, which `AppCoordinator`
  does), where it used to collapse and reopen between cards. Enqueuing a card with the
  same `coalescingKey` as the one on screen now updates that card in place, for the rest
  of its dwell, instead of queueing behind it. A presenter that cannot move an end gets
  the old behavior.

- Framework strings no longer use em dashes; each became " - ": the "Stay expanded" and
  "Haptic feedback" details in Settings ("On - nook stays open after hover ends",
  "Off - closes when the pointer leaves", "On - trackpad pulse on confirmation",
  "Off - silent confirmation"), the shortcut hints ("Press a shortcut - Esc to cancel",
  "Global shortcut - click to change"), the Solid surface caption, the disconnected
  display caption, the banner preview message, and `HotkeyRegistrationFailure.message`
  ("... is unavailable - another app may be using it.").
- The framework draws its strings as written instead of looking its English literals up
  in the host app's string tables; localize with `NookConfiguration.labels`. The shelf's
  file count uses `labels.components.shelfFileCountOneFormat` and
  `shelfFileCountOtherFormat` instead of automatic grammar agreement, with the same
  English.
- A module switch, and a background module's urgent activity reaching the surface, now
  apply that module's chrome look - its theme, `style`, and `transitions` - in the
  switch animation. Before, the chrome kept the launch module's shape and curves until
  `reloadActiveConfiguration()`.
- Peripheral feedback, the launch shimmer included, follows the accent
  (`feedback.tint`), as the theming guide described. With the "System" accent this is
  the macOS accent, as before; a person who picked an accent swatch now sees it on the
  cue too.
- The built-in Settings red and orange (the reset command, shortcut warnings) and the
  glyph button's hover wash now come from the palette roles, with the same default
  colors.
- **Source compatibility:** `NookBackdrop` gained the `.gradient`, `.meshGradient`, and
  `.custom` cases, and `NookFeedback` gained `.pulse`. A host `switch` over either enum
  without a `default` clause needs one; nothing else about existing call sites changes.
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

### Deprecated

- `NookModuleDescriptor.accent` and the descriptor initializer that takes `accent:`. The
  framework never read it; give a module its own accent with its configuration's
  `chromeTheme`.

### Fixed

- An awaited `expand()` or `compact()` returns once content held back by
  `NookContentTransition.delay` has started arriving, and an expand also waits for
  the top bar held back by `motion.header.delay`, where it used to return as soon as
  the chrome settled. `NookTransitionConfiguration.expandedEntranceDuration` (0 by
  default) is how a host declares its own entrances; NookKit sets it from the header
  delay and until the last row marked with `nookStaggered(index:)` has its turn. Only
  the `await` waits: no animation and no hide dwell changes length.
- A live activity from a module that is not on screen draws its pill, peek, capsule, and
  expanded views with its own module's services (`\.appServices`, `\.nookLiveActivities`)
  instead of the displayed module's.
- Opening from a live activity's peek shows the activity's expanded view even when
  Settings was the last view open. Settings comes back with the next open, or when the
  person goes back from the activity.
- A surface claim granted while Settings is showing opens onto the claiming module's
  content instead of Settings. Settings comes back once the last claim ends, unless
  the person picked a view in the meantime or the module on screen no longer offers
  Settings.
- The 2 s deadline on `prepareForSwitchAway` is a hard limit: a module that ignores
  cancellation no longer holds up the rest of the switch away (`onDeactivate`, the
  unload, and the end of its surface denial). Its work is cancelled and left to
  finish on its own.
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
- `NookModule.prepareForSwitchAway()` now runs for every module switched away from,
  in its documented order: `prepareForSwitchAway()`, then `onDeactivate()`, then the
  unload the background policy asks for. A module with the default
  `.unloadOnSwitchAway` policy was unloaded first and never got the call, so an
  owned `NookActivityQueue` was never quiesced; a `.stayResident` module got it after
  `onDeactivate()`. The incoming module is still on screen at once, so its
  `onActivate()` now comes before the outgoing module's `onDeactivate()`. A module
  being switched away from is denied new surface claims until it is finished, and a
  quick switch back to it leaves it loaded and active.
- A background module's `.urgent` surface claim now shows that module's home,
  compact slots, companions, theme, and services while it is on top, and the surface
  goes back to the foreground module when the claim ends. It used to expand the
  surface onto the foreground module's content.
- `AppState.moduleBreadcrumb` no longer leaks from one module into the next. It
  belongs to the module whose content is on screen: a switch parks the outgoing
  module's breadcrumb, a `.stayResident` module gets its own back when the user
  returns, and an unloaded module's is dropped.
- Compact slot content gets the same chrome environment as expanded content and
  companions: the module's `\.appServices`, `\.nookHostBranding`, the chrome labels
  and motion, the theme's accent as the tint, the palette's color-scheme override,
  and active-looking controls on the non-activating panel.
- The default compact trailing glyph and the placeholder home draw the host's
  `NookHostBranding.mark`, as the documentation said, and the placeholder home titles
  itself with `hostName`. Without a host mark they look as before.
- Under the follow-system palette, a macOS light/dark switch re-resolves the backdrop
  and re-renders the theme right away; they used to stay stale until the next expand
  or collapse. A Reduce Transparency change now re-renders the theme too.
- The Settings backdrop strength slider covers `0.15` to `1`, the range the backdrop
  mapping clamps to. It stopped at `0.35`.
- Documentation: Surface materials said the default Liquid Glass is untinted (it is
  tinted toward the theme); the Theming preferences listing lacked `accentPreset` and
  `backdropStrength` and named the presentation cases wrongly; the backdrop resolver
  docs left out Liquid Glass; the launch-seed and brand-mark lists were incomplete.

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
