import Foundation
import Quartz

let url = URL(fileURLWithPath: "evaluation/test_sample.pdf")
guard let doc = PDFDocument(url: url) else { exit(1) }

// The user uploaded 14 pages. Page 13 is index 13 (0-based)
if let page = doc.page(at: 13) {
    if let sel = page.selection(for: page.bounds(for: .cropBox)) {
        for line in sel.selectionsByLine() {
            let text = line.string ?? ""
            var fontSize: CGFloat = 0
            if let attr = line.attributedString {
                attr.enumerateAttributes(in: NSRange(location:0, length: attr.length)) { attrs, _, _ in
                    if let font = attrs[.font] as? NSFont {
                        fontSize = max(fontSize, font.pointSize)
                    }
                }
            }
            print("\(text.prefix(30)) | Size: \(fontSize)")
        }
    }
}
