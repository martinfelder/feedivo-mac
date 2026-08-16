import Foundation
import Testing
import GRDB
@testable import Feedivo

@Suite("MCPServerSessionStore")
struct MCPServerSessionStoreTests {
    private let jetzt = Date(timeIntervalSince1970: 1_786_800_000)

    @Test("Ohne Sitzungen ist die Liste leer")
    func ohneSitzungenLeer() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())

        #expect(try store.activeSessions(now: jetzt, tolerance: 40).isEmpty)
    }

    @Test("Eine frisch eingetragene Sitzung gilt als aktiv")
    func frischeSitzungIstAktiv() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())

        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 10)

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)
        #expect(aktive.count == 1)
        #expect(aktive.first?.pid == 4711)
        #expect(aktive.first?.clientName == "Claude")
        #expect(aktive.first?.toolCount == 10)
    }

    @Test("Eine Sitzung ohne frischen Heartbeat gilt nicht mehr als aktiv")
    func alteSitzungIstNichtAktiv() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 10)

        // 41 Sekunden spaeter: knapp jenseits der Toleranz von 40 Sekunden.
        let aktive = try store.activeSessions(now: jetzt.addingTimeInterval(41), tolerance: 40)

        #expect(aktive.isEmpty)
    }

    @Test("Ein Heartbeat haelt die Sitzung am Leben")
    func heartbeatHaeltSitzungAmLeben() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 10)

        try store.recordHeartbeat(pid: 4711, at: jetzt.addingTimeInterval(30))

        let aktive = try store.activeSessions(now: jetzt.addingTimeInterval(41), tolerance: 40)
        #expect(aktive.count == 1)
        // startedAt bleibt der urspruengliche Startzeitpunkt, nur das Lebenszeichen wandert.
        #expect(abs((aktive.first?.startedAt ?? .distantPast).timeIntervalSince(jetzt)) < 1)
    }

    @Test("Ein erneuter Start mit derselben Prozess-ID ersetzt die alte Zeile")
    func gleicheProzessIDErsetztZeile() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())

        // Prozess-IDs werden vom System wiederverwendet — sonst entstuenden Dubletten.
        try store.startSession(pid: 4711, clientName: "Claude", at: jetzt, toolCount: 7)
        try store.startSession(pid: 4711, clientName: "Cursor", at: jetzt, toolCount: 10)

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)
        #expect(aktive.count == 1)
        #expect(aktive.first?.clientName == "Cursor")
        #expect(aktive.first?.toolCount == 10)
    }

    @Test("deleteSessions entfernt nur Zeilen ohne Lebenszeichen seit dem Stichtag")
    func deleteSessionsEntferntNurAlteZeilen() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        try store.startSession(pid: 1, clientName: "Alt", at: jetzt.addingTimeInterval(-3600), toolCount: 7)
        try store.startSession(pid: 2, clientName: "Neu", at: jetzt, toolCount: 10)

        try store.deleteSessions(lastSeenBefore: jetzt.addingTimeInterval(-600))

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)
        #expect(aktive.map(\.clientName) == ["Neu"])
    }

    @Test("Aktive Sitzungen sind stabil nach Name und Werkzeug-Anzahl sortiert")
    func aktiveSitzungenSindSortiert() throws {
        let store = MCPServerSessionStore(database: try FeedivoDatabase.inMemoryForTests())
        // Reihenfolge des Eintragens bewusst gegen die erwartete Sortierung.
        try store.startSession(pid: 3, clientName: "Cursor", at: jetzt, toolCount: 7)
        try store.startSession(pid: 1, clientName: "Claude", at: jetzt, toolCount: 10)
        try store.startSession(pid: 2, clientName: "Claude", at: jetzt, toolCount: 7)

        let aktive = try store.activeSessions(now: jetzt, tolerance: 40)

        #expect(aktive.map { "\($0.clientName)/\($0.toolCount)" } == ["Claude/7", "Claude/10", "Cursor/7"])
    }
}
