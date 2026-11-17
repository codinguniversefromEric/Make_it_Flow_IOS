//
//  BatchProcessor.swift
//  ePdfUB
//
//  Created by 魏嘉賢 on 2026/6/13.
//  Rewritten for fully edge-compute content extraction on 2026/6/14.
//

import Foundation
import PDFKit
import Vision
import CoreML
import Combine
import CoreText
import NaturalLanguage
#if os(iOS)
import UIKit
#endif

// MARK: - Batch Processor

/// 批次處理器，負責處理 PDF 的讀取、分析、與匯出流程
class BatchProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var exportedFileURL: URL?
    
    @Published var isCancelled: Bool = false
    private var currentTask: Task<Void, Never>?
    private let activityTracker = LiveActivityManager()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
#if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { _ in
                MemoryManager.shared.downgradeToLowEnd()
                LayoutVisionManager.shared.setupEngine()
            }
            .store(in: &cancellables)
#endif
    }
    
    /// 取消當前處理任務
    func cancel() {
        self.isCancelled = true
        self.currentTask?.cancel()
    }
    
    /// 非同步匯出 PDF 文件，包含版面分析與 Markdown/EPUB 產生
    @MainActor
    func exportDocument(_ document: PDFDocument, fileName: String? = nil) async {
        // 向系統申請背景執行權限，確保關閉螢幕或退到背景時轉檔與動態島繼續運作 (Issue: 背景凍結)
#if os(iOS)
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "PDF_Export_Task") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
#endif
        
        AppLogger.shared.info("Starting PDF export. Total pages: \(document.pageCount)")
        self.isCancelled = false
        self.isProcessing = true
        self.progress = 0.0
        self.exportedFileURL = nil
        
        // 📖 從 PDF 元資料萃取文件標題
        let initialTitle: String? = {
            if let firstPage = document.page(at: 0), PDFTextLines.usesLegacyVietnameseEncoding(firstPage) {
                return fileName
            }
            let pdfMetadataTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            var title = pdfMetadataTitle
            if title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                title = fileName
            }
            return title
        }()
        
        let displayTitle = initialTitle ?? "Document"
        Task { await self.activityTracker.start(documentName: displayTitle) }
        
        // 🚀 建立專屬的「匯出資料夾」與「圖片庫」
        let fm = FileManager.default
        let exportDir = fm.temporaryDirectory.appendingPathComponent("LibriAI_Export")
        
        // 如果之前有舊的，先清空
        if fm.fileExists(atPath: exportDir.path) {
            try? fm.removeItem(at: exportDir)
        }
        try? fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        
        let assetsDir = exportDir.appendingPathComponent("assets")
        try? fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        
        self.currentTask = Task.detached(priority: .utility) {
            // 📖 These mutable variables are fully owned by the detached task to avoid data races
            var detectedTitle = initialTitle
            var fullHTML = ""
            var languageSample = ""
            var ocrLanguageSample = ""
            var previousContentPage: Int?
            var chapterStartPage = 0
            let pdfBookmarks = Self.sourceOutline(in: document)
            let chineseOutline = pdfBookmarks.isEmpty ? PDFPrintedOutline.readChinese(document) : nil
            let sourceEntries = chineseOutline?.entries ?? pdfBookmarks
            let entriesByPage = Dictionary(grouping: sourceEntries, by: \.page)
            let numberedChapters = sourceEntries.isEmpty ? Self.numberedChapterStarts(in: document) : [:]
            let printedOutline = pdfBookmarks.isEmpty && numberedChapters.isEmpty && chineseOutline == nil
                ? PDFPrintedOutline.read(document) : nil
            let outline = printedOutline?.outline ?? [:]
            let sourceChapterStarts = Dictionary(uniqueKeysWithValues: entriesByPage.compactMap { page, entries in
                entries.first(where: { $0.depth == 0 }).map { (page, $0.title) }
            })
            let chapterStarts = !sourceEntries.isEmpty ? sourceChapterStarts
                : (outline.isEmpty ? numberedChapters : outline.mapValues(\.title))
            let linkedContents = Self.linkedContents(in: document, destinations: Set(pdfBookmarks.map(\.page)))
            let contentsPages = chineseOutline?.contentsPages ?? printedOutline?.contentsPages ?? (
                pdfBookmarks.isEmpty
                    ? Self.printedContentsPages(in: document, chapterStarts: chapterStarts)
                    : linkedContents?.continuations ?? []
            )
            let repeatedMargins = Self.repeatedMarginLines(in: document)
            var chapterTitles = [initialTitle ?? "Front Matter"]
            var outlineDepths = [-1]
            var chapterNotes = ""
            
            // 🌐 全域文件樣式分析
            AppLogger.shared.info("開始進行全域樣式分析...")
            let styleRegistry = StyleRegistry.analyze(document: document)
            AppLogger.shared.info("全域分析完成: Body \(styleRegistry.bodyFontSize)pt, H1 \(styleRegistry.h1FontSize)pt, H2 \(styleRegistry.h2FontSize)pt")
            
            for pageIndex in 0..<document.pageCount {
                if await MainActor.run(resultType: Bool.self, body: { self.isCancelled }) {
                    AppLogger.shared.info("Processing cancelled by user.")
                    await MainActor.run { self.isProcessing = false }
                    
                    await self.activityTracker.end(progress: 0.0, message: "Cancelled")
                    
                    return
                }
                
                AppLogger.shared.info("Processing page \(pageIndex + 1)/\(document.pageCount)")
                // 🛑 讓 CPU 喘口氣
                await Task.yield()
                
                guard let page = document.page(at: pageIndex) else {
                    AppLogger.shared.warning("Failed to get page at index \(pageIndex)")
                    continue
                }
                
                if contentsPages.contains(pageIndex) {
                    if linkedContents == nil && pageIndex == contentsPages.min() {
                        fullHTML += "<!-- PRINTED_CONTENTS -->\n\n"
                    }
                    continue
                }
                let pageBounds = page.bounds(for: .cropBox)
                
                // 🎯 模型感知的渲染倍率：統一使用 2x
                let scale: CGFloat = 2.0
                let scaledSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
                
                // 🛡️ 記憶體防護罩
                var rawImage: AppImage? = nil
                var cgImg: CGImage? = nil
                
                autoreleasepool {
#if os(iOS)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1.0
                    let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
                    let img = renderer.image { ctx in
                        let context = ctx.cgContext
                        UIColor.white.set()
                        context.fill(CGRect(origin: .zero, size: scaledSize))
                        context.saveGState()
                        context.translateBy(x: 0, y: scaledSize.height)
                        context.scaleBy(x: scale, y: -scale)
                        page.draw(with: .cropBox, to: context)
                        context.restoreGState()
                    }
                    rawImage = img
                    cgImg = img.cgImage
#elseif os(macOS)
                    let nsImage = NSImage(size: scaledSize)
                    nsImage.lockFocus()
                    if let context = NSGraphicsContext.current?.cgContext {
                        context.setFillColor(NSColor.white.cgColor)
                        context.fill(CGRect(origin: .zero, size: scaledSize))
                        
                        // We must scale the context if scale != 1.0
                        context.scaleBy(x: scale, y: scale)
                        page.draw(with: .cropBox, to: context)
                    }
                    nsImage.unlockFocus()
                    
                    var proposedRect = CGRect(origin: .zero, size: scaledSize)
                    if let cgImage = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
                        cgImg = cgImage
                        rawImage = nsImage
                    }
#endif
                }
                
                guard let validCGImg = cgImg, let validRawImage = rawImage else { continue }
                
                // --- 封面擷取 (第 1 頁) ---
                if pageIndex == 0 {
                    if let imageData = validRawImage.appJPEGData(compressionQuality: 0.85) {
                        let fileURL = assetsDir.appendingPathComponent("cover.jpg")
                        try? imageData.write(to: fileURL)
                        AppLogger.shared.info("🖼️ 成功儲存封面圖片 cover.jpg")
                    }
                }
                
                // ═══════════════════════════════════════════
                // STAGE 1: YOLO 視覺區域偵測 (圖片/表格/公式)
                // ═══════════════════════════════════════════
                
                let rawObservations = await LayoutVisionManager.shared.detectLayout(in: validCGImg)
                
                // NMS 過濾 (使用共用工具)
                var filteredObs: [LayoutBlock] = []
                let sortedObs = rawObservations.sorted { $0.confidence > $1.confidence }
                for obs in sortedObs {
                    var keep = true
                    let cRect = obs.boundingBox
                    for kObs in filteredObs {
                        let kRect = kObs.boundingBox
                        if NMSUtils.calcIoU(cRect, kRect) > 0.4 || NMSUtils.calcCoverage(cRect, kRect) > 0.8 {
                            keep = false; break
                        }
                    }
                    if keep { filteredObs.append(obs) }
                }
                
                // ═══════════════════════════════════════════
                // STAGE 1.2: 碎裂表格與跨頁表格合併 (Table Merging)
                // ═══════════════════════════════════════════
                // 將區塊由上到下排序 (Vision 座標 maxY 越大代表在畫面上方)
                filteredObs.sort { $0.boundingBox.maxY > $1.boundingBox.maxY }
                
                var mergedObs: [LayoutBlock] = []
                var obsIdx = 0
                while obsIdx < filteredObs.count {
                    let obs = filteredObs[obsIdx]
                    if obs.label == "Table" {
                        var j = obsIdx + 1
                        var currentRect = obs.boundingBox
                        
                        while j < filteredObs.count {
                            let nextObs = filteredObs[j]
                            // Vision 座標：下方區塊的 maxY 必須緊貼上方區塊的 minY
                            let verticalGap = currentRect.minY - nextObs.boundingBox.maxY
                            let horizontalOverlap = min(currentRect.maxX, nextObs.boundingBox.maxX) - max(currentRect.minX, nextObs.boundingBox.minX)
                            
                            // 允許稍微重疊到些微空白
                            if verticalGap > -0.05 && verticalGap < 0.08 && horizontalOverlap > 0 {
                                // 相鄰表格可合併，旁邊的文字仍保留為可選取內文。
                                if nextObs.label == "Table" {
                                    currentRect = currentRect.union(nextObs.boundingBox)
                                    j += 1
                                    continue
                                }
                            }
                            break
                        }
                        mergedObs.append(LayoutBlock(boundingBox: currentRect, label: "Table", confidence: obs.confidence))
                        obsIdx = j
                    } else {
                        mergedObs.append(obs)
                        obsIdx += 1
                    }
                }
                filteredObs = mergedObs
                
                // ═══════════════════════════════════════════
                // STAGE 1.5: 啟發式公式修正 (YOLO Label Correction)
                // ═══════════════════════════════════════════
                for i in 0..<filteredObs.count {
                    let obs = filteredObs[i]
                    if obs.label == "Section-header" || obs.label == "Title" || obs.label == "Text" {
                        // PDFKit 使用左下角為原點，而 YOLO boundingBox 也是基於左下角 (Vision 標準)
                        let pdfRect = CGRect(
                            x: obs.boundingBox.minX * pageBounds.width,
                            y: obs.boundingBox.minY * pageBounds.height,
                            width: obs.boundingBox.width * pageBounds.width,
                            height: obs.boundingBox.height * pageBounds.height
                        )
                        
                        if let selection = page.selection(for: pdfRect), let text = selection.string {
                            let textForMath = text.replacingOccurrences(of: "\n", with: " ")
                            
                            // Require an equation-shaped relation and an explicit mathematical operator.
                            let relation = #"[\p{L}\p{N}\)\]]\s*[=≈≠≤≥]\s*[\p{L}\p{N}\(√−-]"#
                            let hasRelation = textForMath.range(of: relation, options: .regularExpression) != nil
                            let hasOperator = textForMath.range(of: #"[+×÷∑∫√±−]"#, options: .regularExpression) != nil
                            let hasProse = textForMath.range(of: #"\b[A-Za-z]{4,}\b\s+\b[A-Za-z]{4,}\b"#, options: .regularExpression) != nil
                            if hasRelation && hasOperator && !hasProse && textForMath.count < 150 {
                                filteredObs[i] = LayoutBlock(boundingBox: obs.boundingBox, label: "Formula", confidence: obs.confidence)
                            }
                        }
                    }
                }
                
                let visualLabels: Set<String> = ["Picture", "Figure", "Formula", "Table"]

                // ═══════════════════════════════════════════
                // STAGE 2: PDFKit 富文字萃取 → TextFragment
                // ═══════════════════════════════════════════
                
                var textFragments: [TextFragment] = []
                
                let usesLegacyVietnamese = PDFTextLines.usesLegacyVietnameseEncoding(page)
                let nativeSelections = usesLegacyVietnamese ? [] : PDFTextLines.selections(in: page, bounds: pageBounds)
                for line in nativeSelections {
                    guard let lineText = line.string, !lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                    let pRect = line.bounds(for: page)
                    let displayRect = CGRect(
                        x: pRect.minX * scale,
                        y: (pageBounds.height - pRect.maxY) * scale,
                        width: pRect.width * scale,
                        height: pRect.height * scale
                    )

                    // 📝 嘗試從 attributedString 擷取字體資訊
                    var fontSize: CGFloat = 12.0
                    var fontName: String? = nil
                    var isBold = false
                    var isItalic = false
                    var colorHex = "#000000"
                    var footnoteMarkers: [NSRange] = []
                    let recoveredText = NSMutableString(string: lineText)

                    if let attrStr = line.attributedString, attrStr.length > 0 {
                        let source = attrStr.string as NSString
                        var markerRuns: [(range: NSRange, size: CGFloat)] = []
                        var lineFontSize: CGFloat = 0
                        var longestTextRun = 0
                        attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length)) { attrs, range, _ in
                            if let font = attrs[.font] as? AppFont {
                                let runText = source.substring(with: range)
                                if runText.range(of: #"^(?:[0-9]{1,3}|[*†‡])$"#, options: .regularExpression) != nil {
                                    markerRuns.append((range, font.pointSize))
                                } else {
                                    let letters = runText.filter(\.isLetter).count
                                    if letters > longestTextRun {
                                        longestTextRun = letters
                                        lineFontSize = font.pointSize
                                        fontSize = font.pointSize
                                        fontName = font.fontName
                                        isBold = font.isAppFontBold
                                        #if os(iOS)
                                        isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                                        #elseif os(macOS)
                                        isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                                        #endif
                                    }
                                }
                            }
                            if let color = attrs[.foregroundColor] as? AppColor {
                                let runText = source.substring(with: range)
                                let hex = color.hexString
                                let rgb = UInt32(hex.dropFirst(), radix: 16) ?? 0
                                let red = Int((rgb >> 16) & 255)
                                let green = Int((rgb >> 8) & 255)
                                let blue = Int(rgb & 255)
                                // Some embedded fonts expose the red bullet glyph as a lowercase l.
                                if attrStr.string == lineText, runText == "l",
                                   red - green > 60, red - blue > 60 {
                                    recoveredText.replaceCharacters(in: range, with: "•")
                                } else if runText.contains(where: \.isLetter) {
                                    colorHex = hex
                                }
                            }
                        }
                        if longestTextRun == 0, let font = attrStr.attribute(.font, at: 0, effectiveRange: nil) as? AppFont {
                            fontSize = font.pointSize
                        }
                        if attrStr.string == lineText {
                            footnoteMarkers = markerRuns.filter {
                                $0.range.location > 0 && $0.size <= lineFontSize * 0.80
                            }.map(\.range)
                            if footnoteMarkers.isEmpty {
                                // PDFKit can flatten a superscript into the surrounding run.
                                // The matcher still requires a unique, smaller note on this page.
                                let pattern = #"(?<=[.!?])([0-9]{1,3})(?=\s|$)"#
                                let regex = try! NSRegularExpression(pattern: pattern)
                                footnoteMarkers = regex.matches(in: lineText, range: NSRange(location: 0, length: source.length))
                                    .map { $0.range(at: 1) }
                            }
                        }
                    }

                    let plainText = recoveredText.replacingOccurrences(of: "\u{0007}", with: "")
                    let repairedText = PDFTextLines.repairMetricDefinition(PDFTextLines.repairDimensionSymbols(plainText))
                    let fragment = TextFragment(
                        text: repairedText,
                        bounds: displayRect,
                        fontSize: fontSize * scale,
                        fontName: fontName,
                        isBold: isBold,
                        isItalic: isItalic,
                        colorHex: colorHex,
                        footnoteMarkers: lineText.contains("\u{0007}") || repairedText != plainText ? [] : footnoteMarkers
                    )

                    textFragments.append(fragment)
                }
                // ═══════════════════════════════════════════
                // STAGE 2.1: 去除重疊的重複碎片 (Faux Bold / Shadow 處理)
                // ═══════════════════════════════════════════
                var dedupedFragments: [TextFragment] = []
                for frag in textFragments {
                    var isDuplicate = false
                    // 往前找，檢查是否有重疊的重複字
                    for i in stride(from: dedupedFragments.count - 1, through: 0, by: -1) {
                        let existing = dedupedFragments[i]
                        let intersection = existing.bounds.intersection(frag.bounds)
                        
                        if !intersection.isNull {
                            let minArea = min(existing.bounds.width * existing.bounds.height, frag.bounds.width * frag.bounds.height)
                            let interArea = intersection.width * intersection.height
                            
                            // 如果重疊面積超過較小碎片的 50%，且文字相同或被包含
                            if minArea > 0 && (interArea / minArea) > 0.5 {
                                if existing.text.contains(frag.text) || frag.text.contains(existing.text) {
                                    // 保留較長的文字 (避免 "牌" 和 ""牌" 被錯誤切斷)
                                    if frag.text.count > existing.text.count {
                                        dedupedFragments[i] = frag
                                    }
                                    isDuplicate = true
                                    break
                                }
                            }
                        }
                    }
                    if !isDuplicate {
                        dedupedFragments.append(frag)
                    }
                }
                textFragments = PDFTextLines.attachListMarkers(dedupedFragments)
                
                // Extract visuals after retaining the full set of PDF lines for edge checks.
                // Text suppression and layout assignment use the same rectangle as the saved image.
                var visualRegions: [VisualRegion] = []
                let formulaBounds = PDFTextLines.malformedNumberedFormulaBounds(in: textFragments, pageSize: scaledSize)
                if !formulaBounds.isEmpty {
                    filteredObs.removeAll { observation in
                        guard observation.label == "Formula" else { return false }
                        let rect = VNImageRectForNormalizedRect(observation.boundingBox, Int(scaledSize.width), Int(scaledSize.height))
                        let display = CGRect(x: rect.minX, y: scaledSize.height - rect.maxY, width: rect.width, height: rect.height)
                        return formulaBounds.contains { $0.intersects(display) }
                    }
                    for rect in formulaBounds {
                        let box = CGRect(x: rect.minX / scaledSize.width, y: 1 - rect.maxY / scaledSize.height,
                                         width: rect.width / scaledSize.width, height: rect.height / scaledSize.height)
                        filteredObs.append(LayoutBlock(boundingBox: box, label: "Formula", confidence: 1))
                    }
                }
                let visualIndices = filteredObs.indices.filter { visualLabels.contains(filteredObs[$0].label) }
                var visualFragments: [TextFragment] = []
                for (imageIndex, observationIndex) in visualIndices.enumerated() {
                    let observation = filteredObs[observationIndex]
                    let visionRect = VNImageRectForNormalizedRect(
                        observation.boundingBox, Int(scaledSize.width), Int(scaledSize.height)
                    )
                    let original = CGRect(x: visionRect.minX, y: scaledSize.height - visionRect.maxY,
                                          width: visionRect.width, height: visionRect.height)
                    let crop = observation.label == "Formula"
                        ? VisualCropBoundary.expandedFormulaRect(original, lines: textFragments, pageSize: scaledSize)
                        : VisualCropBoundary.trimmedRect(original, label: observation.label, lines: textFragments)
                    let html: String
                    if observation.label == "Table", page.rotation == 0, pageBounds.origin == .zero,
                       let table = TableReconstructor.reconstruct(page: page, bounds: CGRect(
                           x: crop.minX / scale, y: pageBounds.height - crop.maxY / scale,
                           width: crop.width / scale, height: crop.height / scale
                       )) {
                        html = table
                    } else {
                        let fileName = "\(observation.label.lowercased())_p\(pageIndex + 1)_\(imageIndex)"
                        guard PDFImageExtractor.cropAndSaveImage(from: validRawImage, cropRect: crop,
                                                                 imageName: fileName, assetsURL: assetsDir) != nil else {
                            filteredObs[observationIndex] = LayoutBlock(
                                boundingBox: observation.boundingBox, label: "Text", confidence: observation.confidence
                            )
                            continue
                        }
                        let image = "<img src=\"assets/\(fileName).jpg\" alt=\"figure\" />"
                        html = observation.label == "Formula" ? "<div class=\"doc-formula\">\(image)</div>" : image
                    }

                    if crop != original {
                        let box = CGRect(x: crop.minX / scaledSize.width,
                                         y: 1 - crop.maxY / scaledSize.height,
                                         width: crop.width / scaledSize.width,
                                         height: crop.height / scaledSize.height)
                        filteredObs[observationIndex] = LayoutBlock(
                            boundingBox: box, label: observation.label, confidence: observation.confidence
                        )
                    }
                    visualRegions.append(VisualRegion(label: observation.label, rect: crop,
                                                      confidence: observation.confidence))
                    visualFragments.append(TextFragment(text: html, bounds: crop, fontSize: 12 * scale,
                                                        fontName: nil, isBold: false, isItalic: false,
                                                        colorHex: "#000000"))
                }
                textFragments.removeAll { line in
                    visualRegions.contains { VisualCropBoundary.containsImageText(line.bounds, in: $0) }
                }

                // ═══════════════════════════════════════════
                // STAGE 2.5: 掃描檔無文字層 Fallback (Scanned PDF)
                // ═══════════════════════════════════════════
                let textLabels: Set<String> = ["Text", "Section-header", "Title", "List-item", "Caption", "Footnote"]
                let textRegions = filteredObs.filter { textLabels.contains($0.label) }.map { block in
                    let rect = VNImageRectForNormalizedRect(block.boundingBox, Int(scaledSize.width), Int(scaledSize.height))
                    return CGRect(x: rect.minX, y: scaledSize.height - rect.maxY, width: rect.width, height: rect.height)
                }
                let uncoveredRegions = textRegions.filter { region in
                    !textFragments.contains { fragment in
                        region.contains(CGPoint(x: fragment.bounds.midX, y: fragment.bounds.midY))
                    }
                }
                let hasSparseTextLayer = textFragments.allSatisfy { $0.bounds.maxY <= scaledSize.height * 0.10 ||
                        $0.bounds.minY >= scaledSize.height * 0.90 }
                if !uncoveredRegions.isEmpty || hasSparseTextLayer {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.automaticallyDetectsLanguage = true
                    if let languages = try? request.supportedRecognitionLanguages(), !languages.isEmpty {
                        if usesLegacyVietnamese, languages.contains("vi-VT") {
                            request.recognitionLanguages = ["vi-VT"]
                        } else {
                            request.recognitionLanguages = languages
                        }
                    }
                    request.usesLanguageCorrection = true
                    var recognizedLines = 0
                    var confidentText = ""

                    let handler = VNImageRequestHandler(cgImage: validCGImg, options: [:])
                    do {
                        try handler.perform([request])
                        let nativeLines = textFragments
                        for observation in request.results ?? [] {
                            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.65,
                                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                            let text = candidate.string
                            let rect = VNImageRectForNormalizedRect(observation.boundingBox, Int(scaledSize.width), Int(scaledSize.height))
                            let bounds = CGRect(x: rect.minX, y: scaledSize.height - rect.maxY, width: rect.width, height: rect.height)
                            let midpoint = CGPoint(x: bounds.midX, y: bounds.midY)
                            guard hasSparseTextLayer || uncoveredRegions.contains(where: { $0.contains(midpoint) }),
                                  !nativeLines.contains(where: { $0.bounds.contains(midpoint) || bounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }),
                                  !visualRegions.contains(where: { VisualCropBoundary.containsImageText(bounds, in: $0) }) else { continue }
                            textFragments.append(TextFragment(
                                text: text, bounds: bounds, fontSize: bounds.height * 0.8,
                                fontName: nil, isBold: false, isItalic: false, colorHex: "#000000"
                            ))
                            recognizedLines += 1
                            if candidate.confidence >= 0.85, confidentText.count < 4_000 {
                                confidentText += String(text.prefix(4_000 - confidentText.count)) + "\n"
                            }
                        }
                    } catch {
                        AppLogger.shared.error("OCR failed: \(error)")
                    }
                    if recognizedLines >= 2, ocrLanguageSample.count < 4_000 {
                        ocrLanguageSample += String(confidentText.prefix(4_000 - ocrLanguageSample.count))
                    }
                    if hasSparseTextLayer, recognizedLines < 2,
                       let image = validRawImage.appJPEGData(compressionQuality: 0.85) {
                        let filename = "page_\(pageIndex + 1).jpg"
                        do {
                            try image.write(to: assetsDir.appendingPathComponent(filename), options: .atomic)
                            let bounds = CGRect(origin: .zero, size: scaledSize)
                            let fragment = TextFragment(
                                text: "<img src=\"assets/\(filename)\" alt=\"PDF page \(pageIndex + 1)\" />",
                                bounds: bounds, fontSize: 12 * scale,
                                fontName: nil, isBold: false, isItalic: false, colorHex: "#000000"
                            )
                            let fullPage = LayoutBlock(
                                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                                label: "Picture", confidence: 1
                            )
                            textFragments = []
                            visualFragments = [fragment]
                            filteredObs = [fullPage]
                        } catch {
                            AppLogger.shared.error("Could not retain scanned page \(pageIndex + 1): \(error)")
                        }
                    }
                }

                textFragments.append(contentsOf: visualFragments)
                let startsLinkedContents = linkedContents?.page == pageIndex
                if let linkedContents, startsLinkedContents {
                    textFragments.removeAll { $0.bounds.midY >= linkedContents.verticalOffset * scale }
                }

                // ═══════════════════════════════════════════
                // STAGE 3: 佈局分析引擎 → 基於 YOLO 區塊的幾何重組
                // ═══════════════════════════════════════════
                
                print("📝 第 \(pageIndex + 1) 頁 PDFKit: \(textFragments.count) 文字行")
                
                var paragraphs = LayoutEngine.processWithLayoutBlocks(
                    fragments: textFragments,
                    blocks: filteredObs,
                    pageWidth: scaledSize.width,
                    pageHeight: scaledSize.height
                )
                
                paragraphs = LayoutEngine.separateTrailingNotes(in: paragraphs, pageHeight: scaledSize.height)
                let footnotes = LayoutEngine.matchFootnotes(in: &paragraphs, pageIndex: pageIndex, pageHeight: scaledSize.height)
                // Semantic classification is now handled directly via LayoutEngine mapping from D4LA labels
                
                // 🛡️ 啟發式標題校正 (Heading Leveling & Promotion)
                for i in paragraphs.indices where paragraphs[i].role != .footnote && footnotes.references[i] == nil {
                    let text = paragraphs[i].unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 主標題 (H1)：第X講、第X章、Part X、壹、
                    let isMainChapter = text.range(of: "^第[一二三四五六七八九十百千萬萬0-9\\s]+[章部節节講讲篇卷回]|^chapter\\s+\\d+|^part\\s+\\d+|^[壹貳參肆伍陸柒捌玖拾]+\\s*[、\\.]", options: [.regularExpression, .caseInsensitive]) != nil && text.count < 60
                    
                    if isMainChapter {
                        paragraphs[i].role = .title
                    }
                }
                
                // 🛡️ 啟發式標題降級 (Heading Downgrade)
                for i in 0..<paragraphs.count {
                    let role = paragraphs[i].role
                    if role == .heading || role == .title {
                        let text = paragraphs[i].unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let isTooLong = text.count > 100
                        let hasSentenceBreak = text.range(of: #"(?:[。！？]|[.!?]\s+)\s*\p{L}{2}"#, options: .regularExpression) != nil
                        let isReferencePattern = text.range(of: "^\\[\\d+\\]", options: .regularExpression) != nil
                        let isURL = text.lowercased().contains("http") || text.lowercased().contains("www.")
                        if isTooLong || hasSentenceBreak || isReferencePattern || isURL {
                            // 例外保留真正的 Chapter 或報告標題
                            let isMainChapter = text.range(of: "^第[一二三四五六七八九十百千萬萬0-9\\s]+[章部節节講讲篇卷回]|^chapter\\s+\\d+|^part\\s+\\d+|^[壹貳參肆伍陸柒捌玖拾]+\\s*[、\\.]", options: [.regularExpression, .caseInsensitive]) != nil && text.count < 60
                            let isSubHeading = text.range(of: "^[一二三四五六七八九十]+\\s*[、\\.\\s]|^[0-9]+\\.\\d+|^[0-9]+\\s*[、\\.]", options: [.regularExpression, .caseInsensitive]) != nil && text.count < 60
                            
                            if !isMainChapter && !isSubHeading {
                                paragraphs[i].role = .body
                            }
                        }
                    }
                }
                
                
                // 📊 日誌輸出
                let roleBreakdown = Dictionary(grouping: paragraphs, by: { $0.role })
                    .mapValues { $0.count }
                    .map { "\($0.key.rawValue):\($0.value)" }
                    .joined(separator: ", ")
                print("🏠 第 \(pageIndex + 1) 頁 分類: \(paragraphs.count) 段落 [​\(roleBreakdown)]")
                
                // Cross-page continuation removed: To be implemented in KMP Shared Module
                
                // ═══════════════════════════════════════════
                // STAGE 6: 組裝 Markdown 與智慧分章
                // ═══════════════════════════════════════════
                
                var pageMD = ""
                var pageNotes = ""
                var rawTextForLLM = ""
                
                // 文字段落 → Markdown
                var unmatchedEntries = entriesByPage[pageIndex] ?? []
                let matchingKeys = unmatchedEntries.isEmpty ? [] : Set(paragraphs.map { Self.outlineHeadingKey($0.unifiedText) })
                for (index, block) in paragraphs.enumerated() {
                    let isLinkedNote = footnotes.notes[index] != nil || footnotes.references[index] != nil
                    let isRepeatedMargin = !block.fragments.isEmpty && block.fragments.allSatisfy {
                        guard let key = Self.marginLineKey(text: $0.text, bounds: $0.bounds, pageHeight: scaledSize.height) else { return false }
                        return repeatedMargins.contains(key)
                    }
                    if !isLinkedNote && (isRepeatedMargin || LayoutEngine.shouldDrop(block: block, pageHeight: scaledSize.height)) { continue }
                    
                    // 📖 擷取文件標題
                    if block.role == .title {
                        let titleText = block.unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if detectedTitle == nil {
                            detectedTitle = titleText
                            continue
                        } else if detectedTitle == titleText {
                            continue
                        }
                    }
                    
                    if block.role == .body, footnotes.notes[index] == nil, languageSample.count < 4_000,
                       block.fragments.allSatisfy({ $0.fontName != nil }) {
                        languageSample += String(block.unifiedText.prefix(4_000 - languageSample.count)) + "\n"
                    }

                    let htmlStr = LayoutEngine.toHTML(
                        block: block,
                        baseFontSize: styleRegistry.bodyFontSize,
                        footnoteID: footnotes.notes[index],
                        footnoteLinks: footnotes.references[index] ?? [:]
                    )
                    if footnotes.notes[index] != nil {
                        pageNotes += htmlStr
                    } else {
                        if !htmlStr.isEmpty, !unmatchedEntries.isEmpty {
                            let key = Self.outlineHeadingKey(block.unifiedText)
                            unmatchedEntries.removeAll { entry in
                                let target = Self.outlineHeadingKey(entry.title)
                                let reachesDestination = entry.verticalOffset.map {
                                    !matchingKeys.contains(target) && block.bounds.midY >= $0 * scale
                                } ?? false
                                guard key == target || reachesDestination else { return false }
                                rawTextForLLM += "<span id=\"\(entry.anchor)\"></span>"
                                return true
                            }
                        }
                        rawTextForLLM += htmlStr
                    }
                }
                
                if !rawTextForLLM.isEmpty {
                    pageMD += rawTextForLLM
                }
                if startsLinkedContents {
                    pageMD += "<!-- PRINTED_CONTENTS -->\n\n"
                }
                
                var startsChapter = false
                // 📖 智慧分章
                if let chapterTitle = chapterStarts[pageIndex] {
                    if pageIndex == 0 {
                        chapterTitles[0] = chapterTitle
                        outlineDepths[0] = outline[pageIndex]?.depth ?? -1
                    } else {
                        fullHTML += chapterNotes + "<!-- CHAPTER_SPLIT -->\n\n"
                        chapterNotes = ""
                        startsChapter = true
                        chapterTitles.append(chapterTitle)
                        outlineDepths.append(outline[pageIndex]?.depth ?? -1)
                    }
                } else if chapterStarts.isEmpty && pageIndex > 0 {
                    if let firstBlock = paragraphs.first(where: { !LayoutEngine.shouldDrop(block: $0, pageHeight: scaledSize.height) }),
                       firstBlock.role == .title || firstBlock.role == .heading {
                        
                        let text = firstBlock.unifiedText.lowercased()
                        let isChapterRegex = text.contains("chapter") || text.range(of: "^第[一二三四五六七八九十百千萬萬0-9\\s]+[章部節节講讲篇卷回]", options: .regularExpression) != nil
                        
                        // 根據嚴格的語意角色來判定是否為章節起點 (避免視覺 isH1 誤導)
                        // 只有當它真正是 .title，或者明確符合章節的正則表達式時，才進行切割
                        if firstBlock.role == .title || isChapterRegex {
                            startsChapter = true
                            fullHTML += chapterNotes + "<!-- CHAPTER_SPLIT -->\n\n"
                            chapterNotes = ""
                        }
                    }
                }
                
                if document.pageCount > 50, chapterStarts.isEmpty,
                   !startsChapter, !pageMD.isEmpty, pageIndex - chapterStartPage >= 25 {
                    fullHTML += chapterNotes + "<!-- CHAPTER_SPLIT -->\n\n"
                    chapterNotes = ""
                    startsChapter = true
                }
                if startsChapter {
                    chapterStartPage = pageIndex
                } else if !pageMD.isEmpty, previousContentPage == pageIndex - 1 {
                    fullHTML += LayoutEngine.pageBreakMarker
                }
                if !pageMD.isEmpty {
                    previousContentPage = pageIndex
                }
                for entry in unmatchedEntries {
                    fullHTML += "<span id=\"\(entry.anchor)\"></span>"
                }
                fullHTML += pageMD + "\n\n"
                chapterNotes += pageNotes
                
                // 🧹 即時釋放記憶體
                rawImage = nil
                cgImg = nil
                
                let currentProgress = Double(pageIndex + 1) / Double(document.pageCount)
                await MainActor.run { self.progress = currentProgress }
                
                await self.activityTracker.update(progress: currentProgress, message: "Processing page \(pageIndex + 1)")
            }
            
            // 🚀 完成所有頁面後，進行智慧路由打包
            
            // 執行跨頁段落無縫續接 (縫合被換頁切斷的句子)
            AppLogger.shared.info("開始執行跨頁段落縫合...")
            fullHTML += chapterNotes
            fullHTML = LayoutEngine.stitchCrossPageParagraphs(html: fullHTML)
            fullHTML = await LayoutEngine.repairWrappedWords(html: fullHTML)
            
            // 📖 決定最終書名：PDF 元資料 → 第一個 .title 區塊 → 預設名稱
            let bookTitle = detectedTitle ?? "Libri-AI_轉譯報告"
            
            // 在 HTML 最前面插入書名標題 (只有一份，不會重複)
            fullHTML = "<h1 class=\"doc-title\">\(EPUBSynthesizer.sanitizeForXML(bookTitle))</h1>\n\n" + fullHTML
            
            // 安全檔名：移除不安全字元
            let safeFileName = EPUBSynthesizer.safeFilename(for: bookTitle)
            let mdURL = exportDir.appendingPathComponent("\(safeFileName).html")
            do {
                // 儲存 HTML 備份
                try fullHTML.write(to: mdURL, atomically: true, encoding: .utf8)
                
                let language = Self.detectLanguage(from: languageSample, minimumConfidence: 0.8)
                    ?? Self.detectLanguage(from: ocrLanguageSample, minimumConfidence: 0.95)
                    ?? .undetermined
                let finalEPUB: URL?
                // 🧠 智慧路由：根據頁數決定合成通道
                if !chapterStarts.isEmpty || document.pageCount > 50 {
                    AppLogger.shared.info("📚 偵測到長篇文件 (\(document.pageCount) 頁)，啟動書籍引擎...")
                    finalEPUB = EPUBSynthesizer.createBookEPUB(
                        title: bookTitle,
                        fullHTML: fullHTML,
                        assetsURL: assetsDir,
                        language: language,
                        chapterTitles: chapterStarts.isEmpty ? nil : chapterTitles,
                        outlineDepths: outline.isEmpty ? nil : outlineDepths,
                        sourceEntries: sourceEntries
                    )
                } else {
                    AppLogger.shared.info("📄 短篇論文模式 (\(document.pageCount) 頁)，啟動標準單頁引擎...")
                    finalEPUB = EPUBSynthesizer.createEPUB(
                        title: bookTitle, html: fullHTML, assetsURL: assetsDir, language: language
                    )
                }
                
                if let epubFile = finalEPUB {
                    AppLogger.shared.info("✅ 成功匯出 EPUB: \(epubFile.lastPathComponent)")
                    await MainActor.run {
                        self.exportedFileURL = epubFile
                        self.isProcessing = false
                    }
                    await self.activityTracker.end(progress: 1.0, message: "Done!")
                } else {
                    AppLogger.shared.error("❌ EPUB 檔案未產生")
                    await MainActor.run { self.isProcessing = false }
                    let currentProg = await MainActor.run { self.progress }
                    await self.activityTracker.end(progress: currentProg, message: "Failed")
                }
            } catch {
                AppLogger.shared.error("❌ 匯出匯出失敗: \(error)")
                await MainActor.run { self.isProcessing = false }
                let currentProg = await MainActor.run { self.progress }
                await self.activityTracker.end(progress: currentProg, message: "Failed")
            }
        }
        await self.currentTask?.value
        
#if os(iOS)
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
#endif
    }
    


    private nonisolated static func detectLanguage(from sample: String, minimumConfidence: Double) -> NLLanguage? {
        guard sample.filter(\.isLetter).count >= 100 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let candidate = recognizer.languageHypotheses(withMaximum: 1).first,
              candidate.value >= minimumConfidence else { return nil }
        return candidate.key
    }

    private nonisolated static func marginLineKey(text: String, bounds: CGRect, pageHeight: CGFloat) -> String? {
        guard pageHeight > 0 else { return nil }
        let atTop = bounds.maxY <= pageHeight * 0.10
        let atBottom = bounds.minY >= pageHeight * 0.90
        guard atTop || atBottom else { return nil }
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.count >= 4, normalized.count <= 100,
              normalized.contains(where: \.isLetter) else { return nil }
        let position = Int((bounds.midY / pageHeight * 100).rounded())
        return "\(position)|\(normalized)"
    }

    private nonisolated static func repeatedMarginLines(in document: PDFDocument) -> Set<String> {
        var occurrences: [String: Set<Int>] = [:]
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBounds = page.bounds(for: .cropBox)
            for line in page.selection(for: pageBounds)?.selectionsByLine() ?? [] {
                guard let text = line.string else { continue }
                let source = line.bounds(for: page)
                // Match the display coordinates used by the extraction pipeline.
                let bounds = CGRect(x: source.minX, y: pageBounds.height - source.maxY,
                                    width: source.width, height: source.height)
                if let key = marginLineKey(text: text, bounds: bounds, pageHeight: pageBounds.height) {
                    occurrences[key, default: []].insert(pageIndex)
                }
            }
        }
        return Set(occurrences.filter { $0.value.count >= 3 }.map(\.key))
    }

    private nonisolated static func outlineHeadingKey(_ text: String) -> String {
        let title = text.replacingOccurrences(
            of: #"^\s*(?:[0-9]+(?:[.．][0-9]+)*[.．]?|[A-Z][.．]?)\s+"#,
            with: "", options: .regularExpression
        )
        return PDFPrintedOutline.outlineKey(title)
    }

    private nonisolated static func sourceOutline(in document: PDFDocument) -> [PDFPrintedOutline.LocatedEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [PDFPrintedOutline.LocatedEntry] = []

        func visit(_ parent: PDFOutline, depth: Int) {
            for index in 0..<parent.numberOfChildren {
                guard let entry = parent.child(at: index) else { continue }
                var childDepth = depth
                let destination = entry.destination ?? (entry.action as? PDFActionGoTo)?.destination
                if let destination, let page = destination.page,
                   let title = entry.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    let pageIndex = document.index(for: page)
                    if (0..<document.pageCount).contains(pageIndex) {
                        let bounds = page.bounds(for: .cropBox)
                        let y = bounds.maxY - destination.point.y
                        let offset = page.rotation == 0 && (0...bounds.height).contains(y) ? y : nil
                        entries.append(.init(title: title, page: pageIndex, depth: depth,
                                             anchor: "pdf-contents-\(entries.count + 1)", verticalOffset: offset))
                        childDepth += 1
                    }
                }
                visit(entry, depth: childDepth)
            }
        }

        visit(root, depth: 0)
        return entries
    }

    private nonisolated static func linkedContents(
        in document: PDFDocument, destinations: Set<Int>
    ) -> (page: Int, verticalOffset: CGFloat, continuations: Set<Int>)? {
        guard !destinations.isEmpty else { return nil }
        let labels = ["tableofcontents", "contents", "目錄", "目次"]
        let pageLimit = min(document.pageCount, 20)

        func links(on page: PDFPage, below y: CGFloat) -> Int {
            page.annotations.filter { annotation in
                guard annotation.bounds.midY < y,
                      let target = (annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination)?.page
                else { return false }
                return destinations.contains(document.index(for: target))
            }.count
        }

        for index in 0..<pageLimit {
            guard !destinations.contains(index), let page = document.page(at: index), page.rotation == 0,
                  (page.string ?? "").split(whereSeparator: \.isNewline).contains(where: {
                      labels.contains(PDFPrintedOutline.outlineKey(String($0)).lowercased())
                  }) else { continue }
            let bounds = page.bounds(for: .cropBox)
            guard let heading = PDFTextLines.selections(in: page, bounds: bounds).first(where: {
                labels.contains(PDFPrintedOutline.outlineKey($0.string ?? "").lowercased())
            }) else { continue }
            let headingY = heading.bounds(for: page).maxY
            guard links(on: page, below: headingY) >= 3 else { continue }

            var continuations = Set<Int>()
            for next in (index + 1)..<pageLimit {
                guard !destinations.contains(next), let following = document.page(at: next),
                      links(on: following, below: .greatestFiniteMagnitude) >= 3 else { break }
                continuations.insert(next)
            }
            return (index, bounds.maxY - headingY, continuations)
        }
        return nil
    }

    private nonisolated static func printedContentsPages(
        in document: PDFDocument, chapterStarts: [Int: String]
    ) -> Set<Int> {
        guard let firstChapter = chapterStarts.keys.min(), chapterStarts.count >= 3 else { return [] }
        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let entries = chapterStarts.values.compactMap { title -> String? in
            let fields = title.split(separator: ":", maxSplits: 1)
            guard fields.count == 2,
                  let number = fields[0].split(separator: " ").last else { return nil }
            return String(number) + normalized(String(fields[1]))
        }
        var result: Set<Int> = []
        for index in 0..<firstChapter {
            guard let text = document.page(at: index)?.string, text.count <= 3000 else { continue }
            let key = normalized(text)
            // A contents page has several numbered chapter titles followed by printed folios.
            let matches = entries.filter { entry in
                guard let range = key.range(of: entry), range.upperBound < key.endIndex else { return false }
                return key[range.upperBound].isNumber
            }
            if matches.count >= 3 { result.insert(index) }
        }
        return result
    }

    /// Recognize a complete sequence of chapter-opening labels before trusting page breaks.
    private nonisolated static func numberedChapterStarts(in document: PDFDocument) -> [Int: String] {
        guard document.pageCount > 1 else { return [:] }
        let marker = try! NSRegularExpression(
            pattern: #"^C\h*H\h*A\h*P\h*T\h*E\h*R\h+([0-9](?:\h*[0-9]){0,2})$"#,
            options: .caseInsensitive
        )
        var starts: [Int: String] = [:]

        for pageIndex in 0..<document.pageCount {
            if Task.isCancelled { return [:] }
            guard let pageText = document.page(at: pageIndex)?.string else { continue }
            let lines = pageText.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let first = lines.first,
                  let match = marker.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)),
                  let numberRange = Range(match.range(at: 1), in: first),
                  let number = Int(first[numberRange].filter(\.isNumber)) else { continue }

            guard number == starts.count + 1 else { return [:] }

            // Publisher chapter openers can spread the title over several uppercase lines.
            var title = ""
            for line in lines.dropFirst().prefix(6) {
                guard line.contains(where: \.isUppercase),
                      !line.contains(where: \.isLowercase) else { break }
                if !title.isEmpty && !title.hasSuffix("-") && !title.hasSuffix("—") {
                    title += " "
                }
                title += line
            }
            starts[pageIndex] = title.isEmpty ? "Chapter \(number)" : "Chapter \(number): \(title)"
        }

        return starts.count >= 2 ? starts : [:]
    }

    // MARK: - 圖片裁切工具
    
    final class PDFImageExtractor: Sendable {
        
        /// 直接從全頁圖片中裁切出指定區域並儲存為 JPEG
        nonisolated static func cropAndSaveImage(from sourceImage: AppImage, cropRect: CGRect, imageName: String, assetsURL: URL) -> String? {
            
            // 1. 取出底層的高畫質 CGImage
            guard let cgImage = sourceImage.cgImage else { return nil }
            
            // 2. ✂️ 直接拿 YOLO 算好的絕對座標來切 (毫秒級運算)
            let pixelRect = cropRect.applying(CGAffineTransform(
                scaleX: CGFloat(cgImage.width) / sourceImage.size.width,
                y: CGFloat(cgImage.height) / sourceImage.size.height
            )).integral
            guard let croppedCGImage = cgImage.cropping(to: pixelRect) else { return nil }
            
            // 3. 轉回 AppImage 並準備存檔
            let finalImage = AppImage(cgImage: croppedCGImage, size: cropRect.size)
            guard let imageData = finalImage.appJPEGData(compressionQuality: 0.85) else { return nil }
            
            let fileURL = assetsURL.appendingPathComponent("\(imageName).jpg")
            
            do {
                try imageData.write(to: fileURL)
                return "![圖表/圖片：\(imageName)](assets/\(imageName).jpg)"
            } catch {
                AppLogger.shared.error("❌ 圖片存檔失敗: \(error)")
                return nil
            }
        }
    }
}

extension AppColor {
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        #if os(iOS)
        self.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif os(macOS)
        if let rgbColor = self.usingColorSpace(.deviceRGB) {
            rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        #endif
        let rgb: Int = (Int)(r*255)<<16 | (Int)(g*255)<<8 | (Int)(b*255)<<0
        return String(format: "#%06x", rgb)
    }
}

