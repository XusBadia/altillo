import Foundation
import Testing
@testable import Altillo

/// Organisers hide the join link anywhere: the URL field, the location, or a wall of notes.
struct MeetingLinkTests {
    @Test func findsAKnownProviderInTheLocation() throws {
        let url = try #require(MeetingLink.find(location: "https://meet.google.com/abc-defg-hij"))
        #expect(MeetingLink.provider(for: url) == .meet)
    }

    @Test func findsTheLinkInsideTheNotes() throws {
        let notes = """
        Hola:
        Nos vemos aquí https://acme.zoom.us/j/98765432?pwd=secreto
        Orden del día adjunto.
        """
        let url = try #require(MeetingLink.find(location: "Sala 3", notes: notes))
        #expect(MeetingLink.provider(for: url) == .zoom)
        #expect(url.absoluteString.contains("98765432"))
    }

    @Test func aKnownProviderBeatsAPlainLink() throws {
        let url = try #require(MeetingLink.find(
            url: URL(string: "https://acme.example.com/evento/42"),
            notes: "Llamada: https://teams.microsoft.com/l/meetup-join/xyz"
        ))
        #expect(MeetingLink.provider(for: url) == .teams)
    }

    @Test func fallsBackToThePlainLinkWhenThereIsNoProvider() throws {
        let url = try #require(MeetingLink.find(location: "https://reunion.example.com/sala"))
        #expect(MeetingLink.provider(for: url) == nil)
        #expect(url.host() == "reunion.example.com")
    }

    @Test func ignoresEverythingThatIsNotALink() {
        #expect(MeetingLink.find(location: "Sala grande, segunda planta", notes: "Traer el portátil") == nil)
        #expect(MeetingLink.find(url: URL(string: "mailto:alguien@example.com")) == nil)
    }

    @Test func matchesSubdomainsButNotLookalikes() throws {
        let real = try #require(URL(string: "https://acme.webex.com/meet/xus"))
        let fake = try #require(URL(string: "https://webex.com.phishing.example/meet"))
        #expect(MeetingLink.provider(for: real) == .webex)
        #expect(MeetingLink.provider(for: fake) == nil)
    }
}
