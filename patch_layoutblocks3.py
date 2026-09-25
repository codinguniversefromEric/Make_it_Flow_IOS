import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

new_sort_layout = """    // MARK: - 2. 閱讀順序演算法 (XY-Cut / Projection Profile)

    /// 根據人類閱讀邏輯 (先上後下，先左後右)，對 YOLO 區塊進行幾何排序
    private nonisolated static func sortLayoutBlocks(_ blocks: [LayoutBlock], pageWidth: CGFloat, pageHeight: CGFloat) -> [LayoutBlock] {
        let nonSpanningBlocks = blocks.filter { $0.boundingBox.width < pageWidth * 0.7 }
        let xIntervals = nonSpanningBlocks.map { Interval(start: $0.boundingBox.minX, end: $0.boundingBox.maxX) }
        let columns = mergeIntervals(xIntervals)
        
        let ySorted = blocks.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        
        var regions: [[LayoutBlock]] = []
        var currentRegion: [LayoutBlock] = []
        var isCurrentRegionSpanning = false
        
        for block in ySorted {
            let isSpanning = block.boundingBox.width >= pageWidth * 0.6 || columns.filter { 
                let overlap = max(0, min(block.boundingBox.maxX, $0.end) - max(block.boundingBox.minX, $0.start))
                return overlap > 10.0
            }.count > 1
            
            if currentRegion.isEmpty {
                isCurrentRegionSpanning = isSpanning
                currentRegion.append(block)
            } else {
                let prev = currentRegion.last!
                let yGap = block.boundingBox.minY - prev.boundingBox.maxY
                
                if isSpanning != isCurrentRegionSpanning || yGap > pageHeight * 0.05 {
                    regions.append(currentRegion)
                    currentRegion = [block]
                    isCurrentRegionSpanning = isSpanning
                } else {
                    currentRegion.append(block)
                }
            }
        }
        if !currentRegion.isEmpty { regions.append(currentRegion) }
        
        var finalOrder: [LayoutBlock] = []
        for region in regions {
            let isSpanning = region.first!.boundingBox.width >= pageWidth * 0.6 || columns.filter { 
                let overlap = max(0, min(region.first!.boundingBox.maxX, $0.end) - max(region.first!.boundingBox.minX, $0.start))
                return overlap > 10.0
            }.count > 1
            
            if isSpanning {
                finalOrder.append(contentsOf: region.sorted { $0.boundingBox.minY < $1.boundingBox.minY })
            } else {
                let sortedRegion = region.sorted { a, b in
                    let colA = columns.firstIndex(where: { max(0, min(a.boundingBox.maxX, $0.end) - max(a.boundingBox.minX, $0.start)) > 10 }) ?? 0
                    let colB = columns.firstIndex(where: { max(0, min(b.boundingBox.maxX, $0.end) - max(b.boundingBox.minX, $0.start)) > 10 }) ?? 0
                    if colA != colB {
                        return colA < colB 
                    } else {
                        return a.boundingBox.minY < b.boundingBox.minY 
                    }
                }
                finalOrder.append(contentsOf: sortedRegion)
            }
        }
        return finalOrder
    }"""

start_index = content.find("    // MARK: - 2. 閱讀順序演算法 (XY-Cut / Projection Profile)")
end_index = content.find("    // MARK: - 3. 語意轉換與段落封裝")

if start_index != -1 and end_index != -1:
    content = content[:start_index] + new_sort_layout + "\n\n" + content[end_index:]
    with open(filepath, "w") as f:
        f.write(content)
    print("Patched sortLayoutBlocks by index!")
else:
    print("Could not find bounds")
