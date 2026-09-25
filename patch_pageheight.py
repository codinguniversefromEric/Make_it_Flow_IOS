filepath = "Flow_1/Core/BatchProcessor.swift"
with open(filepath, "r") as f:
    content = f.read()

content = content.replace("pageHeight: pageHeight", "pageHeight: scaledSize.height")
with open(filepath, "w") as f:
    f.write(content)
