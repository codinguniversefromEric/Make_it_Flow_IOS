import Foundation
import CoreGraphics

struct Block {
    var name: String
    var bounds: CGRect
}

struct Interval {
    var start: CGFloat
    var end: CGFloat
}

func mergeIntervals(_ intervals: [Interval]) -> [Interval] {
    guard !intervals.isEmpty else { return [] }
    let sorted = intervals.sorted { $0.start < $1.start }
    var merged: [Interval] = [sorted[0]]
    for i in 1..<sorted.count {
        var last = merged.removeLast()
        if sorted[i].start <= last.end + 5.0 { // X epsilon
            last.end = max(last.end, sorted[i].end)
            merged.append(last)
        } else {
            merged.append(last)
            merged.append(sorted[i])
        }
    }
    return merged
}

func sortReadingOrder(blocks: [Block], pageWidth: CGFloat) -> [Block] {
    // 1. Find Column X-Intervals (ignore full-width blocks)
    let nonSpanningBlocks = blocks.filter { $0.bounds.width < pageWidth * 0.7 }
    let xIntervals = nonSpanningBlocks.map { Interval(start: $0.bounds.minX, end: $0.bounds.maxX) }
    let columns = mergeIntervals(xIntervals)
    
    // 2. Assign blocks to columns. If a block overlaps >1 column, it is a spanning block.
    // To represent reading order, we sort all blocks by Y first.
    let ySorted = blocks.sorted { $0.bounds.minY < $1.bounds.minY }
    
    // We group blocks into Y-regions. A new region starts when a spanning block appears, or when we transition from spanning to columns.
    var regions: [[Block]] = []
    var currentRegion: [Block] = []
    var isCurrentRegionSpanning = false
    
    for block in ySorted {
        let isSpanning = block.bounds.width >= pageWidth * 0.7 || columns.filter { 
            let overlap = max(0, min(block.bounds.maxX, $0.end) - max(block.bounds.minX, $0.start))
            return overlap > 10.0
        }.count > 1
        
        if currentRegion.isEmpty {
            isCurrentRegionSpanning = isSpanning
            currentRegion.append(block)
        } else {
            // Check if we need to break the region
            // Break if transition between spanning and non-spanning
            // Or if there is a massive Y gap > 50?
            let prev = currentRegion.last!
            let yGap = block.bounds.minY - prev.bounds.maxY
            
            if isSpanning != isCurrentRegionSpanning || yGap > 50 {
                regions.append(currentRegion)
                currentRegion = [block]
                isCurrentRegionSpanning = isSpanning
            } else {
                currentRegion.append(block)
            }
        }
    }
    if !currentRegion.isEmpty {
        regions.append(currentRegion)
    }
    
    // 3. Sort each region
    var finalOrder: [Block] = []
    for region in regions {
        let isSpanning = region.first!.bounds.width >= pageWidth * 0.7 || columns.filter { 
            let overlap = max(0, min(region.first!.bounds.maxX, $0.end) - max(region.first!.bounds.minX, $0.start))
            return overlap > 10.0
        }.count > 1
        
        if isSpanning {
            // Sort top-to-bottom
            finalOrder.append(contentsOf: region.sorted { $0.bounds.minY < $1.bounds.minY })
        } else {
            // It's a multi-column region! Sort by Column index first, then Y!
            let sortedRegion = region.sorted { a, b in
                // Find column index for a
                let colA = columns.firstIndex(where: { max(0, min(a.bounds.maxX, $0.end) - max(a.bounds.minX, $0.start)) > 10 }) ?? 0
                let colB = columns.firstIndex(where: { max(0, min(b.bounds.maxX, $0.end) - max(b.bounds.minX, $0.start)) > 10 }) ?? 0
                
                if colA != colB {
                    return colA < colB // Read left column first!
                } else {
                    return a.bounds.minY < b.bounds.minY // Then top-to-bottom!
                }
            }
            finalOrder.append(contentsOf: sortedRegion)
        }
    }
    
    return finalOrder
}

let blocks = [
    Block(name: "Title", bounds: CGRect(x: 50, y: 50, width: 500, height: 40)),
    Block(name: "L1", bounds: CGRect(x: 50, y: 100, width: 200, height: 100)),
    Block(name: "R1", bounds: CGRect(x: 270, y: 100, width: 200, height: 100)),
    Block(name: "L2", bounds: CGRect(x: 50, y: 230, width: 200, height: 100)),
    Block(name: "R2", bounds: CGRect(x: 270, y: 230, width: 200, height: 100))
]

let sorted = sortReadingOrder(blocks: blocks, pageWidth: 600)
for b in sorted {
    print(b.name)
}
