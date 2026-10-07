import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

public struct ePdfUBWidgetAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var progress: Double
        public var statusMessage: String
    }

    public var documentName: String
}

struct ePdfUBWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ePdfUBWidgetAttributes.self) { context in
            // Lock screen / Notification Center UI
            HStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.documentName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                }
                .frame(width: 44, height: 44)
            }
            .padding()
            // Let the system materialize the background rather than forcing a flat tint —
            // keeps correct contrast in both light and dark mode.
            .activityBackgroundTint(Color(UIColor.secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                // Use leading/trailing instead of leaving them empty — this is what gives
                // the Dynamic Island its "one integrated shape" feel rather than a single
                // block crammed into .bottom.
                DynamicIslandExpandedRegion(.leading) {
                    // 左側：精緻的文件圖標 (模仿 Apple Music 專輯封面排版)
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // 右側：半透明的圓形取消按鈕
                    Button(intent: CancelConversionIntent()) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    // 留空
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // 底部：主資訊與高質感進度條
                    VStack(spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(context.attributes.documentName)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text(context.state.statusMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 16)
                            
                            Text("\(Int(context.state.progress * 100))%")
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                                .contentTransition(.numericText())
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(height: 10)
                                
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(0, geo.size.width * context.state.progress), height: 10)
                                    .shadow(color: Color.accentColor.opacity(0.4), radius: 4, x: 0, y: 0)
                            }
                        }
                        .frame(height: 10)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "doc.viewfinder")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            } minimal: {
                Image(systemName: "doc.viewfinder")
                    .foregroundStyle(.tint)
            }
            .keylineTint(Color.accentColor)
        }
    }
}
// MARK: - Previews

#Preview("Expanded", as: .dynamicIsland(.expanded), using: ePdfUBWidgetAttributes(documentName: "Medical_Report_2026.pdf")) {
    ePdfUBWidgetLiveActivity()
} contentStates: {
    ePdfUBWidgetAttributes.ContentState(progress: 0.45, statusMessage: "Processing Page 5 of 12...")
    ePdfUBWidgetAttributes.ContentState(progress: 1.0, statusMessage: "Done!")
}

#Preview("Compact", as: .dynamicIsland(.compact), using: ePdfUBWidgetAttributes(documentName: "Medical_Report_2026.pdf")) {
    ePdfUBWidgetLiveActivity()
} contentStates: {
    ePdfUBWidgetAttributes.ContentState(progress: 0.45, statusMessage: "Processing Page 5 of 12...")
}

#Preview("Lock Screen", as: .content, using: ePdfUBWidgetAttributes(documentName: "Medical_Report_2026.pdf")) {
    ePdfUBWidgetLiveActivity()
} contentStates: {
    ePdfUBWidgetAttributes.ContentState(progress: 0.45, statusMessage: "Processing Page 5 of 12...")
}
