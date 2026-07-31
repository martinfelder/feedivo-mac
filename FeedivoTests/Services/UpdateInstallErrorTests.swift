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
        #expect(!UpdateInstallError.relaunchFailed.requiresFullRedownload)
    }

    @Test func jederFehlerHatEineNichtLeereBeschreibung() {
        for error in [
            UpdateInstallError.downloadFailed,
            .checksumMismatch,
            .unzipFailed,
            .folderAccessDenied,
            .replaceFailed,
            .relaunchFailed
        ] {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
