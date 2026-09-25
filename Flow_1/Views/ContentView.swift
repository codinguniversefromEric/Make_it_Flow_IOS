import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import QuickLook

// MARK: - 動畫狀態

// 動畫狀態枚舉
enum AnimationState {
    case idle
    case showingThumbnail
    case suckingToIsland
    case processing
}

// MARK: - 主畫面整合
// 應用程式主畫面整合視圖
struct ContentView: View {
    @StateObject private var vm = ContentViewModel()
    @State private var isEditing = false
    @State private var selectedItems = Set<UUID>()
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // 乾淨的背景
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            // 1. 原生導航列與主內容
            NavigationView {
                mainContentView
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if isEditing {
                                Button {
                                    if selectedItems.count == vm.libraryStore.items.count && !vm.libraryStore.items.isEmpty {
                                        selectedItems.removeAll()
                                    } else {
                                        selectedItems = Set(vm.libraryStore.items.map { $0.id })
                                    }
                                } label: {
                                    Text(selectedItems.count == vm.libraryStore.items.count && !vm.libraryStore.items.isEmpty ? "Deselect All" : "Select All")
                                }
                            } else {
                                Button { vm.isSettingsPresented = true } label: { Label("Preferences", systemImage: "slider.horizontal.3") }
                                    .accessibilityLabel("Settings")
                                    .accessibilityHint("Open app preferences")
                            }
                        }
                        ToolbarItem(placement: .principal) {
                            Text("flow")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .tracking(-1.5)
                                .foregroundColor(.primary)
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                withAnimation {
                                    isEditing.toggle()
                                    if !isEditing {
                                        selectedItems.removeAll()
                                    }
                                }
                            } label: {
                                Text(isEditing ? "Done" : "Edit")
                                    .fontWeight(.medium)
                            }
                            if !isEditing {
                                Button(action: { vm.showFilePicker = true }) {
                                    Image(systemName: "plus")
                                        .font(.headline)
                                }
                                .accessibilityLabel("Add PDF")
                                .accessibilityHint("Open file picker to select a PDF for conversion")
                            }
                        }
                    }
                    .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            }
            .navigationViewStyle(.stack)
            

            
            // 流暢的水波紋動畫層
            animationOverlay
            
            // 全螢幕打勾動畫 HUD (FaceID Style)
            if vm.showSuccessHUD {
                FaceIDCheckmarkView()
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 30, y: 15)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .zIndex(100)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Conversion complete")
                    .accessibilityAddTraits(.isStaticText)
            }
        }

        .sheet(isPresented: $vm.showFilePicker) {
            PDFDocumentPicker { url in
                vm.handlePickedPDF(url: url)
            }
        }
        .sheet(isPresented: $vm.isSettingsPresented) {
            SettingsView()
        }
        .onChange(of: vm.batchProcessor.exportedFileURL) { newURL in
            if let epubURL = newURL {
                vm.finishConversion(epubURL: epubURL)
            }
        }
        .alert("Conversion Error", isPresented: $vm.showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.errorMessage)
        }
        .onOpenURL { url in
            // Hook Model: External Trigger - Receive shared PDF from Safari/Files
            if url.pathExtension.lowercased() == "pdf" {
                vm.handlePickedPDF(url: url)
            }
        }
    }
}

// MARK: - UI 元件擴充
extension ContentView {
        
        @ViewBuilder
        private var mainContentView: some View {
            if let document = vm.pdfDocument {
                if vm.settings.debugMode {
                    documentDebugView(document)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                homeLibraryView
            }
        }
        
        // 🌟 YOLO Debug 視圖 (包含返回按鈕)
        private func documentDebugView(_ document: PDFDocument) -> some View {
            VStack(spacing: 0) {
                // 頂部控制列
                HStack {
                    Button {
                        vm.pdfDocument = nil
                        vm.batchProcessor.cancel()
                    } label: {
                        Label("Close Debug", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    .accessibilityLabel("Close debug view")
                    .accessibilityHint("Return to the library")
                    Spacer()
                    Text("YOLO Debug Mode")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(.regularMaterial)
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            DebugPageView(document: document, pageIndex: index)
                        }
                    }
                }
                .id("\(document.documentURL?.absoluteString ?? UUID().uuidString)-\(vm.settings.debugMode)")
            }
        }
        
        // 🌟 統一的首頁書庫 (Home Library)
        // 首頁書庫視圖
        private var homeLibraryView: some View {
            ZStack {
                ScrollView {
                    if vm.libraryStore.items.isEmpty {
                        emptyLibraryView
                    } else {
                        populatedLibraryView
                    }
                }
                
                .safeAreaInset(edge: .bottom) {
                    if isEditing {
                        VStack(spacing: 0) {
                            Divider()
                            Button(role: .destructive) {
                                withAnimation {
                                    let itemsToDelete = vm.libraryStore.items.filter { selectedItems.contains($0.id) }
                                    for item in itemsToDelete {
                                        vm.libraryStore.deleteItem(item)
                                    }
                                    selectedItems.removeAll()
                                    isEditing = false
                                }
                            } label: {
                                Text("Delete Selected (\(selectedItems.count))")
                                    .font(.headline)
                                    .foregroundColor(selectedItems.isEmpty ? .gray : .red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                            .disabled(selectedItems.isEmpty)
                            .background(.ultraThinMaterial)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                // 全域拖曳高亮遮罩
                if vm.dragOver {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                        )
                        .padding(16)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.2), value: vm.dragOver)
                        .accessibilityLabel("Drop zone active. Release to import PDF")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.pdf], isTargeted: $vm.dragOver) { providers in vm.handleDrop(providers) }
        }
        
        @ViewBuilder
        private var emptyLibraryView: some View {
            VStack(spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 72))
                    .foregroundColor(Color.secondary.opacity(0.3))
                Text("Library is empty")
                    .font(.title2.weight(.bold))
                Text("Drag & drop PDFs here\nor tap '+' to add")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 160)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Library is empty. Drag a PDF here or tap the add button to get started.")
            
        }
        
        @ViewBuilder
        private var populatedLibraryView: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                ForEach(vm.libraryStore.items) { file in
                    VStack {
                        if let thumb = vm.libraryStore.loadThumbnail(for: file) {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 180)
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.secondarySystemFill))
                                .frame(height: 180)
                        }
                        Text(file.title)
                            .font(.caption).fontWeight(.medium).foregroundColor(.primary)
                            .lineLimit(1).padding(.top, 8)
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    .overlay(
                        Group {
                            if !isEditing {
                                if #available(iOS 16.0, *) {
                                    ShareLink(item: file.url) {
                                        Color.clear
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if isEditing {
                            Image(systemName: selectedItems.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundColor(selectedItems.contains(file.id) ? .blue : .gray.opacity(0.5))
                                .background(Circle().fill(Color.white))
                                .offset(x: -12, y: -12)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .onTapGesture {
                        if isEditing {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                if selectedItems.contains(file.id) {
                                    selectedItems.remove(file.id)
                                } else {
                                    selectedItems.insert(file.id)
                                }
                            }
                        }
                    }
                    .contextMenu {
                        if #available(iOS 16.0, *) {
                            ShareLink(item: file.url) {
                                Label("Share EPUB", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            vm.libraryStore.deleteItem(file)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(file.title)
                    .accessibilityHint("Long press to share this EPUB")
                }
            }
            .padding(24)
            .padding(.bottom, 80)
        }
        
        // 🌟 原生浮動按鈕 (已移除，改由右上角 ToolbarItem 處理)
        // MARK: 動畫層
        @ViewBuilder
        private var animationOverlay: some View {
            if vm.animState != .idle {
                GeometryReader { geo in
                    let islandY: CGFloat = 32
                    
                    ZStack(alignment: .top) {
                        
                        if vm.animState == .showingThumbnail || vm.animState == .suckingToIsland {
                            Color.black.opacity(vm.animState == .showingThumbnail ? 0.15 : 0.0)
                                .ignoresSafeArea()
                                .animation(.easeInOut(duration: 0.3), value: vm.animState)
                            
                            if let thumb = vm.currentThumbnail {
                                Image(uiImage: thumb)
                                    .resizable().scaledToFit().frame(width: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                                    .position(
                                        x: geo.size.width / 2,
                                        y: vm.animState == .showingThumbnail ? (geo.size.height / 2) : islandY - 100
                                    )
                                    .scaleEffect(vm.animState == .showingThumbnail ? 1.0 : 0.02)
                                    .opacity(vm.animState == .suckingToIsland ? 0.0 : 1.0)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: vm.animState)
                            }
                        }
                        
                        if vm.animState == .processing {
                            ZStack {
                                GlassLiquidView(progress: vm.batchProcessor.progress, islandY: islandY)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                                
                                // 原生取消按鈕 (Visibility of System Status)
                                VStack(spacing: 12) {
                                    Spacer()
                                    
                                    Button(role: .cancel, action: {
                                        vm.cancelProcessing()
                                    }) {
                                        Label("Cancel", systemImage: "xmark.circle.fill")
                                            .font(.headline)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.accentColor)
                                    .accessibilityLabel("Cancel conversion")
                                    .accessibilityHint("Stop the current PDF to EPUB conversion")
                                    .controlSize(.large)
                                    .shadow(color: .accentColor.opacity(0.2), radius: 5, y: 2)
                                }
                                .padding(.bottom, 60)
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
    
