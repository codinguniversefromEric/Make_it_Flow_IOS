import CoreGraphics
import Foundation
import PDFKit

enum TableReconstructor {
    private struct Cell {
        var text: String
        var bounds: CGRect
    }

    /// Reconstruct regular text-layer tables. Ambiguous grids use the original crop.
    nonisolated static func reconstruct(page: PDFPage, bounds: CGRect) -> String? {
        guard let selection = page.selection(for: bounds) else { return nil }
        var pieces: [Cell] = []
        var seen: Set<NSRange> = []
        let allowedBounds = bounds.insetBy(dx: -2, dy: -2)
        for index in 0..<selection.numberOfTextRanges(on: page) {
            let pageString = (page.string ?? "") as NSString
            for index in 0..<selection.numberOfTextRanges(on: page) {
                let range = selection.range(at: index, on: page)
                guard range.location != NSNotFound,
                      range.upperBound <= pageString.length else { return nil }

                var failed = false
                pageString.enumerateSubstrings(in: range, options: .byWords) { sub, wordRange, _, stop in
                    // 跳過空白或重複的字（等同原本的 continue）
                    guard let text = sub?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty,
                          seen.insert(wordRange).inserted,
                          let word = page.selection(for: wordRange) else { return }

                    let rect = word.bounds(for: page)
                    // 不合格就整頁放棄（等同原本的 return nil）
                    guard !rect.isEmpty,
                          allowedBounds.contains(CGPoint(x: rect.midX, y: rect.midY)),
                          !text.contains("\u{FFFD}"),
                          !text.unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) }),
                          pieces.count < 1_000 else {
                        failed = true
                        stop.pointee = true
                        return
                    }
                    pieces.append(Cell(text: text, bounds: rect))
                }
                if failed { return nil }
            }
        }
        guard pieces.count >= 6, pieces.count <= 3_000 else { return nil }
        let heights = pieces.map(\.bounds.height).sorted()
        let height = heights[heights.count / 2]
        var lines: [[Cell]] = []
        for piece in pieces.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let last = lines.last?.first, last.bounds.midY - piece.bounds.midY < height * 0.4 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        guard lines.count >= 3 else { return nil }

        let rows = lines.map { line -> [Cell] in
            var cells: [Cell] = []
            for piece in line.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
                if let last = cells.last, piece.bounds.minX - last.bounds.maxX < height * 0.7 {
                    let gap = piece.bounds.minX - last.bounds.maxX
                    let space = gap > 0 ? " " : ""
                    cells[cells.count - 1] = Cell(
                        text: last.text + space + piece.text,
                        bounds: last.bounds.union(piece.bounds)
                    )
                } else {
                    cells.append(piece)
                }
            }
            return cells
        }
        let width = rows[0].count
        guard (2...12).contains(width), rows.allSatisfy({ $0.count == width }) else { return nil }

        // Each column needs its own non-overlapping band across every row.
        for column in 0..<(width - 1) {
            guard let rightEdge = rows.map({ $0[column].bounds.maxX }).max(),
                  let leftEdge = rows.map({ $0[column + 1].bounds.minX }).min(),
                  leftEdge - rightEdge >= height * 0.2 else { return nil }
        }
        let body = rows.map { row in
            "<tr>" + row.map { "<td>\(EPUBSynthesizer.sanitizeForXML($0.text))</td>" }.joined() + "</tr>"
        }.joined(separator: "\n")
        return "<table class=\"doc-table\"><tbody>\n\(body)\n</tbody></table>"
    }
}
