import Foundation
import PDFKit

enum PDFPrintedOutline {
    struct LocatedEntry {
        let title: String
        let page: Int
        let depth: Int
        let anchor: String
        var verticalOffset: CGFloat? = nil
    }

    nonisolated static func readChinese(
        _ document: PDFDocument
    ) -> (entries: [LocatedEntry], contentsPages: Set<Int>)? {
        let linePattern = #"^\s*((?:[壹貳參肆伍陸柒捌玖拾]+[、，,．.]|[一二三四五六七八九十]+[、，,．.]|[（(][一二三四五六七八九十]+[）)])\s*.+?)\s*(?:[.．…·]\s*){2,}\s*([0-9]{1,4})\s*$"#
        let regex = try! NSRegularExpression(pattern: linePattern)
        func lines(on page: Int) -> [String] {
            (document.page(at: page)?.string ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let searchLimit = min(document.pageCount, 24)
        guard let start = (0..<searchLimit).first(where: { page in
            lines(on: page).prefix(4).contains { ["目錄", "目次"].contains(outlineKey($0)) }
        }) else { return nil }

        var rows: [(title: String, folio: Int, depth: Int)] = []
        var contentsPages = Set<Int>()
        var linkOffsets: [Int: Int] = [:]
        for pageIndex in start..<min(start + 12, document.pageCount) {
            let pageLines = lines(on: pageIndex)
            guard !pageLines.prefix(2).contains(where: { ["表次", "圖次", "表目錄", "圖目錄"].contains(outlineKey($0)) })
            else { break }
            let entries = pageLines.compactMap { line -> (title: String, folio: Int, depth: Int)? in
                guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let titleRange = Range(match.range(at: 1), in: line),
                      let folioRange = Range(match.range(at: 2), in: line),
                      let folio = Int(line[folioRange]),
                      let prefix = line[titleRange].first else { return nil }
                let depth = "壹貳參肆伍陸柒捌玖拾".contains(prefix) ? 0 : ("（(".contains(prefix) ? 2 : 1)
                let title = line[titleRange].split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    .replacingOccurrences(of: #"(?<=\p{Han})\s+(?=\p{Han})"#, with: "", options: .regularExpression)
                return (title, folio, depth)
            }
            guard entries.count >= 3 else { break }
            rows += entries
            contentsPages.insert(pageIndex)

            // A single offset maps the printed folios to the PDF's linked destinations.
            let destinations = Set(document.page(at: pageIndex)?.annotations.compactMap { annotation -> Int? in
                let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
                return destination?.page.map { document.index(for: $0) }
            } ?? [])
            for folio in Set(entries.map(\.folio)) {
                for offset in -12...24 where destinations.contains(folio + offset) {
                    linkOffsets[offset, default: 0] += 1
                }
            }
        }
        guard let end = contentsPages.max(), rows.count >= 5, rows.first?.depth == 0,
              zip(rows, rows.dropFirst()).allSatisfy({ $0.folio <= $1.folio && $1.depth <= $0.depth + 1 })
        else { return nil }

        func bestOffset(in counts: [Int: Int], minimum: Int) -> Int? {
            let ranked = counts.sorted { $0.value > $1.value }
            guard let first = ranked.first, first.value >= minimum,
                  first.value >= (ranked.dropFirst().first?.value ?? 0) + 3 else { return nil }
            return first.key
        }

        var offset = bestOffset(in: linkOffsets, minimum: 5)
        if offset == nil {
            var footerOffsets: [Int: Int] = [:]
            for page in (end + 1)..<min(end + 65, document.pageCount) {
                if let last = lines(on: page).last, let folio = Int(last), (-12...24).contains(page - folio) {
                    footerOffsets[page - folio, default: 0] += 1
                }
            }
            offset = bestOffset(in: footerOffsets, minimum: 5)
        }
        guard let offset,
              rows.allSatisfy({ (end + 1..<document.pageCount).contains($0.folio + offset) })
        else { return nil }

        let entries = rows.enumerated().map { index, row in
            LocatedEntry(title: row.title, page: row.folio + offset, depth: row.depth,
                         anchor: "pdf-contents-\(index + 1)")
        }
        return (entries, contentsPages)
    }

    nonisolated static func outlineKey(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber }
    }

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
