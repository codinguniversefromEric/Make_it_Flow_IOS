import Foundation

struct LayoutBlock {
    var id: Int
    var confidence: Float
}

var candidates: [(block: LayoutBlock, area: Double)] = [
    (LayoutBlock(id: 1, confidence: 0.83), 80.0), // Orange
    (LayoutBlock(id: 2, confidence: 0.99), 75.0)  // Blue
]

let fragArea = 100.0
let maxArea = candidates.map { $0.area }.max() ?? 0

// Find top-tier candidates (within 80% of max area, or within 10% of fragArea)
let topTier = candidates.filter { $0.area >= maxArea * 0.8 }

let bestBlock = topTier.max(by: { $0.block.confidence < $1.block.confidence })?.block

print("Best block ID: \(bestBlock?.id ?? -1)")
