import Testing
import Foundation
@testable import Feedivo

struct UpdateChecksumVerifierTests {

    @Test func sha256HexLiefertBekanntenTestvektorFuerABC() {
        let hex = UpdateChecksumVerifier.sha256Hex(of: "abc".data(using: .utf8)!)

        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func matchesIgnoriertGrossKleinschreibung() {
        #expect(UpdateChecksumVerifier.matches(computedHex: "AbCd1234", expectedHex: "abcd1234"))
    }

    @Test func matchesIgnoriertUmgebendenWhitespace() {
        #expect(UpdateChecksumVerifier.matches(computedHex: "abcd1234", expectedHex: "  abcd1234\n"))
    }

    @Test func matchesLiefertFalseBeiUnterschiedlichenHashes() {
        #expect(!UpdateChecksumVerifier.matches(computedHex: "abcd1234", expectedHex: "1234abcd"))
    }
}
