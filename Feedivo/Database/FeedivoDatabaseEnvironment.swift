import SwiftUI

private struct FeedivoDatabaseEnvironmentKey: EnvironmentKey {
    static let defaultValue: FeedivoDatabase? = nil
}

extension EnvironmentValues {
    var feedivoDatabase: FeedivoDatabase? {
        get { self[FeedivoDatabaseEnvironmentKey.self] }
        set { self[FeedivoDatabaseEnvironmentKey.self] = newValue }
    }
}
