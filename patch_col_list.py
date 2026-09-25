import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# For sortLayoutBlocks:
new_col_gen_1 = """        let textBlocks = blocks.filter { ["text", "list-item", "footnote", "caption"].contains($0.label.lowercased()) }
        let nonSpanningBlocks = textBlocks.filter { $0.boundingBox.width < pageWidth * 0.5 }"""
content = re.sub(r'        let textBlocks = blocks\.filter \{ \$0\.label\.lowercased\(\) == "text" \}\n        let nonSpanningBlocks = textBlocks\.filter \{ \$0\.boundingBox\.width < pageWidth \* 0\.5 \}', new_col_gen_1, content)

# For sortParagraphBlocks:
new_col_gen_2 = """        let textBlocks = blocks.filter { $0.role == .body || $0.role == .listItem || $0.role == .footnote || $0.role == .caption }
        let nonSpanningBlocks = textBlocks.filter { $0.bounds.width < pageWidth * 0.5 }"""
content = re.sub(r'        let textBlocks = blocks\.filter \{ \$0\.role == \.body \}\n        let nonSpanningBlocks = textBlocks\.filter \{ \$0\.bounds\.width < pageWidth \* 0\.5 \}', new_col_gen_2, content)

with open(filepath, "w") as f:
    f.write(content)

