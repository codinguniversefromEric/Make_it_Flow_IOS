//
//  AppSettings.swift
//  ePdfUB
//
//  Persistent user preferences via UserDefaults.
//

import Foundation
import SwiftUI
import Combine

// MARK: - App Settings

/// 全域應用程式設定，管理使用者偏好設定
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    

    
    // MARK: - Persisted Keys
    
    /// UserDefaults 所使用的 Keys
    private enum Keys {
        static let selectedModel = "selectedVisionModel"
        static let debugMode = "debugModeEnabled"
    }
    
    // MARK: - Published Properties
    
    /// 選擇的視覺模型 (預設 yolo26m / Medium)
    @Published var selectedModel: VisionModelType {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Keys.selectedModel)
            LayoutVisionManager.shared.setupEngine()
        }
    }
    
    /// 是否啟用 Debug 模式 (顯示 YOLO 框 + 語意標記)
    @Published var debugMode: Bool {
        didSet { UserDefaults.standard.set(debugMode, forKey: Keys.debugMode) }
    }
    
    private init() {
        // 設定為 Nano (yoloFast) 作為預設值，因為 Benchmark 顯示其不僅最快，且錯誤率最低
        let savedModelRaw = UserDefaults.standard.string(forKey: Keys.selectedModel) ?? VisionModelType.yoloFast.rawValue
        #if DEBUG
        self.selectedModel = VisionModelType(rawValue: savedModelRaw) ?? .yoloFast
        #else
        self.selectedModel = .yoloFast
        #endif
        
        #if DEBUG
        self.debugMode = UserDefaults.standard.object(forKey: Keys.debugMode) as? Bool ?? false
        #else
        self.debugMode = false
        UserDefaults.standard.set(false, forKey: Keys.debugMode)
        #endif
    }
}
