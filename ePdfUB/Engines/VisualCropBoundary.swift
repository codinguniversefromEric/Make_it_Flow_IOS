import Foundation
import CoreGraphics

enum VisualCropBoundary {
    nonisolated static func trimmedRect(_ rect: CGRect, label: String, lines: [TextFragment]) -> CGRect {
        guard ["Picture", "Figure", "Table"].contains(label), rect.width > 0, rect.height > 0 else {
            return rect
        }

        let prose = lines.filter { line in
            let words = line.text.split(whereSeparator: \.isWhitespace)
            return line.fontSize > 0 && line.bounds.height >= line.fontSize * 1.35 &&
                line.bounds.height <= line.fontSize * 2.2 && words.count >= 6 &&
                line.text.contains(where: \.isLowercase) && words.filter { $0.contains(where: \.isLetter) }.count >= 5
        }

        var top = rect.minY
        var bottom = rect.maxY
        for line in prose {
            let bounds = line.bounds
            let overlap = bounds.intersection(rect)
            guard !overlap.isNull, overlap.height > 0,
                  overlap.width >= rect.width * 0.55, overlap.width >= bounds.width * 0.8 else { continue }

            let font = line.fontSize
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if bounds.minY <= rect.minY + font * 0.6, bounds.maxY <= rect.minY + font * 2.4,
               text.first?.isLowercase == true,
               text.range(of: #"[.!?][0-9]{0,3}$"#, options: .regularExpression) != nil {
                top = max(top, bounds.maxY + 1)
            }

            if bounds.maxY >= rect.maxY - font * 1.3, bounds.minY >= rect.maxY - font * 3.2,
               prose.contains(where: { neighbor in
                   let gap = neighbor.bounds.minY - bounds.minY
                   return gap >= font * 0.8 && gap <= font * 2 &&
                       abs(neighbor.fontSize - font) <= font * 0.12 &&
                       neighbor.bounds.intersection(rect).width >= rect.width * 0.55 &&
                       neighbor.text.trimmingCharacters(in: .whitespacesAndNewlines).first?.isLowercase == true
               }) {
                bottom = min(bottom, bounds.minY - 1)
            }
        }

        // Keep the crop when edge candidates would remove a substantial part of the visual.
        guard bottom - top >= rect.height * 0.72 else { return rect }
        return CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
    }

    nonisolated static func expandedFormulaRect(
        _ rect: CGRect, lines: [TextFragment], pageSize: CGSize
    ) -> CGRect {
        guard rect.width < pageSize.width * 0.46,
              lines.contains(where: {
                  $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "=" &&
                  rect.intersects($0.bounds)
              }) else { return rect }

        var result = rect
        var rows = 0
        for line in lines.sorted(by: { $0.bounds.minY < $1.bounds.minY }) {
            let bounds = line.bounds
            guard bounds.midY > rect.maxY, bounds.minY > rect.maxY - line.fontSize * 0.3 else { continue }
            if bounds.minY > result.maxY + line.fontSize * 1.3 { break }
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard bounds.width >= rect.width * 1.1, abs(bounds.midX - rect.midX) < pageSize.width * 0.15,
                  text.contains("("), text.contains(")"),
                  text.range(of: #"[+*×÷/]|\s[-−–]\s"#, options: .regularExpression) != nil else { break }
            result = result.union(bounds)
            rows += 1
            if rows == 4 { break }
        }

        guard rows >= 2 else { return rect }
        return result.insetBy(dx: -2, dy: -2).intersection(CGRect(origin: .zero, size: pageSize))
    }

    nonisolated static func containsImageText(_ line: CGRect, in region: VisualRegion) -> Bool {
        let intersection = line.intersection(region.rect)
        let area = line.width * line.height
        guard !intersection.isNull, area > 0 else { return false }
        let ratio = intersection.width * intersection.height / area
        if region.label == "Table" {
            let center = CGPoint(x: line.midX, y: line.midY)
            return ratio > 0.4 || region.rect.insetBy(dx: -5, dy: -5).contains(center)
        }
        if region.label == "Formula" {
            // PDFKit line bounds include font padding beyond the rasterized formula.
            return intersection.width >= line.width * 0.75 &&
                intersection.height >= line.height * 0.45
        }
        return ratio > 0.90
    }
}
