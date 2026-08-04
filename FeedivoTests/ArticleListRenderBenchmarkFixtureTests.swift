import Testing
@testable import Feedivo

@Suite("ArticleListRenderBenchmarkFixture")
struct ArticleListRenderBenchmarkFixtureTests {
    @Test func defaultCountIst1000() {
        #expect(ArticleListRenderBenchmarkFixture.defaultCount == 1_000)
    }

    @Test func makeSnapshotsErzeugtDieAngeforderteAnzahl() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 250)
        #expect(snapshots.count == 250)
    }

    @Test func makeSnapshotsErzeugtEindeutigeIDs() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 500)
        #expect(Set(snapshots.map(\.id)).count == 500)
    }

    @Test func makeSnapshotsMischtArtikelMitUndOhneBild() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 100)
        #expect(snapshots.contains { $0.imageURL != nil })
        #expect(snapshots.contains { $0.imageURL == nil })
    }

    @Test func makeSnapshotsMischtArtikelMitUndOhneSummary() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 100)
        #expect(snapshots.contains { $0.summary != nil })
        #expect(snapshots.contains { $0.summary == nil })
    }

    @Test func makeSnapshotsMischtGelesenUndUngelesen() {
        let snapshots = ArticleListRenderBenchmarkFixture.makeSnapshots(count: 100)
        #expect(snapshots.contains { $0.isRead })
        #expect(snapshots.contains { !$0.isRead })
    }
}
