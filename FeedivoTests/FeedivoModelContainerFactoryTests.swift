import SwiftData
import Testing
@testable import Feedivo

struct FeedivoModelContainerFactoryTests {
    @Test func localConfigurationVerwendetKeinCloudKit() {
        let mode = FeedivoModelContainerFactory.storeMode(
            isCloudSyncEnabled: false
        )

        #expect(mode == .local)

        let configuration = FeedivoModelContainerFactory.configuration(
            for: .local,
            schema: Schema([Feed.self])
        )

        #expect(configuration.isStoredInMemoryOnly == false)
    }

    @Test func cloudConfigurationVerwendetPrivateCloudKitDatenbank() {
        let mode = FeedivoModelContainerFactory.storeMode(
            isCloudSyncEnabled: true
        )

        #expect(mode == .cloud(CloudSyncSettings.cloudKitContainerIdentifier))

        let configuration = FeedivoModelContainerFactory.configuration(
            for: .cloud(CloudSyncSettings.cloudKitContainerIdentifier),
            schema: Schema([Feed.self])
        )

        #expect(configuration.isStoredInMemoryOnly == false)
        #expect(configuration.cloudKitContainerIdentifier == CloudSyncSettings.cloudKitContainerIdentifier)
    }

    @Test func fallbackConfigurationBleibtImmerInMemoryUndCloudKitFrei() {
        let localMode = FeedivoModelContainerFactory.storeMode(isCloudSyncEnabled: false)
        #expect(localMode == .local)

        let localConfiguration = FeedivoModelContainerFactory.configuration(
            for: localMode,
            schema: Schema([Feed.self])
        )

        #expect(localConfiguration.isStoredInMemoryOnly == false)
        #expect(localConfiguration.cloudKitContainerIdentifier == nil)

        let fallbackMode: FeedivoModelContainerFactory.StoreMode = .inMemoryFallback
        #expect(fallbackMode == .inMemoryFallback)

        let fallbackConfiguration = FeedivoModelContainerFactory.configuration(
            for: fallbackMode,
            schema: Schema([Feed.self])
        )

        #expect(fallbackConfiguration.isStoredInMemoryOnly == true)
        #expect(fallbackConfiguration.cloudKitContainerIdentifier == nil)

        let explicitFallbackConfiguration = FeedivoModelContainerFactory.inMemoryFallbackConfiguration()

        #expect(fallbackConfiguration.isStoredInMemoryOnly == explicitFallbackConfiguration.isStoredInMemoryOnly)
        #expect(fallbackConfiguration.cloudKitContainerIdentifier == explicitFallbackConfiguration.cloudKitContainerIdentifier)
    }
}
