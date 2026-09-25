import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# In sortParagraphBlocks:
# Replace the isSpanning logic:
# let isSpanning = block.bounds.width >= pageWidth * 0.6 || columns.filter {
new_logic_1 = """            let isSemanticSpanning = block.role == .title || block.role == .heading || block.role == .pageHeader || block.role == .pageFooter || block.role == .picture || block.role == .figure || block.role == .table
            let isSpanning = isSemanticSpanning || block.bounds.width >= pageWidth * 0.6 || columns.filter {"""

pattern1 = re.compile(r'            let isSpanning = block\.bounds\.width >= pageWidth \* 0\.6 \|\| columns\.filter \{')
content, c1 = pattern1.subn(new_logic_1, content, count=1) # Only the first one inside the loop

new_logic_2 = """            let isSemanticSpanning = region.first!.role == .title || region.first!.role == .heading || region.first!.role == .pageHeader || region.first!.role == .pageFooter || region.first!.role == .picture || region.first!.role == .figure || region.first!.role == .table
            let isSpanning = isSemanticSpanning || region.first!.bounds.width >= pageWidth * 0.6 || columns.filter {"""

pattern2 = re.compile(r'            let isSpanning = region\.first!\.bounds\.width >= pageWidth \* 0\.6 \|\| columns\.filter \{')
content, c2 = pattern2.subn(new_logic_2, content, count=1) # Only the one in the region loop

with open(filepath, "w") as f:
    f.write(content)

print(f"Patched: c1={c1}, c2={c2}")
