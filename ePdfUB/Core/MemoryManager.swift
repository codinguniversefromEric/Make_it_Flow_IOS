import Foundation
#if canImport(os)
import os
#endif

// MARK: - Enums

/// 設備記憶體能力分級
public enum DeviceCapability {
    case highEnd // 6GB RAM or more
    case lowEnd  // 4GB RAM or less
}

// MARK: - Memory Manager

/// 記憶體狀態管理器，負責根據裝置記憶體動態調整處理能力
public class MemoryManager {
    public static let shared = MemoryManager()
    
    // Dynamic capability that can be downgraded if memory warnings occur
    public var currentCapability: DeviceCapability
    
    private init() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryInGB = physicalMemory / (1024 * 1024 * 1024)
        
        AppLogger.shared.info("📱 Device Physical Memory: \(memoryInGB) GB")
        
        // 6GB RAM is the threshold for Surya (High-End)
        if memoryInGB >= 6 {
            self.currentCapability = .highEnd
            AppLogger.shared.info("🚀 Device classified as High-End (Surya Engine enabled)")
        } else {
            self.currentCapability = .lowEnd
            AppLogger.shared.info("🔋 Device classified as Low-End (YOLO Engine fallback enabled)")
        }
    }
    
    /// 降級至低階模式，以應對記憶體不足
    public func downgradeToLowEnd() {
        if currentCapability == .highEnd {
            currentCapability = .lowEnd
            AppLogger.shared.warning("⚠️ Memory Warning received! Downgrading to Low-End YOLO Engine.")
        }
    }
    
    /// 檢查系統可用記憶體容量
    public func checkAvailableMemory() -> Int64 {
#if os(iOS)
        if #available(iOS 13.0, *) {
            return Int64(os_proc_available_memory())
        }
#endif
        return -1
    }
}
