//
//  LayoutEngine.swift
//  Flow_1
//
//  Created by Libri-AI Engine on 2026/6/14.
//

import Foundation
import CoreGraphics
import Vision

// MARK: - 佈局分析引擎：基於 YOLO 區塊的語意重組與幾何排序

enum LayoutEngine: Sendable {

    // MARK: - Cached Regex Patterns
    private static let eqRegex = try! NSRegularExpression(pattern: "(?i)(Accuracy|Precision|Sensitivity|score|Recall|Specificity)\\s*\u{FFFD}\\s*")
    private static let mulRegex = try! NSRegularExpression(pattern: "([0-9A-Za-z])\\s*\u{FFFD}\\s*([0-9A-Za-z])")

    // MARK: - 1. 基於 LayoutBlock 的核心處理流程

    /// 使用 YOLO 給出的區塊，將 PDFKit 散落的文字碎片重新排序與封裝
    /// - Parameters:
    ///   - fragments: PDFKit 萃取的底層文字碎片
    ///   - blocks: YOLO 偵測出的佈局區塊 (LayoutBlock)
    ///   - pageWidth: 頁面寬度
    ///   - pageHeight: 頁面高度
    /// - Returns: 依人類閱讀順序排序好的完美段落

    nonisolated static func processWithLayoutBlocks(
        fragments: [TextFragment],
        blocks: [LayoutBlock],
        pageWidth: CGFloat,
        pageHeight: CGFloat
    ) -> [ParagraphBlock] {
        guard !fragments.isEmpty else { return [] }
        guard !blocks.isEmpty else {
            return []
        }

        // 1. 幾何排序 YOLO 區塊 (Reading Order Algorithm)
        let sortedBlocks = sortLayoutBlocks(blocks, pageWidth: pageWidth, pageHeight: pageHeight)

        // 2. 將文字碎片分配到排序好的 YOLO 區塊中
        var blockFragmentsMap: [UUID: [TextFragment]] = [:]
        var unassignedFragments: [TextFragment] = []
        
        for frag in fragments {
            let fragArea = frag.bounds.width * frag.bounds.height
            let fragMid = CGPoint(x: frag.bounds.midX, y: frag.bounds.midY)
            
            if let matchedBlock = sortedBlocks.first(where: {
                let rect = VNImageRectForNormalizedRect($0.boundingBox, Int(pageWidth), Int(pageHeight))
                let invertedRect = CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
                
                let intersection = invertedRect.intersection(frag.bounds)
                if !intersection.isNull {
                    let intersectionArea = intersection.width * intersection.height
                    let expanded = invertedRect.insetBy(dx: -5, dy: -5)
                    return (fragArea > 0 && intersectionArea / fragArea > 0.4) || expanded.contains(fragMid)
                } else {
                    let expanded = invertedRect.insetBy(dx: -5, dy: -5)
                    return expanded.contains(fragMid)
                }
            }) {
                blockFragmentsMap[matchedBlock.id, default: []].append(frag)
            } else {
                unassignedFragments.append(frag)
            }
        }

        // 3. 依序組裝 YOLO 的 ParagraphBlock
        var finalParagraphs: [ParagraphBlock] = []
        for block in sortedBlocks {
            guard let frags = blockFragmentsMap[block.id], !frags.isEmpty else { continue }
            let sortedFrags = frags.sorted { a, b in
                let yA = round(a.bounds.midY / 10.0)
                let yB = round(b.bounds.midY / 10.0)
                if yA == yB {
                    return a.bounds.minX < b.bounds.minX
                }
                return yA < yB
            }
            let role = mapYoloLabelToRole(block.label)
            finalParagraphs.append(buildParagraphBlock(from: sortedFrags, role: role))
        }

        // 4. 對未被 YOLO 框選的碎片進行 fallback 處理，避免漏字
        if !unassignedFragments.isEmpty {
            // 按 Y 軸排序，然後用 proximity grouping 組裝成段落
            let ySortedOrphans = unassignedFragments.sorted { a, b in
                let yA = round(a.bounds.midY / 10.0)
                let yB = round(b.bounds.midY / 10.0)
                if yA == yB {
                    return a.bounds.minX < b.bounds.minX
                }
                return yA < yB
            }
            var currentGroup: [TextFragment] = [ySortedOrphans[0]]
            
            for i in 1..<ySortedOrphans.count {
                let curr = ySortedOrphans[i]
                let prevMaxY = currentGroup.last!.bounds.maxY
                // 如果 Y 軸間隔小於一行高度 (約 20pt)，視為同一段落
                if curr.bounds.minY - prevMaxY < 20.0 {
                    currentGroup.append(curr)
                } else {
                    finalParagraphs.append(buildParagraphBlock(from: currentGroup, role: .body))
                    currentGroup = [curr]
                }
            }
            if !currentGroup.isEmpty {
                finalParagraphs.append(buildParagraphBlock(from: currentGroup, role: .body))
            }
        }
            
        // 將所有段落使用標準的閱讀順序排序 (分區段 -> 分欄 -> 排序)
        return sortParagraphBlocks(finalParagraphs, pageWidth: pageWidth)
    }

    // MARK: - 段落排序

    /// 對最終的 ParagraphBlock 進行閱讀順序排序
    private nonisolated static func sortParagraphBlocks(_ blocks: [ParagraphBlock], pageWidth: CGFloat) -> [ParagraphBlock] {
        guard blocks.count > 1 else { return blocks }
        
        let ySorted = blocks.sorted { $0.bounds.minY < $1.bounds.minY }
        
        var regions: [[ParagraphBlock]] = []
        var currentRegion: [ParagraphBlock] = [ySorted[0]]
        var currentMaxY = ySorted[0].bounds.maxY
        let regionBreakGap = pageWidth * 0.15
        
        for i in 1..<ySorted.count {
            let curr = ySorted[i]
            let gap = curr.bounds.minY - currentMaxY
            
            // 如果這是一個佔據版面 > 60% 的超寬區塊 (例如大標題、摘要)，強制切斷 Region！
            // 這樣可以避免置中標題被吸進雙欄的排序災難裡
            // 注意：雙欄論文每欄約 45% 寬，所以閾值必須 > 0.5
            let isFullWidth = curr.bounds.width > (pageWidth * 0.6)
            let prevIsFullWidth = currentRegion.last!.bounds.width > (pageWidth * 0.6)
            
            if gap > regionBreakGap || isFullWidth || prevIsFullWidth {
                regions.append(currentRegion)
                currentRegion = [curr]
                currentMaxY = curr.bounds.maxY
            } else {
                currentRegion.append(curr)
                currentMaxY = max(currentMaxY, curr.bounds.maxY)
            }
        }
        if !currentRegion.isEmpty { regions.append(currentRegion) }
        
        var finalSorted: [ParagraphBlock] = []
        
        for region in regions {
            if region.count <= 1 {
                finalSorted.append(contentsOf: region)
                continue
            }
            
            // 使用「區塊中線 (Center X)」來分欄，徹底解決 minX 因為突發寬度而崩潰的問題
            let xSorted = region.sorted { $0.bounds.midX < $1.bounds.midX }
            var columns: [[ParagraphBlock]] = []
            var currentColumn: [ParagraphBlock] = [xSorted[0]]
            
            for i in 1..<xSorted.count {
                let curr = xSorted[i]
                let prev = currentColumn.last!
                let centerJump = curr.bounds.midX - prev.bounds.midX
                
                if centerJump > pageWidth * 0.15 {
                    columns.append(currentColumn)
                    currentColumn = [curr]
                } else {
                    currentColumn.append(curr)
                }
            }
            if !currentColumn.isEmpty { columns.append(currentColumn) }
            
            for col in columns {
                let ySortedCol = col.sorted { a, b in
                    let yA = round(a.bounds.midY / 15.0)
                    let yB = round(b.bounds.midY / 15.0)
                    if yA == yB {
                        return a.bounds.minX < b.bounds.minX
                    }
                    return yA < yB
                }
                finalSorted.append(contentsOf: ySortedCol)
            }
        }
        
        return finalSorted
    }
    // MARK: - 2. 閱讀順序演算法 (XY-Cut / Projection Profile)

    /// 根據人類閱讀邏輯 (先上後下，先左後右)，對 YOLO 區塊進行幾何排序
    private nonisolated static func sortLayoutBlocks(_ blocks: [LayoutBlock], pageWidth: CGFloat, pageHeight: CGFloat) -> [LayoutBlock] {
        // 先換算成顯示座標的 CGRect
        let rectBlocks: [(block: LayoutBlock, rect: CGRect)] = blocks.map {
            let rect = VNImageRectForNormalizedRect($0.boundingBox, Int(pageWidth), Int(pageHeight))
            let inverted = CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
            return ($0, inverted)
        }
        
        // 按照 Y 座標由上而下初步排序
        let ySorted = rectBlocks.sorted { $0.rect.minY < $1.rect.minY }
        
        // 1. Y 軸大區塊切割 (Region Segmentation)
        var regions: [[(block: LayoutBlock, rect: CGRect)]] = []
        var currentRegion: [(block: LayoutBlock, rect: CGRect)] = [ySorted[0]]
        var currentMaxY = ySorted[0].rect.maxY
        let regionBreakGap = pageWidth * 0.15
        
        for i in 1..<ySorted.count {
            let curr = ySorted[i]
            let gap = curr.rect.minY - currentMaxY
            
            // 如果遇到明顯的 Y 軸斷層，視為新區塊 (例如摘要結束、雙欄開始)
            if gap > regionBreakGap {
                regions.append(currentRegion)
                currentRegion = [curr]
                currentMaxY = curr.rect.maxY
            } else {
                currentRegion.append(curr)
                currentMaxY = max(currentMaxY, curr.rect.maxY)
            }
        }
        if !currentRegion.isEmpty {
            regions.append(currentRegion)
        }
        
        // 2. 針對每個 Region 進行 X 軸分欄與排序
        var finalSortedBlocks: [LayoutBlock] = []
        
        for region in regions {
            let sortedRegionBlocks = sortRegionColumns(region, pageWidth: pageWidth)
            finalSortedBlocks.append(contentsOf: sortedRegionBlocks.map { $0.block })
        }
        
        return finalSortedBlocks
    }

    /// 在一個水平大區塊 (Region) 內，區分出左右欄位並進行排序
    private nonisolated static func sortRegionColumns(_ region: [(block: LayoutBlock, rect: CGRect)], pageWidth: CGFloat) -> [(block: LayoutBlock, rect: CGRect)] {
        guard region.count > 1 else { return region }
        
        // 判斷該 Region 是否只有單一寬區塊，避免強制分欄
        let xSorted = region.sorted { $0.rect.midX < $1.rect.midX }
        
        var columns: [[(block: LayoutBlock, rect: CGRect)]] = []
        var currentColumn: [(block: LayoutBlock, rect: CGRect)] = [xSorted[0]]
        
        for i in 1..<xSorted.count {
            let curr = xSorted[i]
            let prev = currentColumn.last!
            let centerJump = curr.rect.midX - prev.rect.midX
            
            // 基於 Center X 分欄
            if centerJump > pageWidth * 0.15 {
                columns.append(currentColumn)
                currentColumn = [curr]
            } else {
                currentColumn.append(curr)
            }
        }
        if !currentColumn.isEmpty { columns.append(currentColumn) }
        
        var sortedRegion: [(block: LayoutBlock, rect: CGRect)] = []
        for col in columns {
            let ySortedCol = col.sorted { a, b in
                let yA = round(a.rect.minY / 15.0)
                let yB = round(b.rect.minY / 15.0)
                if yA == yB {
                    return a.rect.minX < b.rect.minX
                }
                return yA < yB
            }
            sortedRegion.append(contentsOf: ySortedCol)
        }
        
        return sortedRegion
    }


    // MARK: - 3. 語意轉換與段落封裝

    /// 將 YOLO 的標籤映射到我們定義的 SemanticRole
    private nonisolated static func mapYoloLabelToRole(_ label: String) -> SemanticRole {
        switch label.lowercased() {
        case "title": return .title
        case "section-header": return .heading
        case "text": return .body
        case "list-item": return .listItem
        case "caption": return .caption
        case "footnote": return .footnote
        case "formula": return .formula
        case "picture": return .picture
        case "table": return .table
        case "page-header": return .pageHeader
        case "page-footer": return .pageFooter
        default: return .body
        }
    }

    /// 從一組連續的文字碎片建構一個 ParagraphBlock
    private nonisolated static func buildParagraphBlock(from fragments: [TextFragment], role: SemanticRole) -> ParagraphBlock {
        // 先對每個 fragment 執行 OCR 亂碼修復 (數學符號等)
        let sanitizedFragments = fragments.map { frag -> TextFragment in
            return TextFragment(
                text: sanitizeScientificOCR(frag.text),
                bounds: frag.bounds,
                fontSize: frag.fontSize,
                fontName: frag.fontName,
                isBold: frag.isBold,
                isItalic: frag.isItalic,
                colorHex: frag.colorHex
            )
        }

        // 計算外接矩形
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for frag in sanitizedFragments {
            minX = min(minX, frag.bounds.minX)
            minY = min(minY, frag.bounds.minY)
            maxX = max(maxX, frag.bounds.maxX)
            maxY = max(maxY, frag.bounds.maxY)
        }

        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // 斷字修復
        let lines = sanitizedFragments.map { $0.text }
        var unified = recoverHyphenation(lines: lines)
        
        // 再次確保 unified 也是乾淨的 (其實上面已經修復過每個碎片了，但為保險再過一次)
        unified = sanitizeScientificOCR(unified)

        return ParagraphBlock(
            fragments: sanitizedFragments,
            role: role,
            unifiedText: unified,
            bounds: bounds
        )
    }

    /// 修復跨行斷字 (e.g., "hyperdon-" + "tia" → "hyperdontia")
    private nonisolated static func recoverHyphenation(lines: [String]) -> String {
        var parts: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let lastPart = parts.last, lastPart.hasSuffix("-"),
               let lastChar = lastPart.dropLast().last, lastChar.isLetter {
                // 發現斷字：移除末尾連字號，直接拼接下一行的第一個詞
                parts[parts.count - 1] = String(lastPart.dropLast()) + trimmed
            } else {
                parts.append(trimmed)
            }
        }

        return parts.joined(separator: " ")
    }

    /// 針對論文常見的 PDF 字體亂碼進行修正
    private nonisolated static func sanitizeScientificOCR(_ text: String) -> String {
        var clean = text
        
        // 修正加號
        clean = clean.replacingOccurrences(of: "þ", with: "+")
        
        // 將常見的評估指標後方的亂碼視為等號
        clean = Self.eqRegex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "$1 = ")
        
        // 將被夾在字母數字中間的亂碼視為乘號
        clean = Self.mulRegex.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "$1 * $2")
        
        // 清除剩餘無法辨識的亂碼
        clean = clean.replacingOccurrences(of: "\u{FFFD}", with: " ")
        
        return clean
    }
    
    // MARK: - Temporary Helpers for Transition to KMP

    nonisolated static func shouldDrop(_ role: SemanticRole) -> Bool {
        return role == .pageHeader || role == .pageFooter
    }

    nonisolated static func shouldDrop(block: ParagraphBlock, pageHeight: CGFloat) -> Bool {
        if shouldDrop(block.role) { return true }
        
        // 🚨 安全機制：如果 YOLO 已經明確判定這是標題 (Heading/Title)，絕對不可以使用啟發式規則丟棄！
        if block.role == .heading || block.role == .title { return false }
        
        let text = block.unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isAtTop = block.bounds.minY < pageHeight * 0.15 || block.bounds.maxY < pageHeight * 0.15
        let isAtBottom = block.bounds.minY > pageHeight * 0.85 || block.bounds.maxY > pageHeight * 0.85
        
        if isAtTop || isAtBottom {
            // 特徵 A: 純數字頁碼
            if text.range(of: "^\\d+$", options: .regularExpression) != nil {
                return true
            }
            
            // 特徵 B: 帶有特殊分隔符的大寫字母 (如 T H E  B O O K)
            if text.range(of: "(?:[A-Z]\\s+){3,}[A-Z]", options: .regularExpression) != nil {
                return true
            }
            
            // 特徵 C: 短字串且包含疑似頁碼的數字結尾/開頭
            if text.count < 80 {
                if text.range(of: "^\\d+\\s*·?", options: .regularExpression) != nil || 
                   text.range(of: "·?\\s*\\d+$", options: .regularExpression) != nil {
                    return true
                }
            }
        }
        
        return false
    }

    nonisolated static func toHTML(block: ParagraphBlock, baseFontSize: CGFloat) -> String {
        // 如果是視覺區塊 (圖片、圖表、公式、表格)，直接輸出原始 HTML (不跳脫、不加 span)
        if block.role == .picture || block.role == .formula || block.role == .table {
            return block.fragments.map { $0.text }.joined(separator: "\n") + "\n"
        }
        
        var innerHTML = ""
        for frag in block.fragments {
            let escapedText = EPUBSynthesizer.sanitizeForXML(frag.text)
            
            // 使用相對比例 (em)，允許閱讀器自適應字體大小
            let safeBase = baseFontSize > 0 ? baseFontSize : 12.0
            let emSize = frag.fontSize / safeBase
            
            var style = ""
            // [V2 Patch] 只在字體大小有明顯變化時才寫入 inline font-size，避免 Apple Books 樣式失靈
            // [V3 Patch] 標題本身已有 h1/h2 預設大小，避免再疊加極端的 em 導致破版
            // [V4 Patch] 嚴格限制 .body 內文的最大字體倍率，防止 PDF 元數據異常導致內文變成超大字體 (e.g. 2.5em)
            let maxEmSize: CGFloat = (block.role == .title || block.role == .heading) ? 1.0 : 1.25
            let cappedEmSize = min(emSize, maxEmSize)
            let formattedEm = String(format: "%.2f", cappedEmSize)
            
            if abs(cappedEmSize - 1.0) > 0.15 {
                style += "font-size: \(formattedEm)em;"
            }
            
            var isBold = frag.isBold
            var isItalic = frag.isItalic
            
            if let fontName = frag.fontName {
                let lowerFont = fontName.lowercased()
                if lowerFont.contains("bold") { isBold = true }
                if lowerFont.contains("italic") || lowerFont.contains("oblique") { isItalic = true }
                
                if !fontName.contains("System") && !fontName.contains("UI") && !fontName.contains("Math") && !fontName.contains("Symbol") {
                    if lowerFont.contains("times") || lowerFont.contains("minion") || lowerFont.contains("georgia") || lowerFont.contains("cambria") || lowerFont.contains("serif") {
                        style += " font-family: serif;"
                    } else {
                        // 不要寫死 fallback，讓 Reader 自由決定
                    }
                }
            }
            
            style = style.trimmingCharacters(in: .whitespaces)
            if isBold { style += " font-weight: bold;" }
            if isItalic { style += " font-style: italic;" }
            if frag.colorHex != "#000000" { style += " color: \(frag.colorHex);" }
            
            innerHTML += "<span style=\"\(style)\">\(escapedText)</span> "
        }
        
        switch block.role {
        case .title:
            return "<h1 class=\"doc-title\">\(innerHTML)</h1>\n"
        case .heading:
            return "<h2 class=\"doc-heading\">\(innerHTML)</h2>\n"
        case .listItem:
            return "<ul class=\"doc-list\"><li class=\"doc-list-item\">\(innerHTML)</li></ul>\n"
        case .caption:
            return "<div class=\"doc-caption\">\(innerHTML)</div>\n"
        case .formula:
            return "<div class=\"doc-formula\">\(innerHTML)</div>\n"
        default:
            return "<p class=\"doc-body\">\(innerHTML)</p>\n"
        }
    }
    
    // MARK: - 跨頁段落縫合 (Cross-Page Stitching)
    
    /// 基於啟發式法則 (標點符號與大小寫) 自動縫合因 PDF 換頁而被強制截斷的段落
    nonisolated static func stitchCrossPageParagraphs(html: String) -> String {
        // 匹配條件：
        // 1. 上一段結尾不是終結標點符號 (如 . ! ? 。 ！ ？ ： ； " ')
        // 2. 下一段開頭是小寫字母、數字，或是中文字 (\p{Han})
        // 動作：移除這兩段之間的 </p> <p class="doc-body">，並補上一個空白，將它們合併為同一個 <p>
        
        let pattern = "([^.!?:;。！？：；>”\"’']\\s*</span>\\s*)</p>\\s*<p class=\"doc-body\">(\\s*<span[^>]*>\\s*[a-z0-9\\p{Han}])"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }
        
        // 由於連續合併 (例如跨 3 頁的超長段落) 會需要多次匹配，因此我們執行取代直到無法再匹配為止
        var result = html
        var previous = ""
        
        while result != previous {
            previous = result
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "$1 $2" // 插入一個空白來連接
            )
        }
        
        return result
    }
}
