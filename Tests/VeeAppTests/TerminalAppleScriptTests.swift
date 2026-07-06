import XCTest
@testable import VeeApp

/// Guards the "Run in Terminal" command builder against shell / AppleScript
/// injection from untrusted plugin values (`bash=`, `paramN=`).
final class TerminalAppleScriptTests: XCTestCase {
    func testShellQuoteWrapsAndEscapesSingleQuotes() {
        XCTAssertEqual(AppActionDispatcher.shellQuote("plain"), "'plain'")
        XCTAssertEqual(AppActionDispatcher.shellQuote("has space"), "'has space'")
        // The classic breakout: a single quote must become '\'' so it can't end
        // the quoted region.
        XCTAssertEqual(AppActionDispatcher.shellQuote("a'b"), "'a'\\''b'")
        // Shell metacharacters stay inside the quotes → inert.
        XCTAssertEqual(AppActionDispatcher.shellQuote("$(rm -rf ~)"), "'$(rm -rf ~)'")
        XCTAssertEqual(AppActionDispatcher.shellQuote("x; y && z"), "'x; y && z'")
    }

    func testAppleScriptEscapeNeutralizesQuotesAndNewlines() {
        XCTAssertEqual(AppActionDispatcher.appleScriptEscape("say \"hi\""), "say \\\"hi\\\"")
        XCTAssertEqual(AppActionDispatcher.appleScriptEscape("a\\b"), "a\\\\b")
        // A newline must not terminate the `do script "…"` line.
        XCTAssertEqual(AppActionDispatcher.appleScriptEscape("line1\nline2"), "line1\\nline2")
    }

    func testInjectionAttemptsAreContained() {
        // An argument that tries to break out of shell quoting and inject a
        // second command. The raw breakout sequence `hi'; rm` must never appear
        // verbatim — the `'` is neutralized before the `;` can start a new word.
        let shellInjection = AppActionDispatcher.terminalAppleScript(
            launchPath: "/bin/echo",
            arguments: ["hi'; rm -rf ~ #"]
        )
        XCTAssertFalse(shellInjection.contains("hi'; rm"), "single-quote breakout must be escaped")

        // An argument with a newline + AppleScript payload must stay a single
        // `do script "…"` line (no raw newline injected into the source) and must
        // not spawn a second `tell application` statement.
        let asInjection = AppActionDispatcher.terminalAppleScript(
            launchPath: "/bin/echo",
            arguments: ["x\"\nend tell\ntell application \"Finder\" to delete"]
        )
        let doScriptLines = asInjection
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("do script") }
        XCTAssertEqual(doScriptLines.count, 1, "payload newline must not create extra AppleScript lines")
        XCTAssertFalse(asInjection.contains("end tell\ntell application \"Finder\""),
                       "payload must not terminate the tell block and inject a new one")
        // The only structural lines are the three we emit.
        XCTAssertEqual(asInjection.split(separator: "\n").count, 4)
    }
}
