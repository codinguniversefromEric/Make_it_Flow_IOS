with open("Flow_1/Core/BatchProcessor.swift", "r") as f:
    content = f.read()

old_code = """                // Semantic classification is now handled directly via LayoutEngine mapping from D4LA labels"""

new_code = """                // Semantic classification is now handled directly via LayoutEngine mapping from D4LA labels
                
                // 🛡️ 啟發式標題升級 (Heading Promotion)：修復 YOLO 遺漏標題導致的 TOC 斷層
                for i in 0..<paragraphs.count {
                    if paragraphs[i].role == .body {
                        let text = paragraphs[i].unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let firstFragSize = paragraphs[i].fragments.first?.fontSize ?? 12.0
                        
                        let isChapter = text.lowercased().hasPrefix("chapter") || (text.contains("第") && text.contains("章"))
                        let isLargeFont = firstFragSize >= styleRegistry.h1FontSize * 0.85
                        let isMediumFont = firstFragSize >= styleRegistry.h2FontSize * 0.85
                        
                        if isChapter || isLargeFont {
                            paragraphs[i].role = .title
                        } else if isMediumFont && text.count < 60 { // H2 不能太長
                            paragraphs[i].role = .heading
                        }
                    }
                }"""

content = content.replace(old_code, new_code)
with open("Flow_1/Core/BatchProcessor.swift", "w") as f:
    f.write(content)
