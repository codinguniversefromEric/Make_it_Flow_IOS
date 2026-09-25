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

func mergeIntervals(_ intervals: [Interval], epsilon: CGFloat) -> [Interval] {
    guard !intervals.isEmpty else { return [] }
    let sorted = intervals.sorted { $0.start < $1.start }
    var merged: [Interval] = [sorted[0]]
    for i in 1..<sorted.count {
        var last = merged.removeLast()
        if sorted[i].start <= last.end + epsilon {
            last.end = max(last.end, sorted[i].end)
            merged.append(last)
        } else {
            merged.append(last)
            merged.append(sorted[i])
        }
    }
    return merged
}

func recursiveXYCut(blocks: [Block], depth: Int = 0) -> [Block] {
    guard blocks.count > 1 else { return blocks }
    
    // 1. Try X-cut FIRST! (Vertical split for columns)
    let xIntervals = blocks.map { Interval(start: $0.bounds.minX, end: $0.bounds.maxX) }
    let mergedX = mergeIntervals(xIntervals, epsilon: 15.0) // columns usually have >15pt gap
    
    if mergedX.count > 1 {
        var groups: [[Block]] = Array(repeating: [], count: mergedX.count)
        for block in blocks {
            let midX = block.bounds.midX
            var bestIdx = 0
            var minDist = CGFloat.greatestFiniteMagnitude
            for (i, inv) in mergedX.enumerated() {
                let dist = max(0, inv.start - midX, midX - inv.end)
                if dist < minDist {
                    minDist = dist
                    bestIdx = i
                }
            }
            groups[bestIdx].append(block)
        }
        return groups.flatMap { recursiveXYCut(blocks: $0, depth: depth + 1) }
    }
    
    // 2. Try Y-cut (Horizontal split for rows)
    let yIntervals = blocks.map { Interval(start: $0.bounds.minY, end: $0.bounds.maxY) }
    let mergedY = mergeIntervals(yIntervals, epsilon: 2.0)
    
    if mergedY.count > 1 {
        var groups: [[Block]] = Array(repeating: [], count: mergedY.count)
        for block in blocks {
            let midY = block.bounds.midY
            var bestIdx = 0
            var minDist = CGFloat.greatestFiniteMagnitude
            for (i, inv) in mergedY.enumerated() {
                let dist = max(0, inv.start - midY, midY - inv.end)
                if dist < minDist {
                    minDist = dist
                    bestIdx = i
                }
            }
            groups[bestIdx].append(block)
        }
        return groups.flatMap { recursiveXYCut(blocks: $0, depth: depth + 1) }
    }
    
    // 3. Fallback sorting
    return blocks.sorted { a, b in
        if abs(a.bounds.minY - b.bounds.minY) < 5.0 {
            return a.bounds.minX < b.bounds.minX
        }
        return a.bounds.minY < b.bounds.minY
    }
}

let blocks = [
    Block(name: "Title", bounds: CGRect(x: 50, y: 50, width: 500, height: 40)),
    Block(name: "L1", bounds: CGRect(x: 50, y: 100, width: 200, height: 100)),
    Block(name: "R1", bounds: CGRect(x: 350, y: 100, width: 200, height: 100)),
    Block(name: "L2", bounds: CGRect(x: 50, y: 210, width: 200, height: 100)),
    Block(name: "R2", bounds: CGRect(x: 350, y: 210, width: 200, height: 100))
]

let sorted = recursiveXYCut(blocks: blocks)
for b in sorted {
    print(b.name)
}
