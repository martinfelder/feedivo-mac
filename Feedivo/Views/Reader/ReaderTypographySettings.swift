import Foundation

/// UserDefaults-Schlüssel für die Reader-Typografie-Einstellungen.
///
/// Die 8 Schlüssel wurden zuvor als String-Literale in `@AppStorage("…")`
/// dreifach gepflegt (ReaderView, SettingsView, ArticleExportSheet). Über
/// diese Konstanten gibt es genau eine Stelle pro Schlüssel. Die Defaults
/// selbst bleiben bei `ReaderTypography`/`ReaderFontPreset` (Domain-Konstanten)
/// und werden in den `@AppStorage`-Deklarationen referenziert.
enum ReaderTypographySettings {
    static let titleFontPresetKey = "readerTitleFontPreset"
    static let bodyFontPresetKey = "readerBodyFontPreset"
    static let titleFontIsBoldKey = "readerTitleFontIsBold"
    static let bodyFontIsBoldKey = "readerBodyFontIsBold"
    static let bodyFontSizeKey = "readerBodyFontSize"
    static let lineSpacingKey = "readerLineSpacing"
    static let titleLineSpacingKey = "readerTitleLineSpacing"
    static let contentWidthKey = "readerContentWidth"
    static let showsArticleImagesKey = "readerShowsArticleImages"
}
