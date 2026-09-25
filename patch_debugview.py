import re

filepath = "Flow_1/Views/DebugPageView.swift"
with open(filepath, "r") as f:
    content = f.read()

content = content.replace("for para in paragraphs where !LayoutEngine.shouldDrop(para.role) {", "for para in paragraphs {")

old_block = """                if LayoutEngine.shouldDrop(para.role) {
                    return Color.gray.opacity(0.3)
                }"""
new_block = """                if LayoutEngine.shouldDrop(para.role) {
                    return Color.gray.opacity(0.3)
                }"""
# Let's keep it as is, role based, because `shouldDrop(role:)` still exists! It returns true for .pageHeader and .pageFooter.

with open(filepath, "w") as f:
    f.write(content)

