import re

with open("Flow_1/Engines/LayoutEngine.swift", "r") as f:
    content = f.read()

# 1. Replace sortParagraphBlocks to just return blocks (remove double sorting)
old_sortPara = re.search(r'private nonisolated static func sortParagraphBlocks.*?print\("🔍 finalSorted blocks.*?return finalSorted\n    \}', content, re.DOTALL)
if old_sortPara:
    new_sortPara = """private nonisolated static func sortParagraphBlocks(_ blocks: [ParagraphBlock], pageWidth: CGFloat) -> [ParagraphBlock] {
        // [V2 Patch] 完全移除破壞性的二次排序，100% 信任 YOLO + Topological Sort 的結果
        return blocks
    }"""
    content = content.replace(old_sortPara.group(0), new_sortPara)

# 2. Replace sortRegionColumns with Topological Sort
old_regionCol = re.search(r'private nonisolated static func sortRegionColumns.*?return sortedRegion\n    \}', content, re.DOTALL)
if old_regionCol:
    new_regionCol = """private nonisolated static func sortRegionColumns(_ region: [(block: LayoutBlock, rect: CGRect)], pageWidth: CGFloat) -> [(block: LayoutBlock, rect: CGRect)] {
        guard region.count > 1 else { return region }
        
        // [V2 Patch] Topological 幾何排序
        // 不再暴力切割欄位，而是基於垂直重疊率決定左右，無重疊則看上下
        var sortedBlocks = region.sorted { $0.rect.minY < $1.rect.minY }
        
        var changed = true
        var iterations = 0
        while changed && iterations < 100 {
            changed = false
            iterations += 1
            for i in 0..<(sortedBlocks.count - 1) {
                let current = sortedBlocks[i]
                let next = sortedBlocks[i+1]
                
                let yOverlap = max(0, min(current.rect.maxY, next.rect.maxY) - max(current.rect.minY, next.rect.minY))
                let minHeight = min(current.rect.height, next.rect.height)
                
                if yOverlap > minHeight * 0.3 {
                    // 垂直有明顯重疊 (在同一行)，必須由左而右
                    if current.rect.minX > next.rect.minX + (pageWidth * 0.05) {
                        sortedBlocks.swapAt(i, i+1)
                        changed = true
                    }
                } else {
                    // 垂直無重疊，必須由上而下
                    if current.rect.minY > next.rect.minY + 5.0 {
                        sortedBlocks.swapAt(i, i+1)
                        changed = true
                    }
                }
            }
        }
        return sortedBlocks
    }"""
    content = content.replace(old_regionCol.group(0), new_regionCol)

# 3. Clean up font size output
old_font = re.search(r'var style = "font-size: \\\(formattedEm\)em;".*?if isItalic \{ style \+= " font-style: italic;" \}', content, re.DOTALL)
if old_font:
    new_font = """var style = ""
            // [V2 Patch] 只在字體大小有明顯變化時才寫入 inline font-size，避免 Apple Books 樣式失靈
            if abs(emSize - 1.0) > 0.15 {
                style += "font-size: \\(formattedEm)em;"
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
            if isItalic { style += " font-style: italic;" }"""
    content = content.replace(old_font.group(0), new_font)


with open("Flow_1/Engines/LayoutEngine.swift", "w") as f:
    f.write(content)

