filepath = "Flow_1/Core/BatchProcessor.swift"
with open(filepath, "r") as f:
    content = f.read()

content = content.replace("        var bgTaskID: UIBackgroundTaskIdentifier = .invalid\n#if os(iOS)", "#if os(iOS)\n        var bgTaskID: UIBackgroundTaskIdentifier = .invalid")
with open(filepath, "w") as f:
    f.write(content)
