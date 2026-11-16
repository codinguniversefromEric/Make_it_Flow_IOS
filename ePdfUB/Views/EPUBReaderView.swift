import SwiftUI
import QuickLook

// 簡易 EPUB 閱讀器
struct EPUBReaderView: View {
    let file: LibraryItem

    var body: some View {
        Group {
            if QLPreviewController.canPreview(file.url as NSURL) {
                QuickLookPreview(url: file.url)
                    .id(file.id)
            } else {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "book.closed",
                    description: Text("Use Share to open this EPUB in a reading app.")
                )
            }
        }
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: file.url)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as NSURL
        }
    }
}
