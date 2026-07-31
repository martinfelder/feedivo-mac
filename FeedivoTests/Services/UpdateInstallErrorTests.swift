import Testing
@testable import Feedivo

struct UpdateInstallErrorTests {

    @Test func downloadUndChecksumUndUnzipFehlerBrauchenKompletttenNeustart() {
        #expect(UpdateInstallError.downloadFailed.requiresFullRedownload)
        #expect(UpdateInstallError.checksumMismatch.requiresFullRedownload)
        #expect(UpdateInstallError.unzipFailed.requiresFullRedownload)
    }

    @Test func ordnerZugriffUndAustauschFehlerBrauchenKeinenNeuenDownload() {
        #expect(!UpdateInstallError.folderAccessDenied.requiresFullRedownload)
        #expect(!UpdateInstallError.replaceFailed.requiresFullRedownload)
    }

    @Test func jederFehlerHatEineNichtLeereBeschreibung() {
        for error in [
            UpdateInstallError.downloadFailed,
            .checksumMismatch,
            .unzipFailed,
            .folderAccessDenied,
            .replaceFailed
        ] {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
