import re

with open("Flow_CLI/Sources/Flow_CLI/main.swift", "r") as f:
    content = f.read()

old_log = 'AppLogger.shared.info("Starting Flow_CLI processing for \\(inputURL.lastPathComponent) using \\(selectedModel.rawValue)")'
new_log = 'print("🚀 啟動 Flow_CLI: 正在處理 \\(inputURL.lastPathComponent)")\n    print("🧠 載入視覺引擎: \\(selectedModel.rawValue)")'

content = content.replace(old_log, new_log)

with open("Flow_CLI/Sources/Flow_CLI/main.swift", "w") as f:
    f.write(content)
