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

struct Gap {
    var width: CGFloat
    var splitPoint: CGFloat
    var isX: Bool
    var score: CGFloat { width * (isX ? 3.0 : 1.0) }
}

func mergeIntervals(_ intervals: [Interval]) -> [Interval] {
    guard !intervals.isEmpty else { return [] }
    let sorted = intervals.sorted { $0.start < $1.start }
    var merged: [Interval] = [sorted[0]]
    for i in 1..<sorted.count {
        var last = merged.removeLast()
        if sorted[i].start <= last.end + 0.1 {
            last.end = max(last.end, sorted[i].end)
            merged.append(last)
        } else {
            merged.append(last)
            merged.append(sorted[i])
        }
    }
    return merged
}

func findGaps(intervals: [Interval], isX: Bool) -> [Gap] {
    let merged = mergeIntervals(intervals)
    var gaps: [Gap] = []
    for i in 1..<merged.count {
        let width = merged[i].start - merged[i-1].end
        let splitPoint = (merged[i].start + merged[i-1].end) / 2
        gaps.append(Gap(width: width, splitPoint: splitPoint, isX: isX))
    }
    return gaps
}

func recursiveXYCut(blocks: [Block], depth: Int = 0) -> [Block] {
    guard blocks.count > 1 else { return blocks }
    
    let xIntervals = blocks.map { Interval(start: $0.bounds.minX, end: $0.bounds.maxX) }
    let yIntervals = blocks.map { Interval(start: $0.bounds.minY, end: $0.bounds.maxY) }
    
    var xGaps = findGaps(intervals: xIntervals, isX: true).filter { $0.width > 15.0 } // Column gutters usually > 15
    var yGaps = findGaps(intervals: yIntervals, isX: false).filter { $0.width > 2.0 }  // Paragraph breaks usually > 2
    
    let allGaps = (xGaps + yGaps).sorted { $0.score > $1.score }
    
    if let bestGap = allGaps.first {
        var g1: [Block] = []
        var g2: [Block] = []
        
        if bestGap.isX {
            for b in blocks {
                if b.bounds.midX < bestGap.splitPoint { g1.append(b) } else { g2.append(b) }
            }
            return recursiveXYCut(blocks: g1, depth: depth + 1) + recursiveXYCut(blocks: g2, depth: depth + 1)
        } else {
            for b in blocks {
                if b.bounds.midY < bestGap.splitPoint { g1.append(b) } else { g2.append(b) }
            }
            return recursiveXYCut(blocks: g1, depth: depth + 1) + recursiveXYCut(blocks: g2, depth: depth + 1)
        }
    }
    
    // Fallback
    return blocks.sorted { a, b in
        if abs(a.bounds.minY - b.bounds.minY) < 5.0 {
            return a.bounds.minX < b.bounds.minX
        }
        return a.bounds.minY < b.bounds.minY
    }
}

// Small gutter, large paragraph break test
let blocks = [
    Block(name: "Title", bounds: CGRect(x: 50, y: 50, width: 500, height: 40)),
    Block(name: "L1", bounds: CGRect(x: 50, y: 100, width: 200, height: 100)),
    Block(name: "R1", bounds: CGRect(x: 270, y: 100, width: 200, height: 100)), // Gutter is 270 - 250 = 20pt
    Block(name: "L2", bounds: CGRect(x: 50, y: 230, width: 200, height: 100)), // Gap is 230 - 200 = 30pt
    Block(name: "R2", bounds: CGRect(x: 270, y: 230, width: 200, height: 100))
]

let sorted = recursiveXYCut(blocks: blocks)
for b in sorted {
    print(b.name)
}
