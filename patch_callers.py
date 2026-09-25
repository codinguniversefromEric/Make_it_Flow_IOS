import re

filepath = "Flow_1/Core/BatchProcessor.swift"
with open(filepath, "r") as f:
    content = f.read()

# Replace: if LayoutEngine.shouldDrop(block.role) { continue }
content = content.replace(
    "if LayoutEngine.shouldDrop(block.role) { continue }", 
    "if LayoutEngine.shouldDrop(block: block, pageHeight: pageHeight) { continue }"
)

# Replace: if let firstBlock = paragraphs.first(where: { !LayoutEngine.shouldDrop($0.role) }),
content = content.replace(
    "if let firstBlock = paragraphs.first(where: { !LayoutEngine.shouldDrop($0.role) }),",
    "if let firstBlock = paragraphs.first(where: { !LayoutEngine.shouldDrop(block: $0, pageHeight: pageHeight) }),"
)

with open(filepath, "w") as f:
    f.write(content)

filepath = "Flow_1/Views/DebugPageView.swift"
with open(filepath, "r") as f:
    content = f.read()

# DebugPageView might not have pageHeight easily accessible, or it might.
# For DebugPageView, maybe just use the old shouldDrop($0.role) to prevent errors.
# The user already asked me to remove shouldDrop from DebugPageView in earlier commits, but in 756ec05 it's still there!
content = content.replace(
    "for para in paragraphs where !LayoutEngine.shouldDrop(para.role) {",
    "for para in paragraphs where !LayoutEngine.shouldDrop(para.role) {"  # keep it same, role based
)

with open(filepath, "w") as f:
    f.write(content)

