import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

old_shouldDrop = """    nonisolated static func shouldDrop(_ role: SemanticRole) -> Bool {
        return role == .pageHeader || role == .pageFooter
    }"""

new_shouldDrop = """    nonisolated static func shouldDrop(_ role: SemanticRole) -> Bool {
        return role == .pageHeader || role == .pageFooter
    }

    nonisolated static func shouldDrop(block: ParagraphBlock, pageHeight: CGFloat) -> Bool {
        if shouldDrop(block.role) { return true }
        
        // 🚨 安全機制：如果 YOLO 已經明確判定這是標題 (Heading/Title)，絕對不可以使用啟發式規則丟棄！
        if block.role == .heading || block.role == .title { return false }
        
        let text = block.unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isAtTop = block.bounds.minY < pageHeight * 0.15 || block.bounds.maxY < pageHeight * 0.15
        let isAtBottom = block.bounds.minY > pageHeight * 0.85 || block.bounds.maxY > pageHeight * 0.85
        
        if isAtTop || isAtBottom {
            // 特徵 A: 純數字頁碼
            if text.range(of: "^\\\\d+$", options: .regularExpression) != nil {
                return true
            }
            
            // 特徵 B: 帶有特殊分隔符的大寫字母 (如 T H E  B O O K)
            if text.range(of: "(?:[A-Z]\\\\s+){3,}[A-Z]", options: .regularExpression) != nil {
                return true
            }
            
            // 特徵 C: 短字串且包含疑似頁碼的數字結尾/開頭
            if text.count < 80 {
                if text.range(of: "^\\\\d+\\\\s*·?", options: .regularExpression) != nil || 
                   text.range(of: "·?\\\\s*\\\\d+$", options: .regularExpression) != nil {
                    return true
                }
            }
        }
        
        return false
    }"""

content = content.replace(old_shouldDrop, new_shouldDrop)

with open(filepath, "w") as f:
    f.write(content)
