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

func sortReadingOrder(blocks: [Block], pageWidth: CGFloat, pageHeight: CGFloat) -> [Block] {
    let nonSpanningBlocks = blocks.filter { $0.bounds.width < pageWidth * 0.7 }
    let xIntervals = nonSpanningBlocks.map { Interval(start: $0.bounds.minX, end: $0.bounds.maxX) }
    let columns = mergeIntervals(xIntervals)
    
    let ySorted = blocks.sorted { $0.bounds.minY < $1.bounds.minY }
    
    var regions: [[Block]] = []
    var currentRegion: [Block] = []
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
            
            // Allow small overlaps in Y, but if Y gap is huge, break region
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
    
    var finalOrder: [Block] = []
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
}

let blocks = [
    Block(name: "Title", bounds: CGRect(x: 50, y: 50, width: 500, height: 40)),
    Block(name: "L1", bounds: CGRect(x: 50, y: 100, width: 200, height: 100)),
    Block(name: "L2", bounds: CGRect(x: 50, y: 210, width: 200, height: 100)),
    Block(name: "L_IMG", bounds: CGRect(x: 50, y: 320, width: 200, height: 100)), // Image inside left column
    Block(name: "R1", bounds: CGRect(x: 270, y: 100, width: 200, height: 150)),
    Block(name: "R2", bounds: CGRect(x: 270, y: 260, width: 200, height: 100)),
    Block(name: "Footer", bounds: CGRect(x: 50, y: 700, width: 500, height: 40))
]

let sorted = sortReadingOrder(blocks: blocks, pageWidth: 600, pageHeight: 800)
for b in sorted {
    print(b.name)
}
