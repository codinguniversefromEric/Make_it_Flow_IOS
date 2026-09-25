filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

old_font = """            if let fontName = frag.fontName, !fontName.contains("System") && !fontName.contains("UI") {
                style += " font-family: '\\(fontName)', sans-serif;"
            }"""

new_font = """            if let fontName = frag.fontName, !fontName.contains("System") && !fontName.contains("UI") && !fontName.contains("Math") && !fontName.contains("Symbol") {
                style += " font-family: '\\(fontName)', sans-serif;"
            }"""

content = content.replace(old_font, new_font)
with open(filepath, "w") as f:
    f.write(content)
