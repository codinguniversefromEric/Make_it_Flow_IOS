import Foundation
import PDFKit

@MainActor
func main() async {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        print("Usage: Flow_CLI <input.pdf> <output.epub> [nano|small|medium]")
        exit(1)
    }
    
    let inputPath = args[1]
    let outputPath = args[2]
    
    var selectedModel: VisionModelType = .yoloStandard
    if args.count >= 4 {
        let modelArg = args[3].lowercased()
        if modelArg == "nano" { selectedModel = .yoloFast }
        else if modelArg == "small" { selectedModel = .yoloStandard }
        else if modelArg == "medium" { selectedModel = .yoloMedium }
    }
    
    let inputURL = URL(fileURLWithPath: inputPath)
    guard let document = PDFDocument(url: inputURL) else {
        print("❌ Error: Could not load PDF at \(inputPath)")
        exit(1)
    }
    
    print("🚀 啟動 Flow_CLI: 正在處理 \(inputURL.lastPathComponent)")
    print("🧠 載入視覺引擎: \(selectedModel.rawValue)")
    AppSettings.shared.selectedModel = selectedModel
    let processor = BatchProcessor()
    
    let startTime = Date()
    await processor.exportDocument(document, fileName: inputURL.deletingPathExtension().lastPathComponent)
    let timeElapsed = Date().timeIntervalSince(startTime)
    let pages = document.pageCount
    print(String(format: "⏱ Processing time: %.2f seconds (%.2f s/page)", timeElapsed, timeElapsed / Double(pages)))
    
    if let resultURL = processor.exportedFileURL {
        do {
            if FileManager.default.fileExists(atPath: outputPath) {
                try FileManager.default.removeItem(atPath: outputPath)
            }
            try FileManager.default.copyItem(at: resultURL, to: URL(fileURLWithPath: outputPath))
            print("✅ File successfully copied to \(outputPath)")
        } catch {
            print("❌ Failed to copy to output path: \(error)")
            exit(1)
        }
    } else {
        print("❌ Processing failed or cancelled.")
        exit(1)
    }
}

// Run main
Task {
    await main()
    exit(0)
}
RunLoop.main.run()
