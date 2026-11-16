import PDFKit
import Foundation

enum PDFTextLines {
    nonisolated static func selections(in page: PDFPage, bounds: CGRect) -> [PDFSelection] {
        guard let selection = page.selection(for: bounds) else { return [] }
        let source = (page.string ?? "") as NSString
        var seen: Set<NSRange> = []
        return selection.selectionsByLine().flatMap { line -> [PDFSelection] in
            guard line.numberOfTextRanges(on: page) == 1 else { return [line] }
            let range = line.range(at: 0, on: page)
            guard range.location != NSNotFound, range.upperBound <= source.length else { return [line] }
            let raw = source.substring(with: range)
            guard raw.contains("\u{0007}") || raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: #"^\d{1,2}\.$"#, options: .regularExpression) != nil else { return [line] }

            var result: [PDFSelection] = []
            var location = range.location
            for piece in raw.components(separatedBy: "\u{0007}") {
                let part = piece as NSString
                defer { location += part.length + 1 }
                let full = NSRange(location: 0, length: part.length)
                guard let start = piece.rangeOfCharacter(from: .whitespacesAndNewlines.inverted),
                      let end = piece.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: .backwards) else { continue }
                let local = NSRange(start.lowerBound..<end.upperBound, in: piece)
                let text = part.substring(with: local)
                // PDFKit repeats the last glyph of the preceding line at these boundaries.
                if raw.contains("\u{0007}"), text.count == 1,
                   text != "l", !text.contains(where: \.isNumber) { continue }
                let subrange = NSRange(location: location + local.location, length: local.length)
                guard NSLocationInRange(local.location, full),
                      let sub = page.selection(for: subrange), seen.insert(subrange).inserted else { continue }
                result.append(sub)
            }
            return result
        }
    }
}

extension PDFTextLines {
    nonisolated static func attachListMarkers(_ fragments: [TextFragment]) -> [TextFragment] {
        let markerPattern = #"^(?:[0-9]{1,2}\.|[a-z]\.|[•■])$"#
        var output = fragments
        var absorbed: Set<Int> = []
        for (index, marker) in fragments.enumerated() {
            let label = marker.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.range(of: markerPattern, options: .regularExpression) != nil else { continue }
            let candidates = output.indices.filter { target in
                guard target != index, !absorbed.contains(target) else { return false }
                let line = output[target]
                let gap = line.bounds.minX - marker.bounds.maxX
                return gap >= -marker.fontSize * 0.2 && gap <= line.fontSize * 3 &&
                    abs(line.bounds.midY - marker.bounds.midY) <= line.fontSize * 0.55 &&
                    line.text.split(whereSeparator: \.isWhitespace).count >= 2 &&
                    line.text.contains(where: \.isLetter) &&
                    line.text.range(of: #"^\s*(?:[0-9]{1,2}\.|[a-z]\.|[•■])\s"#, options: .regularExpression) == nil
            }
            guard let target = candidates.min(by: {
                output[$0].bounds.minX < output[$1].bounds.minX
            }) else { continue }
            let line = output[target]
            let prefix = label + " "
            output[target] = TextFragment(
                text: prefix + line.text, bounds: marker.bounds.union(line.bounds),
                fontSize: line.fontSize, fontName: line.fontName, isBold: line.isBold,
                isItalic: line.isItalic, colorHex: line.colorHex,
                footnoteMarkers: line.footnoteMarkers.map {
                    NSRange(location: $0.location + prefix.utf16.count, length: $0.length)
                }
            )
            absorbed.insert(index)
        }
        return output.enumerated().compactMap { absorbed.contains($0.offset) ? nil : $0.element }
    }
}
