import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

# For LayoutBlock
new_y_sort_1 = """region.sorted { abs($0.boundingBox.minY - $1.boundingBox.minY) < 5.0 ? $0.boundingBox.minX < $1.boundingBox.minX : $0.boundingBox.minY < $1.boundingBox.minY }"""
content = re.sub(r'region\.sorted \{ \$0\.boundingBox\.minY < \$1\.boundingBox\.minY \}', new_y_sort_1, content)

new_col_sort_1 = """                    if colA != colB {
                        return colA < colB 
                    } else {
                        return abs(a.boundingBox.minY - b.boundingBox.minY) < 5.0 ? a.boundingBox.minX < b.boundingBox.minX : a.boundingBox.minY < b.boundingBox.minY 
                    }"""
content = re.sub(r'                    if colA != colB \{\n                        return colA < colB \n                    \} else \{\n                        return a\.boundingBox\.minY < b\.boundingBox\.minY \n                    \}', new_col_sort_1, content)

# For ParagraphBlock
new_y_sort_2 = """region.sorted { abs($0.bounds.minY - $1.bounds.minY) < 5.0 ? $0.bounds.minX < $1.bounds.minX : $0.bounds.minY < $1.bounds.minY }"""
content = re.sub(r'region\.sorted \{ \$0\.bounds\.minY < \$1\.bounds\.minY \}', new_y_sort_2, content)

new_col_sort_2 = """                    if colA != colB {
                        return colA < colB 
                    } else {
                        return abs(a.bounds.minY - b.bounds.minY) < 5.0 ? a.bounds.minX < b.bounds.minX : a.bounds.minY < b.bounds.minY 
                    }"""
content = re.sub(r'                    if colA != colB \{\n                        return colA < colB \n                    \} else \{\n                        return a\.bounds\.minY < b\.bounds\.minY \n                    \}', new_col_sort_2, content)


with open(filepath, "w") as f:
    f.write(content)

