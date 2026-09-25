//
//  BatchProcessor.swift
//  Flow_1
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
                
                // 分離視覺區域 vs 文字區域
                var visualRegions: [VisualRegion] = []
                var textRegionRects: [CGRect] = []
                
                for obs in filteredObs {
                    let label = obs.label
                    let conf = obs.confidence
                    let cRect = VNImageRectForNormalizedRect(obs.boundingBox, Int(scaledSize.width), Int(scaledSize.height))
                    let dRect = CGRect(x: cRect.minX, y: scaledSize.height - cRect.maxY, width: cRect.width, height: cRect.height)
                    
                    if label == "Picture" || label == "Figure" || label == "Formula" || label == "Table" {
                        visualRegions.append(VisualRegion(label: label, rect: dRect, confidence: conf))
                    } else {
                        textRegionRects.append(dRect)
                    }
                }
                
                print("📊 第 \(pageIndex + 1) 頁 YOLO: \(filteredObs.count) 區域 (\(visualRegions.count) 視覺)")
                
                // ═══════════════════════════════════════════
                // STAGE 2: PDFKit 富文字萃取 → TextFragment
                // ═══════════════════════════════════════════
                
                var textFragments: [TextFragment] = []
                var tableFragments: [Int: [TextFragment]] = [:]
                
                if let selection = page.selection(for: pageBounds) {
                    for line in selection.selectionsByLine() {
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
                        
                        if let attrStr = line.attributedString {
                            attrStr.enumerateAttributes(in: NSRange(location: 0, length: attrStr.length)) { attrs, _, _ in
                                if let font = attrs[.font] as? AppFont {
                                    fontSize = font.pointSize
                                    fontName = font.fontName
                                    isBold = font.isAppFontBold
                                    #if os(iOS)
                                    isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                                    #elseif os(macOS)
                                    isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                                    #endif
                                }
                                if let color = attrs[.foregroundColor] as? AppColor {
                                    colorHex = color.hexString
                                }
                            }
                        }
                        
                        let fragment = TextFragment(
                            text: lineText,
                            bounds: displayRect,
                            fontSize: fontSize * scale,
                            fontName: fontName,
                            isBold: isBold,
                            isItalic: isItalic,
                            colorHex: colorHex
                        )
                        
                        // 🔍 排除落在視覺區域 (圖片/表格/公式) 內的文字行，但保留表格內的碎片用於結構重建
                        var handledByVisualRegion = false
                        let lineArea = displayRect.width * displayRect.height
                        
                        for (index, region) in visualRegions.enumerated() {
                            let intersection = region.rect.intersection(displayRect)
                            if !intersection.isNull {
                                let intersectionArea = intersection.width * intersection.height
                                let ratio = lineArea > 0 ? intersectionArea / lineArea : 0
                                let expandedRegion = region.rect.insetBy(dx: -5, dy: -5)
                                let lineMid = CGPoint(x: displayRect.midX, y: displayRect.midY)
                                
                                if region.label == "Table" {
                                    // 表格：40% 重疊就排除，但保存碎片用於結構重建
                                    if ratio > 0.4 || expandedRegion.contains(lineMid) {
                                        tableFragments[index, default: []].append(fragment)
                                        handledByVisualRegion = true
                                        break
                                    }
                                } else if region.label == "Picture" || region.label == "Figure" || region.label == "Formula" {
                                    // 圖片/公式：90% 重疊才排除，保守策略以保留 caption
                                    if ratio > 0.90 {
                                        handledByVisualRegion = true
                                        break
                                    }
                                }
                            }
                        }
                        if handledByVisualRegion { continue }
                        
                        textFragments.append(fragment)
                    }
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
                textFragments = dedupedFragments
                
                // OCR Fallback and extra logics removed for YOLO 99% accuracy transition
                
                // ═══════════════════════════════════════════
                // STAGE 2.6: 視覺區塊實體擷取 (Formula, Picture, Figure)
                // ═══════════════════════════════════════════
                
                for (index, region) in visualRegions.enumerated() {
                    if region.label == "Formula" || region.label == "Picture" || region.label == "Figure" || region.label == "Table" {
                        AppLogger.shared.info("🖼️ 擷取視覺區塊 (\(region.label))...")
                        let fileName = "\(region.label.lowercased())_p\(pageIndex + 1)_\(index)"
                        
                        if let _ = PDFImageExtractor.cropAndSaveImage(from: validRawImage, cropRect: region.rect, imageName: fileName, assetsURL: assetsDir) {
                            let prefix = region.label == "Table" ? "表格" : "圖表/圖片"
                            let imgHTML = "<img src=\"assets/\(fileName).jpg\" alt=\"\(prefix)：\(fileName)\" />"
                            let mdText = region.label == "Formula" ? "<div class=\"doc-formula\">\(imgHTML)</div>" : imgHTML
                            
                            let fragment = TextFragment(
                                text: mdText,
                                bounds: region.rect,
                                fontSize: 12.0 * scale,
                                fontName: nil,
                                isBold: false,
                                isItalic: false,
                                colorHex: "#000000"
                            )
                            textFragments.append(fragment)
                        }
                    }
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
                
                // Semantic classification is now handled directly via LayoutEngine mapping from D4LA labels
                
                // 🛡️ 啟發式標題升級 (Heading Promotion) V2：極簡安全版
                for i in 0..<paragraphs.count {
                    if paragraphs[i].role == .body {
                        let text = paragraphs[i].unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // [V2 Patch] 升級為嚴格正則表達式，避免長篇內文剛好包含「第」和「章」就被誤判
                        let isChapter = text.range(of: "^第[一二三四五六七八九十百千萬萬0-9\\s]+章|^chapter\\s+\\d+", options: [.regularExpression, .caseInsensitive]) != nil && text.count < 60
                        
                        if isChapter {
                            paragraphs[i].role = .title
                        }
                    }
                }
                
                // 🛡️ 啟發式標題降級 (Heading Downgrade)：修正 YOLO 錯誤將內文分類為標題
                for i in 0..<paragraphs.count {
                    let role = paragraphs[i].role
                    if role == .heading || role == .title {
                        let text = paragraphs[i].unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let isTooLong = text.count > 100
                        
                        // 避免將 "1.1" 這種合法的標題結尾點誤判，加上長度 > 15 的限制
                        let endsWithPunctuation = text.range(of: "[.!?。！？]$", options: .regularExpression) != nil && text.count > 15
                        
                        // 計算句子數量 (依據句號出現次數)
                        let sentenceCount = text.components(separatedBy: ".").count - 1 +
                                            text.components(separatedBy: "。").count - 1
                        let isMultiSentence = sentenceCount >= 2
                        
                        if isTooLong || endsWithPunctuation || isMultiSentence {
                            // 例外保留真正的 Chapter 標題
                            let isChapter = text.range(of: "^第[一二三四五六七八九十百千萬萬0-9\\s]+章|^chapter\\s+\\d+", options: [.regularExpression, .caseInsensitive]) != nil && text.count < 60
                            if !isChapter {
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
                var rawTextForLLM = ""
                
                // 文字段落 → Markdown
                for block in paragraphs {
                    if LayoutEngine.shouldDrop(block: block, pageHeight: scaledSize.height) { continue }
                    
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
                    
                    let htmlStr = LayoutEngine.toHTML(block: block, baseFontSize: styleRegistry.bodyFontSize)
                    if !htmlStr.isEmpty {
                        rawTextForLLM += htmlStr
                    }
                }
                
                if !rawTextForLLM.isEmpty {
                    pageMD += rawTextForLLM
                }
                
                // 📖 智慧分章
                if pageIndex > 0 {
                    if let firstBlock = paragraphs.first(where: { !LayoutEngine.shouldDrop(block: $0, pageHeight: scaledSize.height) }),
                       firstBlock.role == .title || firstBlock.role == .heading {
                        
                        let text = firstBlock.unifiedText.lowercased()
                        let isChapterRegex = text.contains("chapter") || text.contains("第")
                        let isH1 = (firstBlock.fragments.first?.fontSize ?? 0) >= styleRegistry.h1FontSize * 0.95
                        
                        // 根據角色、正規表示式、或字體大小判定是否為章節起點
                        if firstBlock.role == .title || isChapterRegex || isH1 {
                            fullHTML += "<!-- CHAPTER_SPLIT -->\n\n"
                        }
                    }
                }
                
                fullHTML += pageMD + "\n\n"
                
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
            fullHTML = LayoutEngine.stitchCrossPageParagraphs(html: fullHTML)
            
            // 📖 決定最終書名：PDF 元資料 → 第一個 .title 區塊 → 預設名稱
            let bookTitle = detectedTitle ?? "Libri-AI_轉譯報告"
            
            // 在 HTML 最前面插入書名標題 (只有一份，不會重複)
            fullHTML = "<h1 class=\"doc-title\">\(bookTitle)</h1>\n\n" + fullHTML
            
            // 安全檔名：移除不安全字元
            let safeFileName = bookTitle.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .prefix(80)
            let mdURL = exportDir.appendingPathComponent("\(safeFileName).html")
            do {
                // 儲存 HTML 備份
                try fullHTML.write(to: mdURL, atomically: true, encoding: .utf8)
                
                let finalEPUB: URL?
                // 🧠 智慧路由：根據頁數決定合成通道
                if document.pageCount > 50 {
                    AppLogger.shared.info("📚 偵測到長篇文件 (\(document.pageCount) 頁)，啟動書籍引擎...")
                    finalEPUB = EPUBSynthesizer.createBookEPUB(title: bookTitle, fullHTML: fullHTML, assetsURL: assetsDir)
                } else {
                    AppLogger.shared.info("📄 短篇論文模式 (\(document.pageCount) 頁)，啟動標準單頁引擎...")
                    finalEPUB = EPUBSynthesizer.createEPUB(title: bookTitle, html: fullHTML, assetsURL: assetsDir)
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
    


    // MARK: - 圖片裁切工具
    
    final class PDFImageExtractor: Sendable {
        
        /// 直接從全頁圖片中裁切出指定區域並儲存為 JPEG
        nonisolated static func cropAndSaveImage(from sourceImage: AppImage, cropRect: CGRect, imageName: String, assetsURL: URL) -> String? {
            
            // 1. 取出底層的高畫質 CGImage
            guard let cgImage = sourceImage.cgImage else { return nil }
            
            // 2. ✂️ 直接拿 YOLO 算好的絕對座標來切 (毫秒級運算)
            guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
            
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

