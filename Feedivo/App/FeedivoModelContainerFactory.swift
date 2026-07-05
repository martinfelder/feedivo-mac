import SwiftData

@available(*, deprecated, message: "Legacy-Helfer für SwiftData-Migrationspfade. Produktiv läuft FeedivoApp ohne ModelContainer.")
enum FeedivoModelContainerFactory {
    enum StoreMode: Equatable {
        case local
        case cloud(String)
        case inMemoryFallback
    }

    static func storeMode(isCloudSyncEnabled: Bool) -> StoreMode {
        isCloudSyncEnabled
            ? .cloud(CloudSyncSettings.cloudKitContainerIdentifier)
            : .local
    }

    static func configuration(for mode: StoreMode, schema: Schema) -> ModelConfiguration {
        switch mode {
        case .local:
            return ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )
        case let .cloud(containerIdentifier):
            return ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(containerIdentifier)
            )
        case .inMemoryFallback:
            return inMemoryFallbackConfiguration()
        }
    }

    static func persistentConfiguration(
        schema: Schema,
        isCloudSyncEnabled: Bool
    ) -> ModelConfiguration {
        configuration(
            for: storeMode(isCloudSyncEnabled: isCloudSyncEnabled),
            schema: schema
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

    static func makeInMemoryFallbackContainer(schema: Schema) throws -> ModelContainer {
        let configuration = inMemoryFallbackConfiguration()
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
