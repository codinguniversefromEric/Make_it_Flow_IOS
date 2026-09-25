import re

with open("Flow_1/Engines/LayoutEngine.swift", "r") as f:
    content = f.read()

# 1. Restore sortParagraphBlocks to original clustering, but with Center X!
old_sortPara = re.search(r'private nonisolated static func sortParagraphBlocks.*?return blocks\n    \}', content, re.DOTALL)
if old_sortPara:
    new_sortPara = """private nonisolated static func sortParagraphBlocks(_ blocks: [ParagraphBlock], pageWidth: CGFloat) -> [ParagraphBlock] {
        guard blocks.count > 1 else { return blocks }
        
        let ySorted = blocks.sorted { $0.bounds.minY < $1.bounds.minY }
        
        var regions: [[ParagraphBlock]] = []
        var currentRegion: [ParagraphBlock] = [ySorted[0]]
        var currentMaxY = ySorted[0].bounds.maxY
        let regionBreakGap = pageWidth * 0.12
        
        for i in 1..<ySorted.count {
            let curr = ySorted[i]
            let gap = curr.bounds.minY - currentMaxY
            
            // 如果這是一個佔據版面 > 40% 的超寬區塊 (例如大標題、摘要)，強制切斷 Region！
            // 這樣可以避免置中標題被吸進雙欄的排序災難裡
            let isFullWidth = curr.bounds.width > (pageWidth * 0.4)
            let prevIsFullWidth = currentRegion.last!.bounds.width > (pageWidth * 0.4)
            
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
                let ySortedCol = col.sorted { $0.bounds.minY < $1.bounds.minY }
                finalSorted.append(contentsOf: ySortedCol)
            }
        }
        
        return finalSorted
    }"""
    content = content.replace(old_sortPara.group(0), new_sortPara)

# 2. Restore sortRegionColumns to do the exact same Center X clustering!
old_regionCol = re.search(r'private nonisolated static func sortRegionColumns.*?return sortedBlocks\n    \}', content, re.DOTALL)
if old_regionCol:
    new_regionCol = """private nonisolated static func sortRegionColumns(_ region: [(block: LayoutBlock, rect: CGRect)], pageWidth: CGFloat) -> [(block: LayoutBlock, rect: CGRect)] {
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
    }"""
    content = content.replace(old_regionCol.group(0), new_regionCol)

with open("Flow_1/Engines/LayoutEngine.swift", "w") as f:
    f.write(content)
