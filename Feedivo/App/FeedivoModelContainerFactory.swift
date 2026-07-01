import SwiftData

enum FeedivoModelContainerFactory {
    static func persistentConfiguration(
        schema: Schema,
        isCloudSyncEnabled: Bool
    ) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            cloudKitDatabase: isCloudSyncEnabled
                ? .private(CloudSyncSettings.cloudKitContainerIdentifier)
                : .none
        )
    }

    static func inMemoryFallbackConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
    }

    static func makePersistentContainer(
        schema: Schema,
        isCloudSyncEnabled: Bool
    ) throws -> ModelContainer {
        let configuration = persistentConfiguration(
            schema: schema,
            isCloudSyncEnabled: isCloudSyncEnabled
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func makeInMemoryFallbackContainer(schema: Schema) -> ModelContainer {
        let configuration = inMemoryFallbackConfiguration()
        return try! ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
