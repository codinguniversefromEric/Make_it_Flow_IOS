//
//  DebugPageView.swift
//  Flow_1
//
//  Created by 魏嘉賢 on 2026/6/13.
//  Rewritten to reuse shared LayoutEngine/SemanticClassifier on 2026/6/14.
//

import SwiftUI
import PDFKit
import Vision

// 頁面顯示與除錯主畫面
struct DebugPageView: View {
    let document: PDFDocument
    let pageIndex: Int
    @State private var pageImage: UIImage? = nil
    @State private var extractedMarkdown: String = "等待 AI 解析與文字萃取..."
    
    var body: some View {
        VStack(spacing: 0) {
            if let image = pageImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
                    .padding()
                    .accessibilityLabel("Debug visualization for page \(pageIndex + 1)")
            } else {
                VStack {
                    ProgressView()
                    Text("AI 模型通靈第 \(pageIndex + 1) 頁中...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.75, contentMode: .fit)
                .background(Color.gray.opacity(0.05))
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading page \(pageIndex + 1)")
                .accessibilityAddTraits(.updatesFrequently)
            }
            
            VStack(alignment: .leading) {
                Text("📝 Markdown 萃取結果")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding(.bottom, 4)
                
                ScrollView {
                    Text(extractedMarkdown)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .frame(height: 250)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .task {
            let result = await renderPageWithAIAttention()
            self.pageImage = result.0
            self.extractedMarkdown = result.1
        }
    }
    
    // MARK: - 核心處理
    
    // 核心：使用 AI 進行版面分析並回傳渲染圖片與 Markdown
    private func renderPageWithAIAttention() async -> (UIImage?, String) {
        guard let page = document.page(at: pageIndex) else { return (nil, "載入頁面失敗") }
        
        return await Task.detached(priority: .utility) { () -> (UIImage?, String) in
            let pageBounds = page.bounds(for: .cropBox)
            let scale: CGFloat = 2.0
            let scaledSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
            
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            
            let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
            let rawImage = renderer.image { ctx in
                let context = ctx.cgContext
                UIColor.white.set()
                context.fill(CGRect(origin: .zero, size: scaledSize))
                context.saveGState()
                context.translateBy(x: 0, y: scaledSize.height)
                context.scaleBy(x: scale, y: -scale)
                page.draw(with: .cropBox, to: context)
                context.restoreGState()
            }
            guard let cgImage = rawImage.cgImage else { return (nil, "圖片生成失敗") }
            
            // ═══════════════════════════════════════
            // YOLO 偵測
            // ═══════════════════════════════════════
            
            let rawObservations = await LayoutVisionManager.shared.detectLayout(in: cgImage)
            
            // NMS 過濾 (使用共用 NMSUtils)
            let sortedObs = rawObservations.sorted { $0.confidence > $1.confidence }
            var filteredObservations: [LayoutBlock] = []
            for obs in sortedObs {
                var keep = true
                let cRect = obs.boundingBox
                for kObs in filteredObservations {
                    let kRect = kObs.boundingBox
                    if NMSUtils.calcIoU(cRect, kRect) > 0.4 || NMSUtils.calcCoverage(cRect, kRect) > 0.8 {
                        keep = false; break
                    }
                }
                if keep { filteredObservations.append(obs) }
            }
            
            // 轉換為顯示座標
            struct DebugBlock {
                let label: String
                let rect: CGRect
                let confidence: Float
            }
            
            let debugBlocks: [DebugBlock] = filteredObservations.map { obs in
                let visionRect = obs.boundingBox
                let convertedRect = VNImageRectForNormalizedRect(visionRect, Int(scaledSize.width), Int(scaledSize.height))
                let drawRect = CGRect(
                    x: convertedRect.minX,
                    y: scaledSize.height - convertedRect.maxY,
                    width: convertedRect.width,
                    height: convertedRect.height
                )
                return DebugBlock(
                    label: obs.label,
                    rect: drawRect,
                    confidence: obs.confidence
                )
            }
            
            // ═══════════════════════════════════════
            // PDFKit 文字萃取 → TextFragment
            // ═══════════════════════════════════════
            
            var textFragments: [TextFragment] = []
            
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
                    
                    textFragments.append(TextFragment(
                        text: lineText,
                        bounds: displayRect,
                        fontSize: fontSize * scale,
                        fontName: fontName,
                        isBold: isBold,
                        isItalic: isItalic,
                        colorHex: colorHex
                    ))
                }
            }
            
            // ═══════════════════════════════════════
            // LayoutEngine → 欄位偵測 + 段落重組
            // ═══════════════════════════════════════
            
            var paragraphs = LayoutEngine.processWithLayoutBlocks(
                fragments: textFragments,
                blocks: filteredObservations,
                pageWidth: scaledSize.width,
                pageHeight: scaledSize.height
            )
            
            // ═══════════════════════════════════════
            // 繪製除錯視覺化圖層
            // ═══════════════════════════════════════
            
            let finalImage = renderer.image { ctx in
                let context = ctx.cgContext
                rawImage.draw(at: .zero)
                
                // 繪製 YOLO 偵測框
                for (index, block) in debugBlocks.enumerated() {
                    let blockColor = getColor(for: block.label)
                    
                    context.setFillColor(blockColor.withAlphaComponent(0.15).cgColor)
                    context.fill(block.rect)
                    context.setStrokeColor(blockColor.cgColor)
                    context.setLineWidth(2.0)
                    context.stroke(block.rect)
                    
                    let textAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 14, weight: .black),
                        .foregroundColor: UIColor.white,
                        .backgroundColor: blockColor.withAlphaComponent(0.9)
                    ]
                    let labelString = NSAttributedString(string: " \(index + 1). \(block.label) ", attributes: textAttributes)
                    let textPoint = CGPoint(x: block.rect.minX, y: max(0, block.rect.minY - 20))
                    
                    UIGraphicsPushContext(context)
                    labelString.draw(at: textPoint)
                    UIGraphicsPopContext()
                }
                
                // 繪製語意分類段落框 (半透明藍色)
                for para in paragraphs {
                    let roleColor = getRoleColor(for: para.role)
                    context.setStrokeColor(roleColor.withAlphaComponent(0.5).cgColor)
                    context.setLineWidth(1.0)
                    context.setLineDash(phase: 0, lengths: [4, 4])
                    context.stroke(para.bounds)
                    context.setLineDash(phase: 0, lengths: [])
                }
            }
            
            // ═══════════════════════════════════════
            // 組裝 Markdown 輸出
            // ═══════════════════════════════════════
            
            var markdownOutput = ""
            
            // YOLO 視覺區域
            for block in debugBlocks {
                if block.label == "Picture" || block.label == "Figure" {
                    markdownOutput += "![圖片/圖表]() (conf: \(String(format: "%.2f", block.confidence)))\n\n"
                } else if block.label == "Table" {
                    markdownOutput += "> [表格區塊] (conf: \(String(format: "%.2f", block.confidence)))\n\n"
                } else if block.label == "Formula" {
                    markdownOutput += "$$ [公式] $$ (conf: \(String(format: "%.2f", block.confidence)))\n\n"
                }
            }
            
            // 語意分類段落
            for para in paragraphs {
                if LayoutEngine.shouldDrop(para.role) {
                    markdownOutput += "~~[\(para.role.rawValue)] \(para.unifiedText.prefix(40))...~~ (已丟棄)\n\n"
                } else {
                    markdownOutput += LayoutEngine.toHTML(block: para, baseFontSize: 12.0)
                }
            }
            
            return (finalImage, markdownOutput.isEmpty ? "未提取到任何文字" : markdownOutput)
        }.value
    }
    
    // MARK: - 顏色工具
    
    private func getColor(for label: String) -> UIColor {
        switch label {
        case "Section-header": return .systemRed
        case "Text", "Paragraph": return .systemGreen
        case "Table": return .systemPurple
        case "Picture", "Figure": return .systemOrange
        case "Formula": return .systemTeal
        case "List-item": return .systemBlue
        case "Page-header", "Page-footer", "Footnote": return .systemGray
        case "Caption": return .systemYellow
        default: return .systemPink
        }
    }
    
    private func getRoleColor(for role: SemanticRole) -> UIColor {
        switch role {
        case .title: return .systemRed
        case .heading: return .systemOrange
        case .body: return .systemGreen
        case .listItem: return .systemBlue
        case .footnote: return .systemGray
        case .caption: return .systemYellow
        case .formula: return .systemTeal
        case .table, .picture: return .systemPurple
        case .pageHeader, .pageFooter, .pageNumber: return .systemGray
        }
    }
}
