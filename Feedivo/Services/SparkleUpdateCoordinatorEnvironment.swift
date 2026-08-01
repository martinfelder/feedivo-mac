import SwiftUI

private struct SparkleUpdateCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: SparkleUpdateCoordinator? = nil
}

extension EnvironmentValues {
    var sparkleUpdateCoordinator: SparkleUpdateCoordinator? {
        get { self[SparkleUpdateCoordinatorEnvironmentKey.self] }
        set { self[SparkleUpdateCoordinatorEnvironmentKey.self] = newValue }
    }
}
