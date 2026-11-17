import SwiftUI
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer

struct EPUBReaderView: View {
    let file: LibraryItem

    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("epubReaderFontSize") private var fontSize = 1.0
    @State private var navigator: EPUBNavigatorViewController?
    @State private var contents: [ReadiumShared.Link] = []
    @State private var showsContents = false
    @State private var failedToOpen = false
    @State private var showsNavigationError = false

    private func readerPreferences(for publication: Publication) -> EPUBPreferences {
        // Generated Traditional Chinese EPUBs (and older exports tagged zh-TW)
        // are horizontal, so use the converter's left-to-right page order.
        let language = publication.metadata.language?.code.bcp47.lowercased()
        let needsHorizontalProgression = publication.metadata.layout != .fixed &&
            (language == "zh-tw" || language == "zh-hant")
        return EPUBPreferences(
            fontSize: fontSize,
            readingProgression: needsHorizontalProgression ? .ltr : nil,
            verticalText: false
        )
    }

    var body: some View {
        Group {
            if let navigator {
                EPUBNavigatorHost(navigator: navigator, bookID: file.id)
            } else if failedToOpen {
                ContentUnavailableView(
                    "Unable to Open EPUB",
                    systemImage: "book.closed",
                    description: Text("The file may be missing, damaged, or protected.")
                )
            } else {
                ProgressView("Opening book…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !contents.isEmpty {
                    Button("Table of Contents", systemImage: "list.bullet") {
                        showsContents = true
                    }
                }
                if let navigator, navigator.publication.metadata.layout != .fixed {
                    Menu("Text Size", systemImage: "textformat.size") {
                        Button("Larger Text", systemImage: "plus.magnifyingglass") {
                            fontSize = min(2.5, fontSize + 0.125)
                        }
                        .disabled(fontSize >= 2.5)
                        Button("Smaller Text", systemImage: "minus.magnifyingglass") {
                            fontSize = max(0.75, fontSize - 0.125)
                        }
                        .disabled(fontSize <= 0.75)
                        Button("Reset Text Size") { fontSize = 1.0 }
                    }
                }
                ShareLink(item: file.url)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if let navigator {
                    let leadingIsRight = layoutDirection == .rightToLeft
                    pageTurnButton(for: navigator, towardRight: leadingIsRight, icon: "chevron.backward")
                    Spacer()
                    pageTurnButton(for: navigator, towardRight: !leadingIsRight, icon: "chevron.forward")
                }
            }
        }
        .task { await openBook() }
        .onChange(of: fontSize) {
            if let navigator {
                navigator.submitPreferences(readerPreferences(for: navigator.publication))
            }
        }
        .sheet(isPresented: $showsContents) {
            NavigationStack {
                List {
                    ForEach(Array(contents.enumerated()), id: \.offset) { _, link in
                        EPUBContentsRow(link: link, select: jump)
                    }
                }
                .navigationTitle("Table of Contents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showsContents = false }
                    }
                }
            }
        }
        .alert("Unable to Open Chapter", isPresented: $showsNavigationError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func pageTurnButton(
        for navigator: EPUBNavigatorViewController, towardRight: Bool, icon: String
    ) -> some View {
        let isForward = towardRight == (navigator.presentation.readingProgression == .ltr)
        return Button(isForward ? "Next Page" : "Previous Page", systemImage: icon) {
            Task {
                let options = NavigatorGoOptions(animated: true)
                if isForward {
                    await navigator.goForward(options: options)
                } else {
                    await navigator.goBackward(options: options)
                }
            }
        }
    }

    private func openBook() async {
        guard navigator == nil else { return }

        do {
            guard let url = FileURL(url: file.url) else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let client = DefaultHTTPClient()
            let retriever = AssetRetriever(httpClient: client)
            let opener = PublicationOpener(parser: DefaultPublicationParser(
                httpClient: client,
                assetRetriever: retriever,
                pdfFactory: DefaultPDFDocumentFactory()
            ))
            let asset = try await retriever.retrieve(url: url).get()
            let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
            try Task.checkCancellation()
            guard !publication.readingOrder.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let savedLocation = UserDefaults.standard.string(forKey: LibraryItem.readingPositionKey(file.id))
            let locator = savedLocation.flatMap { try? Locator(jsonString: $0) }
            let controller = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: locator,
                config: .init(preferences: readerPreferences(for: publication))
            )
            DirectionalNavigationAdapter(pointerPolicy: .init(types: [.mouse, .touch])).bind(to: controller)
            navigator = controller

            let tableOfContents = try? await publication.tableOfContents().get()
            try Task.checkCancellation()
            contents = tableOfContents ?? []
        } catch {
            if !Task.isCancelled {
                failedToOpen = true
            }
        }
    }

    private func jump(to link: ReadiumShared.Link) {
        guard let navigator else { return }
        showsContents = false
        Task {
            if !(await navigator.go(to: link, options: .init())) {
                showsNavigationError = true
            }
        }
    }
}

private struct EPUBContentsRow: View {
    let link: ReadiumShared.Link
    let select: (ReadiumShared.Link) -> Void

    var body: some View {
        if link.children.isEmpty {
            chapterButton
        } else {
            DisclosureGroup {
                ForEach(Array(link.children.enumerated()), id: \.offset) { _, child in
                    EPUBContentsRow(link: child, select: select)
                }
            } label: {
                chapterButton
            }
        }
    }

    private var chapterButton: some View {
        Button(link.title ?? link.href) { select(link) }
    }
}

private struct EPUBNavigatorHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    let bookID: UUID

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        navigator.delegate = context.coordinator
        return navigator
    }

    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(bookID: bookID) }

    final class Coordinator: EPUBNavigatorDelegate {
        let bookID: UUID

        init(bookID: UUID) { self.bookID = bookID }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            if let position = locator.jsonString {
                UserDefaults.standard.set(position, forKey: LibraryItem.readingPositionKey(bookID))
            }
        }

        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            guard let controller = navigator as? UIViewController else { return }
            let alert = UIAlertController(
                title: String(localized: "This selection cannot be copied."),
                message: nil,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            controller.present(alert, animated: true)
        }
    }
}
