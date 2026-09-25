import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

pattern = r'    /// 根據人類閱讀邏輯 \(先上後下，先左後右\)，對 YOLO 區塊進行幾何排序\n    private nonisolated static func sortLayoutBlocks.*?return finalOrder\n    \}'

new_code = """    /// 根據人類閱讀邏輯 (先上後下，先左後右)，對 YOLO 區塊進行幾何排序
    private nonisolated static func sortLayoutBlocks(_ blocks: [LayoutBlock], pageWidth: CGFloat, pageHeight: CGFloat) -> [LayoutBlock] {
        guard blocks.count > 1 else { return blocks }
        
        let rectBlocks = blocks.map { block -> (block: LayoutBlock, rect: CGRect) in
            // 對於內文，我們稍微縮小寬度，避免跨欄誤判
            let inset: CGFloat = block.label == "Text" ? 5.0 : 0
            return (block, block.boundingBox.insetBy(dx: inset, dy: 0))
        }
        
        let ySorted = rectBlocks.sorted { abs($0.rect.minY - $1.rect.minY) < 5.0 ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }
        
        var regions: [[(block: LayoutBlock, rect: CGRect)]] = []
        var currentRegion: [(block: LayoutBlock, rect: CGRect)] = [ySorted[0]]
        var currentMaxY = ySorted[0].rect.maxY
        let regionBreakGap = max(pageHeight * 0.05, 30.0)
        
        for i in 1..<ySorted.count {
            let curr = ySorted[i]
            let gap = curr.rect.minY - currentMaxY
            
            if gap > regionBreakGap {
                regions.append(currentRegion)
                currentRegion = [curr]
                currentMaxY = curr.rect.maxY
            } else {
                currentRegion.append(curr)
                currentMaxY = max(currentMaxY, curr.rect.maxY)
            }
        }
        if !currentRegion.isEmpty { regions.append(currentRegion) }
        
        var finalSortedBlocks: [LayoutBlock] = []
        for region in regions {
            let sortedRegionBlocks = sortRegionColumns(region, pageWidth: pageWidth)
            finalSortedBlocks.append(contentsOf: sortedRegionBlocks.map { $0.block })
        }
        
        return finalSortedBlocks
    }

    private nonisolated static func sortRegionColumns(_ region: [(block: LayoutBlock, rect: CGRect)], pageWidth: CGFloat) -> [(block: LayoutBlock, rect: CGRect)] {
        guard region.count > 1 else { return region }
        
        let xSorted = region.sorted { $0.rect.minX < $1.rect.minX }
        
        var columns: [[(block: LayoutBlock, rect: CGRect)]] = []
        var currentColumn: [(block: LayoutBlock, rect: CGRect)] = [xSorted[0]]
        var currentMaxX = xSorted[0].rect.maxX
        
        for i in 1..<xSorted.count {
            let curr = xSorted[i]
            let prev = xSorted[i-1]
            let xJump = curr.rect.minX - prev.rect.minX
            let isOverlapping = curr.rect.minX < (currentMaxX - 20.0)
            
            if !isOverlapping && xJump > pageWidth * 0.10 {
                let minX = currentColumn.map { $0.rect.minX }.min()!
                let colWidth = currentMaxX - minX
                
                if colWidth < (pageWidth * 0.15) {
                    currentColumn.append(curr)
                } else {
                    columns.append(currentColumn)
                    currentColumn = [curr]
                }
            } else {
                currentColumn.append(curr)
            }
            currentMaxX = max(currentMaxX, curr.rect.maxX)
        }
        if !currentColumn.isEmpty {
            columns.append(currentColumn)
        }
        
        var sortedRegion: [(block: LayoutBlock, rect: CGRect)] = []
        for col in columns {
            let xySortedCol = col.sorted { a, b in
                let yGap = a.rect.minY - b.rect.maxY
                if abs(yGap) < 10 {
                    return a.rect.minX < b.rect.minX
                }
                return a.rect.minY < b.rect.minY
            }
            sortedRegion.append(contentsOf: xySortedCol)
        }
        
        return sortedRegion
    }"""

content, count = re.subn(pattern, new_code, content, flags=re.DOTALL)
print(f"Replaced {count} occurrences")

with open(filepath, "w") as f:
    f.write(content)

