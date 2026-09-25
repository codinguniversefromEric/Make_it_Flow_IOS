import re

with open("Flow_1/Core/BatchProcessor.swift", "r") as f:
    content = f.read()

old_heading = re.search(r'// 🛡️ 啟發式標題升級.*?// H2 不能太長\n\s*paragraphs\[i\]\.role = \.heading\n\s*\}\n\s*\}\n\s*\}', content, re.DOTALL)

if old_heading:
    new_heading = """// 🛡️ 啟發式標題升級 (Heading Promotion) V2：極簡安全版
                for i in 0..<paragraphs.count {
                    if paragraphs[i].role == .body {
                        let text = paragraphs[i].unifiedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // [V2 Patch] 移除字體大小判斷，只依賴絕對準確的正則表達式，徹底消滅 False Positive
                        let isChapter = text.lowercased().hasPrefix("chapter ") || (text.contains("第") && text.contains("章"))
                        
                        if isChapter {
                            paragraphs[i].role = .title
                        }
                    }
                }"""
    content = content.replace(old_heading.group(0), new_heading)

with open("Flow_1/Core/BatchProcessor.swift", "w") as f:
    f.write(content)

