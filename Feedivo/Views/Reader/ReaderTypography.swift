import Foundation

enum ReaderTypography {
    static let defaultTitleFontSize = 31.0
    static let defaultBodyFontSize = 17.0
    static let bodyFontSizeRange = 14.0...24.0

    static let defaultLineSpacing = 5.0
    static let lineSpacingRange = 1.0...12.0

    static let defaultTitleLineSpacing = 2.0
    static let titleLineSpacingRange = 0.0...10.0

    static let defaultContentWidth = 720.0
    static let contentWidthRange = 520.0...980.0
    static let contentWidthStep = 20.0

    static let articleTopPadding = 44.0
    static let articleBottomPadding = 28.0
    static let headerSpacing = 14.0
    static let contentBlockSpacing = 22.0
    static let leadImageMaxHeight = 460.0
    static let footerTopPadding = 12.0

    static func clampedBodyFontSize(_ value: Double) -> Double {
        min(max(value, bodyFontSizeRange.lowerBound), bodyFontSizeRange.upperBound)
    }

    static func clampedLineSpacing(_ value: Double) -> Double {
        min(max(value, lineSpacingRange.lowerBound), lineSpacingRange.upperBound)
    }

    static func clampedTitleLineSpacing(_ value: Double) -> Double {
        min(max(value, titleLineSpacingRange.lowerBound), titleLineSpacingRange.upperBound)
    }

    static func clampedContentWidth(_ value: Double) -> Double {
        min(max(value, contentWidthRange.lowerBound), contentWidthRange.upperBound)
    }

    static func metadataFontSize(forBodyFontSize bodyFontSize: Double) -> Double {
        max(12, (clampedBodyFontSize(bodyFontSize) * 0.75).rounded())
    }
}
