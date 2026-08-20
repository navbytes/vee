import SwiftUI
import VeePluginFormat

/// Renders a plugin's interactive `toggle=`/`slider=` control as a compact
/// SwiftUI control on a Liquid Glass surface — rich, *interactive* UI rendered
/// natively, with no WebView. Styling matches `SparklineChartView` (a
/// continuous rounded rectangle over a translucent material) so the two popover
/// kinds read as one family.
///
/// The view owns its live value and calls `onCommit` when the user finishes a
/// change (toggle flip, or slider drag release) so the host can re-invoke the
/// plugin exactly once per settled value rather than on every intermediate tick.
public struct PluginControlView: View {
    private let control: PluginControl
    private let title: String
    private let onCommit: @MainActor (Double) -> Void
    private let onDetach: (() -> Void)?

    @State private var toggleOn: Bool
    @State private var sliderValue: Double
    /// True while a slider drag is in flight. A detached control keeps
    /// receiving the plugin's refreshes, and re-seeding the knob mid-drag would
    /// yank it out from under the user — so incoming values wait.
    @State private var isEditing = false

    /// `onDetach` is supplied by the popover host to offer "open in a window";
    /// the detached window renders the same view without it, since there is
    /// nothing left to detach.
    public init(
        control: PluginControl,
        title: String = "",
        onDetach: (() -> Void)? = nil,
        onCommit: @escaping @MainActor (Double) -> Void
    ) {
        self.control = control
        self.title = title
        self.onDetach = onDetach
        self.onCommit = onCommit
        switch control {
        case .toggle(let on):
            _toggleOn = State(initialValue: on)
            _sliderValue = State(initialValue: on ? 1 : 0)
        case .slider(_, _, let value):
            _toggleOn = State(initialValue: value != 0)
            _sliderValue = State(initialValue: value)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title).font(.headline).lineLimit(1)
            }
            control(for: self.control)
        }
        .padding(14)
        .frame(minWidth: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Corner.popover, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let onDetach { DetachButton(action: onDetach) }
        }
        // In a popover this never fires (it closes before the next refresh); in
        // a detached window it is what keeps the control showing the plugin's
        // real current state instead of the state it had when it was torn off.
        .onChange(of: control) { _, updated in
            guard !isEditing else { return }
            reseed(from: updated)
        }
    }

    /// Adopts a value pushed in from a refresh.
    private func reseed(from control: PluginControl) {
        switch control {
        case .toggle(let on):
            toggleOn = on
            sliderValue = on ? 1 : 0
        case .slider(_, _, let value):
            toggleOn = value != 0
            sliderValue = value
        }
    }

    @ViewBuilder
    private func control(for control: PluginControl) -> some View {
        switch control {
        case .toggle:
            Toggle(isOn: Binding(
                get: { toggleOn },
                set: { toggleOn = $0; onCommit($0 ? 1 : 0) }
            )) {
                Text(toggleOn ? "On" : "Off")
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .tint(.accentColor)

        case .slider(let min, let max, _):
            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: $sliderValue,
                    in: min...max,
                    onEditingChanged: { editing in
                        isEditing = editing
                        // Commit once, when the drag settles.
                        if !editing { onCommit(sliderValue) }
                    }
                )
                .tint(.accentColor)
                HStack {
                    Text(numberString(min)).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text(numberString(sliderValue)).font(.caption).monospacedDigit()
                    Spacer()
                    Text(numberString(max)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func numberString(_ value: Double) -> String {
        CompactNumber.label(value)
    }
}
