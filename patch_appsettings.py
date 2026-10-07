import os
path = "ePdfUB/App/AppSettings.swift"
with open(path, "r") as f:
    content = f.read()

content = content.replace("self.selectedModel = VisionModelType(rawValue: savedModelRaw) ?? .yoloFast", """#if DEBUG
        self.selectedModel = VisionModelType(rawValue: savedModelRaw) ?? .yoloFast
        #else
        self.selectedModel = .yoloFast
        #endif""")

with open(path, "w") as f:
    f.write(content)
