import Foundation

enum ReaderTypography {
    static let defaultTitleFontSize = 34.0
    static let defaultBodyFontSize = 17.0
    static let bodyFontSizeRange = 14.0...24.0

    static let defaultLineSpacing = 5.0
    static let lineSpacingRange = 1.0...12.0

    static func clampedBodyFontSize(_ value: Double) -> Double {
        min(max(value, bodyFontSizeRange.lowerBound), bodyFontSizeRange.upperBound)
    }

    static func clampedLineSpacing(_ value: Double) -> Double {
        min(max(value, lineSpacingRange.lowerBound), lineSpacingRange.upperBound)
    }

    static func metadataFontSize(forBodyFontSize bodyFontSize: Double) -> Double {
        max(12, (clampedBodyFontSize(bodyFontSize) * 0.75).rounded())
    }
}
