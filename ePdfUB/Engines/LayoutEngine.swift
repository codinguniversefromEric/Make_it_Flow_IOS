//
//  LayoutEngine.swift
//  ePdfUB
//
//  Created by Libri-AI Engine on 2026/6/14.
//

import Foundation
import CoreGraphics
import Vision
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 佈局分析引擎：基於 YOLO 區塊的語意重組與幾何排序

enum LayoutEngine: Sendable {

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

        // 1. 幾何排序 YOLO 區塊 (Reading Order Algorithm)
        let sortedBlocks = sortLayoutBlocks(blocks, pageWidth: pageWidth, pageHeight: pageHeight)

        // 2. 預處理：解決 YOLO 區塊重疊問題 (De-Overlap by Confidence Priority)
        //    當兩個 YOLO 區塊在垂直方向重疊時，低信心度的區塊被裁剪，讓高信心度的區塊獨佔重疊區域。
        //    這可以從根本上解決 Section-header 搶走 List-item 文字的問題。
        var adjustedRects: [(block: LayoutBlock, rect: CGRect)] = sortedBlocks.map { block in
            let rect = VNImageRectForNormalizedRect(block.boundingBox, Int(pageWidth), Int(pageHeight))
            let invertedRect = CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
            return (block, invertedRect)
        }
        
        // 按信心度排序 (高 → 低)，高信心度的區塊優先保留完整邊界
        let byConfidence = adjustedRects.indices.sorted { adjustedRects[$0].block.confidence > adjustedRects[$1].block.confidence }
        
        for pass in 0..<byConfidence.count {
            let winnerIdx = byConfidence[pass]
            let winnerRect = adjustedRects[winnerIdx].rect
            
            for later in (pass + 1)..<byConfidence.count {
                let loserIdx = byConfidence[later]
                var loserRect = adjustedRects[loserIdx].rect
                
                let intersection = winnerRect.intersection(loserRect)
                // 只處理有意義的垂直重疊 (> 5pt)
                guard !intersection.isNull && intersection.height > 5 else { continue }
                
                // 判斷低信心度區塊的中心在高信心度區塊的上方還是下方，決定裁剪方向
                let loserCenterY = loserRect.midY
                let winnerCenterY = winnerRect.midY
                
                if loserCenterY > winnerCenterY {
                    // 低信心度區塊在下方 → 將其頂部推到高信心度區塊的底部
                    let newMinY = winnerRect.maxY
                    let newHeight = loserRect.maxY - newMinY
                    if newHeight > 10 {
                        loserRect = CGRect(x: loserRect.minX, y: newMinY, width: loserRect.width, height: newHeight)
                    }
                } else {
                    // 低信心度區塊在上方 → 將其底部推到高信心度區塊的頂部
                    let newHeight = winnerRect.minY - loserRect.minY
                    if newHeight > 10 {
                        loserRect = CGRect(x: loserRect.minX, y: loserRect.minY, width: loserRect.width, height: newHeight)
                    }
                }
                
                adjustedRects[loserIdx] = (adjustedRects[loserIdx].block, loserRect)
            }
        }
        
        // 建立 Block ID → 裁剪後的 CGRect 查詢表
        var adjustedRectMap: [UUID: CGRect] = [:]
        for item in adjustedRects {
            adjustedRectMap[item.block.id] = item.rect
        }
        
        // 3. 將文字碎片分配到裁剪後的 YOLO 區塊中
        var blockFragmentsMap: [UUID: [TextFragment]] = [:]
        var unassignedFragments: [TextFragment] = []
        
        for frag in fragments {
            let fragArea = frag.bounds.width * frag.bounds.height
            let fragMid = CGPoint(x: frag.bounds.midX, y: frag.bounds.midY)
            
            var bestBlock: LayoutBlock? = nil
            var maxIntersectionArea: CGFloat = 0
            
            for block in sortedBlocks {
                guard let adjustedRect = adjustedRectMap[block.id] else { continue }
                
                let intersection = adjustedRect.intersection(frag.bounds)
                if !intersection.isNull {
                    let area = intersection.width * intersection.height
                    if area > maxIntersectionArea {
                        maxIntersectionArea = area
                        bestBlock = block
                    }
                }
            }
            
            let overlapRatio = fragArea > 0 ? maxIntersectionArea / fragArea : 0
            // DEBUG：確認首行被分到 header 的原因
            let t = frag.text.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Because I recognize") || t.contains("BOOK") || t == "K" {
                var log = "[assign] \"\(t.prefix(30))\" bounds=\(frag.bounds) fontSize=\(frag.fontSize)"
                for block in sortedBlocks {
                    guard let r = adjustedRectMap[block.id] else { continue }
                    let i = r.intersection(frag.bounds)
                    let a = i.isNull ? 0 : i.width * i.height
                    log += "\n   \(block.label)(\(block.confidence)) rect=\(r) area=\(Int(a))"
                }
                log += "\n   ratio=\(String(format: "%.2f", overlapRatio)) → \(bestBlock?.label ?? "nil")"
                print(log)
            }
            if overlapRatio > 0.4, let matched = bestBlock {
                blockFragmentsMap[matched.id, default: []].append(frag)
            } else {
                // Fallback：使用中心點距離判定
                var closestBlock: LayoutBlock? = nil
                var minDistance: CGFloat = .greatestFiniteMagnitude
                
                for block in sortedBlocks {
                    guard let adjustedRect = adjustedRectMap[block.id] else { continue }
                    var expanded = adjustedRect.insetBy(dx: -5, dy: -5)
                    
                    // 特殊處理：首字放大 (Drop Cap) 通常在段落左側，字數極少且字體明顯較大
                    let isPotentialDropCap = frag.text.count <= 3 && frag.fontSize > 18
                    if isPotentialDropCap {
                        expanded = CGRect(
                            x: adjustedRect.minX - 80,
                            y: adjustedRect.minY - 20,
                            width: adjustedRect.width + 85,
                            height: adjustedRect.height + 40
                        )
                    }
                    
                    if expanded.contains(fragMid) {
                        let centerBlock = CGPoint(x: adjustedRect.midX, y: adjustedRect.midY)
                        let dx = centerBlock.x - fragMid.x
                        let dy = centerBlock.y - fragMid.y
                        let distance = dx * dx + dy * dy
                        if distance < minDistance {
                            minDistance = distance
                            closestBlock = block
                        }
                    }
                }
                
                if let fallbackBlock = closestBlock {
                    blockFragmentsMap[fallbackBlock.id, default: []].append(frag)
                } else {
                    unassignedFragments.append(frag)
                }
            }
        }

        // 4. 依序組裝 YOLO 的 ParagraphBlock
        var finalParagraphs: [ParagraphBlock] = []
        for block in sortedBlocks {
            guard let frags = blockFragmentsMap[block.id], !frags.isEmpty else { continue }
            let sortedFrags = frags.sorted { a, b in
                let yA = round(readingLineY(a) / 10.0)
                let yB = round(readingLineY(b) / 10.0)
                if yA == yB {
                    return a.bounds.minX < b.bounds.minX
                }
                return yA < yB
            }
            let role = mapYoloLabelToRole(block.label)
            if role == .heading || role == .title {
                print("[heading] \(block.label)(\(block.confidence))")
                for f in sortedFrags {
                    print("   \(String(reflecting: f.text)) bounds=\(f.bounds)")
                }
            }
            finalParagraphs.append(buildParagraphBlock(from: sortedFrags, role: role))
        }

        // 4. 對未被 YOLO 框選的碎片進行 fallback 處理，避免漏字
        if !unassignedFragments.isEmpty {
            // 按 Y 軸排序，然後用 proximity grouping 組裝成段落
            let ySortedOrphans = unassignedFragments.sorted { a, b in
                let yA = round(readingLineY(a) / 10.0)
                let yB = round(readingLineY(b) / 10.0)
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
        guard blocks.count > 1 else { return blocks }

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
    private nonisolated static func readingLineY(_ fragment: TextFragment) -> CGFloat {
        // A drop cap extends below the baseline of its first line.
        if fragment.fontSize > 0, fragment.bounds.height > fragment.fontSize * 2.5 {
            return fragment.bounds.minY + fragment.fontSize * 0.75
        }
        return fragment.bounds.midY
    }

    private nonisolated static func buildParagraphBlock(from fragments: [TextFragment], role: SemanticRole) -> ParagraphBlock {
        // 計算外接矩形
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for frag in fragments {
            minX = min(minX, frag.bounds.minX)
            minY = min(minY, frag.bounds.minY)
            maxX = max(maxX, frag.bounds.maxX)
            maxY = max(maxY, frag.bounds.maxY)
        }

        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let unified = joinLines(lines: fragments.map(\.text))

        return ParagraphBlock(
            fragments: fragments,
            role: role,
            unifiedText: unified,
            bounds: bounds
        )
    }

    private nonisolated static func isEastAsianBoundary(_ character: Character) -> Bool {
        guard !character.isASCII else { return false }
        return String(character).range(
            of: #"[\p{Han}\p{Hiragana}\p{Katakana}\u3001-\u303F\uFF01\uFF08\uFF09\uFF0C\uFF0E\uFF1A\uFF1B\uFF1F]"#,
            options: .regularExpression
        ) != nil
    }

    /// Join physical lines while preserving characters from the source.
    private nonisolated static func joinLines(lines: [String]) -> String {
        var parts: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let lastPart = parts.last, lastPart.hasSuffix("-"),
               let lastChar = lastPart.dropLast().last, lastChar.isLetter,
               trimmed.first?.isLowercase == true {
                parts[parts.count - 1] += trimmed
            } else if let last = parts.last?.last, let first = trimmed.first,
                      isEastAsianBoundary(last) || isEastAsianBoundary(first) {
                parts[parts.count - 1] += trimmed
            } else {
                parts.append(trimmed)
            }
        }

        return parts.joined(separator: " ")
    }

    nonisolated static func shouldDrop(block: ParagraphBlock, pageHeight: CGFloat) -> Bool {
        // Check the entire block so a paragraph that extends into the margin survives.
        let isInTopMargin = block.bounds.maxY <= pageHeight * 0.10
        let isInBottomMargin = block.bounds.minY >= pageHeight * 0.90
        guard pageHeight > 0, isInTopMargin || isInBottomMargin else { return false }

        let text = block.unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "^\\d+$", options: .regularExpression) != nil {
            return true
        }
        guard text.count < 80 else { return false }

        // Running titles often combine a folio with a centered dot, or use spaced capitals.
        // A bare leading or trailing number can also be a list item, note, or contents entry.
        let folio = "^\\d+\\s*·\\s*\\p{Lu}[^.!?]*$|^\\p{Lu}[^.!?]*\\s*·\\s*\\d+$"
        let runningTitle = "^(?:[A-Z]\\s+){3,}[A-Z]$"
        return text.range(of: folio, options: .regularExpression) != nil ||
            text.range(of: runningTitle, options: .regularExpression) != nil
    }

    nonisolated static func separateTrailingNotes(
        in blocks: [ParagraphBlock],
        pageHeight: CGFloat
    ) -> [ParagraphBlock] {
        let markers = Set(blocks.flatMap { block in
            block.fragments.flatMap { fragment in
                fragment.footnoteMarkers.map { (fragment.text as NSString).substring(with: $0) }
            }
        })
        return blocks.flatMap { block -> [ParagraphBlock] in
            guard block.role == .body, block.fragments.count > 1 else { return [block] }
            let rows = block.fragments
            for index in rows.indices.dropFirst() {
                let first = rows[index]
                let prefix = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard first.bounds.minY > pageHeight * 0.74,
                      let markerRange = prefix.range(of: #"^[0-9]{1,3}(?=\s)"#, options: .regularExpression),
                      markers.contains(String(prefix[markerRange])) else { continue }
                let bodySize = rows[..<index].map(\.fontSize).max() ?? 0
                let trailingRows = rows[index...]
                guard trailingRows.allSatisfy({ $0.fontSize <= bodySize * 0.85 }) else { continue }
                return [
                    buildParagraphBlock(from: Array(rows[..<index]), role: .body),
                    buildParagraphBlock(from: Array(trailingRows), role: .footnote)
                ]
            }
            return [block]
        }
    }

    struct FootnoteLinks {
        var notes: [Int: String] = [:]
        var references: [Int: [String: String]] = [:]
    }

    nonisolated static func matchFootnotes(
        in blocks: inout [ParagraphBlock],
        pageIndex: Int,
        pageHeight: CGFloat
    ) -> FootnoteLinks {
        var candidates: [String: [Int]] = [:]
        var references: [String: [(block: Int, fontSize: CGFloat)]] = [:]
        for (index, block) in blocks.enumerated() {
            // Preserve uncertain model detections in reading order.
            if block.role == .footnote { blocks[index].role = .body }
            guard block.role == .footnote || block.role == .body ||
                  block.role == .listItem || block.role == .pageFooter else { continue }

            let text = block.unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = text.range(of: #"^(?:[0-9]{1,3}(?=[.)]?\s)|[*†‡](?=\s*\S))"#,
                                      options: .regularExpression),
               text[range.upperBound...].contains(where: \.isLetter) {
                candidates[String(text[range]), default: []].append(index)
            }

            guard block.role != .pageFooter, !shouldDrop(block: block, pageHeight: pageHeight) else { continue }
            for fragment in block.fragments {
                let source = fragment.text as NSString
                for range in fragment.footnoteMarkers {
                    references[source.substring(with: range), default: []].append((index, fragment.fontSize))
                }
            }
        }

        var links = FootnoteLinks()
        for (marker, matches) in references {
            guard matches.count == 1, let reference = matches.first else { continue }
            let source = blocks[reference.block]
            let eligible = (candidates[marker] ?? []).filter { index in
                let note = blocks[index]
                return note.bounds.minY >= source.bounds.maxY &&
                    note.dominantFontSize <= reference.fontSize * 0.85 &&
                    !shouldDrop(block: note, pageHeight: pageHeight)
            }
            guard eligible.count == 1, let index = eligible.first else { continue }
            let id = "footnote-p\(pageIndex + 1)-\(index + 1)"
            links.notes[index] = id
            links.references[reference.block, default: [:]][marker] = id
        }
        // A note must have a reference outside every other note candidate.
        var nestedTargets: Set<String> = []
        for index in links.notes.keys {
            if let nested = links.references.removeValue(forKey: index) {
                nestedTargets.formUnion(nested.values)
            }
        }
        links.notes = links.notes.filter { !nestedTargets.contains($0.value) }
        for index in links.notes.keys { blocks[index].role = .footnote }
        return links
    }

    nonisolated static func toHTML(
        block: ParagraphBlock,
        baseFontSize: CGFloat,
        footnoteID: String? = nil,
        footnoteLinks: [String: String] = [:]
    ) -> String {
        // 如果是視覺區塊 (圖片、圖表、公式、表格)，直接輸出原始 HTML (不跳脫、不加 span)
        if block.role == .picture || block.role == .formula || block.role == .table {
            return block.fragments.map { $0.text }.joined(separator: "\n") + "\n"
        }
        
        var innerHTML = ""
        for (index, frag) in block.fragments.enumerated() {
            // 去除 PDF 行首與行尾的排版空白，再合併行內連續空白。
            let text = frag.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
            
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
            
            // Reflowable body text follows the reader's chosen size. PDF font changes
            // within a line must not shrink an entire body span.
            let usesBodySize = block.role != .title && block.role != .heading &&
                block.role != .caption && block.role != .footnote
            if !usesBodySize && abs(cappedEmSize - 1.0) > 0.15 {
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
            
            let needsTrailingSpace: Bool
            var marksWordWrap = false
            if index + 1 < block.fragments.count,
               let last = text.last,
               let first = block.fragments[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines).first {
                let next = block.fragments[index + 1]
                let isHyphenatedWord = "-\u{00AD}".contains(last) && first.isLowercase &&
                    (text.dropLast().last?.isLetter ?? false)
                let isURLContinuation = text.split(whereSeparator: \.isWhitespace).last.map {
                    $0.hasPrefix("https://") || $0.hasPrefix("http://") || $0.hasPrefix("www.")
                } ?? false
                marksWordWrap = isHyphenatedWord && !isURLContinuation &&
                    readingLineY(next) - readingLineY(frag) > max(2, min(frag.fontSize, next.fontSize) * 0.45)
                needsTrailingSpace = !isHyphenatedWord && !isURLContinuation &&
                    !isEastAsianBoundary(last) && !isEastAsianBoundary(first) &&
                    !"([{“‘".contains(last) && !".,;:!?%)]}”’".contains(first)
            } else {
                needsTrailingSpace = false
            }

            let escapedText = renderFootnoteReferences(in: text, fragment: frag, links: footnoteLinks)
            innerHTML += "<span style=\"\(style)\">\(escapedText)"
            if marksWordWrap { innerHTML += wordWrapMarker }
            innerHTML += "</span>" + (needsTrailingSpace ? " " : "")
        }
        
        if let footnoteID {
            return "<aside epub:type=\"footnote\" id=\"\(footnoteID)\"><p class=\"doc-body\">\(innerHTML)</p><p><a href=\"#\(footnoteID)-ref\">Return to text</a></p></aside>\n"
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
    
    private nonisolated static func renderFootnoteReferences(
        in text: String,
        fragment: TextFragment,
        links: [String: String]
    ) -> String {
        let source = fragment.text as NSString
        var html = ""
        var cursor = text.startIndex
        for range in fragment.footnoteMarkers {
            let marker = source.substring(with: range)
            guard let id = links[marker] else { continue }
            let prefix = source.substring(to: range.location)
                .replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
            guard text.hasPrefix(prefix),
                  let start = text.index(text.startIndex, offsetBy: prefix.count, limitedBy: text.endIndex),
                  start >= cursor, text[start...].hasPrefix(marker) else { continue }
            html += EPUBSynthesizer.sanitizeForXML(String(text[cursor..<start]))
            html += "<sup><a epub:type=\"noteref\" id=\"\(id)-ref\" href=\"#\(id)\">\(marker)</a></sup>"
            cursor = text.index(start, offsetBy: marker.count)
        }
        return html + EPUBSynthesizer.sanitizeForXML(String(text[cursor...]))
    }

    // MARK: - 跨頁段落縫合 (Cross-Page Stitching)
    
    nonisolated static let pageBreakMarker = "<!-- PDF_PAGE_BREAK -->"
    private nonisolated static let wordWrapMarker = "<!-- PDF_WORD_WRAP -->"

    /// Only inspect hyphens at recorded line or page breaks.
    nonisolated static func repairWrappedWords(html: String) async -> String {
        guard html.contains(wordWrapMarker) else { return html }
        let marker = NSRegularExpression.escapedPattern(for: wordWrapMarker)
        let pattern = #"(?:^|[>\s(“‘-])([A-Za-z]+)([-\u00AD])"# + marker
            + #"</span>\s*(?:<span id="pdf-contents-[0-9]+"></span>)*<span[^>]*>\s*([a-z]+)(?![A-Za-z0-9_/])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let candidates = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match
            -> (range: NSRange, left: String, right: String, softHyphen: Bool)? in
            guard let left = Range(match.range(at: 1), in: html),
                  let hyphen = Range(match.range(at: 2), in: html),
                  let right = Range(match.range(at: 3), in: html) else { return nil }
            return (match.range(at: 2), String(html[left]), String(html[right]), html[hyphen] == "\u{00AD}")
        }
        guard !candidates.isEmpty else {
            return html.replacingOccurrences(of: wordWrapMarker, with: "")
        }

        // Markup separates fragments so a wrapped spelling does not count as
        // evidence that the author used a hyphen in ordinary running text.
        let plainText = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let candidateSpellings = Set(candidates.flatMap { [
            ($0.left + $0.right).lowercased(), ($0.left + "-" + $0.right).lowercased()
        ] })
        var occurrences: [String: Int] = [:]
        for token in plainText.matches(of: #/[A-Za-z]+(?:-[A-Za-z]+)*/#) {
            let word = token.output.lowercased()
            if candidateSpellings.contains(word) { occurrences[word, default: 0] += 1 }
        }

        return await applyWordWrapRepairs(html: html, candidates: candidates, occurrences: occurrences)
    }

    @MainActor
    private static func applyWordWrapRepairs(
        html: String,
        candidates: [(range: NSRange, left: String, right: String, softHyphen: Bool)],
        occurrences: [String: Int]
    ) -> String {
        var knownWords: [String: Bool] = [:]
#if os(iOS)
        let checker = UITextChecker()
#elseif os(macOS)
        let checker = NSSpellChecker.shared
#endif
        func isKnown(_ word: String) -> Bool {
            let word = word.lowercased()
            if let known = knownWords[word] { return known }
#if os(iOS)
            let misspelling = checker.rangeOfMisspelledWord(
                in: word, range: NSRange(word.startIndex..., in: word),
                startingAt: 0, wrap: false, language: "en_US"
            )
#elseif os(macOS)
            let misspelling = checker.checkSpelling(
                of: word, startingAt: 0, language: "en_US", wrap: false,
                inSpellDocumentWithTag: 0, wordCount: nil
            )
#endif
            let known = misspelling.location == NSNotFound
            knownWords[word] = known
            return known
        }

        let result = NSMutableString(string: html)
        for candidate in candidates.reversed() {
            let joined = (candidate.left + candidate.right).lowercased()
            let hyphenated = (candidate.left + "-" + candidate.right).lowercased()
            let prefersJoined = occurrences[joined, default: 0] >= 2
            let usesHyphen = occurrences[hyphenated, default: 0] > 0
            if candidate.softHyphen || (!usesHyphen &&
                (prefersJoined || (isKnown(joined) && !(isKnown(candidate.left) && isKnown(candidate.right))))) {
                result.deleteCharacters(in: candidate.range)
            }
        }
        return (result as String).replacingOccurrences(of: wordWrapMarker, with: "")
    }

    /// Only consider paragraph pairs separated by an actual PDF page boundary.
    nonisolated static func stitchCrossPageParagraphs(html: String) -> String {
        let marker = NSRegularExpression.escapedPattern(for: pageBreakMarker)
        let join = #"\s*<\/span>\s*)</p>\s*"# + marker
            + #"\s*((?:<span id="pdf-contents-[0-9]+"></span>)*)<p class="doc-body">(\s*<span[^>]*>\s*"#
        let rules = [
            (#"([A-Za-z][-\u00AD])("# + join + #"[a-z])"#, "$1" + wordWrapMarker + "$2$3$4"),
            (#"([A-Za-z0-9,%])("# + join + #"[a-z0-9])"#, "$1$2$3 $4"),
            (#"([\p{Han}，、])("# + join + #"[\p{Han}])"#, "$1$2$3$4"),
        ]
        var result = html
        for (pattern, replacement) in rules {
            let regex = try! NSRegularExpression(pattern: pattern)
            var previous: String
            repeat {
                previous = result
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            } while result != previous
        }
        return result.replacingOccurrences(of: pageBreakMarker, with: "")
    }
}
