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
        Hi:
        See you here https://acme.zoom.us/j/98765432?pwd=secret
        Agenda attached.
        """
        let url = try #require(MeetingLink.find(location: "Room 3", notes: notes))
        #expect(MeetingLink.provider(for: url) == .zoom)
        #expect(url.absoluteString.contains("98765432"))
    }

    @Test func aKnownProviderBeatsAPlainLink() throws {
        let url = try #require(MeetingLink.find(
            url: URL(string: "https://acme.example.com/event/42"),
            notes: "Llamada: https://teams.microsoft.com/l/meetup-join/xyz"
        ))
        #expect(MeetingLink.provider(for: url) == .teams)
    }

    @Test func fallsBackToThePlainLinkWhenThereIsNoProvider() throws {
        let url = try #require(MeetingLink.find(location: "https://meeting.example.com/room"))
        #expect(MeetingLink.provider(for: url) == nil)
        #expect(url.host() == "meeting.example.com")
    }

    @Test func ignoresEverythingThatIsNotALink() {
        #expect(MeetingLink.find(location: "Big room, second floor", notes: "Bring the laptop") == nil)
        #expect(MeetingLink.find(url: URL(string: "mailto:someone@example.com")) == nil)
    }

    @Test func matchesSubdomainsButNotLookalikes() throws {
        let real = try #require(URL(string: "https://acme.webex.com/meet/xus"))
        let fake = try #require(URL(string: "https://webex.com.phishing.example/meet"))
        #expect(MeetingLink.provider(for: real) == .webex)
        #expect(MeetingLink.provider(for: fake) == nil)
    }
}
