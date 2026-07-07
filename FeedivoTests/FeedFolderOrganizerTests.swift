import Testing
@testable import Feedivo

struct FeedFolderOrganizerTests {

    @Test func folderNamesKoennenAusLeichtenStringsGebildetWerden() {
        let feedFolderNames = [" Tech ", "News", "tech", ""]
        let folderNames = ["Later", " news "]

        #expect(
            FeedFolderOrganizer.folderNames(
                feedFolderNames: feedFolderNames,
                explicitFolderNames: folderNames
            ) == ["Later", "News", "Tech"]
        )
    }

    @Test func normalizeFolderNameSpeichertNilFuerLeereEingaben() {
        #expect(FeedFolderOrganizer.normalizedFolderName(" News ") == "News")
        #expect(FeedFolderOrganizer.normalizedFolderName(" ") == nil)
        #expect(FeedFolderOrganizer.normalizedFolderName(nil) == nil)
    }
}
