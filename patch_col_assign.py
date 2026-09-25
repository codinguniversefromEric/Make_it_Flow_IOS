import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# For sortLayoutBlocks
new_col_assign_1 = """                let sortedRegion = region.sorted { a, b in
                    let midXA = a.boundingBox.midX
                    let midXB = b.boundingBox.midX
                    let colA = columns.firstIndex(where: { midXA >= $0.start && midXA <= $0.end }) ?? columns.firstIndex(where: { max(0, min(a.boundingBox.maxX, $0.end) - max(a.boundingBox.minX, $0.start)) > 0 }) ?? 0
                    let colB = columns.firstIndex(where: { midXB >= $0.start && midXB <= $0.end }) ?? columns.firstIndex(where: { max(0, min(b.boundingBox.maxX, $0.end) - max(b.boundingBox.minX, $0.start)) > 0 }) ?? 0
                    if colA != colB {"""

content = re.sub(r'                let sortedRegion = region\.sorted \{ a, b in\n                    let colA = columns\.firstIndex\(where: \{ max\(0, min\(a\.boundingBox\.maxX, \$0\.end\) - max\(a\.boundingBox\.minX, \$0\.start\)\) > 10 \}\) \?\? 0\n                    let colB = columns\.firstIndex\(where: \{ max\(0, min\(b\.boundingBox\.maxX, \$0\.end\) - max\(b\.boundingBox\.minX, \$0\.start\)\) > 10 \}\) \?\? 0\n                    if colA != colB \{', new_col_assign_1, content)


# For sortParagraphBlocks
new_col_assign_2 = """                let sortedRegion = region.sorted { a, b in
                    let midXA = a.bounds.midX
                    let midXB = b.bounds.midX
                    let colA = columns.firstIndex(where: { midXA >= $0.start && midXA <= $0.end }) ?? columns.firstIndex(where: { max(0, min(a.bounds.maxX, $0.end) - max(a.bounds.minX, $0.start)) > 0 }) ?? 0
                    let colB = columns.firstIndex(where: { midXB >= $0.start && midXB <= $0.end }) ?? columns.firstIndex(where: { max(0, min(b.bounds.maxX, $0.end) - max(b.bounds.minX, $0.start)) > 0 }) ?? 0
                    if colA != colB {"""

content = re.sub(r'                let sortedRegion = region\.sorted \{ a, b in\n                    let colA = columns\.firstIndex\(where: \{ max\(0, min\(a\.bounds\.maxX, \$0\.end\) - max\(a\.bounds\.minX, \$0\.start\)\) > 10 \}\) \?\? 0\n                    let colB = columns\.firstIndex\(where: \{ max\(0, min\(b\.bounds\.maxX, \$0\.end\) - max\(b\.bounds\.minX, \$0\.start\)\) > 10 \}\) \?\? 0\n                    if colA != colB \{', new_col_assign_2, content)


with open(filepath, "w") as f:
    f.write(content)

