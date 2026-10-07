//
//  StyleRegistry.swift
//  ePdfUB
//
//  Created by Libri-AI Engine.
//

import Foundation
import CoreGraphics
import PDFKit

// MARK: - Style Registry

/// 全域文件樣式分析器
/// 預先掃描整份文件，建立字型大小分佈基準，以提升分類準確度。
struct StyleRegistry: Sendable {
    /// 文件的主要內文字體大小
    let bodyFontSize: CGFloat
    
    /// H1 (大標題) 字體大小閾值
    let h1FontSize: CGFloat
    
    /// H2 (中標題) 字體大小閾值
    let h2FontSize: CGFloat

    /// 初始化並分析 PDF 文件
    /// - Parameter document: 待掃描的 PDF 文件
    /// - Returns: 分析完成的全域樣式註冊表
    nonisolated static func analyze(document: PDFDocument) -> StyleRegistry {
        var allFontSizes: [CGFloat] = []
        var largeFontSizes: [CGFloat] = []
        
        let pageCount = min(document.pageCount, 30) // 最多取前 30 頁作為全域統計樣本，避免記憶體或時間消耗過大
        
        for pageIndex in 0..<pageCount {
            autoreleasepool {
                guard let page = document.page(at: pageIndex) else { return }
                let pageBounds = page.bounds(for: .cropBox)
                
                if let selection = page.selection(for: pageBounds) {
                    for line in selection.selectionsByLine() {
                        guard let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        
                        var fontSize: CGFloat = 12.0
                        if let attrStr = line.attributedString {
                            attrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
                                if let font = value as? AppFont {
                                    fontSize = font.pointSize
                                }
                            }
                        }
                        
                        // 統一使用 2.0 倍率計算，以符合 BatchProcessor 後續的顯示座標系
                        let scaledSize = round(fontSize * 2.0 * 10) / 10
                        allFontSizes.append(scaledSize)
                    }
                }
            }
        }
        
        // 如果完全抓不到文字，給定合理預設值
        guard !allFontSizes.isEmpty else {
            return StyleRegistry(bodyFontSize: 24.0, h1FontSize: 36.0, h2FontSize: 28.0)
        }
        
        // 計算 bodyFontSize (出現頻率最高的字體大小)
        let counts = Dictionary(grouping: allFontSizes, by: { $0 })
        let sortedCounts = counts.sorted(by: { $0.value.count > $1.value.count })
        let bodySize = sortedCounts.first?.key ?? 24.0
        
        // 計算標題大小 (找大於 bodySize 的顯著字體)
        for (size, items) in counts {
            if size > bodySize * 1.1 && items.count > 1 {
                largeFontSizes.append(size)
            }
        }
        largeFontSizes.sort(by: >)
        
        let h1Size: CGFloat
        let h2Size: CGFloat
        
        if largeFontSizes.count >= 2 {
            h1Size = largeFontSizes[0]
            h2Size = largeFontSizes[1]
        } else if largeFontSizes.count == 1 {
            h1Size = largeFontSizes[0]
            h2Size = max(bodySize * 1.2, largeFontSizes[0] * 0.8)
        } else {
            h1Size = bodySize * 1.6
            h2Size = bodySize * 1.2
        }
        
        return StyleRegistry(bodyFontSize: bodySize, h1FontSize: h1Size, h2FontSize: h2Size)
    }
}
