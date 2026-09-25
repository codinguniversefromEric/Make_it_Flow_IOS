import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# For sortLayoutBlocks:
new_col_gen_1 = """        let textBlocks = blocks.filter { $0.label.lowercased() == "text" }
        let nonSpanningBlocks = textBlocks.filter { $0.boundingBox.width < pageWidth * 0.5 }
        let xIntervals = nonSpanningBlocks.map { Interval(start: $0.boundingBox.minX, end: $0.boundingBox.maxX) }"""
content = re.sub(r'        let nonSpanningBlocks = blocks\.filter \{ \$0\.boundingBox\.width < pageWidth \* 0\.7 \}\n        let xIntervals = nonSpanningBlocks\.map \{ Interval\(start: \$0\.boundingBox\.minX, end: \$0\.boundingBox\.maxX\) \}', new_col_gen_1, content)

# For sortParagraphBlocks:
new_col_gen_2 = """        let textBlocks = blocks.filter { $0.role == .body }
        let nonSpanningBlocks = textBlocks.filter { $0.bounds.width < pageWidth * 0.5 }
        let xIntervals = nonSpanningBlocks.map { Interval(start: $0.bounds.minX, end: $0.bounds.maxX) }"""
content = re.sub(r'        let nonSpanningBlocks = blocks\.filter \{ \$0\.bounds\.width < pageWidth \* 0\.7 \}\n        let xIntervals = nonSpanningBlocks\.map \{ Interval\(start: \$0\.bounds\.minX, end: \$0\.bounds\.maxX\) \}', new_col_gen_2, content)

with open(filepath, "w") as f:
    f.write(content)

