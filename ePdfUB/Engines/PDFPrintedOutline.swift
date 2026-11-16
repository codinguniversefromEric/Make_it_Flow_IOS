import Foundation
import PDFKit

enum PDFPrintedOutline {
    struct Entry {
        let title: String
        let folio: Int?
    }

    nonisolated static func read(
        _ document: PDFDocument
    ) -> (outline: [Int: (title: String, depth: Int)], contentsPages: Set<Int>)? {
        let contentsLabels = ["contents", "table of contents"]
        let groupPattern = #"^(?:PART\s+(?:[IVXLCDM]+|[0-9]+)\s*:\s*\S.*|BONUS)$"#
        let numberedLine = try! NSRegularExpression(pattern: #"^(.+?)\s+(\d{1,4})$"#)

        func lines(_ index: Int) -> [String] {
            (document.page(at: index)?.string ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        func parse(_ lines: [String]) -> [Entry]? {
            var result: [Entry] = []
            for line in lines {
                if line.range(of: groupPattern, options: .regularExpression) != nil {
                    result.append(Entry(title: line, folio: nil))
                    continue
                }
                guard let match = numberedLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let titleRange = Range(match.range(at: 1), in: line),
                      let pageRange = Range(match.range(at: 2), in: line),
                      let folio = Int(line[pageRange]),
                      line[titleRange].contains(where: \.isLetter) else { return nil }
                result.append(Entry(title: String(line[titleRange]), folio: folio))
            }
            return result.filter { $0.folio != nil }.count >= 5 ? result : nil
        }

        guard let start = (0..<min(document.pageCount, 24)).first(where: {
            guard let heading = lines($0).first else { return false }
            return contentsLabels.contains(heading.lowercased())
        }), let first = parse(Array(lines(start).dropFirst())) else { return nil }

        var entries = first
        var end = start + 1
        while end < min(start + 12, document.pageCount), let continuation = parse(lines(end)) {
            entries += continuation
            end += 1
        }

        let pages = entries.compactMap(\.folio)
        guard pages.count >= 10, zip(pages, pages.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        let numbered = entries.filter { $0.folio != nil }
        let headings = (0..<document.pageCount).map { normalized(lines($0).prefix(6).joined(separator: " ")) }
        let scores = (-12...24).map { offset in
            let matched = numbered.filter { entry in
                guard let folio = entry.folio else { return false }
                let page = folio + offset
                return page >= end && headings.indices.contains(page) &&
                    headings[page].contains(normalized(entry.title))
            }
            return (offset: offset, count: matched.count)
        }.sorted { $0.count > $1.count }
        guard let best = scores.first, best.count * 5 >= numbered.count * 4,
              best.count >= scores[1].count + 3 else { return nil }

        var outline: [Int: (title: String, depth: Int)] = [:]
        var insidePart = false
        var hasChapter = false
        var previousPage = end - 1
        for (index, entry) in entries.enumerated() {
            let page: Int
            let depth: Int
            if let folio = entry.folio {
                page = folio + best.offset
                let isChapter = entry.title.contains(where: \.isUppercase) && !entry.title.contains(where: \.isLowercase)
                depth = insidePart ? (isChapter || !hasChapter ? 1 : 2) : 0
                if insidePart && depth == 1 { hasChapter = true }
            } else {
                guard let next = entries.dropFirst(index + 1).compactMap(\.folio).first else { return nil }
                let nextPage = next + best.offset
                let lower = max(previousPage + 1, nextPage - 6)
                guard lower < nextPage, nextPage <= headings.count,
                      let divider = (lower..<nextPage).last(where: {
                          headings[$0].hasPrefix(normalized(entry.title))
                      }) else { return nil }
                page = divider
                depth = 0
                insidePart = true
                hasChapter = false
            }
            guard page > previousPage, headings.indices.contains(page) else { return nil }
            outline[page] = (entry.title, depth)
            previousPage = page
        }
        return (outline, Set(start..<end))
    }
}
