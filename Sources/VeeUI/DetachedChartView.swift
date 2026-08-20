import SwiftUI
import VeePluginFormat

/// What a detached window is currently showing. The two cases are exactly the
/// read-only popover surfaces: a `sparkline=` series and a `pie=`/`donut=`/
/// `stackedbar=` share chart. Interactive controls (`toggle=`/`slider=`) are
/// deliberately absent — a one-switch floating remote earns its screen space
/// rarely, and a detached control would need its own re-invocation lifetime.
public enum DetachedChartContent: Equatable, Sendable {
    case sparkline([Double])
    case chart(ChartParams)
}

/// Backing model for one detached chart window. The app updates it after every
/// plugin refresh (see `DetachedChartWindows` in `VeeApp`), which is the whole
/// point of the window: it is a live view of one menu row, not a screenshot of
/// the moment it was torn off.
///
/// Shaped like `PluginDebugModel` — the other window that keeps updating while
/// its plugin re-runs — so the two read the same way.
@MainActor
public final class DetachedChartModel: ObservableObject {
    public let pluginName: String
    @Published public var title: String
    @Published public var content: DetachedChartContent
    /// Set when the row this window was torn off from is no longer in the
    /// plugin's menu. The window keeps showing the last value it saw rather
    /// than blanking, but says so — a frozen chart that looks live is worse
    /// than one that admits it is frozen.
    @Published public var isStale: Bool = false

    public init(pluginName: String, title: String, content: DetachedChartContent) {
        self.pluginName = pluginName
        self.title = title
        self.content = content
    }

    public func update(title: String, content: DetachedChartContent) {
        self.title = title
        self.content = content
        self.isStale = false
    }

    public func markStale() {
        isStale = true
    }
}

/// The contents of a detached chart window: the same view the popover shows,
/// kept live by `DetachedChartModel`, plus a note when its row goes away.
public struct DetachedChartView: View {
    @ObservedObject private var model: DetachedChartModel

    public init(model: DetachedChartModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.content {
            case .sparkline(let values):
                SparklineChartView(values: values, title: model.title)
            case .chart(let chart):
                CategoryChartView(chart: chart, title: model.title)
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

/// The corner affordance that turns a popover into a window. Shown only when a
/// host passes a handler, so the detached window itself — which has nothing left
/// to detach — renders without one.
struct DetachButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "macwindow.on.rectangle")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(8)
        .help("Open in a window")
        .accessibilityLabel("Open in a window")
    }
}
