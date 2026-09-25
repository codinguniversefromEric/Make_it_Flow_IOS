import Foundation
import CoreGraphics

struct LayoutBlock {
    var bounds: CGRect
    var name: String
}

func sortRegionColumns(_ region: [LayoutBlock], pageWidth: CGFloat) -> [LayoutBlock] {
    guard region.count > 1 else { return region }
    
    var columns: [[LayoutBlock]] = []
    let xSorted = region.sorted { $0.bounds.minX < $1.bounds.minX }
    
    var currentColumn: [LayoutBlock] = [xSorted[0]]
    var currentMaxX = xSorted[0].bounds.maxX
    
    for i in 1..<xSorted.count {
        let curr = xSorted[i]
        let prev = xSorted[i-1]
        let xJump = curr.bounds.minX - prev.bounds.minX
        let isOverlapping = curr.bounds.minX < (currentMaxX - pageWidth * 0.02)
        
        if !isOverlapping && xJump > pageWidth * 0.10 {
            let minX = currentColumn.map { $0.bounds.minX }.min()!
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
        currentMaxX = max(currentMaxX, curr.bounds.maxX)
    }
    if !currentColumn.isEmpty { columns.append(currentColumn) }
    
    var finalSorted: [LayoutBlock] = []
    for col in columns {
        let xySortedCol = col.sorted { a, b in
            let yA = round(a.bounds.minY / (pageWidth * 0.02))
            let yB = round(b.bounds.minY / (pageWidth * 0.02))
            if yA == yB {
                return a.bounds.minX < b.bounds.minX
            }
            return yA < yB
        }
        finalSorted.append(contentsOf: xySortedCol)
    }
    return finalSorted
}

let blocks = [
    LayoutBlock(bounds: CGRect(x: 50, y: 50, width: 500, height: 40), name: "Title"),
    LayoutBlock(bounds: CGRect(x: 50, y: 100, width: 200, height: 100), name: "L1"),
    LayoutBlock(bounds: CGRect(x: 270, y: 100, width: 200, height: 100), name: "R1"),
    LayoutBlock(bounds: CGRect(x: 50, y: 230, width: 200, height: 100), name: "L2"),
    LayoutBlock(bounds: CGRect(x: 270, y: 230, width: 200, height: 100), name: "R2")
]

let sorted = sortRegionColumns(blocks, pageWidth: 600)
for b in sorted {
    print(b.name)
}
