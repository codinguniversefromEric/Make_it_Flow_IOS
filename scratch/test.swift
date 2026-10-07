import Foundation
public struct LayoutBlock: Identifiable {
    public let id = UUID()
    public let boundingBox: CGRect
    public let label: String
    public let confidence: Float
}
let b = LayoutBlock(boundingBox: .zero, label: "Test", confidence: 1.0)
print(b.label)
