//
//  EPUBSynthesizer.swift
//  Flow_1
//
//  Created by 魏嘉賢 on 2026/6/14.
//  Rewritten with compliant stored-mode ZIP writer on 2026/6/14.
//

import Foundation

/// 負責將 XHTML 內容轉換並封裝為合規的 EPUB 檔案
final class EPUBSynthesizer: Sendable {
    
    // MARK: - Cached Regex Patterns
    private static let altRegex = try! NSRegularExpression(pattern: "alt=\\\"[^\\\"]*\\\"")
    private static let imgRegex = try! NSRegularExpression(pattern: "<img([^>]+)(?<!/)>")
    private static let ampRegex = try! NSRegularExpression(pattern: "&(?!(?:[a-zA-Z][a-zA-Z0-9]+|#[0-9]+|#x[0-9a-fA-F]+);)")
    private static let headingRegex = try! NSRegularExpression(pattern: "<(h[1-3])([^>]*)>((?:(?!</h[1-3]>).)*?)</\\1>", options: [.dotMatchesLineSeparators])
    
    // MARK: - XML 安全工具
    
    /// 移除 XML 1.0 中不合法的控制字元 (例如 \x07 bell, \x08 backspace 等)
    nonisolated static func removeInvalidXMLCharacters(_ text: String) -> String {
        let invalidXMLChars = CharacterSet(charactersIn: "\u{0000}"..."\u{001F}")
            .subtracting(CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000D}"))
        return text.components(separatedBy: invalidXMLChars).joined()
    }

    /// 將標題的危險符號跳脫，防止 toc.ncx 導覽檔崩潰
    nonisolated static func sanitizeForXML(_ text: String) -> String {
        let cleanText = removeInvalidXMLCharacters(text)
        return cleanText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    /// 將 Ink 產生的寬鬆 HTML5，強制洗白成極度嚴格的 XHTML
    nonisolated static func sanitizeHTMLBody(_ html: String) -> String {
        var clean = removeInvalidXMLCharacters(html)
        clean = clean.replacingOccurrences(of: "<br>", with: "<br/>")
        clean = clean.replacingOccurrences(of: "<hr>", with: "<hr/>")
        
        // 抹除 alt 屬性亂碼
        clean = Self.altRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "alt=\"figure\"")
        
        // 強制 img 標籤自閉合
        clean = Self.imgRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "<img$1/>")
        
        // 處理未跳脫的 & 符號
        clean = Self.ampRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: clean.utf16.count), withTemplate: "&amp;")
        
        return clean
    }

    // MARK: - 標題擷取與 ID 注入
    
    /// 掃描 HTML 中的 h1/h2/h3 標籤，注入唯一 id 屬性，並返回標題清單
    struct TOCEntry {
        let level: Int       // 1, 2, or 3
        let id: String       // "heading-1", "heading-2", ...
        let text: String     // 標題純文字
    }
    
    /// 對 HTML 中的 h1/h2/h3 標籤注入 id 屬性，讓 EPUB TOC 可以連結到具體位置
    nonisolated static func injectHeadingIDs(_ html: String) -> (String, [TOCEntry]) {
        var result = html
        var entries: [TOCEntry] = []
        var counter = 0
        var seenTexts: Set<String> = []  // 用於去重
        
        // 匹配 <h1>, <h2>, <h3> 標籤 — 使用 [^<]* 避免跨標籤匹配
        // 同時支援 <h1>text</h1> 和 <h1><strong>text</strong></h1>
        let regex = Self.headingRegex
        
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
        
        var replacements: [(range: NSRange, replacement: String, entry: TOCEntry?)] = []
        
        for match in matches {
            guard let tagRange = Range(match.range(at: 1), in: result),
                  let contentRange = Range(match.range(at: 3), in: result) else { continue }
            
            let tag = String(result[tagRange])
            let level = Int(String(tag.last!)) ?? 1
            let content = String(result[contentRange])
            
            // 去除 HTML 標籤取得純文字
            let plainText = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !plainText.isEmpty else { continue }
            
            // 過濾極長的垃圾標題 (> 120 字元不太可能是真正的標題)
            let truncatedText = plainText.count > 120 ? String(plainText.prefix(120)) + "..." : plainText
            
            counter += 1
            let headingID = "heading-\(counter)"
            
            // 檢查是否已有 id 屬性
            let attrsRange = match.range(at: 2)
            let existingAttrs = attrsRange.length > 0 ? (Range(attrsRange, in: result).map { String(result[$0]) } ?? "") : ""
            
            if existingAttrs.contains("id=") {
                // 已有 id，不重複注入，但仍擷取 TOC 條目
                if !seenTexts.contains(truncatedText) {
                    seenTexts.insert(truncatedText)
                    // 嘗試擷取現有 id
                    if let idMatch = existingAttrs.range(of: "id=\"([^\"]+)\"", options: .regularExpression) {
                        let existingID = String(existingAttrs[idMatch]).replacingOccurrences(of: "id=\"", with: "").replacingOccurrences(of: "\"", with: "")
                        entries.append(TOCEntry(level: level, id: existingID, text: truncatedText))
                    }
                }
                continue  // 不修改 HTML
            }
            
            let replacement = "<\(tag) id=\"\(headingID)\"\(existingAttrs)>\(content)</\(tag)>"
            
            // 去重：相同文字的標題只出現一次在 TOC 中
            var entry: TOCEntry? = nil
            if !seenTexts.contains(truncatedText) {
                seenTexts.insert(truncatedText)
                entry = TOCEntry(level: level, id: headingID, text: truncatedText)
            }
            
            replacements.append((range: match.range, replacement: replacement, entry: entry))
        }
        
        // 從後往前替換 (所有 heading 都注入 id，但只有非重複的進入 TOC)
        for rep in replacements.reversed() {
            if let range = Range(rep.range, in: result) {
                result.replaceSubrange(range, with: rep.replacement)
                if let entry = rep.entry {
                    entries.insert(entry, at: 0)
                }
            }
        }
        
        return (result, entries)
    }
    
    /// 從 TOCEntry 陣列生成 EPUB nav 的 <ol> 內容
    nonisolated static func buildNavLinks(entries: [TOCEntry], xhtmlFile: String) -> String {
        guard !entries.isEmpty else {
            return "<li><a href=\"\(xhtmlFile)\">正文</a></li>"
        }
        var links = ""
        for entry in entries {
            let indent = String(repeating: "  ", count: entry.level - 1)
            links += "\(indent)<li><a href=\"\(xhtmlFile)#\(entry.id)\">\(sanitizeForXML(entry.text))</a></li>\n"
        }
        return links
    }

    // MARK: - 標準通道：單頁論文引擎

    /// 建立單頁或無分章論文的 EPUB 檔案
    nonisolated static func createEPUB(title: String, html: String, assetsURL: URL) -> URL? {
        let fm = FileManager.default
        let epubURL = fm.temporaryDirectory.appendingPathComponent("\(title).epub")
        let bookUUID = UUID().uuidString
        
        do {
            // 🛡️ 單頁引擎不支援分章，將 <!-- CHAPTER_SPLIT --> 轉為 <hr/>
            let cleanHTML = html.replacingOccurrences(of: "<!-- CHAPTER_SPLIT -->", with: "\n\n<hr/>\n\n")

            // 🛡️ 直接套用清洗
            let rawHTML = sanitizeHTMLBody(cleanHTML)
            
            // 📖 注入標題 ID 並擷取 TOC 條目
            let (htmlBody, tocEntries) = injectHeadingIDs(rawHTML)
            
            // 📊 TOC 日誌
            print("📖 TOC 擷取結果: \(tocEntries.count) 條標題")
            for entry in tocEntries.prefix(10) {
                print("  h\(entry.level): \(entry.text.prefix(60))")
            }
            if tocEntries.count > 10 { print("  ... 還有 \(tocEntries.count - 10) 條") }
            
            let fullHTML = """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
                <title>\(sanitizeForXML(title))</title>
                <meta charset="utf-8"/>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; padding: 4%; color: #1c1c1e; background-color: #ffffff; }
                    p { margin-bottom: 1.2em; text-indent: 0; }
                    h1, h2, h3 { font-weight: 700; letter-spacing: -0.02em; color: #000000; margin-top: 1.8em; margin-bottom: 0.8em; }
                    h1.doc-title { font-size: 2.2em; text-align: center; margin-bottom: 1.5em; }
                    img { max-width: 100%; height: auto; display: block; margin: 30px auto; border-radius: 12px; }
                    .doc-caption { text-align: center; font-size: 0.85em; color: #6c6c70; margin-top: -20px; margin-bottom: 30px; }
                    table { border-collapse: collapse; width: 100%; margin: 24px 0; font-size: 0.9em; }
                    th, td { border: 1px solid #d1d1d6; padding: 12px 16px; }
                    th { background-color: #f2f2f7; }
                    @media (prefers-color-scheme: dark) {
                        body { color: #e5e5ea; background-color: #000000; }
                        h1, h2, h3 { color: #ffffff; }
                        th { background-color: #1c1c1e; }
                        th, td { border-color: #38383a; }
                        .doc-caption { color: #8e8e93; }
                    }
                </style>
            </head>
            <body>\(htmlBody)</body>
            </html>
            """
            
            let containerXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """
            
            // 📖 從實際標題建構 TOC
            var navLinks = buildNavLinks(entries: tocEntries, xhtmlFile: "chapter.xhtml")
            if navLinks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                navLinks = "<li><a href=\"chapter_1.xhtml\">正文</a></li>\n"
            }
            
            let navHTML = """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head><title>目錄</title></head>
            <body><nav epub:type="toc" id="toc"><h1>目錄</h1><ol>
            \(navLinks)
            </ol></nav></body>
            </html>
            """
            
            // 收集圖片清單
            var imageItems = ""
            let oebpsAssetsPath = "OEBPS/assets"
            if fm.fileExists(atPath: assetsURL.path),
               let images = try? fm.contentsOfDirectory(atPath: assetsURL.path) {
                for (index, image) in images.enumerated() where !image.hasPrefix(".") {
                    imageItems += "<item id=\"img\(index)\" href=\"assets/\(image)\" media-type=\"image/png\"/>\n"
                }
            }
            
            let contentOPF = """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
                <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>\(sanitizeForXML(title))</dc:title>
                    <dc:language>zh-TW</dc:language>
                    <dc:identifier id="pub-id">urn:uuid:\(bookUUID)</dc:identifier>
                </metadata>
                <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
                    \(imageItems)
                </manifest>
                <spine><itemref idref="chapter"/></spine>
            </package>
            """
            
            // 🚀 組裝 EPUB 檔案條目
            var entries: [EPUBArchiveEntry] = []
            entries.append(EPUBArchiveEntry(path: "mimetype", data: Data("application/epub+zip".utf8)))
            entries.append(EPUBArchiveEntry(path: "META-INF/container.xml", data: Data(containerXML.utf8)))
            entries.append(EPUBArchiveEntry(path: "OEBPS/content.opf", data: Data(contentOPF.utf8)))
            entries.append(EPUBArchiveEntry(path: "OEBPS/nav.xhtml", data: Data(navHTML.utf8)))
            entries.append(EPUBArchiveEntry(path: "OEBPS/chapter.xhtml", data: Data(fullHTML.utf8)))
            
            // 加入圖片資源
            if fm.fileExists(atPath: assetsURL.path),
               let images = try? fm.contentsOfDirectory(atPath: assetsURL.path) {
                for image in images where !image.hasPrefix(".") {
                    let imageURL = assetsURL.appendingPathComponent(image)
                    if let imageData = try? Data(contentsOf: imageURL) {
                        entries.append(EPUBArchiveEntry(path: "OEBPS/assets/\(image)", data: imageData))
                    }
                }
            }
            
            // 寫入合規 EPUB ZIP
            let archiveData = try StoredZIPArchive(entries: entries).data()
            if fm.fileExists(atPath: epubURL.path) { try fm.removeItem(at: epubURL) }
            try archiveData.write(to: epubURL)
            
            return epubURL
        } catch {
            AppLogger.shared.error("❌ EPUB 合成失敗: \(error)")
            return nil
        }
    }

    // MARK: - 書籍專用通道：多章節引擎

    /// 建立多章節書籍的 EPUB 檔案
    nonisolated static func createBookEPUB(title: String, fullHTML: String, assetsURL: URL) -> URL? {
        let fm = FileManager.default
        let epubURL = fm.temporaryDirectory.appendingPathComponent("\(title).epub")
        let bookUUID = UUID().uuidString
        
        do {
            var rawChapters = fullHTML.components(separatedBy: "<!-- CHAPTER_SPLIT -->")
            rawChapters = rawChapters.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            var manifestItems = ""
            var spineItems = ""
            var navLinks = ""
            var ncxNavPoints = ""
            var chapterEntries: [EPUBArchiveEntry] = []
            
            for (index, chapterHTML) in rawChapters.enumerated() {
                let chapterId = "chapter_\(index + 1)"
                let fileName = "\(chapterId).xhtml"
                
                // Try to extract a title from the first heading tag in this chapter
                var safeTitle = "Chapter \(index + 1)"
                if let headingMatch = headingRegex.firstMatch(in: chapterHTML, options: [], range: NSRange(location: 0, length: chapterHTML.utf16.count)) {
                    if let contentRange = Range(headingMatch.range(at: 3), in: chapterHTML) {
                        let plainText = String(chapterHTML[contentRange]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !plainText.isEmpty {
                            safeTitle = sanitizeForXML(plainText)
                        }
                    }
                }
                
                let rawHTML = sanitizeHTMLBody(chapterHTML)
                // 📖 注入標題 ID 並擷取 TOC 條目
                let (htmlBody, tocEntries) = injectHeadingIDs(rawHTML)
                
                let fullHTML = """
                <?xml version="1.0" encoding="utf-8"?>
                <!DOCTYPE html>
                <html xmlns="http://www.w3.org/1999/xhtml">
                <head>
                    <title>\(safeTitle)</title>
                    <meta charset="utf-8"/>
                    <style>
                        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; padding: 4%; color: #1c1c1e; background-color: #ffffff; }
                        p { margin-bottom: 1.2em; text-indent: 0; }
                        h1, h2, h3 { font-weight: 700; letter-spacing: -0.02em; color: #000000; margin-top: 1.8em; margin-bottom: 0.8em; }
                        h1.doc-title { font-size: 2.2em; text-align: center; margin-bottom: 1.5em; }
                        img { max-width: 100%; height: auto; display: block; margin: 30px auto; border-radius: 12px; }
                        .doc-caption { text-align: center; font-size: 0.85em; color: #6c6c70; margin-top: -20px; margin-bottom: 30px; }
                        table { border-collapse: collapse; width: 100%; margin: 24px 0; font-size: 0.9em; }
                        th, td { border: 1px solid #d1d1d6; padding: 12px 16px; }
                        th { background-color: #f2f2f7; }
                        @media (prefers-color-scheme: dark) {
                            body { color: #e5e5ea; background-color: #000000; }
                            h1, h2, h3 { color: #ffffff; }
                            th { background-color: #1c1c1e; }
                            th, td { border-color: #38383a; }
                            .doc-caption { color: #8e8e93; }
                        }
                    </style>
                </head>
                <body>\(htmlBody)</body>
                </html>
                """
                
                chapterEntries.append(EPUBArchiveEntry(path: "OEBPS/\(fileName)", data: Data(fullHTML.utf8)))
                
                manifestItems += "<item id=\"\(chapterId)\" href=\"\(fileName)\" media-type=\"application/xhtml+xml\"/>\n"
                spineItems += "<itemref idref=\"\(chapterId)\"/>\n"
                
                // 📖 建構章節目錄 (含內部標題)
                navLinks += "<li><a href=\"\(fileName)\">\(safeTitle)</a>\n"
                
                var subEntries = tocEntries
                if let firstEntry = subEntries.first, sanitizeForXML(firstEntry.text) == safeTitle {
                    // 去除「標題雙胞胎」：如果第一個內建標題跟章節名稱一模一樣，就拔掉它
                    subEntries.removeFirst()
                }
                
                if !subEntries.isEmpty {
                    navLinks += "<ol>\n"
                    navLinks += buildNavLinks(entries: subEntries, xhtmlFile: fileName)
                    navLinks += "</ol>\n"
                }
                navLinks += "</li>\n"
                
                ncxNavPoints += """
                <navPoint id="navPoint-\(index + 1)" playOrder="\(index + 1)">
                    <navLabel><text>\(safeTitle)</text></navLabel>
                    <content src="\(fileName)"/>
                </navPoint>\n
                """
            }
            
            let navHTML = """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head><title>目錄</title></head>
            <body><nav epub:type="toc" id="toc"><h1>目錄</h1><ol>\n\(navLinks)\n</ol></nav></body>
            </html>
            """
            
            let tocNCX = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                <head>
                    <meta name="dtb:uid" content="urn:uuid:\(bookUUID)"/>
                    <meta name="dtb:depth" content="1"/>
                    <meta name="dtb:totalPageCount" content="0"/>
                    <meta name="dtb:maxPageNumber" content="0"/>
                </head>
                <docTitle><text>\(sanitizeForXML(title))</text></docTitle>
                <navMap>\n\(ncxNavPoints)\n</navMap>
            </ncx>
            """
            
            // 圖片資源清單
            var imageManifest = ""
            var hasCover = false
            if fm.fileExists(atPath: assetsURL.path),
               let images = try? fm.contentsOfDirectory(atPath: assetsURL.path) {
                for (index, image) in images.enumerated() where !image.hasPrefix(".") {
                    let isJPG = image.lowercased().hasSuffix(".jpg") || image.lowercased().hasSuffix(".jpeg")
                    let mediaType = isJPG ? "image/jpeg" : "image/png"
                    let isCover = image == "cover.jpg"
                    if isCover { hasCover = true }
                    
                    let id = isCover ? "cover-image" : "img\(index)"
                    let properties = isCover ? " properties=\"cover-image\"" : ""
                    imageManifest += "<item id=\"\(id)\" href=\"assets/\(image)\" media-type=\"\(mediaType)\"\(properties)/>\n"
                }
            }
            
            let contentOPF = """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
                <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>\(sanitizeForXML(title))</dc:title>
                    <dc:language>zh-TW</dc:language>
                    <dc:identifier id="pub-id">urn:uuid:\(bookUUID)</dc:identifier>
                </metadata>
                <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                    \(manifestItems)
                    \(imageManifest)
                </manifest>
                <spine toc="ncx">\n\(spineItems)\n</spine>
            </package>
            """
            
            // 🚀 組裝所有 EPUB 條目
            var entries: [EPUBArchiveEntry] = []
            entries.append(EPUBArchiveEntry(path: "mimetype", data: Data("application/epub+zip".utf8)))
            entries.append(EPUBArchiveEntry(path: "META-INF/container.xml", data: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """.utf8)))
            entries.append(EPUBArchiveEntry(path: "OEBPS/content.opf", data: Data(contentOPF.utf8)))
            entries.append(EPUBArchiveEntry(path: "OEBPS/nav.xhtml", data: Data(navHTML.utf8)))
            entries.append(EPUBArchiveEntry(path: "OEBPS/toc.ncx", data: Data(tocNCX.utf8)))
            
            // 章節 XHTML
            for entry in chapterEntries {
                entries.append(entry)
            }
            
            // 圖片資源
            if fm.fileExists(atPath: assetsURL.path),
               let images = try? fm.contentsOfDirectory(atPath: assetsURL.path) {
                for image in images where !image.hasPrefix(".") {
                    let imageURL = assetsURL.appendingPathComponent(image)
                    if let imageData = try? Data(contentsOf: imageURL) {
                        entries.append(EPUBArchiveEntry(path: "OEBPS/assets/\(image)", data: imageData))
                    }
                }
            }
            
            // 寫入合規 EPUB ZIP
            let archiveData = try StoredZIPArchive(entries: entries).data()
            if fm.fileExists(atPath: epubURL.path) { try fm.removeItem(at: epubURL) }
            try archiveData.write(to: epubURL)
            
            return epubURL
        } catch {
            AppLogger.shared.error("❌ 書籍 EPUB 合成失敗: \(error)")
            return nil
        }
    }
}

// MARK: - 合規 Stored-Mode ZIP 寫入器

/// EPUB 檔案條目
struct EPUBArchiveEntry {
    let path: String
    let data: Data
}

/// 純 Swift 實作的 Stored (不壓縮) ZIP 歸檔器
/// 保證 mimetype 為第一個條目且無壓縮、無 extra field，完全符合 EPUB 規範
private struct StoredZIPArchive {
    let entries: [EPUBArchiveEntry]
    
    nonisolated func data() throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var centralDirEntries: [(entry: EPUBArchiveEntry, crc: UInt32, offset: UInt32)] = []
        
        // 1. 寫入 Local File Headers + File Data
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let localHeaderOffset = UInt32(archive.count)
            let size = UInt32(entry.data.count)
            
            // Local File Header Signature (0x04034b50)
            archive.appendUInt32(0x04034b50)
            archive.appendUInt16(20)      // Version needed (2.0)
            archive.appendUInt16(0)       // General purpose bit flag
            archive.appendUInt16(0)       // Compression method (0 = Stored)
            archive.appendUInt16(0)       // Last mod file time
            archive.appendUInt16(0)       // Last mod file date
            archive.appendUInt32(crc)     // CRC-32
            archive.appendUInt32(size)    // Compressed size
            archive.appendUInt32(size)    // Uncompressed size
            archive.appendUInt16(UInt16(nameData.count)) // File name length
            archive.appendUInt16(0)       // Extra field length (必須為 0，尤其 mimetype)
            archive.append(nameData)
            archive.append(entry.data)
            
            centralDirEntries.append((entry, crc, localHeaderOffset))
        }
        
        // 2. 寫入 Central Directory
        let centralDirectoryOffset = archive.count
        for item in centralDirEntries {
            let nameData = Data(item.entry.path.utf8)
            let size = UInt32(item.entry.data.count)
            
            centralDirectory.appendUInt32(0x02014b50)  // Central Directory Header Signature
            centralDirectory.appendUInt16(20)  // Version made by
            centralDirectory.appendUInt16(20)  // Version needed
            centralDirectory.appendUInt16(0)   // General purpose bit flag
            centralDirectory.appendUInt16(0)   // Compression method
            centralDirectory.appendUInt16(0)   // Last mod file time
            centralDirectory.appendUInt16(0)   // Last mod file date
            centralDirectory.appendUInt32(item.crc)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)   // Extra field length
            centralDirectory.appendUInt16(0)   // File comment length
            centralDirectory.appendUInt16(0)   // Disk number start
            centralDirectory.appendUInt16(0)   // Internal file attributes
            centralDirectory.appendUInt32(0)   // External file attributes
            centralDirectory.appendUInt32(item.offset)
            centralDirectory.append(nameData)
        }
        
        // 3. 寫入 End of Central Directory (EOCD)
        archive.append(centralDirectory)
        archive.appendUInt32(0x06054b50)  // EOCD Signature
        archive.appendUInt16(0)           // Disk number
        archive.appendUInt16(0)           // Disk where CD starts
        archive.appendUInt16(UInt16(centralDirEntries.count))
        archive.appendUInt16(UInt16(centralDirEntries.count))
        archive.appendUInt32(UInt32(centralDirectory.count))
        archive.appendUInt32(UInt32(centralDirectoryOffset))
        archive.appendUInt16(0)           // Comment length
        
        return archive
    }
}

// MARK: - Data 擴充：寫入小端位元組

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

// MARK: - CRC-32 計算 (純 Swift，不需外部框架)

private enum CRC32 {
    nonisolated(unsafe) static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 == 1 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
    }()
    
    nonisolated static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
