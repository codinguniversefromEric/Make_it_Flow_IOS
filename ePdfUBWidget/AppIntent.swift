//
//  AppIntent.swift
//  ePdfUBWidget
//
//  Created by 魏嘉賢 on 2026/6/15.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

@available(iOS 16.1, *)
struct CancelConversionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel Conversion"
    static var description: IntentDescription = IntentDescription("Cancels the current PDF conversion task.")
    
    init() {}
    
    func perform() async throws -> some IntentResult {
        // 發送通知給主 App 請求取消任務
        NotificationCenter.default.post(name: Notification.Name("CancelConversionActivity"), object: nil)
        return .result()
    }
}
