import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import QuickLook

enum AnimationState {
    case idle
    case showingThumbnail
    case suckingToIsland
    case processing
}

struct ContentView: View {
    @StateObject private var vm = ContentViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var isGridView = false
    @State private var documentName = ""
    @State private var fileToDelete: LibraryItem? = nil
    @State private var showBrutalistSuccess = false
    @State private var successFileURL: URL? = nil

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM dd"
        df.locale = Locale(identifier: "en_US")
        return df
    }()

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    if vm.animState == .processing {
                        processingView
                    } else if showBrutalistSuccess {
                        successView
                    } else {
                        libraryView
                    }

                    if vm.animState != .processing {
                        devToolsPanel
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $vm.showFilePicker) {
            PDFDocumentPicker { url in
                documentName = url.deletingPathExtension().lastPathComponent
                vm.handlePickedPDF(url: url)
            }
        }
        .onChange(of: vm.batchProcessor.exportedFileURL) { newURL in
            if let epubURL = newURL {
                successFileURL = epubURL
                vm.finishConversion(epubURL: epubURL)
                showBrutalistSuccess = true
            }
        }
        .alert("Conversion Error", isPresented: $vm.showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.errorMessage)
        }
        .onOpenURL { url in
            if url.pathExtension.lowercased() == "pdf" {
                documentName = url.deletingPathExtension().lastPathComponent
                vm.handlePickedPDF(url: url)
            }
        }
    }

    // MARK: - Library View
    @ViewBuilder
    private var libraryView: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
                Text("PDFlux.")
                    .font(.custom("Times New Roman", size: 36))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Toggle Buttons
                HStack(spacing: 8) {
                    Button(action: { isGridView = false }) {
                        Image(systemName: "list.dash")
                            .font(.system(size: 20))
                            .foregroundColor(!isGridView ? Color(UIColor.systemBackground) : .primary)
                            .frame(width: 36, height: 36)
                            .background(!isGridView ? Color.primary : Color(UIColor.systemBackground))
                            .border(Color.primary, width: 2)
                    }
                    
                    Button(action: { isGridView = true }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 20))
                            .foregroundColor(isGridView ? Color(UIColor.systemBackground) : .primary)
                            .frame(width: 36, height: 36)
                            .background(isGridView ? Color.primary : Color(UIColor.systemBackground))
                            .border(Color.primary, width: 2)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .padding(.bottom, 8)
            .background(
                Rectangle()
                    .frame(height: 3)
                    .foregroundColor(.primary)
                    .offset(y: 3),
                alignment: .bottom
            )
            .zIndex(1)

            // Content
            if vm.libraryStore.items.isEmpty {
                Spacer()
                Text("No EPUBs generated yet.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                if isGridView {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                            ForEach(vm.libraryStore.items.sorted { $0.createdAt > $1.createdAt }) { file in
                                gridItem(for: file)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.libraryStore.items.sorted { $0.createdAt > $1.createdAt }) { file in
                                listItem(for: file)
                            }
                        }
                    }
                }
            }
            
            // Bottom Action
            VStack(spacing: 0) {
                Rectangle()
                    .frame(height: 3)
                    .foregroundColor(.primary)
                
                Button(action: { vm.showFilePicker = true }) {
                    Text("+")
                        .font(.custom("Times New Roman", size: 48))
                        .fontWeight(.light)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .border(Color.primary, width: 3)
                }
                .padding(24)
            }
            .background(Color(UIColor.systemBackground))
        }
        .overlay(
            Group {
                if let file = fileToDelete {
                    deleteDialog(file: file)
                }
            }
        )
    }

    // MARK: - List & Grid Items
    @ViewBuilder
    private func listItem(for file: LibraryItem) -> some View {
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path)
        let size = (attrs?[.size] as? Double) ?? 0.0
        let sizeStr = String(format: "%.1f MB", size / (1024 * 1024))
        let dateStr = dateFormatter.string(from: file.createdAt).uppercased()

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.title)
                    .font(.custom("Times New Roman", size: 14))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(dateStr) • \(sizeStr)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                    .tracking(1.5)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(Color(UIColor.systemGray5))
                .offset(y: 2),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture {
            shareOrOpen(file: file)
        }
        .onLongPressGesture {
            fileToDelete = file
        }
    }

    @ViewBuilder
    private func gridItem(for file: LibraryItem) -> some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(Color(UIColor.systemBackground))
                    .aspectRatio(3/4, contentMode: .fit)
                    .border(Color.primary, width: 3)
                
                // Dog ear / corner fold
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 16, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: 16))
                    path.closeSubpath()
                }
                .fill(Color.primary)
                
                Text(String(file.title.first ?? "D").uppercased())
                    .font(.custom("Times New Roman", size: 64))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 12)
            
            Text(file.title)
                .font(.custom("Times New Roman", size: 12))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            shareOrOpen(file: file)
        }
        .onLongPressGesture {
            fileToDelete = file
        }
    }
    
    private func shareOrOpen(file: LibraryItem) {
        let activityVC = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Delete Dialog
    @ViewBuilder
    private func deleteDialog(file: LibraryItem) -> some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Delete")
                    .font(.custom("Times New Roman", size: 24))
                    .fontWeight(.bold)
                
                Text("Remove \(file.title)?")
                    .font(.system(size: 12, design: .monospaced))
                
                HStack {
                    Spacer()
                    Button(action: { fileToDelete = nil }) {
                        Text("CANCEL")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    Button(action: {
                        vm.libraryStore.deleteItem(file)
                        fileToDelete = nil
                    }) {
                        Text("DELETE")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(24)
            .background(Color(UIColor.systemBackground))
            .border(Color.primary, width: 3)
            .padding(40)
        }
    }

    // MARK: - Processing View
    @ViewBuilder
    private var processingView: some View {
        VStack(spacing: 64) {
            Spacer()
            
            VStack(spacing: 64) {
                Text(documentName.isEmpty ? "document.pdf" : "\(documentName).pdf")
                    .font(.custom("Times New Roman", size: 24))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                // 10 blocks progress bar
                let totalGrids = 10
                let progress = vm.batchProcessor.progress
                let completedGrids = min(totalGrids, Int(progress * 10))
                
                HStack(spacing: 6) {
                    ForEach(0..<totalGrids, id: \.self) { i in
                        let isCompleted = i < completedGrids
                        let isCurrent = i == completedGrids
                        
                        Rectangle()
                            .fill(isCompleted ? Color.primary : Color(UIColor.systemBackground))
                            .border(isCurrent ? Color.primary : (isCompleted ? Color.primary : Color(UIColor.systemGray5)), width: 2)
                            .frame(height: 24)
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            Button(action: { vm.cancelProcessing() }) {
                Text("CANCEL")
                    .font(.custom("Times New Roman", size: 12))
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .border(Color.primary, width: 2)
            }
            .padding(24)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Success View
    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 64) {
            Spacer()
            
            VStack(spacing: 24) {
                Text("Ready.")
                    .font(.custom("Times New Roman", size: 64))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 0) {
                    Text(documentName.isEmpty ? "document" : documentName)
                    Text(".epub")
                        .background(Color(UIColor.systemGray5))
                }
                .font(.custom("Times New Roman", size: 18))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.bottom, 8)
                .padding(.horizontal, 16)
                .background(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(.primary)
                        .offset(y: 2),
                    alignment: .bottom
                )
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    if let url = successFileURL {
                        shareOrOpen(file: LibraryItem(id: UUID(), url: url, title: documentName, createdAt: Date(), diagnosticsSummary: ""))
                    }
                }) {
                    VStack(spacing: 2) {
                        Text("EXPORT EPUB")
                            .font(.custom("Times New Roman", size: 12))
                            .fontWeight(.bold)
                            .tracking(2)
                        Text("(SHARE TO APPLE BOOKS)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary)
                        .border(Color.primary, width: 3)
                }
                
                Button(action: {
                    documentName = ""
                    showBrutalistSuccess = false
                }) {
                    Text("CONVERT ANOTHER")
                        .font(.custom("Times New Roman", size: 12))
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(UIColor.systemBackground))
                        .border(Color.primary, width: 3)
                }
            }
            .padding(24)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Dev Tools Panel
    @ViewBuilder
    private var devToolsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🛠️ DEV TOOLS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.bottom, 4)
            
            HStack {
                Toggle(isOn: $settings.debugMode) {
                    Text("Artifacts")
                        .font(.system(size: 10, design: .monospaced))
                }
                .toggleStyle(CheckboxToggleStyle())
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(VisionModelType.allCases, id: \.self) { model in
                        Text(model.rawValue)
                            .font(.system(size: 9))
                            .foregroundColor(settings.selectedModel == model ? Color(UIColor.systemBackground) : .primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(settings.selectedModel == model ? Color.primary : Color.clear)
                            .border(settings.selectedModel == model ? Color.primary : Color.gray, width: 1)
                            .onTapGesture {
                                settings.selectedModel = model
                            }
                    }
                }
            }
            
            if settings.debugMode, let doc = vm.pdfDocument {
                NavigationLink(destination: DebugPageView(document: doc, pageIndex: 0)) {
                    Text("Open Visual Debugger")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .border(Color.primary, width: 1)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.systemGray6))
        .background(
            Rectangle()
                .frame(height: 3)
                .foregroundColor(.primary)
                .offset(y: -3),
            alignment: .top
        )
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(.primary)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}
