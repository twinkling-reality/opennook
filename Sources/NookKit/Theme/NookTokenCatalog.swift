// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

// The token ids the framework defines. `NookTokenRegistry` holds each one's default, and the tests
// check the tables against `NookChromeMetrics`, `NookChromeTypography`, and `NookChromeMotion` so
// the ids, their defaults, and the chrome fields they feed cannot drift apart.
extension NookColorID {
    /// The most prominent text. Default white 0.95 on dark chrome, black 0.88 on light.
    public static let labelPrimary: NookColorID = "color.label.primary"
    /// Supporting text. Default white 0.62 / black 0.55.
    public static let labelSecondary: NookColorID = "color.label.secondary"
    /// The faintest readable text. Default white 0.46 / black 0.42.
    public static let labelTertiary: NookColorID = "color.label.tertiary"
    /// Decorative text. Default white 0.34 / black 0.32.
    public static let labelQuaternary: NookColorID = "color.label.quaternary"
    /// The fill behind small controls. Default white 0.055 / black 0.030, a touch stronger on an opaque surface.
    public static let fillSubtle: NookColorID = "color.fill.subtle"
    /// The hairline around small controls. Default white 0.14 / black 0.09.
    public static let strokeSubtle: NookColorID = "color.stroke.subtle"
    /// A top bar icon that is not active. Default white 0.42 / black 0.38.
    public static let iconInactive: NookColorID = "color.icon.inactive"
    /// The interactive tint. Defaults to the theme's `accent` knob, which defaults to the macOS accent.
    public static let accent: NookColorID = "color.accent"
    /// The chrome's own background on the solid surface. Default black on dark chrome, white on light.
    public static let surface: NookColorID = "color.surface"
    /// The wash a hovered control is filled with, at the control's own opacity. Default white.
    public static let hoverWash: NookColorID = "color.hoverWash"
    /// Destructive actions. Default `Color.red`.
    public static let destructive: NookColorID = "color.destructive"
    /// Warnings. Default `Color.orange`.
    public static let warning: NookColorID = "color.warning"
    /// Success. Default `Color.green`.
    public static let success: NookColorID = "color.success"
    /// The tint of the chrome's peripheral feedback cues, the launch shimmer included. Defaults to the accent.
    public static let feedbackTint: NookColorID = "feedback.tint"

    // MARK: Chrome colors (one per `NookChromeColors` field)

    /// ``NookChromeColors/bannerSeverityError``. Default the accent.
    public static let bannerSeverityError: NookColorID = "banner.severity.error.color"
    /// ``NookChromeColors/bannerSeverityWarning``. Default the accent.
    public static let bannerSeverityWarning: NookColorID = "banner.severity.warning.color"
    /// ``NookChromeColors/bannerSeverityInfo``. Default the accent.
    public static let bannerSeverityInfo: NookColorID = "banner.severity.info.color"
    /// ``NookChromeColors/bannerSeveritySuccess``. Default the accent.
    public static let bannerSeveritySuccess: NookColorID = "banner.severity.success.color"
}

extension NookDimensionID {
    // MARK: Semantic

    /// Spacing step, 2 at scale 1.
    public static let spaceXXS: NookDimensionID = "space.xxs"
    /// Spacing step, 4 at scale 1.
    public static let spaceXS: NookDimensionID = "space.xs"
    /// Spacing step, 6 at scale 1.
    public static let spaceSM: NookDimensionID = "space.sm"
    /// Spacing step, 8 at scale 1.
    public static let spaceMD: NookDimensionID = "space.md"
    /// Spacing step, 10 at scale 1.
    public static let spaceLG: NookDimensionID = "space.lg"
    /// Spacing step, 12 at scale 1.
    public static let spaceXL: NookDimensionID = "space.xl"
    /// Spacing step, 16 at scale 1.
    public static let spaceXXL: NookDimensionID = "space.xxl"
    /// Corner radius step, 6 at the standard radius.
    public static let radiusSM: NookDimensionID = "radius.sm"
    /// Corner radius step, 10 at the standard radius.
    public static let radiusMD: NookDimensionID = "radius.md"
    /// Corner radius step, 12 at the standard radius.
    public static let radiusLG: NookDimensionID = "radius.lg"
    /// Type size, 8 at scale 1.
    public static let typeSize2XS: NookDimensionID = "type.size.2xs"
    /// Type size, 9 at scale 1.
    public static let typeSizeXS: NookDimensionID = "type.size.xs"
    /// Type size, 10 at scale 1.
    public static let typeSizeSM: NookDimensionID = "type.size.sm"
    /// Type size, 11 at scale 1.
    public static let typeSizeMD: NookDimensionID = "type.size.md"
    /// Type size, 12 at scale 1.
    public static let typeSizeLG: NookDimensionID = "type.size.lg"
    /// Type size, 13 at scale 1.
    public static let typeSizeXL: NookDimensionID = "type.size.xl"
    /// Type size, 14 at scale 1.
    public static let typeSize2XL: NookDimensionID = "type.size.2xl"
    /// Type size for large glyphs, 24 at scale 1.
    public static let typeSizeDisplay: NookDimensionID = "type.size.display"
    /// The expanded chrome's corner into the notch arch. Default 19, not scaled.
    public static let chromeTopRadius: NookDimensionID = "shape.chrome.topRadius"
    /// The expanded chrome's corner at the wallpaper. Default 24 at the standard radius.
    public static let chromeBottomRadius: NookDimensionID = "shape.chrome.bottomRadius"
    /// The expanded content's top inset inside the chrome. Default 0.
    public static let chromeInsetTop: NookDimensionID = "shape.chrome.insets.top"
    /// The expanded content's bottom inset. Default 8.
    public static let chromeInsetBottom: NookDimensionID = "shape.chrome.insets.bottom"
    /// The expanded content's leading inset. Default 8.
    public static let chromeInsetLeading: NookDimensionID = "shape.chrome.insets.leading"
    /// The expanded content's trailing inset. Default 8.
    public static let chromeInsetTrailing: NookDimensionID = "shape.chrome.insets.trailing"
    /// The compact pill's corner into the notch arch. Default 6, the chrome's fixed value today.
    public static let compactTopRadius: NookDimensionID = "shape.compact.topRadius"
    /// The compact pill's lower corner. Default 14, the chrome's fixed value today.
    public static let compactBottomRadius: NookDimensionID = "shape.compact.bottomRadius"
    /// The bottom corner of the compact pill while it peeks. Default 22.
    public static let peekBottomRadius: NookDimensionID = "shape.peek.bottomRadius"
    /// The tallest the peek content makes the pill grow below its slots. Default 120.
    public static let peekMaxHeight: NookDimensionID = "shape.peek.maxHeight"
    /// The peek content's top margin inside the grown pill. Default 2.
    public static let peekInsetTop: NookDimensionID = "shape.peek.insets.top"
    /// The peek content's bottom margin. Default 10.
    public static let peekInsetBottom: NookDimensionID = "shape.peek.insets.bottom"
    /// The peek content's leading margin. Default 14.
    public static let peekInsetLeading: NookDimensionID = "shape.peek.insets.leading"
    /// The peek content's trailing margin. Default 14.
    public static let peekInsetTrailing: NookDimensionID = "shape.peek.insets.trailing"
    /// The floating panel's corner radius. Default the expanded chrome's bottom radius, as today.
    public static let floatingExpandedRadius: NookDimensionID = "shape.floating.expandedRadius"
    /// Seconds the expanded content waits, after the chrome starts growing, before entering.
    /// Default 0, as today.
    public static let contentEnterDelay: NookDimensionID = "motion.content.enterDelay"
    /// Seconds the framework top bar waits after the content starts entering. Default 0, as today.
    public static let headerDelay: NookDimensionID = "motion.header.delay"
    /// Seconds between successive rows entering, for rows marked with `nookStaggered(index:)`.
    /// Default 0, as today.
    public static let stagger: NookDimensionID = "motion.stagger"
    /// The ambient wash's opacity at the top of the expanded panel, where content lights it with
    /// `nookAmbientColor(_:)`. Default 0.34.
    public static let ambientWashTop: NookDimensionID = "ambient.wash.top"
    /// The ambient wash's opacity a third of the way down. Default 0.16.
    public static let ambientWashUpper: NookDimensionID = "ambient.wash.upper"
    /// The ambient wash's opacity two thirds of the way down. Default 0.06.
    public static let ambientWashLower: NookDimensionID = "ambient.wash.lower"
    /// The ambient wash's opacity at the bottom. Default 0.02.
    public static let ambientWashBottom: NookDimensionID = "ambient.wash.bottom"

    // MARK: Chrome metrics (one per `NookChromeMetrics` field)

    /// ``NookChromeMetrics/edgePadding``.
    public static let edgePadding: NookDimensionID = "expanded.edgePadding"
    /// ``NookChromeMetrics/expandedColumnSpacing``.
    public static let expandedColumnSpacing: NookDimensionID = "expanded.columnSpacing"
    /// ``NookChromeMetrics/topBarHeight``.
    public static let topBarHeight: NookDimensionID = "topBar.height"
    /// ``NookChromeMetrics/topBarItemSpacing``.
    public static let topBarItemSpacing: NookDimensionID = "topBar.itemSpacing"
    /// ``NookChromeMetrics/leadingClusterSpacing``.
    public static let leadingClusterSpacing: NookDimensionID = "topBar.leadingCluster.spacing"
    /// ``NookChromeMetrics/trailingClusterSpacing``.
    public static let trailingClusterSpacing: NookDimensionID = "topBar.trailingCluster.spacing"
    /// ``NookChromeMetrics/breadcrumbMaxWidth``.
    public static let breadcrumbMaxWidth: NookDimensionID = "topBar.breadcrumb.maxWidth"
    /// ``NookChromeMetrics/headerIconSize``.
    public static let headerIconSize: NookDimensionID = "topBar.headerIcon.size"
    /// ``NookChromeMetrics/headerIconCornerRadius``.
    public static let headerIconCornerRadius: NookDimensionID = "topBar.headerIcon.cornerRadius"
    /// ``NookChromeMetrics/headerIconStrokeWidth``.
    public static let headerIconStrokeWidth: NookDimensionID = "topBar.headerIcon.strokeWidth"
    /// ``NookChromeMetrics/headerIconHoverLabelOpacity``.
    public static let headerIconHoverLabelOpacity: NookDimensionID = "topBar.headerIcon.hoverLabelOpacity"
    /// ``NookChromeMetrics/brandMarkSize``.
    public static let brandMarkSize: NookDimensionID = "topBar.brandMark.size"
    /// ``NookChromeMetrics/brandMarkStrokeWidth``.
    public static let brandMarkStrokeWidth: NookDimensionID = "topBar.brandMark.strokeWidth"
    /// ``NookChromeMetrics/brandMarkOpacity``.
    public static let brandMarkOpacity: NookDimensionID = "topBar.brandMark.opacity"
    /// ``NookChromeMetrics/compactSlotSize``.
    public static let compactSlotSize: NookDimensionID = "compact.slotSize"
    /// ``NookChromeMetrics/compactLeadingGlyphOpacity``.
    public static let compactLeadingGlyphOpacity: NookDimensionID = "compact.leadingGlyph.opacity"
    /// ``NookChromeMetrics/compactTrailingMarkSize``.
    public static let compactTrailingMarkSize: NookDimensionID = "compact.trailingMark.size"
    /// ``NookChromeMetrics/compactTrailingMarkStrokeWidth``.
    public static let compactTrailingMarkStrokeWidth: NookDimensionID = "compact.trailingMark.strokeWidth"
    /// ``NookChromeMetrics/compactTrailingMarkOpacity``.
    public static let compactTrailingMarkOpacity: NookDimensionID = "compact.trailingMark.opacity"
    /// ``NookChromeMetrics/bannerRowSpacing``.
    public static let bannerRowSpacing: NookDimensionID = "banner.rowSpacing"
    /// ``NookChromeMetrics/bannerCornerRadius``.
    public static let bannerCornerRadius: NookDimensionID = "banner.cornerRadius"
    /// ``NookChromeMetrics/bannerContentHorizontalPadding``.
    public static let bannerContentHorizontalPadding: NookDimensionID = "banner.padding.horizontal"
    /// ``NookChromeMetrics/bannerContentVerticalPadding``.
    public static let bannerContentVerticalPadding: NookDimensionID = "banner.padding.vertical"
    /// ``NookChromeMetrics/bannerSeverityGlyphTopInset``.
    public static let bannerSeverityGlyphTopInset: NookDimensionID = "banner.severityGlyph.topInset"
    /// ``NookChromeMetrics/bannerDismissButtonSize``.
    public static let bannerDismissButtonSize: NookDimensionID = "banner.dismissButton.size"
    /// ``NookChromeMetrics/bannerMessageLabelOpacity``.
    public static let bannerMessageLabelOpacity: NookDimensionID = "banner.message.opacity"
    /// ``NookChromeMetrics/bannerStrokeOpacity``.
    public static let bannerStrokeOpacity: NookDimensionID = "banner.stroke.opacity"
    /// ``NookChromeMetrics/bannerStrokeWidth``.
    public static let bannerStrokeWidth: NookDimensionID = "banner.stroke.width"
    /// ``NookChromeMetrics/shelfContentSpacing``.
    public static let shelfContentSpacing: NookDimensionID = "shelf.contentSpacing"
    /// ``NookChromeMetrics/shelfRootVerticalPadding``.
    public static let shelfRootVerticalPadding: NookDimensionID = "shelf.padding.vertical"
    /// ``NookChromeMetrics/shelfDropZoneVerticalPadding``.
    public static let shelfDropZoneVerticalPadding: NookDimensionID = "shelf.dropZone.padding.vertical"
    /// ``NookChromeMetrics/shelfDropZoneCornerRadius``.
    public static let shelfDropZoneCornerRadius: NookDimensionID = "shelf.dropZone.cornerRadius"
    /// ``NookChromeMetrics/shelfDropZoneStrokeWidth``.
    public static let shelfDropZoneStrokeWidth: NookDimensionID = "shelf.dropZone.strokeWidth"
    /// ``NookChromeMetrics/shelfHeaderSpacing``.
    public static let shelfHeaderSpacing: NookDimensionID = "shelf.header.spacing"
    /// ``NookChromeMetrics/shelfChipSpacing``.
    public static let shelfChipSpacing: NookDimensionID = "shelf.chip.spacing"
    /// ``NookChromeMetrics/shelfChipWidth``.
    public static let shelfChipWidth: NookDimensionID = "shelf.chip.width"
    /// ``NookChromeMetrics/shelfChipPadding``.
    public static let shelfChipPadding: NookDimensionID = "shelf.chip.padding"
    /// ``NookChromeMetrics/shelfChipCornerRadius``.
    public static let shelfChipCornerRadius: NookDimensionID = "shelf.chip.cornerRadius"
    /// ``NookChromeMetrics/shelfIconSize``.
    public static let shelfIconSize: NookDimensionID = "shelf.icon.size"
    /// ``NookChromeMetrics/shelfRowVerticalPadding``.
    public static let shelfRowVerticalPadding: NookDimensionID = "shelf.row.padding.vertical"
    /// ``NookChromeMetrics/activityCardSpacing``.
    public static let activityCardSpacing: NookDimensionID = "activity.card.spacing"
    /// ``NookChromeMetrics/activityIconWidth``.
    public static let activityIconWidth: NookDimensionID = "activity.icon.width"
    /// ``NookChromeMetrics/activityTextSpacing``.
    public static let activityTextSpacing: NookDimensionID = "activity.text.spacing"
    /// ``NookChromeMetrics/activityCardVerticalPadding``.
    public static let activityCardVerticalPadding: NookDimensionID = "activity.card.padding.vertical"
    /// ``NookChromeMetrics/activityCardHorizontalPadding``.
    public static let activityCardHorizontalPadding: NookDimensionID = "activity.card.padding.horizontal"
    /// ``NookChromeMetrics/volumeGlyphOpacity``.
    public static let volumeGlyphOpacity: NookDimensionID = "volume.glyph.opacity"
    /// ``NookChromeMetrics/placeholderStackSpacing``.
    public static let placeholderStackSpacing: NookDimensionID = "placeholder.spacing"
    /// ``NookChromeMetrics/placeholderMarkSize``.
    public static let placeholderMarkSize: NookDimensionID = "placeholder.mark.size"
    /// ``NookChromeMetrics/placeholderMarkStrokeWidth``.
    public static let placeholderMarkStrokeWidth: NookDimensionID = "placeholder.mark.strokeWidth"
    /// ``NookChromeMetrics/placeholderVerticalPadding``.
    public static let placeholderVerticalPadding: NookDimensionID = "placeholder.padding.vertical"
    /// ``NookChromeMetrics/settingsSectionSpacing``.
    public static let settingsSectionSpacing: NookDimensionID = "settings.section.spacing"
    /// ``NookChromeMetrics/settingsGroupSpacing``.
    public static let settingsGroupSpacing: NookDimensionID = "settings.group.spacing"
    /// ``NookChromeMetrics/settingsRowSpacing``.
    public static let settingsRowSpacing: NookDimensionID = "settings.row.spacing"
    /// ``NookChromeMetrics/settingsBlockSpacing``.
    public static let settingsBlockSpacing: NookDimensionID = "settings.block.spacing"
    /// ``NookChromeMetrics/settingsFieldSpacing``.
    public static let settingsFieldSpacing: NookDimensionID = "settings.field.spacing"
    /// ``NookChromeMetrics/settingsTextSpacing``.
    public static let settingsTextSpacing: NookDimensionID = "settings.text.spacing"
    /// ``NookChromeMetrics/settingsAboutTextSpacing``.
    public static let settingsAboutTextSpacing: NookDimensionID = "settings.about.textSpacing"
    /// ``NookChromeMetrics/settingsInlineSpacing``.
    public static let settingsInlineSpacing: NookDimensionID = "settings.inline.spacing"
    /// ``NookChromeMetrics/settingsContentBottomPadding``.
    public static let settingsContentBottomPadding: NookDimensionID = "settings.content.padding.bottom"
    /// ``NookChromeMetrics/settingsRowVerticalPadding``.
    public static let settingsRowVerticalPadding: NookDimensionID = "settings.row.padding.vertical"
    /// ``NookChromeMetrics/settingsIconWidth``.
    public static let settingsIconWidth: NookDimensionID = "settings.icon.width"
    /// ``NookChromeMetrics/settingsDisclosureGutter``.
    public static let settingsDisclosureGutter: NookDimensionID = "settings.disclosure.gutter"
    /// ``NookChromeMetrics/settingsSectionLabelTracking``.
    public static let settingsSectionLabelTracking: NookDimensionID = "settings.sectionLabel.tracking"
    /// ``NookChromeMetrics/settingsConnectorWidth``.
    public static let settingsConnectorWidth: NookDimensionID = "settings.connector.width"
    /// ``NookChromeMetrics/settingsConnectorOpacity``.
    public static let settingsConnectorOpacity: NookDimensionID = "settings.connector.opacity"
    /// ``NookChromeMetrics/settingsAccentSwatchSize``.
    public static let settingsAccentSwatchSize: NookDimensionID = "settings.accentSwatch.size"
    /// ``NookChromeMetrics/settingsAccentSwatchStrokeWidth``.
    public static let settingsAccentSwatchStrokeWidth: NookDimensionID = "settings.accentSwatch.strokeWidth"
    /// ``NookChromeMetrics/settingsAccentSwatchSelectedOpacity``.
    public static let settingsAccentSwatchSelectedOpacity: NookDimensionID = "settings.accentSwatch.selectedOpacity"
    /// ``NookChromeMetrics/shortcutKeyCapMinWidth``.
    public static let shortcutKeyCapMinWidth: NookDimensionID = "settings.keyCap.minWidth"
    /// ``NookChromeMetrics/shortcutKeyCapMinHeight``.
    public static let shortcutKeyCapMinHeight: NookDimensionID = "settings.keyCap.minHeight"
    /// ``NookChromeMetrics/shortcutKeyCapCornerRadius``.
    public static let shortcutKeyCapCornerRadius: NookDimensionID = "settings.keyCap.cornerRadius"
    /// ``NookChromeMetrics/shortcutKeyCapLabelOpacity``.
    public static let shortcutKeyCapLabelOpacity: NookDimensionID = "settings.keyCap.labelOpacity"
    /// ``NookChromeMetrics/shortcutKeyCapFillOpacity``.
    public static let shortcutKeyCapFillOpacity: NookDimensionID = "settings.keyCap.fillOpacity"
    /// ``NookChromeMetrics/shortcutKeyCapStrokeOpacity``.
    public static let shortcutKeyCapStrokeOpacity: NookDimensionID = "settings.keyCap.strokeOpacity"
    /// ``NookChromeMetrics/shortcutKeyCapStrokeWidth``.
    public static let shortcutKeyCapStrokeWidth: NookDimensionID = "settings.keyCap.strokeWidth"
    /// ``NookChromeMetrics/shortcutKeyCapSpacing``.
    public static let shortcutKeyCapSpacing: NookDimensionID = "settings.keyCap.spacing"
    /// ``NookChromeMetrics/settingsRecordingHorizontalPadding``.
    public static let settingsRecordingHorizontalPadding: NookDimensionID = "settings.recording.padding.horizontal"
    /// ``NookChromeMetrics/settingsRecordingMinHeight``.
    public static let settingsRecordingMinHeight: NookDimensionID = "settings.recording.minHeight"
    /// ``NookChromeMetrics/settingsRecordingFillOpacity``.
    public static let settingsRecordingFillOpacity: NookDimensionID = "settings.recording.fillOpacity"
    /// ``NookChromeMetrics/settingsRecordingStrokeOpacity``.
    public static let settingsRecordingStrokeOpacity: NookDimensionID = "settings.recording.strokeOpacity"
    /// ``NookChromeMetrics/settingsRecordingStrokeWidth``.
    public static let settingsRecordingStrokeWidth: NookDimensionID = "settings.recording.strokeWidth"
    /// ``NookChromeMetrics/settingsTitleEmphasisOpacity``.
    public static let settingsTitleEmphasisOpacity: NookDimensionID = "settings.title.emphasisOpacity"
    /// ``NookChromeMetrics/settingsRecordingLabelOpacity``.
    public static let settingsRecordingLabelOpacity: NookDimensionID = "settings.recording.labelOpacity"
    /// ``NookChromeMetrics/settingsFailureRowSpacing``.
    public static let settingsFailureRowSpacing: NookDimensionID = "settings.failure.rowSpacing"
}

extension NookFontID {
    // MARK: Semantic

    /// Body text: 11 regular at scale 1.
    public static let typeBody: NookFontID = "type.body"
    /// Glyphs and emphasis: 11 semibold at scale 1.
    public static let typeGlyph: NookFontID = "type.glyph"
    /// Labels: 11 medium at scale 1.
    public static let typeLabel: NookFontID = "type.label"
    /// Captions: 10 regular at scale 1.
    public static let typeCaption: NookFontID = "type.caption"

    // MARK: Chrome typography (one per `NookChromeTypography` field)

    /// ``NookChromeTypography/headerIcon``.
    public static let headerIcon: NookFontID = "topBar.headerIcon.font"
    /// ``NookChromeTypography/topBarLabel``.
    public static let topBarLabel: NookFontID = "topBar.label.font"
    /// ``NookChromeTypography/breadcrumbChevron``.
    public static let breadcrumbChevron: NookFontID = "topBar.breadcrumb.chevron.font"
    /// ``NookChromeTypography/switcherChevron``.
    public static let switcherChevron: NookFontID = "topBar.switcher.chevron.font"
    /// ``NookChromeTypography/compactLeadingGlyph``.
    public static let compactLeadingGlyph: NookFontID = "compact.leadingGlyph.font"
    /// ``NookChromeTypography/bannerSeverityGlyph``.
    public static let bannerSeverityGlyph: NookFontID = "banner.severityGlyph.font"
    /// ``NookChromeTypography/bannerMessage``.
    public static let bannerMessage: NookFontID = "banner.message.font"
    /// ``NookChromeTypography/bannerDismissGlyph``.
    public static let bannerDismissGlyph: NookFontID = "banner.dismissGlyph.font"
    /// ``NookChromeTypography/shelfDropZoneIcon``.
    public static let shelfDropZoneIcon: NookFontID = "shelf.dropZone.icon.font"
    /// ``NookChromeTypography/shelfCaption``.
    public static let shelfCaption: NookFontID = "shelf.caption.font"
    /// ``NookChromeTypography/shelfHeaderLabel``.
    public static let shelfHeaderLabel: NookFontID = "shelf.header.label.font"
    /// ``NookChromeTypography/shelfChipLabel``.
    public static let shelfChipLabel: NookFontID = "shelf.chip.label.font"
    /// ``NookChromeTypography/shelfFallbackGlyph``.
    public static let shelfFallbackGlyph: NookFontID = "shelf.fallbackGlyph.font"
    /// ``NookChromeTypography/shelfRemoveGlyph``.
    public static let shelfRemoveGlyph: NookFontID = "shelf.removeGlyph.font"
    /// ``NookChromeTypography/activityIcon``.
    public static let activityIcon: NookFontID = "activity.icon.font"
    /// ``NookChromeTypography/activityTitle``.
    public static let activityTitle: NookFontID = "activity.title.font"
    /// ``NookChromeTypography/activitySubtitle``.
    public static let activitySubtitle: NookFontID = "activity.subtitle.font"
    /// ``NookChromeTypography/volumeGlyph``.
    public static let volumeGlyph: NookFontID = "volume.glyph.font"
    /// ``NookChromeTypography/placeholderTitle``.
    public static let placeholderTitle: NookFontID = "placeholder.title.font"
    /// ``NookChromeTypography/placeholderBody``.
    public static let placeholderBody: NookFontID = "placeholder.body.font"
    /// ``NookChromeTypography/settingsSectionLabel``.
    public static let settingsSectionLabel: NookFontID = "settings.sectionLabel.font"
    /// ``NookChromeTypography/settingsHint``.
    public static let settingsHint: NookFontID = "settings.hint.font"
    /// ``NookChromeTypography/settingsCaption``.
    public static let settingsCaption: NookFontID = "settings.caption.font"
    /// ``NookChromeTypography/settingsVersionLabel``.
    public static let settingsVersionLabel: NookFontID = "settings.versionLabel.font"
    /// ``NookChromeTypography/settingsFieldLabel``.
    public static let settingsFieldLabel: NookFontID = "settings.fieldLabel.font"
    /// ``NookChromeTypography/settingsCommandChevron``.
    public static let settingsCommandChevron: NookFontID = "settings.command.chevron.font"
    /// ``NookChromeTypography/settingsRowDetail``.
    public static let settingsRowDetail: NookFontID = "settings.row.detail.font"
    /// ``NookChromeTypography/settingsRowTitle``.
    public static let settingsRowTitle: NookFontID = "settings.row.title.font"
    /// ``NookChromeTypography/settingsEmphasis``.
    public static let settingsEmphasis: NookFontID = "settings.emphasis.font"
    /// ``NookChromeTypography/settingsCommandTitle``.
    public static let settingsCommandTitle: NookFontID = "settings.command.title.font"
    /// ``NookChromeTypography/settingsCommandIcon``.
    public static let settingsCommandIcon: NookFontID = "settings.command.icon.font"
    /// ``NookChromeTypography/settingsDisclosureChevron``.
    public static let settingsDisclosureChevron: NookFontID = "settings.disclosure.chevron.font"
}

extension NookAnimationID {
    // MARK: Semantic

    /// A quick spring: response 0.26, damping 0.82.
    public static let springSnappy: NookAnimationID = "spring.snappy"
    /// The default spring: response 0.34, damping 0.86.
    public static let springDefault: NookAnimationID = "spring.default"
    /// A gentle spring: response 0.38, damping 0.84.
    public static let springGentle: NookAnimationID = "spring.gentle"
    /// A quick ease-out, 0.18 s.
    public static let curveQuick: NookAnimationID = "curve.quick"
    /// The surface's expand from hidden: response 0.52, damping 0.88, blend 0.12.
    public static let transitionOpen: NookAnimationID = "transition.open"
    /// The surface's collapse to hidden: response 0.46, damping 0.93, blend 0.10.
    public static let transitionClose: NookAnimationID = "transition.close"
    /// The surface's compact and expanded conversion: response 0.54, damping 0.86, blend 0.12.
    public static let transitionConvert: NookAnimationID = "transition.convert"
    /// The compact pill growing into its peek and back. Default `{spring.snappy}`.
    public static let transitionPeek: NookAnimationID = "transition.peek"

    // MARK: Chrome motion (one per `NookChromeMotion` field)

    /// ``NookChromeMotion/viewModeChange``.
    public static let viewModeChange: NookAnimationID = "motion.viewModeChange"
    /// ``NookChromeMotion/leadingClusterBack``.
    public static let leadingClusterBack: NookAnimationID = "motion.leadingClusterBack"
    /// ``NookChromeMotion/leadingClusterHover``.
    public static let leadingClusterHover: NookAnimationID = "motion.leadingClusterHover"
    /// ``NookChromeMotion/statusBanner``.
    public static let statusBanner: NookAnimationID = "motion.statusBanner"
    /// ``NookChromeMotion/breadcrumb``.
    public static let breadcrumb: NookAnimationID = "motion.breadcrumb"
    /// ``NookChromeMotion/settingsDisclosure``.
    public static let settingsDisclosure: NookAnimationID = "motion.settingsDisclosure"
    /// ``NookChromeMotion/moduleSwitch``.
    public static let moduleSwitch: NookAnimationID = "motion.moduleSwitch"
    /// ``NookChromeMotion/activityCard``.
    public static let activityCard: NookAnimationID = "motion.activityCard"
}

extension NookTransitionID {
    /// How expanded content leaves. Default fade, blur 6, vertical scale 0.72 from the top, on the surface's curve.
    /// A theme that does not write it leaves with `motion.content.enter` in reverse.
    public static let contentExit: NookTransitionID = "motion.content.exit"
    /// How expanded content enters. Default the same as it leaves.
    public static let contentEnter: NookTransitionID = "motion.content.enter"
    /// How compact slot content enters and leaves. Default fade, blur 6, and a horizontal scale
    /// from 0, on the surface's curve.
    public static let compactContent: NookTransitionID = "motion.compact.transition"
    /// How the peek content enters, and leaves unless `motion.peek.exit` is written. Default
    /// fade, blur 4, and a vertical scale from 0.9 at the top, on the peek curve.
    public static let peekEnter: NookTransitionID = "motion.peek.enter"
    /// How the peek content leaves. A theme that does not write it leaves with
    /// `motion.peek.enter` in reverse.
    public static let peekExit: NookTransitionID = "motion.peek.exit"
}

extension NookSoundID {
    /// The nook expands. Default none.
    public static let open: NookSoundID = "sound.open"
    /// The nook collapses. Default none.
    public static let close: NookSoundID = "sound.close"
    /// The nook peeks out. Default none.
    public static let peek: NookSoundID = "sound.peek"
    /// Something needs attention. Default none.
    public static let alert: NookSoundID = "sound.alert"
    /// A task finished. Default none.
    public static let finish: NookSoundID = "sound.finish"
    /// The pointer reaches the nook. Default none.
    public static let hover: NookSoundID = "sound.hover"
    /// A peripheral feedback cue plays. Default none.
    public static let feedback: NookSoundID = "sound.feedback"

    /// Every sound event, in a stable order.
    public static let allEvents: [NookSoundID] = [.open, .close, .peek, .alert, .finish, .hover, .feedback]
}

extension NookShadowID {
    /// A shadow cast by the chrome. Default none, as today.
    public static let chrome: NookShadowID = "shadow.chrome"
}

// MARK: - Widgets

extension NookColorID {
    /// The card behind each widget on a ``NookWidgetGrid``. Default `color.fill.subtle`.
    public static let widgetCardBackground: NookColorID = "widget.card.background.color"
    /// The hairline around each widget card. Default `color.stroke.subtle`.
    public static let widgetCardBorder: NookColorID = "widget.card.border.color"
}

extension NookDimensionID {
    /// The space between widgets on a grid, both across and down. Default `{space.md}`, 8.
    public static let widgetGap: NookDimensionID = "widget.gap"
    /// The height of one grid row. Default 72.
    public static let widgetRowHeight: NookDimensionID = "widget.rowHeight"
    /// The tallest a board's grid grows before it scrolls. Default 320.
    public static let widgetBoardMaxHeight: NookDimensionID = "widget.board.maxHeight"
    /// A widget card's corner radius. Default 16: the chrome's 24 less the 8 point edge
    /// padding, so the card's corner follows the panel's.
    public static let widgetCardCornerRadius: NookDimensionID = "widget.card.cornerRadius"
    /// The margin inside a widget card. Default `{space.lg}`, 10.
    public static let widgetCardPadding: NookDimensionID = "widget.card.padding"
}

extension NookAnimationID {
    /// How widgets move when a board's layout changes. Default `{spring.default}`.
    public static let widgetLayout: NookAnimationID = "motion.widgetLayout"
}

// MARK: - Shared elements

extension NookAnimationID {
    /// How a shared element (`nookSharedElement(_:style:)`) moves between the compact pill and
    /// the expanded content. Default `{transition.convert}`, the chrome's own curve.
    public static let sharedElementConvert: NookAnimationID = "motion.sharedElement.convert"
    /// How a shared element moves between the pill and its peek. Default `{transition.peek}`.
    public static let sharedElementPeek: NookAnimationID = "motion.sharedElement.peek"
}
