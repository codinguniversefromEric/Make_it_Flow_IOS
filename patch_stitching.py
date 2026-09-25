import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

stitching_code = """
    // MARK: - 跨頁段落縫合 (Cross-Page Stitching)
    
    /// 基於啟發式法則 (標點符號與大小寫) 自動縫合因 PDF 換頁而被強制截斷的段落
    nonisolated static func stitchCrossPageParagraphs(html: String) -> String {
        let pattern = "([^.!?:;。！？：；>\\\\”\\\\\"\\\\''])\\\\s*</span>\\\\s*</p>\\\\s*<p class=\\\\\"doc-body\\\\\">\\\\s*(<span[^>]*>\\\\s*[a-z0-9\\\\p{Han}])"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }
        
        var result = html
        var previous = ""
        
        while result != previous {
            previous = result
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "$1 $2" 
            )
        }
        
        return result
    }
}
"""
content = re.sub(r'\}$', stitching_code, content.strip())

with open(filepath, "w") as f:
    f.write(content)

filepath = "Flow_1/Core/BatchProcessor.swift"
with open(filepath, "r") as f:
    content = f.read()

content = content.replace("            // --- EPUB 合成 ---", """            // --- 跨頁縫合 ---
            AppLogger.shared.info("🟢 [INFO] 開始執行跨頁段落縫合...")
            fullHTML = LayoutEngine.stitchCrossPageParagraphs(html: fullHTML)
            
            // --- EPUB 合成 ---""")

with open(filepath, "w") as f:
    f.write(content)

