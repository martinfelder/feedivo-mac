import Foundation

struct ReadabilityFailureNotice: Equatable {
    let titleKey: String
    let detailKey: String

    static func make(for _: Error) -> ReadabilityFailureNotice {
        ReadabilityFailureNotice(
            titleKey: "reader.readability.failed",
            detailKey: "reader.readability.providerBlocked.detail"
        )
    }
}
