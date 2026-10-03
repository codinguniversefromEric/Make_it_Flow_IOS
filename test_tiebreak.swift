import Foundation

struct LayoutBlock {
    var id: Int
    var confidence: Float
}

var bestBlock: LayoutBlock? = nil
var maxIntersectionArea: CGFloat = 0

let overlaps = [
    (LayoutBlock(id: 1, confidence: 0.83), 100.0),
    (LayoutBlock(id: 2, confidence: 0.99), 100.0)
]

for (block, area) in overlaps {
    if bestBlock == nil {
        maxIntersectionArea = area
        bestBlock = block
    } else if area > maxIntersectionArea + 0.1 {
        maxIntersectionArea = area
        bestBlock = block
    } else if abs(area - maxIntersectionArea) <= 0.1 {
        // Tie!
        if block.confidence > bestBlock!.confidence {
            bestBlock = block
        }
    }
}

print(bestBlock!.id)
