import SwiftUI

/// The frame Vee draws around *every* plugin popover, and the only place the
/// "open in a window" affordance lives.
///
/// Detaching is a property of the popover, not of what happens to be inside it:
/// a sparkline, a share chart, and a `toggle=`/`slider=` control are all just
/// content, and none of them should have to know they can be torn off. Keeping
/// the button here means one implementation and one position for all of them,
/// and content views that stay content views.
///
/// The detached window renders the same content views with no chrome around
/// them — it has nothing left to detach.
public struct PopoverChrome<Content: View>: View {
    private let onDetach: (() -> Void)?
    private let content: Content

    /// `onDetach` is supplied by the popover host; passing `nil` renders the
    /// content bare, which is what suppresses the button where detaching would
    /// not work.
    public init(onDetach: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onDetach = onDetach
        self.content = content()
    }

    public var body: some View {
        // Overlaid *outside* the content, which also keeps the button its own
        // VoiceOver target: `CategoryChartView` combines its children into one
        // accessibility element, and a button drawn inside that would be folded
        // into the chart's spoken summary.
        content
            .overlay(alignment: .topTrailing) {
                if let onDetach { DetachButton(action: onDetach) }
            }
    }
}

/// The corner affordance that turns a popover into a window.
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
