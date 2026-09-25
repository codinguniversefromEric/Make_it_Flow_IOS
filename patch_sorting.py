import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

helpers = """    // MARK: - 段落排序

    private struct Interval {
        var start: CGFloat
        var end: CGFloat
    }

    private nonisolated static func mergeIntervals(_ intervals: [Interval]) -> [Interval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [Interval] = [sorted[0]]
        for i in 1..<sorted.count {
            var last = merged.removeLast()
            if sorted[i].start <= last.end + 5.0 {
                last.end = max(last.end, sorted[i].end)
                merged.append(last)
            } else {
                merged.append(last)
                merged.append(sorted[i])
            }
        }
        return merged
    }

    /// 對最終的 ParagraphBlock 進行閱讀順序排序
    private nonisolated static func sortParagraphBlocks(_ blocks: [ParagraphBlock], pageWidth: CGFloat, pageHeight: CGFloat) -> [ParagraphBlock] {
        let nonSpanningBlocks = blocks.filter { $0.bounds.width < pageWidth * 0.7 }
        let xIntervals = nonSpanningBlocks.map { Interval(start: $0.bounds.minX, end: $0.bounds.maxX) }
        let columns = mergeIntervals(xIntervals)
        
        let ySorted = blocks.sorted { $0.bounds.minY < $1.bounds.minY }
        
        var regions: [[ParagraphBlock]] = []
        var currentRegion: [ParagraphBlock] = []
        var isCurrentRegionSpanning = false
        
        for block in ySorted {
            let isSpanning = block.bounds.width >= pageWidth * 0.6 || columns.filter { 
                let overlap = max(0, min(block.bounds.maxX, $0.end) - max(block.bounds.minX, $0.start))
                return overlap > 10.0
            }.count > 1
            
            if currentRegion.isEmpty {
                isCurrentRegionSpanning = isSpanning
                currentRegion.append(block)
            } else {
                let prev = currentRegion.last!
                let yGap = block.bounds.minY - prev.bounds.maxY
                
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
        
        var finalOrder: [ParagraphBlock] = []
        for region in regions {
            let isSpanning = region.first!.bounds.width >= pageWidth * 0.6 || columns.filter { 
                let overlap = max(0, min(region.first!.bounds.maxX, $0.end) - max(region.first!.bounds.minX, $0.start))
                return overlap > 10.0
            }.count > 1
            
            if isSpanning {
                finalOrder.append(contentsOf: region.sorted { $0.bounds.minY < $1.bounds.minY })
            } else {
                let sortedRegion = region.sorted { a, b in
                    let colA = columns.firstIndex(where: { max(0, min(a.bounds.maxX, $0.end) - max(a.bounds.minX, $0.start)) > 10 }) ?? 0
                    let colB = columns.firstIndex(where: { max(0, min(b.bounds.maxX, $0.end) - max(b.bounds.minX, $0.start)) > 10 }) ?? 0
                    if colA != colB {
                        return colA < colB 
                    } else {
                        return a.bounds.minY < b.bounds.minY 
                    }
                }
                finalOrder.append(contentsOf: sortedRegion)
            }
        }
        return finalOrder
    }"""

pattern1 = re.compile(r'    // MARK: - 段落排序.*?return finalSorted\n    }', re.DOTALL)
content, count1 = pattern1.subn(helpers, content)
print(f"Patched sortParagraphBlocks: {count1}")


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

pattern2 = re.compile(r'    // MARK: - 2\. 閱讀順序演算法 \(XY-Cut / Projection Profile\).*?return finalSorted\n    }', re.DOTALL)
content, count2 = pattern2.subn(new_sort_layout, content)
print(f"Patched sortLayoutBlocks: {count2}")


with open(filepath, "w") as f:
    f.write(content)

