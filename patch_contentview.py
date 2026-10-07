import os
path = "ePdfUB/Views/ContentView.swift"
with open(path, "r") as f:
    content = f.read()

content = content.replace("    // MARK: - Dev Tools Panel", "#if DEBUG\n    // MARK: - Dev Tools Panel")
content = content.replace("        )\n    }", "        )\n    }\n#endif")

with open(path, "w") as f:
    f.write(content)
