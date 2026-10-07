//
//  TableReconstructor.swift
//  ePdfUB
//
//  Created by Libri-AI Engine on 2026/6/15.
//

import Foundation
import CoreGraphics

// MARK: - 表格結構解析器

/// 啟發式表格結構解析器 (Rule-based Table Structure Recognition)
enum TableReconstructor: Sendable {
    
    /// 嘗試將表格區域內的文字碎片重建為 Markdown 表格
    /// - Parameters:
    ///   - fragments: 落在表格視覺區域內的文字碎片
    ///   - tableBounds: 表格的邊界 (顯示座標系)
    /// - Returns: 若成功重建則回傳 Markdown 表格字串，否則回傳 nil (交由影像裁切處理)
    // MARK: - 核心解析方法
    
    nonisolated static func reconstruct(fragments: [TextFragment], tableBounds: CGRect) -> String? {
        // FIXME: 目前 DocLayNet 模型不具備 Cell (儲存格) 級別的辨識能力，
        // 且 PDFKit 經常將表格列合併，導致啟發式解析失敗。
        // 為了避免產生「每行都只有一欄」的破碎表格，這裡強制返回 nil，
        // 讓系統自動退回使用高品質的「圖片裁切」來保留表格原始樣貌。
        return nil
    }
}
