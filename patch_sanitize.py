filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

old_block = """    private nonisolated static func buildParagraphBlock(from fragments: [TextFragment], role: SemanticRole) -> ParagraphBlock {
        // 計算外接矩形
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for frag in fragments {
            minX = min(minX, frag.bounds.minX)
            minY = min(minY, frag.bounds.minY)
            maxX = max(maxX, frag.bounds.maxX)
            maxY = max(maxY, frag.bounds.maxY)
        }

        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // 斷字修復
        let lines = fragments.map { $0.text }
        var unified = recoverHyphenation(lines: lines)
        
        // 論文特化 OCR 錯誤修復
        unified = sanitizeScientificOCR(unified)

        return ParagraphBlock(
            fragments: fragments,
            role: role,
            unifiedText: unified,
            bounds: bounds
        )
    }"""

new_block = """    private nonisolated static func buildParagraphBlock(from fragments: [TextFragment], role: SemanticRole) -> ParagraphBlock {
        // 先對每個 fragment 執行 OCR 亂碼修復 (數學符號等)
        let sanitizedFragments = fragments.map { frag -> TextFragment in
            return TextFragment(
                text: sanitizeScientificOCR(frag.text),
                bounds: frag.bounds,
                fontSize: frag.fontSize,
                fontName: frag.fontName,
                isBold: frag.isBold,
                isItalic: frag.isItalic,
                colorHex: frag.colorHex
            )
        }

        // 計算外接矩形
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for frag in sanitizedFragments {
            minX = min(minX, frag.bounds.minX)
            minY = min(minY, frag.bounds.minY)
            maxX = max(maxX, frag.bounds.maxX)
            maxY = max(maxY, frag.bounds.maxY)
        }

        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // 斷字修復
        let lines = sanitizedFragments.map { $0.text }
        var unified = recoverHyphenation(lines: lines)
        
        // 再次確保 unified 也是乾淨的 (其實上面已經修復過每個碎片了，但為保險再過一次)
        unified = sanitizeScientificOCR(unified)

        return ParagraphBlock(
            fragments: sanitizedFragments,
            role: role,
            unifiedText: unified,
            bounds: bounds
        )
    }"""

content = content.replace(old_block, new_block)
with open(filepath, "w") as f:
    f.write(content)
