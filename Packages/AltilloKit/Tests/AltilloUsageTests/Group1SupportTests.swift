import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

struct Group1SupportTests {
    @Test func apiKeyFileFormats() {
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"apiKey":" sk-1 "}"#) == "sk-1")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"api_key":"sk-2"}"#) == "sk-2")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"key":"sk-3"}"#) == "sk-3")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: "sk-plain\n") == "sk-plain")
        #expect(LocalAPIKeySource.apiKey(fromConfigText: #"{"other":"x"}"#) == nil)
        #expect(LocalAPIKeySource.apiKey(fromConfigText: "  ") == nil)
    }

    @Test func filesWinOverEnvironmentAndXDGIsHonoured() {
        let file = URL(fileURLWithPath: "/cfg/p/key.json")
        let both = LocalAPIKeySource(files: [file], environmentNames: ["A", "B"], environment: ["B": "env"],
                                     readFile: { $0 == file ? "from-file" : nil })
        #expect(both.key() == "from-file")
        let envOnly = LocalAPIKeySource(files: [file], environmentNames: ["A", "B"], environment: ["B": " env "],
                                        readFile: { _ in nil })
        #expect(envOnly.key() == "env")
        let home = URL(fileURLWithPath: "/Users/t")
        #expect(LocalAPIKeySource.configFile("zai", environment: [:], home: home).path == "/Users/t/.config/zai/key.json")
        #expect(LocalAPIKeySource.configFile("zai", environment: ["XDG_CONFIG_HOME": "/x"], home: home).path
            == "/x/zai/key.json")
    }

    @Test func securityCLIKeychainNeverAsksForMissingItems() async {
        let missing = FakeRunner([CommandResult(status: 44, stdout: Data())])
        #expect(await SecurityCLIKeychain(runner: missing).secret(service: "svc", account: nil) == .notFound)
        #expect(missing.arguments == [["find-generic-password", "-s", "svc"]]) // no -w: no prompt

        let found = FakeRunner([CommandResult(status: 0, stdout: Data()),
                                CommandResult(status: 0, stdout: Data("secret\n".utf8))])
        #expect(await SecurityCLIKeychain(runner: found).secret(service: "svc", account: "me") == .found("secret"))
        #expect(found.arguments.last == ["find-generic-password", "-s", "svc", "-a", "me", "-w"])

        let refused = FakeRunner([CommandResult(status: 0, stdout: Data()),
                                  CommandResult(status: 128, stdout: Data(), timedOut: true)])
        #expect(await SecurityCLIKeychain(runner: refused).secret(service: "svc", account: nil) == .denied)
    }

    @Test func goKeyringAndJWT() {
        #expect(Group1Support.unwrapGoKeyring("go-keyring-base64:" + Data("tok".utf8).base64EncodedString()) == "tok")
        #expect(Group1Support.unwrapGoKeyring(" plain ") == "plain")
        #expect(Group1Support.unwrapGoKeyring("go-keyring-base64:!!!") == nil)
        let jwt = cursorJWT(sub: "a|b", expires: referenceNow)
        #expect(Group1Support.jwtPayload(jwt)?["sub"] as? String == "a|b")
        #expect(Group1Support.jwtPayload("nope") == nil)
    }
}
