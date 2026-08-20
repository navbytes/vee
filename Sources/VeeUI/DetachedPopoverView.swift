import SwiftUI
import VeePluginFormat

/// What a detached window is currently showing — one case per popover kind Vee
/// opens from a menu row, so every popover can be torn off, not just the
/// read-only ones. (`webview=` is absent because it is already a window.)
public enum DetachedPopoverContent: Equatable, Sendable {
    case sparkline([Double])
    case chart(ChartParams)
    case control(PluginControl)
}

/// Backing model for one detached popover window. The app updates it after every
/// plugin refresh (see `DetachedPopoverWindows` in `VeeApp`), which is the whole
/// point of the window: it is a live view of one menu row, not a screenshot of
/// the moment it was torn off.
///
/// Shaped like `PluginDebugModel` — the other window that keeps updating while
/// its plugin re-runs — so the two read the same way.
@MainActor
public final class DetachedPopoverModel: ObservableObject {
    public let pluginName: String
    @Published public var title: String
    @Published public var content: DetachedPopoverContent
    /// Set when the row this window was torn off from is no longer in the
    /// plugin's menu. The window keeps showing the last value it saw rather
    /// than blanking, but says so — a frozen reading that looks live is worse
    /// than one that admits it is frozen.
    @Published public var isStale: Bool = false

    /// `onCommit` carries a detached `toggle=`/`slider=` back to the plugin.
    /// Read-only windows pass nothing and never call it.
    private let onCommit: @MainActor (Double) -> Void

    public init(
        pluginName: String,
        title: String,
        content: DetachedPopoverContent,
        onCommit: @escaping @MainActor (Double) -> Void = { _ in }
    ) {
        self.pluginName = pluginName
        self.title = title
        self.content = content
        self.onCommit = onCommit
    }

    /// Called by a detached control when the user settles on a new value. The
    /// window resolves the row's *current* command before running it, so a
    /// detached control keeps working across refreshes rather than firing the
    /// command the row happened to carry when it was torn off.
    public func commit(_ value: Double) {
        onCommit(value)
    }

    public func update(title: String, content: DetachedPopoverContent) {
        self.title = title
        self.content = content
        self.isStale = false
    }

    public func markStale() {
        isStale = true
    }
}

/// The contents of a detached popover window: the same view the popover shows,
/// kept live by `DetachedPopoverModel`, plus a note when its row goes away.
public struct DetachedPopoverView: View {
    @ObservedObject private var model: DetachedPopoverModel

    public init(model: DetachedPopoverModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.content {
            case .sparkline(let values):
                SparklineChartView(values: values, title: model.title)
            case .chart(let chart):
                CategoryChartView(chart: chart, title: model.title)
            case .control(let control):
                PluginControlView(control: control, title: model.title) { value in
                    model.commit(value)
                }
            }
            if model.isStale { staleNote }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var staleNote: some View {
        Label("This row is no longer in \(model.pluginName)'s menu — showing the last value.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
