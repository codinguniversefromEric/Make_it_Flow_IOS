import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count == 2 else { exit(1) }
let pdfURL = URL(fileURLWithPath: args[1])
guard let document = PDFDocument(url: pdfURL) else { exit(1) }

var fullText = ""
for i in 0..<document.pageCount {
    if let page = document.page(at: i), let string = page.string {
        fullText += string + "\n"
    }
}
print(fullText)
