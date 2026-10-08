import Foundation

@main
struct QuicklinkTemplateTests {
    static func main() {
        let context = QuicklinkTemplateEngine.ExpansionContext(
            clipboard: "a & b", selection: "selected text", now: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!, makeUUID: { "fixed-id" })
        let link = QuicklinkTemplateEngine.expand(
            text: "https://example.com/?q={clipboard}&s={selection}", context: context,
            encoding: .percentEncoding)
        precondition(link.text == "https://example.com/?q=a%20%26%20b&s=selected%20text")
        let arguments = QuicklinkTemplateEngine.expand(
            text: "{argument name=\"query\"} {argument name=\"lang\" default=\"en\"}", context: context)
        precondition(arguments.missingArguments.map(\.name) == ["query"])
        let supplied = QuicklinkTemplateEngine.expand(
            text: "{argument name=\"query\"}", context: context,
            userArguments: ["query": "{clipboard}"])
        precondition(supplied.text == "{clipboard}")
        let formatted = QuicklinkTemplateEngine.expand(
            text: "{date format=\"yyyy-MM-dd\"} {uuid} {selection | uppercase}", context: context)
        precondition(formatted.text == "1970-01-01 fixed-id SELECTED TEXT")
        precondition(QuicklinkTemplateEngine.usesSelection("{selection}"))
        precondition(!QuicklinkTemplateEngine.usesSelection("plain text"))
        print("Quicklink template checks passed")
    }
}
