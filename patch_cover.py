import re

filepath = "Flow_1/Core/BatchProcessor.swift"
with open(filepath, "r") as f:
    content = f.read()

cover_code = """                guard let validCGImg = cgImg, let validRawImage = rawImage else { continue }
                
                // --- 封面擷取 (第 1 頁) ---
                if pageIndex == 0 {
                    if let imageData = validRawImage.appJPEGData(compressionQuality: 0.85) {
                        let fileURL = assetsDir.appendingPathComponent("cover.jpg")
                        try? imageData.write(to: fileURL)
                        AppLogger.shared.info("🖼️ 成功儲存封面圖片 cover.jpg")
                    }
                }"""

content = content.replace("                guard let validCGImg = cgImg, let validRawImage = rawImage else { continue }", cover_code)
with open(filepath, "w") as f:
    f.write(content)


filepath = "Flow_1/Engines/EPUBSynthesizer.swift"
with open(filepath, "r") as f:
    content = f.read()

old_manifest = """            if fm.fileExists(atPath: assetsURL.path),
               let images = try? fm.contentsOfDirectory(atPath: assetsURL.path) {
                for (index, image) in images.enumerated() where !image.hasPrefix(".") {
                    imageManifest += "<item id=\\\"img\\(index)\\\" href=\\\"assets/\\(image)\\\" media-type=\\\"image/png\\\"/>\\n"
                }
            }"""

new_manifest = """            var hasCover = false
            if fm.fileExists(atPath: assetsURL.path),
               let images = try? fm.contentsOfDirectory(atPath: assetsURL.path) {
                for (index, image) in images.enumerated() where !image.hasPrefix(".") {
                    let isJPG = image.lowercased().hasSuffix(".jpg") || image.lowercased().hasSuffix(".jpeg")
                    let mediaType = isJPG ? "image/jpeg" : "image/png"
                    let isCover = image == "cover.jpg"
                    if isCover { hasCover = true }
                    
                    let id = isCover ? "cover-image" : "img\\(index)"
                    let properties = isCover ? " properties=\\\"cover-image\\\"" : ""
                    imageManifest += "<item id=\\\"\\(id)\\\" href=\\\"assets/\\(image)\\\" media-type=\\\"\\(mediaType)\\\"\\(properties)/>\\n"
                }
            }"""

content = content.replace(old_manifest, new_manifest)
with open(filepath, "w") as f:
    f.write(content)

