import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# In sortLayoutBlocks
new_logic_1 = """            let label = block.label.lowercased()
            let isSemanticSpanning = label == "title" || label == "section-header" || label == "page-header" || label == "page-footer" || label == "picture" || label == "figure" || label == "table"
            let isSpanning = isSemanticSpanning || block.boundingBox.width >= pageWidth * 0.6 || columns.filter {"""

pattern1 = re.compile(r'            let isSpanning = block\.boundingBox\.width >= pageWidth \* 0\.6 \|\| columns\.filter \{')
content, c1 = pattern1.subn(new_logic_1, content, count=1) 

new_logic_2 = """            let label = region.first!.label.lowercased()
            let isSemanticSpanning = label == "title" || label == "section-header" || label == "page-header" || label == "page-footer" || label == "picture" || label == "figure" || label == "table"
            let isSpanning = isSemanticSpanning || region.first!.boundingBox.width >= pageWidth * 0.6 || columns.filter {"""

pattern2 = re.compile(r'            let isSpanning = region\.first!\.boundingBox\.width >= pageWidth \* 0\.6 \|\| columns\.filter \{')
content, c2 = pattern2.subn(new_logic_2, content, count=1)

with open(filepath, "w") as f:
    f.write(content)

print(f"Patched: c1={c1}, c2={c2}")
