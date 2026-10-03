import SwiftUI
import PDFKit
import Vision

struct DebugPageView: View {
    let document: PDFDocument
    @State var pageIndex: Int
    @Environment(\.presentationMode) var presentationMode
    
    // Toggles
    @State private var showYolo = true
    @State private var showText = true
    @State private var showParagraphs = true
    @State private var showOrder = true
    
    // Zoom/Pan
    @State private var scale: CGFloat = 1.0
    
    // Data
    @State private var isLoading = true
    @State private var image: UIImage? = nil
    @State private var yoloBlocks: [DebugBlock] = []
    @State private var textFragments: [TextFragment] = []
    @State private var paragraphs: [ParagraphWrapper] = [] // using a wrapper to avoid type issues if name differs
    
    struct DebugBlock: Identifiable {
        let id = UUID()
        let label: String
        let rect: CGRect
        let confidence: Float
    }
    
    // Wrapper for whatever type LayoutEngine returns
    struct ParagraphWrapper: Identifiable {
        let id = UUID()
        let bounds: CGRect
        let roleName: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            HStack {
                Button(action: {
                    if pageIndex > 0 {
                        pageIndex -= 1
                        loadData()
                    }
                }) {
                    Text("PREV")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(pageIndex > 0 ? .primary : .gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .border(pageIndex > 0 ? Color.primary : Color.gray, width: 2)
                }
                .disabled(pageIndex == 0)
                
                Spacer()
                
                Text("PAGE \(pageIndex + 1) / \(document.pageCount)")
                    .font(.custom("Times New Roman", size: 16))
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    if pageIndex < document.pageCount - 1 {
                        pageIndex += 1
                        loadData()
                    }
                }) {
                    Text("NEXT")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(pageIndex < document.pageCount - 1 ? .primary : .gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .border(pageIndex < document.pageCount - 1 ? Color.primary : Color.gray, width: 2)
                }
                .disabled(pageIndex >= document.pageCount - 1)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .border(Color.primary, width: 3)
            .padding(.bottom, 8)
            .zIndex(1)
            
            // Canvas View
            GeometryReader { geo in
                ZStack {
                    Color(UIColor.systemGray5)
                    
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("ANALYZING PAGE \(pageIndex + 1)...")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                    } else if let img = image {
                        ScrollView([.horizontal, .vertical], showsIndicators: false) {
                            let renderScale = (geo.size.width * scale) / img.size.width
                            
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geo.size.width * scale)
                                    .border(Color.primary, width: 2)
                                
                                // Text Fragments
                                if showText {
                                    ForEach(0..<textFragments.count, id: \.self) { i in
                                        let frag = textFragments[i]
                                        Rectangle()
                                            .fill(Color.green.opacity(0.3))
                                            .frame(width: frag.bounds.width * renderScale, height: frag.bounds.height * renderScale)
                                            .offset(x: frag.bounds.minX * renderScale, y: frag.bounds.minY * renderScale)
                                    }
                                }
                                
                                // YOLO Blocks
                                if showYolo {
                                    ForEach(yoloBlocks) { block in
                                        let bColor = getColor(for: block.label)
                                        Rectangle()
                                            .fill(bColor.opacity(0.15))
                                            .border(bColor, width: 3)
                                            .frame(width: block.rect.width * renderScale, height: block.rect.height * renderScale)
                                            .offset(x: block.rect.minX * renderScale, y: block.rect.minY * renderScale)
                                    }
                                }
                                
                                // Paragraphs & Badges
                                ForEach(0..<paragraphs.count, id: \.self) { index in
                                    let para = paragraphs[index]
                                    
                                    if showParagraphs {
                                        Rectangle()
                                            .fill(Color.blue.opacity(0.1))
                                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                            .foregroundColor(.blue)
                                            .frame(width: para.bounds.width * renderScale, height: para.bounds.height * renderScale)
                                            .offset(x: para.bounds.minX * renderScale, y: para.bounds.minY * renderScale)
                                    }
                                    
                                    if showOrder || showYolo {
                                        let badgeText = getBadgeText(index: index, para: para)
                                        
                                        if !badgeText.isEmpty {
                                            Text(badgeText)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(showOrder ? Color.blue : Color.red)
                                                .cornerRadius(4)
                                                .offset(
                                                    x: (para.bounds.maxX * renderScale) - 100, // Approximate offset to top right
                                                    y: para.bounds.minY * renderScale
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .clipped()
            
            // Toggles
            HStack(spacing: 0) {
                toggleItem("YOLO", checked: $showYolo)
                toggleItem("TEXT", checked: $showText)
                toggleItem("PARAGRAPHS", checked: $showParagraphs)
                toggleItem("ORDER", checked: $showOrder)
            }
            .padding(.vertical, 16)
            .background(Color(UIColor.systemBackground))
            .border(Color.primary, width: 3)
            
            // Zoom Controls
            HStack(spacing: 16) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Text("CLOSE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .border(Color.primary, width: 3)
                }
                
                Spacer()
                
                Button(action: { scale = max(1.0, scale - 0.5) }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .padding(12)
                        .border(Color.primary, width: 3)
                }
                
                Button(action: { scale = min(4.0, scale + 0.5) }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .padding(12)
                        .border(Color.primary, width: 3)
                }
            }
            .padding(16)
            .background(Color(UIColor.systemBackground))
        }
        .navigationBarHidden(true)
        .onAppear {
            loadData()
        }
    }
    
    private func toggleItem(_ label: String, checked: Binding<Bool>) -> some View {
        Button(action: { checked.wrappedValue.toggle() }) {
            VStack(spacing: 4) {
                Image(systemName: checked.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundColor(.primary)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func loadData() {
        isLoading = true
        Task {
            let (img, yolo, texts, paras) = await processPage()
            DispatchQueue.main.async {
                self.image = img
                self.yoloBlocks = yolo
                self.textFragments = texts
                self.paragraphs = paras
                self.isLoading = false
            }
        }
    }
    
    private func getBadgeText(index: Int, para: ParagraphWrapper) -> String {
        var labelPart = para.roleName
        var confPart = ""
        
        var maxIntersection: CGFloat = 0
        var matchedYolo: DebugBlock? = nil
        
        for block in yoloBlocks {
            let intersection = block.rect.intersection(para.bounds)
            let area = intersection.width * intersection.height
            if area > maxIntersection {
                maxIntersection = area
                matchedYolo = block
            }
        }
        
        if let matched = matchedYolo, maxIntersection > 0 {
            labelPart = matched.label
            confPart = String(format: " (%.2f)", matched.confidence)
        }
        
        if showOrder && showYolo {
            return "\(index + 1) | \(labelPart)\(confPart)"
        } else if showOrder {
            return "\(index + 1)"
        } else if showYolo {
            return "\(labelPart)\(confPart)"
        }
        return ""
    }
    
    private func processPage() async -> (UIImage?, [DebugBlock], [TextFragment], [ParagraphWrapper]) {
        guard let page = document.page(at: pageIndex) else { return (nil, [], [], []) }
        
        return await Task.detached(priority: .utility) {
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
            guard let cgImage = rawImage.cgImage else { return (nil, [], [], []) }
            
            // YOLO
            let rawObservations = await LayoutVisionManager.shared.detectLayout(in: cgImage)
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
            
            let debugBlocks: [DebugBlock] = filteredObservations.map { obs in
                let visionRect = obs.boundingBox
                let convertedRect = VNImageRectForNormalizedRect(visionRect, Int(scaledSize.width), Int(scaledSize.height))
                let drawRect = CGRect(
                    x: convertedRect.minX,
                    y: scaledSize.height - convertedRect.maxY,
                    width: convertedRect.width,
                    height: convertedRect.height
                )
                return DebugBlock(label: obs.label, rect: drawRect, confidence: obs.confidence)
            }
            
            // Text Extraction
            var fragments: [TextFragment] = []
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
                    
                    fragments.append(TextFragment(
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
            
            // Engine
            let engineParas = LayoutEngine.processWithLayoutBlocks(
                fragments: fragments,
                blocks: filteredObservations,
                pageWidth: scaledSize.width,
                pageHeight: scaledSize.height
            )
            
            let paras: [ParagraphWrapper] = engineParas.map {
                ParagraphWrapper(bounds: $0.bounds, roleName: $0.role.rawValue)
            }
            
            return (rawImage, debugBlocks, fragments, paras)
        }.value
    }
    
    private func getColor(for label: String) -> Color {
        switch label {
        case "Picture", "Figure": return Color(hex: "E91E63") // Pink
        case "Table": return Color(hex: "9C27B0") // Purple
        case "Formula": return Color(hex: "3F51B5") // Indigo
        case "Text", "Paragraph": return Color(hex: "4CAF50") // Green
        case "Title", "Section-header": return Color(hex: "FF9800") // Orange
        case "List-item": return Color(hex: "00BCD4") // Cyan
        default: return Color.gray
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
