import PDFKit
import Foundation

enum PDFTextLines {
    nonisolated static func repairDimensionSymbols(_ text: String) -> String {
        guard text.contains("\u{FFFD}"),
              text.range(of: #"\b(?:resolution\s+of|normalized(?:\s+to)?\s+[0-9]|kernel\s+sizes?|MBConv\s+[0-9]|[0-9]\s*�\s*[0-9]+(?:\.[0-9]+)?\s+(?:cm\)|convolutional))"#,
                         options: [.regularExpression, .caseInsensitive]) != nil else { return text }
        return text.replacingOccurrences(of: #"(?<=[0-9])\h*�\h*(?=[0-9])"#,
                                         with: " × ", options: .regularExpression)
    }

    nonisolated static func repairMetricDefinition(_ text: String) -> String {
        guard let separator = text.firstIndex(of: "\u{FFFD}"), text.contains("þ"),
              text.range(of: #"^\s*(?:Accuracy|Precision|Sensitivity|F1 score)\s*�\s*(?:\(|TP\s*/)"#,
                         options: .regularExpression) != nil else { return text }
        let label = text[..<separator].trimmingCharacters(in: .whitespaces)
        let expression = text[text.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "þ", with: "+")
        if label == "F1 score" {
            return label + " = " + expression.replacingOccurrences(of: "�", with: "×")
        }
        return label + " = " + expression
    }

    /// Some TeX symbol fonts map several distinct operators to U+FFFD in their
    /// text layer. The rendered page still contains the correct glyphs.
    nonisolated static func malformedNumberedFormulaBounds(
        in fragments: [TextFragment], pageSize: CGSize
    ) -> [CGRect] {
        let damagedNumber = #"ð\s*[0-9]{1,3}\s*Þ\s*$"#
        let markers = fragments.indices.filter {
            fragments[$0].text.range(of: damagedNumber, options: .regularExpression) != nil
        }
        var rowsByMarker: [Int: [TextFragment]] = [:]
        for line in fragments {
            guard let marker = markers.filter({ index in
                let anchor = fragments[index]
                return (anchor.bounds.maxX <= pageSize.width / 2) == (line.bounds.midX <= pageSize.width / 2) &&
                    abs(anchor.bounds.midY - line.bounds.midY) <= max(anchor.fontSize, line.fontSize) * 1.9
            }).min(by: {
                abs(fragments[$0].bounds.midY - line.bounds.midY) <
                    abs(fragments[$1].bounds.midY - line.bounds.midY)
            }) else { continue }

            let hasDamagedOperator = line.text.contains("\u{FFFD}") || line.text.contains("þ") ||
                line.text.range(of: damagedNumber, options: .regularExpression) != nil
            let isShortMathLine = line.text.range(of: #"^\s*[A-Za-z0-9()\s./+−=]+\s*$"#, options: .regularExpression) != nil &&
                line.text.split(whereSeparator: \.isWhitespace).count <= 2 &&
                line.text.count <= 12
            if hasDamagedOperator || isShortMathLine { rowsByMarker[marker, default: []].append(line) }
        }

        return markers.compactMap { marker in
            guard let rows = rowsByMarker[marker], rows.contains(where: { $0.text.contains("\u{FFFD}") }) else {
                return nil
            }
            let bounds = rows.reduce(CGRect.null) { $0.union($1.bounds) }
            return bounds.insetBy(dx: -4, dy: -1).intersection(CGRect(origin: .zero, size: pageSize))
        }
    }

    /// Older TCVN3 fonts can render correctly while providing no Unicode mapping.
    nonisolated static func usesLegacyVietnameseEncoding(_ page: PDFPage) -> Bool {
        guard let dictionary = page.pageRef?.dictionary else { return false }
        var resources: CGPDFDictionaryRef?
        var fonts: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return false }

        var hasLegacyFont = false
        CGPDFDictionaryApplyBlock(fonts, { _, object, _ in
            var font: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &font), let font else { return true }
            var baseFont: UnsafePointer<CChar>?
            var unicode: CGPDFStreamRef?
            guard CGPDFDictionaryGetName(font, "BaseFont", &baseFont), let baseFont,
                  !CGPDFDictionaryGetStream(font, "ToUnicode", &unicode) else { return true }
            let name = String(cString: baseFont).split(separator: "+").last?.lowercased() ?? ""
            hasLegacyFont = name.hasPrefix(".vn")
            return !hasLegacyFont
        }, nil)
        return hasLegacyFont
    }

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
