import SwiftUI
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer

struct EPUBReaderView: View {
    let file: LibraryItem

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("epubReaderFontSize") private var fontSize = 1.0
    @State private var navigator: EPUBNavigatorViewController?
    @State private var contents: [ReadiumShared.Link] = []
    @State private var showsContents = false
    @State private var failedToOpen = false
    @State private var showsNavigationError = false

    private let readerBackground = SwiftUI.Color(uiColor: .systemBackground)

    private func readerPreferences(for publication: Publication) -> EPUBPreferences {
        // Earlier Traditional Chinese conversions are horizontal despite their language tag.
        let language = publication.metadata.language?.code.bcp47.lowercased()
        let needsHorizontalProgression = publication.metadata.layout != .fixed &&
            (language == "zh-tw" || language == "zh-hant")
        return EPUBPreferences(
            fontSize: fontSize,
            readingProgression: needsHorizontalProgression ? .ltr : nil,
            // Readium paints the canvas outside publisher-styled content.
            theme: colorScheme == .dark ? .dark : .light,
            // The PDF converter emits horizontal text regardless of language metadata.
            verticalText: false
        )
    }

    var body: some View {
        Group {
            if let navigator {
                EPUBNavigatorHost(navigator: navigator, bookID: file.id)
                    .onChange(of: readerPreferences(for: navigator.publication), initial: true) { _, preferences in
                        navigator.submitPreferences(preferences)
                    }
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
        .background(readerBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            readerRule
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let navigator {
                pageControls(for: navigator)
            }
        }
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(readerBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .tint(.primary)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(file.title)
                    .font(.custom("Times New Roman", size: 18, relativeTo: .headline).bold())
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .primaryAction) {
                readerActions
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task { await openBook() }
        .sheet(isPresented: $showsContents) {
            NavigationStack {
                List {
                    ForEach(Array(contents.enumerated()), id: \.offset) { _, link in
                        EPUBContentsRow(link: link, select: jump)
                    }
                }
                .listStyle(.plain)
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

    private var readerActions: some View {
        HStack(spacing: 8) {
            if !contents.isEmpty {
                Button("Table of Contents", systemImage: "list.bullet") {
                    showsContents = true
                }
            }
            if let navigator, navigator.publication.metadata.layout != .fixed {
                Menu {
                    Button("Larger Text", systemImage: "plus.magnifyingglass") {
                        fontSize = min(2.5, fontSize + 0.125)
                    }
                    .disabled(fontSize >= 2.5)
                    Button("Smaller Text", systemImage: "minus.magnifyingglass") {
                        fontSize = max(0.75, fontSize - 0.125)
                    }
                    .disabled(fontSize <= 0.75)
                    Button("Reset Text Size") { fontSize = 1.0 }
                } label: {
                    Label("Text Size", systemImage: "textformat.size")
                        .modifier(ReaderControlFrame())
                }
                .menuIndicator(.hidden)
            }
            ShareLink(item: file.url)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ReaderControlStyle())
    }

    private var readerRule: some View {
        Rectangle()
            .fill(.primary)
            .frame(height: 3)
    }

    private func pageControls(for navigator: EPUBNavigatorViewController) -> some View {
        VStack(spacing: 0) {
            readerRule
            HStack {
                let leadingIsRight = layoutDirection == .rightToLeft
                pageTurnButton(for: navigator, towardRight: leadingIsRight, icon: "chevron.backward")
                Spacer()
                pageTurnButton(for: navigator, towardRight: !leadingIsRight, icon: "chevron.forward")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(ReaderControlStyle())
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .background(readerBackground)
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
                config: .init(
                    preferences: readerPreferences(for: publication),
                    contentInset: [.regular: (top: 16, bottom: 16)]
                )
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

private struct ReaderControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ReaderControlFrame(isPressed: configuration.isPressed))
    }
}

private struct ReaderControlFrame: ViewModifier {
    var isPressed = false

    func body(content: Self.Content) -> some View {
        content
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .background(.primary.opacity(isPressed ? 0.15 : 0))
            .border(.primary, width: 2)
            .contentShape(Rectangle())
    }
}

private struct EPUBContentsRow: View {
    let link: ReadiumShared.Link
    var depth = 0
    let select: (ReadiumShared.Link) -> Void

    @State private var isExpanded = false

    private var title: String { link.title ?? link.href }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                select(link)
            } label: {
                Text(title)
                    .font(.custom("Times New Roman", size: 16, relativeTo: .body))
                    .multilineTextAlignment(.leading)
                    .padding(.leading, CGFloat(min(depth, 4)) * 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !link.children.isEmpty {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 56, height: 48)
                        .background(.primary.opacity(0.08))
                        .border(.primary.opacity(0.35))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? Text("Collapse \(title)") : Text("Expand \(title)"))
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

        if isExpanded {
            ForEach(Array(link.children.enumerated()), id: \.offset) { _, child in
                EPUBContentsRow(link: child, depth: depth + 1, select: select)
            }
        }
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
