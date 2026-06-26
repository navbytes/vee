import Foundation
import VeeProtocol

/// On-disk plugin discovery for the live app.
///
/// A discovered plugin is a parsed `vee.json` manifest paired with its bundle JS
/// source (the IIFE the host evaluates) and a launcher icon hint.
///
/// Two layouts are searched, in order:
///
/// 1. **Production (packaged `.app`)** —
///    `Bundle.main.resourcePath/vee-plugins/<id>/{vee.json,bundle.js}`.
///    Each plugin is its own folder named by manifest id; `vee.json` is the
///    `PluginManifest` and `bundle.js` is the built single-file bundle. The
///    packaging script writes exactly this layout.
///
/// 2. **Dev fallback (running from the repo)** — iterate
///    `<cwd>/plugins/samples/*/vee.json` and pair each with
///    `<cwd>/plugins/fixtures/<manifest.id>.bundle.js`. This mirrors the repo's
///    checked-in sample manifests + prebuilt fixture bundles, so `swift run vee`
///    surfaces every sample without a packaging step.
///
/// Pure-ish (filesystem reads only, no host/AppKit), so discovery can be reasoned
/// about independently of wiring.
enum PluginDiscovery {

    /// One discovered plugin ready to `host.load`.
    struct Discovered {
        let manifest: PluginManifest
        /// The bundle JS source (already read off disk).
        let source: String
        /// Launcher icon hint (SF Symbol name) for the `cmd:` root candidate.
        let icon: String
    }

    /// Per-id launcher icon hints. Anything not listed falls back to
    /// `defaultIcon`. Reverse-DNS ids keep these readable + in one place.
    static let iconByID: [String: String] = [
        "com.vee.essentials": "command",
        "com.vee.clipboard": "doc.on.clipboard",
        "com.vee.hacker-news": "newspaper",
        "com.vee.github": "checkmark.seal",
        "com.vee.snippets": "text.quote",
        "com.vee.meetings": "calendar",
        "com.vee.jira": "ladybug",
        "com.vee.api": "network",
    ]

    /// Default icon for a plugin with no specific mapping.
    static let defaultIcon = "puzzlepiece"

    /// Discover every plugin on disk (production Resources first, dev fallback
    /// otherwise). Manifests that fail to parse or whose bundle can't be read are
    /// skipped (a single bad plugin must not block the others). Results are sorted
    /// by id for a stable, deterministic order in the root list.
    static func discoverAll(bundle: Bundle = .main,
                            fileManager: FileManager = .default,
                            currentDirectory: String = FileManager.default.currentDirectoryPath)
        -> [Discovered] {
        var found = discoverFromResources(bundle: bundle, fileManager: fileManager)
        if found.isEmpty {
            found = discoverFromDevTree(currentDirectory: currentDirectory, fileManager: fileManager)
        }
        // R2-HIGH-3 (plugin authenticity): refuse duplicate ids. Plugins load only
        // from the signed app bundle (or the dev tree) — there is no user-droppable
        // external dir — so the trust root is the app's own signature. As a guard
        // against a manifest claiming another plugin's id (which keys Keychain
        // isolation), the first occurrence after a stable sort wins and any later
        // duplicate id is dropped — a spoofed/duplicate id cannot shadow a real
        // plugin to reach its Keychain namespace. (Full per-plugin code-signing is
        // deferred until an external plugin-install path exists.)
        var seen = Set<String>()
        var deduped: [Discovered] = []
        for d in found.sorted(by: { $0.manifest.id < $1.manifest.id }) {
            guard seen.insert(d.manifest.id).inserted else {
                FileHandle.standardError.write(Data(
                    "vee: refused duplicate plugin id '\(d.manifest.id)'\n".utf8))
                continue
            }
            deduped.append(d)
        }
        return deduped
    }

    // MARK: - Production: Resources/vee-plugins/<id>/{vee.json,bundle.js}

    private static func discoverFromResources(bundle: Bundle,
                                              fileManager: FileManager) -> [Discovered] {
        guard let resourcePath = bundle.resourcePath else { return [] }
        let root = (resourcePath as NSString).appendingPathComponent("vee-plugins")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { return [] }

        var out: [Discovered] = []
        for entry in entries {
            let dir = (root as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let manifestPath = (dir as NSString).appendingPathComponent("vee.json")
            let bundlePath = (dir as NSString).appendingPathComponent("bundle.js")
            if let discovered = load(manifestPath: manifestPath, bundlePath: bundlePath) {
                // R2-HIGH-3: bind identity to the trusted install layout. The
                // packaging script names each folder by manifest id, so a manifest
                // claiming an id other than its own folder is refused — it can't
                // pose as another plugin (and reach that id's Keychain namespace).
                guard discovered.manifest.id == entry else {
                    FileHandle.standardError.write(Data(
                        "vee: plugin id '\(discovered.manifest.id)' != folder '\(entry)' — refusing\n".utf8))
                    continue
                }
                out.append(discovered)
            }
        }
        return out
    }

    // MARK: - Dev: plugins/samples/*/vee.json + plugins/fixtures/<id>.bundle.js

    private static func discoverFromDevTree(currentDirectory: String,
                                           fileManager: FileManager) -> [Discovered] {
        let samples = ((currentDirectory as NSString)
            .appendingPathComponent("plugins") as NSString)
            .appendingPathComponent("samples")
        let fixtures = ((currentDirectory as NSString)
            .appendingPathComponent("plugins") as NSString)
            .appendingPathComponent("fixtures")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: samples) else { return [] }

        var out: [Discovered] = []
        for entry in entries.sorted() {
            let manifestPath = (((samples as NSString)
                .appendingPathComponent(entry)) as NSString)
                .appendingPathComponent("vee.json")
            guard let manifest = parseManifest(at: manifestPath, fileManager: fileManager) else {
                continue
            }
            // Fixture bundles are named by manifest id, not folder name.
            let bundlePath = (fixtures as NSString)
                .appendingPathComponent("\(manifest.id).bundle.js")
            guard let source = try? String(contentsOfFile: bundlePath, encoding: .utf8) else {
                continue
            }
            out.append(Discovered(manifest: manifest, source: source, icon: icon(for: manifest.id)))
        }
        return out
    }

    // MARK: - Shared helpers

    /// Load a `vee.json` + `bundle.js` pair into a `Discovered`, or nil if either
    /// is missing/unreadable or the manifest is malformed.
    private static func load(manifestPath: String, bundlePath: String) -> Discovered? {
        guard let manifest = parseManifest(at: manifestPath, fileManager: .default),
              let source = try? String(contentsOfFile: bundlePath, encoding: .utf8) else {
            return nil
        }
        return Discovered(manifest: manifest, source: source, icon: icon(for: manifest.id))
    }

    /// Decode a `PluginManifest` from a `vee.json` file, or nil on read/parse error.
    ///
    /// Decodes through a LENIENT mirror rather than `PluginManifest` directly:
    /// `PluginManifest`/`PluginCommand`/`Capabilities` (frozen in VeeProtocol)
    /// synthesize Codable conformances that REQUIRE every non-optional key — but
    /// the checked-in sample/shipped `vee.json` files omit fields that carry
    /// `init` defaults (notably `command.hotkeyActions`). Decoding the real types
    /// directly therefore throws `keyNotFound`. The mirror makes those fields
    /// optional and reconstructs the real values via their initializers (which
    /// supply the defaults), so a manifest that omits a defaulted field still
    /// loads. This is the app-side parsing concern; VeeProtocol stays untouched.
    private static func parseManifest(at path: String, fileManager: FileManager) -> PluginManifest? {
        guard let data = fileManager.contents(atPath: path) else { return nil }
        guard let lenient = try? JSONDecoder().decode(LenientManifest.self, from: data) else {
            return nil
        }
        return lenient.toManifest()
    }

    // MARK: - Lenient manifest mirror (tolerates omitted, init-defaulted fields)

    /// Mirror of `PluginManifest` whose every field defaults, so a `vee.json` that
    /// omits a value carrying an `init` default still decodes. Reconstructs the
    /// real `PluginManifest` via its initializer.
    private struct LenientManifest: Decodable {
        var id: String
        var name: String?
        var version: String?
        var entrypoint: String?
        var commands: [LenientCommand]?
        var capabilities: LenientCapabilities?
        /// Extension-level declared preferences. `PluginPreference` decodes
        /// leniently on its own (only name/type/title are required), so the real
        /// type is decoded directly here.
        var preferences: [PluginPreference]?

        func toManifest() -> PluginManifest {
            PluginManifest(
                id: id,
                name: name ?? id,
                version: version ?? "0.0.0",
                entrypoint: entrypoint ?? "",
                commands: (commands ?? []).map { $0.toCommand() },
                capabilities: capabilities?.toCapabilities() ?? Capabilities(),
                preferences: preferences ?? [])
        }
    }

    private struct LenientCommand: Decodable {
        var name: String
        var title: String?
        var subtitle: String?
        var mode: String?
        var refreshIntervalSeconds: Double?
        var hotkeyActions: [String]?
        var preferences: [PluginPreference]?

        func toCommand() -> PluginCommand {
            PluginCommand(
                name: name,
                title: title ?? name,
                subtitle: subtitle,
                mode: PluginCommand.Mode(rawValue: mode ?? "view") ?? .view,
                refreshIntervalSeconds: refreshIntervalSeconds,
                hotkeyActions: hotkeyActions ?? [],
                preferences: preferences ?? [])
        }
    }

    private struct LenientCapabilities: Decodable {
        var network: [String]?
        var open: [String]?
        var filesystem: [String]?
        var clipboard: Bool?
        var calendar: Bool?
        var keychainNamespaces: [String]?
        var hotkeyActions: [String]?

        func toCapabilities() -> Capabilities {
            Capabilities(
                network: network ?? [],
                open: open ?? [],
                filesystem: filesystem ?? [],
                clipboard: clipboard ?? false,
                calendar: calendar ?? false,
                keychainNamespaces: keychainNamespaces ?? [],
                hotkeyActions: hotkeyActions ?? [])
        }
    }

    private static func icon(for id: String) -> String {
        iconByID[id] ?? defaultIcon
    }
}
