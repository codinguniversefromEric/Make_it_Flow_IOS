import re
with open("Flow_1/Engines/LayoutEngine.swift", "r") as f:
    content = f.read()

# Fix 1: Add horizontal overlap check to sortParagraphBlocks
# We will use regex to find sortParagraphBlocks and replace its column logic

old_para_col = """            for i in 1..<xSorted.count {
            let curr = xSorted[i]
            let prev = xSorted[i-1]
            let xJump = curr.bounds.minX - prev.bounds.minX
            
            if xJump > pageWidth * 0.15 {
                    let minX = currentColumn.map { $0.bounds.minX }.min()!
                    let maxX = currentColumn.map { $0.bounds.maxX }.max()!
                    let colWidth = maxX - minX
                    
                    if colWidth < (pageWidth * 0.10) {
                        currentColumn.append(curr)
                    } else {
                        columns.append(currentColumn)
                        currentColumn = [curr]
                    }
                } else {
                    currentColumn.append(curr)
                }
            }"""

new_para_col = """            for i in 1..<xSorted.count {
                let curr = xSorted[i]
                let xJump = curr.bounds.minX - currentColumn.map { $0.bounds.minX }.max()!
                
                // 判斷是否為新欄位：X跳躍夠大，且沒有明顯的水平重疊
                // 如果目前的欄位已經延伸到 curr 的 minX 之後 (即 maxX > curr.minX)，代表是重疊的置中標題或縮排，不是新欄位
                let hasHorizontalOverlap = currentMaxX > curr.bounds.minX + (pageWidth * 0.05)
                
                if xJump > pageWidth * 0.15 && !hasHorizontalOverlap {
                    columns.append(currentColumn)
                    currentColumn = [curr]
                    currentMaxX = curr.bounds.maxX
                } else {
                    currentColumn.append(curr)
                    currentMaxX = max(currentMaxX, curr.bounds.maxX)
                }
            }"""

content = content.replace(old_para_col, new_para_col)

# Fix 2: Fix sortRegionColumns as well
old_region_col = """        for i in 1..<xSorted.count {
            let curr = xSorted[i]
            let prev = xSorted[i-1]
            let xJump = curr.rect.minX - prev.rect.minX
            
            if xJump > pageWidth * 0.15 {
                let minX = currentColumn.map { $0.rect.minX }.min()!
                let colWidth = currentMaxX - minX
                
                if colWidth < (pageWidth * 0.10) {
                    currentColumn.append(curr)
                } else {
                    columns.append(currentColumn)
                    currentColumn = [curr]
                }
            } else {
                currentColumn.append(curr)
            }
        }"""

new_region_col = """        for i in 1..<xSorted.count {
            let curr = xSorted[i]
            let xJump = curr.rect.minX - currentColumn.map { $0.rect.minX }.max()!
            
            let hasHorizontalOverlap = currentMaxX > curr.rect.minX + (pageWidth * 0.05)
            
            if xJump > pageWidth * 0.15 && !hasHorizontalOverlap {
                columns.append(currentColumn)
                currentColumn = [curr]
                currentMaxX = curr.rect.maxX
            } else {
                currentColumn.append(curr)
                currentMaxX = max(currentMaxX, curr.rect.maxX)
            }
        }"""

content = content.replace(old_region_col, new_region_col)

# Fix 3: font parsing in toHTML
old_font = """            var style = "font-size: \\(formattedEm)em;"
            if let fontName = frag.fontName, !fontName.contains("System") && !fontName.contains("UI") && !fontName.contains("Math") && !fontName.contains("Symbol") {
                style += " font-family: '\\(fontName)', sans-serif;"
            }
            if frag.isBold { style += " font-weight: bold;" }
            if frag.isItalic { style += " font-style: italic;" }"""

new_font = """            var style = "font-size: \\(formattedEm)em;"
            var isBold = frag.isBold
            var isItalic = frag.isItalic
            
            if let fontName = frag.fontName {
                let lowerFont = fontName.lowercased()
                if lowerFont.contains("bold") { isBold = true }
                if lowerFont.contains("italic") || lowerFont.contains("oblique") { isItalic = true }
                
                if !fontName.contains("System") && !fontName.contains("UI") && !fontName.contains("Math") && !fontName.contains("Symbol") {
                    // 如果是 Serif 系列字體，轉換為通用的 serif 以便 Apple Books 正常顯示
                    if lowerFont.contains("times") || lowerFont.contains("minion") || lowerFont.contains("georgia") || lowerFont.contains("cambria") || lowerFont.contains("serif") {
                        style += " font-family: serif;"
                    } else {
                        // 否則預設給 sans-serif，不要寫死奇怪的 TTF 名稱，避免閱讀器找不到字體而失靈
                        style += " font-family: sans-serif;"
                    }
                }
            }
            if isBold { style += " font-weight: bold;" }
            if isItalic { style += " font-style: italic;" }"""

content = content.replace(old_font, new_font)

with open("Flow_1/Engines/LayoutEngine.swift", "w") as f:
    f.write(content)

