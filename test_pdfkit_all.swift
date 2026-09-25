import Foundation
import PDFKit

let url = URL(fileURLWithPath: "/Users/giyoshimiken/Documents/testbooks/book 1/Eric-Jorgenson_The-Almanack-of-Naval-Ravikant_Final.pdf")
guard let doc = PDFDocument(url: url) else { exit(1) }

var fullText = ""
for i in 0..<doc.pageCount {
    if let page = doc.page(at: i), let str = page.string {
        fullText += str
    }
}
print("Total pages: \\(doc.pageCount)")
print("Count of + : \\(fullText.filter { $0 == \"+\" }.count)")
print("Count of - : \\(fullText.filter { $0 == \"-\" }.count)")
print("Count of * : \\(fullText.filter { $0 == \"*\" }.count)")
print("Count of / : \\(fullText.filter { $0 == \"/\" }.count)")
