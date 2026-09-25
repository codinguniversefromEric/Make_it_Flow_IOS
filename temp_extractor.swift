import Foundation
import PDFKit
let pdfURL = URL(fileURLWithPath: CommandLine.arguments[1])
if let document = PDFDocument(url: pdfURL) {
    var fullText = ""
    for i in 0..<document.pageCount {
        if let page = document.page(at: i), let string = page.string {
            fullText += string + " "
        }
    }
    print("Extracted Length: \(fullText.count)")
} else {
    print("Could not open PDF")
}
