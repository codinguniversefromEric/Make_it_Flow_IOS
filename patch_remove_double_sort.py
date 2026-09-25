import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# Replace the end of processWithLayoutBlocks
old_code = """        if !unassignedFragments.isEmpty {
            let fallbackBlocks = fallbackLayout(fragments: unassignedFragments, pageWidth: pageWidth, pageHeight: pageHeight)
            finalParagraphs.append(contentsOf: fallbackBlocks)
        }
            
        // 將兩者混合後，使用標準的閱讀順序排序 (分區段 -> 分欄 -> 排序)
        return sortParagraphBlocks(finalParagraphs, pageWidth: pageWidth, pageHeight: pageHeight)"""

new_code = """        if !unassignedFragments.isEmpty {
            let fallbackBlocks = fallbackLayout(fragments: unassignedFragments, pageWidth: pageWidth, pageHeight: pageHeight)
            // 將 fallback 區塊依據 Y 軸稍微排序後，附加在最後。
            // 絕對不要對 finalParagraphs 重新進行全域排序，否則會破壞 YOLO 的雙欄結構 (Double Sorting Bug)
            finalParagraphs.append(contentsOf: fallbackBlocks.sorted { $0.bounds.minY < $1.bounds.minY })
        }
            
        return finalParagraphs"""

content = content.replace(old_code, new_code)

with open(filepath, "w") as f:
    f.write(content)

