import Foundation

// We just want to make sure the Swift syntax for the new logic is correct.
struct CGPoint { var x: Double; var y: Double }
struct CGRect { 
    var minX: Double; var minY: Double; var width: Double; var height: Double
    var midX: Double { minX + width / 2 }
    var midY: Double { minY + height / 2 }
    func contains(_ p: CGPoint) -> Bool {
        return p.x >= minX && p.x <= minX + width && p.y >= minY && p.y <= minY + height
    }
}
print("Syntax OK")
