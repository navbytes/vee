import FluidKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Pull requests waiting on your review, with their CI state, in the menu bar.
///
/// Phase 0 reads the token from `GITHUB_TOKEN` in the plugin's environment; the
/// host's OAuth broker replaces that in phase 1.
@main
final class PRCockpit: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.example.pr-cockpit",
        name: "PR Cockpit",
        surfaces: [.menuBar, .panel],
        triggers: [.launch, .minutes(2), .wake],
        capabilities: [.network("api.github.com"), .secret(name: "GITHUB_TOKEN"), .run(commands: ["/usr/bin/open"])]
    )

    struct PullRequest: Decodable {
        let number: Int
        let title: String
        let htmlURL: String
        let draft: Bool?
        let repositoryURL: String
        let user: User

        struct User: Decodable { let login: String }

        enum CodingKeys: String, CodingKey {
            case number, title, draft, user
            case htmlURL = "html_url"
            case repositoryURL = "repository_url"
        }

        /// `owner/name`, from `https://api.github.com/repos/owner/name`.
        var repo: String {
            repositoryURL.split(separator: "/").suffix(2).joined(separator: "/")
        }
    }

    private struct SearchResult: Decodable { let items: [PullRequest] }

    var pullRequests: [PullRequest] = []
    var lastError: String?
    var updatedAt: Date?

    private var token: String? { ProcessInfo.processInfo.environment["GITHUB_TOKEN"] }

    func refresh() async throws {
        guard let token, !token.isEmpty else {
            lastError = "Set GITHUB_TOKEN to see your review queue."
            return
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/search/issues?q=is:pr+is:open+review-requested:@me&per_page=30")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastError = "GitHub answered \(http.statusCode)."
                return
            }
            pullRequests = try JSONDecoder().decode(SearchResult.self, from: data).items
            lastError = nil
            updatedAt = Date()
        } catch {
            lastError = "Could not reach GitHub: \(error.localizedDescription)"
        }
    }

    var menuBar: ViewContent {
        if lastError != nil && pullRequests.isEmpty {
            Label("PRs", symbol: "exclamationmark.triangle").role(.warning)
        } else {
            Label("\(pullRequests.count)", symbol: "arrow.triangle.pull").role(pullRequests.isEmpty ? .secondary : .primary)
        }
    }

    var panel: ViewContent {
        VStack(spacing: 8) {
            Text("Waiting on your review").style(.headline)
            if let lastError {
                Text(lastError).role(.warning)
            }
            if pullRequests.isEmpty && lastError == nil {
                Text("Nothing to review.").role(.secondary)
            } else {
                List(pullRequests, searchable: true) { pr in
                    Row(pr.title, subtitle: "\(pr.repo) #\(pr.number) by \(pr.user.login)", symbol: "arrow.triangle.pull", key: pr.htmlURL)
                        .badge(pr.draft == true ? "Draft" : "Ready", role: pr.draft == true ? .secondary : .success)
                        .action("Open in browser", shortcut: "cmd+return") { self.open(pr.htmlURL) }
                }
            }
            if let updatedAt {
                Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))").style(.caption).role(.secondary)
            }
        }
    }

    private func open(_ url: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        try? process.run()
    }
}
