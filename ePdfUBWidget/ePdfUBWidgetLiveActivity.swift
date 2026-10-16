
import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Activity Attributes

public struct ePdfUBWidgetAttributes: ActivityAttributes, Sendable {

    public struct ContentState: Codable, Hashable, Sendable {
        public var progress: Double
        public var statusMessage: String

        public init(
            progress: Double,
            statusMessage: String
        ) {
            self.progress = progress
            self.statusMessage = statusMessage
        }
    }

    public var documentName: String

    public init(documentName: String) {
        self.documentName = documentName
    }
}

// MARK: - E-Ink Style

private enum EInk {

    static let black = Color.black
    static let white = Color.white
    static let gray = Color.gray.opacity(0.25)

    static func progress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func percentage(_ value: Double) -> Int {
        Int(progress(value) * 100)
    }
}

// MARK: - Progress Bar

private struct EInkProgressBar: View {

    let progress: Double
    var height: CGFloat = 3
    var foreground: Color = .white
    var track: Color = .gray.opacity(0.25)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {

                Capsule()
                    .fill(track)

                Capsule()
                    .fill(foreground)
                    .frame(
                        width: geometry.size.width *
                            EInk.progress(progress)
                    )
            }
        }
        .frame(height: height)
        .accessibilityLabel("Conversion progress")
        .accessibilityValue(
            "\(EInk.percentage(progress)) percent"
        )
    }
}

// MARK: - Live Activity Widget

struct ePdfUBWidgetLiveActivity: Widget {

    var body: some WidgetConfiguration {

        ActivityConfiguration(
            for: ePdfUBWidgetAttributes.self
        ) { context in

            // MARK: Lock Screen

            VStack(spacing: 12) {

                HStack(spacing: 12) {

                    Image(systemName: "doc.text")
                        .font(.system(size: 23))
                        .foregroundStyle(EInk.black)

                    VStack(alignment: .leading, spacing: 4) {

                        Text(context.attributes.documentName)
                            .font(
                                .system(
                                    size: 15,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(EInk.black)
                            .lineLimit(1)

                        Text(context.state.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                EInk.black.opacity(0.6)
                            )
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(
                        "\(EInk.percentage(context.state.progress))%"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(EInk.black)
                    .monospacedDigit()
                }

                EInkProgressBar(
                    progress: context.state.progress,
                    height: 3,
                    foreground: EInk.black,
                    track: EInk.gray
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(EInk.white)
            .activityBackgroundTint(EInk.white)
            .activitySystemActionForegroundColor(EInk.black)

        } dynamicIsland: { context in

            DynamicIsland {

                // MARK: Expanded Leading

                // MARK: - Expanded Leading

                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(EInk.white)
                        .frame(width: 40, height: 50)
                        .padding(.leading, 0)
                        .accessibilityHidden(true)
                }

                // MARK: - Expanded Trailing

                // MARK: - Expanded Trailing

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.progress < 1 {
                        Button(intent: CancelConversionIntent()) {
                            ZStack {
                                Circle()
                                    .stroke(.white.opacity(0.15), lineWidth: 1.5)

                                Circle()
                                    .trim(
                                        from: 0,
                                        to: min(max(context.state.progress, 0), 1)
                                    )
                                    .stroke(
                                        .white.opacity(0.9),
                                        style: StrokeStyle(
                                            lineWidth: 1.5,
                                            lineCap: .round
                                        )
                                    )
                                    .rotationEffect(.degrees(-90))

                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .frame(width: 40, height: 50)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel conversion")
                        .accessibilityValue(
                            "\(Int(min(max(context.state.progress, 0), 1) * 100)) percent"
                        )
                    }
                }

                // MARK: - Expanded Center

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.documentName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // MARK: - Expanded Bottom

                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {

                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EInk.white)
                    .frame(width: 18, height: 18)

            } compactTrailing: {

                Text("\(EInk.percentage(context.state.progress))%")
                    .font(
                        .system(
                            size: 10,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(EInk.white)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)

            } minimal: {

                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EInk.white)
            }
            .keylineTint(EInk.white)
        }
    }
}

// MARK: - Previews

#Preview(
    "Expanded",
    as: .dynamicIsland(.expanded),
    using: ePdfUBWidgetAttributes(
        documentName: "Medical_Report.pdf"
    )
) {
    ePdfUBWidgetLiveActivity()
} contentStates: {

    ePdfUBWidgetAttributes.ContentState(
        progress: 0.45,
        statusMessage: "Processing page 5 of 12"
    )

    ePdfUBWidgetAttributes.ContentState(
        progress: 1.0,
        statusMessage: "Done"
    )
}

#Preview(
    "Compact",
    as: .dynamicIsland(.compact),
    using: ePdfUBWidgetAttributes(
        documentName: "Medical_Report.pdf"
    )
) {
    ePdfUBWidgetLiveActivity()
} contentStates: {

    ePdfUBWidgetAttributes.ContentState(
        progress: 0.45,
        statusMessage: "Processing page 5 of 12"
    )
    ePdfUBWidgetAttributes.ContentState(
        progress: 1,
        statusMessage: "Done"
    )
}

#Preview(
    "Lock Screen",
    as: .content,
    using: ePdfUBWidgetAttributes(
        documentName: "Medical_Report.pdf"
    )
) {
    ePdfUBWidgetLiveActivity()
} contentStates: {

    ePdfUBWidgetAttributes.ContentState(
        progress: 0.45,
        statusMessage: "Processing page 5 of 12"
    )
}
