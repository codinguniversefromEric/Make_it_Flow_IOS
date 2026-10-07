//
//  TextFragment.swift
//  ePdfUB
//
//  Created by Libri-AI Engine on 2026/6/14.
//

import Foundation
import CoreGraphics

// MARK: - 核心資料模型：從 PDF 萃取的文字碎片

/// 單行文字碎片，攜帶完整的幾何與排版資訊
struct TextFragment: Sendable {
    let text: String
    let bounds: CGRect          // 顯示座標系 (Y 已翻轉，原點在左上)
    let fontSize: CGFloat
    let fontName: String?
    let isBold: Bool
    let isItalic: Bool
    let colorHex: String
}

// MARK: - Semantic Role

/// 段落語意角色
enum SemanticRole: String, Sendable {
    case title          // 文件標題 (size ≥ 1.6× body, bold, 頁面上方)
    case heading        // 章節標題 (size ≥ 1.2× body)
    case body           // 內文段落
    case footnote       // 頁尾註 (size < 0.85× body, 頁底, < 300 字)
    case caption        // 圖表說明 (size < 0.88× body, < 120 字)
    case listItem       // 列表項目
    case formula        // 數學公式
    case table          // 表格 (由 YOLO 偵測)
    case picture        // 圖片/圖表 (由 YOLO 偵測)
    case pageHeader     // 頁眉 → 應被丟棄
    case pageFooter     // 頁腳 → 應被丟棄
    case pageNumber     // 頁碼 → 應被丟棄
}

// MARK: - Paragraph Block

/// 聚合後的段落區塊
struct ParagraphBlock: Sendable {
    let fragments: [TextFragment]
    var role: SemanticRole
    var unifiedText: String     // 斷字修復、空白合併後的完整文字
    let bounds: CGRect          // 所有碎片的外接矩形

    /// 主要字體大小 (取碎片中出現最多的 fontSize) — cached at init
    let dominantFontSize: CGFloat
    
    /// 粗體比例 (0.0 ~ 1.0) — cached at init
    let boldRatio: CGFloat

    nonisolated init(fragments: [TextFragment], role: SemanticRole, unifiedText: String, bounds: CGRect) {
        self.fragments = fragments
        self.role = role
        self.unifiedText = unifiedText
        self.bounds = bounds
        
        // Cache dominantFontSize
        let sizes = fragments.map { $0.fontSize }
        if sizes.isEmpty {
            self.dominantFontSize = 12.0
        } else {
            let counts = Dictionary(grouping: sizes, by: { round($0 * 10) / 10 })
            self.dominantFontSize = counts.max(by: { $0.value.count < $1.value.count })?.value.first ?? sizes[0]
        }
        
        // Cache boldRatio
        if fragments.isEmpty {
            self.boldRatio = 0.0
        } else {
            let boldCount = fragments.filter { $0.isBold }.count
            self.boldRatio = CGFloat(boldCount) / CGFloat(fragments.count)
        }
    }

    /// 歸一化 Y 位置 (0.0 = 頁頂, 1.0 = 頁底)
    nonisolated func normalizedY(pageHeight: CGFloat) -> CGFloat {
        guard pageHeight > 0 else { return 0.5 }
        return bounds.midY / pageHeight
    }
}

// MARK: - Column Region

/// 欄位區域
struct ColumnRegion: Sendable {
    let xRange: ClosedRange<CGFloat>
    var fragments: [TextFragment]
}

// MARK: - YOLO 偵測到的視覺區域 (圖片/表格/公式)

/// YOLO 識別出的非文字區域，需要物理裁切為圖片
struct VisualRegion: Sendable {
    let label: String       // "Picture", "Table", "Formula", "Figure"
    let rect: CGRect        // 顯示座標系
    let confidence: Float
}

// MARK: - NMS 工具函式 (共用，不再重複)

enum NMSUtils: Sendable {
    /// 計算兩個矩形的 IoU (Intersection over Union)
    nonisolated static func calcIoU(_ rectA: CGRect, _ rectB: CGRect) -> CGFloat {
        let intersection = rectA.intersection(rectB)
        guard !intersection.isNull else { return 0.0 }
        let interArea = intersection.width * intersection.height
        let unionArea = (rectA.width * rectA.height) + (rectB.width * rectB.height) - interArea
        guard unionArea > 0 else { return 0.0 }
        return interArea / unionArea
    }

    /// 計算 inner 被 outer 覆蓋的比例
    nonisolated static func calcCoverage(_ inner: CGRect, _ outer: CGRect) -> CGFloat {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull else { return 0.0 }
        let innerArea = inner.width * inner.height
        guard innerArea > 0 else { return 0.0 }
        return (intersection.width * intersection.height) / innerArea
    }

    /// 對 VNRecognizedObjectObservation 陣列進行 NMS 過濾
    nonisolated static func filterObservations(
        _ observations: [any NSObjectProtocol],
        iouThreshold: CGFloat = 0.4,
        coverageThreshold: CGFloat = 0.8,
        getBoundingBox: (any NSObjectProtocol) -> CGRect,
        getConfidence: (any NSObjectProtocol) -> Float
    ) -> [Int] {
        // 按信心度排序
        let sorted = observations.enumerated().sorted { getConfidence($0.element) > getConfidence($1.element) }
        var keptIndices: [Int] = []
        var keptBoxes: [CGRect] = []

        for (originalIndex, obs) in sorted {
            let box = getBoundingBox(obs)
            var keep = true
            for keptBox in keptBoxes {
                if calcIoU(box, keptBox) > iouThreshold || calcCoverage(box, keptBox) > coverageThreshold {
                    keep = false
                    break
                }
            }
            if keep {
                keptIndices.append(originalIndex)
                keptBoxes.append(box)
            }
        }
        return keptIndices
    }
}
