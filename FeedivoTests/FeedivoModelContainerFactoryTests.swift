import SwiftData
import Testing
@testable import Feedivo

struct FeedivoModelContainerFactoryTests {
    @Test func localConfigurationVerwendetKeinCloudKit() {
        let configuration = FeedivoModelContainerFactory.persistentConfiguration(
            schema: Schema([Feed.self]),
            isCloudSyncEnabled: false
        )

        #expect(configuration.isStoredInMemoryOnly == false)
        #expect(isCloudKitDatabaseNone(configuration.cloudKitDatabase))
    }

    @Test func cloudConfigurationVerwendetPrivateCloudKitDatenbank() {
        let configuration = FeedivoModelContainerFactory.persistentConfiguration(
            schema: Schema([Feed.self]),
            isCloudSyncEnabled: true
        )

        #expect(configuration.isStoredInMemoryOnly == false)
        #expect(isCloudKitDatabaseConfigured(configuration.cloudKitDatabase))
        #expect(isCloudKitDatabasePrivate(configuration.cloudKitDatabase))
        #expect(configuration.cloudKitContainerIdentifier == CloudSyncSettings.cloudKitContainerIdentifier)
    }

    @Test func fallbackConfigurationBleibtImmerInMemoryUndCloudKitFrei() {
        let configuration = FeedivoModelContainerFactory.inMemoryFallbackConfiguration()

        #expect(configuration.isStoredInMemoryOnly == true)
        #expect(isCloudKitDatabaseNone(configuration.cloudKitDatabase))
    }
}

private func isCloudKitDatabaseNone(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
    let mirror = Mirror(reflecting: database)

    for child in mirror.children {
        if child.label == "_none", let value = child.value as? Bool {
            return value
        }
    }

    return false
}

private func isCloudKitDatabasePrivate(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
    let mirror = Mirror(reflecting: database)

    for child in mirror.children {
        if child.label == "_privateDBName" {
            if let privateDBName = child.value as? String {
                return !privateDBName.isEmpty
            }
            if let privateDBName = child.value as? Optional<String> {
                return privateDBName != nil
            }
        }
    }

    return false
}

private func isCloudKitDatabaseConfigured(_ database: ModelConfiguration.CloudKitDatabase) -> Bool {
    return !isCloudKitDatabaseNone(database)
}
