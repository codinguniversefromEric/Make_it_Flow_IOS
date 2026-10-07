//
//  LiveActivityManager.swift
//  ePdfUB
//
//  Created by Libri-AI on 2026/07/08.
//

import Foundation

#if os(iOS)
import ActivityKit

// MARK: - Activity Tracking

/// 追蹤與管理動態島及鎖定畫面的即時活動
@MainActor final class LiveActivityManager {
    private var currentActivity: Activity<ePdfUBWidgetAttributes>? = nil
    
    init() {
        Task {
            for activity in Activity<ePdfUBWidgetAttributes>.activities {
                let finalState = ePdfUBWidgetAttributes.ContentState(progress: 0.0, statusMessage: "Cancelled")
                if #available(iOS 16.2, *) {
                    await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                } else {
                    await activity.end(using: finalState, dismissalPolicy: .immediate)
                }
            }
        }
    }
    
    /// 開始追蹤即時活動
    func start(documentName: String) {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = ePdfUBWidgetAttributes(documentName: documentName)
            let initialState = ePdfUBWidgetAttributes.ContentState(progress: 0.0, statusMessage: "Starting...")
            do {
                if #available(iOS 16.2, *) {
                    self.currentActivity = try Activity.request(attributes: attributes, content: .init(state: initialState, staleDate: nil))
                } else {
                    self.currentActivity = try Activity.request(attributes: attributes, contentState: initialState)
                }
            } catch {
                AppLogger.shared.error("Activity request failed: \(error)")
            }
        }
    }
    
    /// 更新即時活動進度與狀態訊息
    func update(progress: Double, message: String) async {
        guard let activity = currentActivity else { return }
        let currentState = ePdfUBWidgetAttributes.ContentState(progress: progress, statusMessage: message)
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: currentState, staleDate: nil))
        } else {
            await activity.update(using: currentState)
        }
    }
    
    /// 結束即時活動
    func end(progress: Double, message: String) async {
        guard let activity = currentActivity else { return }
        let finalState = ePdfUBWidgetAttributes.ContentState(progress: progress, statusMessage: message)
        if #available(iOS 16.2, *) {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        } else {
            await activity.end(using: finalState, dismissalPolicy: .immediate)
        }
        self.currentActivity = nil
    }
}
#else
final class LiveActivityManager {
    init() {}
    func start(documentName: String) {}
    func update(progress: Double, message: String) async {}
    func end(progress: Double, message: String) async {}
}
#endif

// MARK: - Intents

#if os(iOS)
import AppIntents

/// 取消轉換任務的意圖，供 Live Activity 介面使用
@available(iOS 16.1, *)
public struct CancelConversionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Cancel Conversion"
    public static var description: IntentDescription = IntentDescription("Cancels the current PDF conversion task.")
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("CancelConversionActivity"), object: nil)
        return .result()
    }
}
#endif
