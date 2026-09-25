//
//  ContentViewModel.swift
//  Flow_1
//
//  ViewModel for the main content view, managing state and business logic.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import Combine

@MainActor
// 負責主畫面狀態與業務邏輯的 ViewModel
class ContentViewModel: ObservableObject {
    // MARK: - Dependencies
    let batchProcessor = BatchProcessor()
    let libraryStore = LibraryStore.shared
    let settings = AppSettings.shared
    
    // MARK: - UI State
    @Published var showFilePicker = false
    @Published var isSettingsPresented = false
    @Published var dragOver = false
    @Published var showSuccessHUD = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""

    
    // MARK: - Document State
    @Published var pdfDocument: PDFDocument? = nil
    @Published var animState: AnimationState = .idle
    @Published var currentThumbnail: UIImage? = nil

    
    // MARK: - Combine: Forward nested ObservableObject changes
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // SwiftUI only observes @Published on this ViewModel.
        // Nested ObservableObjects must forward their changes manually.
        batchProcessor.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        

        libraryStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: Notification.Name("CancelConversionActivity"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.batchProcessor.cancel()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Business Logic
    
    // 處理檔案拖放邏輯
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) else { return false }
        
        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] url, error in
            guard let url = url else { return }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
                DispatchQueue.main.async { self?.handlePickedPDF(url: tempURL) }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to import PDF: \(error.localizedDescription)"
                    self?.showErrorAlert = true
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
        return true
    }
    
    // 處理使用者選擇的 PDF 檔案
    func handlePickedPDF(url: URL) {
        showFilePicker = false
        
        Task { @MainActor in
            // 將產生縮圖與讀取龐大 PDF 移至背景執行，避免卡死主畫面 UI (Issue: 點擊延遲 1 秒)
            let (thumbnail, doc) = await Task.detached(priority: .utility) {
                let t = self.generatePDFThumbnail(from: url)
                let d = PDFDocument(url: url)
                return (t, d)
            }.value
            
            self.currentThumbnail = thumbnail
            withAnimation { animState = .showingThumbnail }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            // 縮短人工等待時間，讓 UI 更輕快流暢
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation { animState = .suckingToIsland }
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation { animState = .processing }
            
            if let doc = doc {
                self.pdfDocument = doc
                let fileName = url.deletingPathExtension().lastPathComponent
                await batchProcessor.exportDocument(doc, fileName: fileName)
                
                if batchProcessor.exportedFileURL == nil {
                    withAnimation { 
                        animState = .idle 
                        self.pdfDocument = nil
                        self.currentThumbnail = nil
                    }
                    if !batchProcessor.isCancelled {
                        errorMessage = "Conversion failed. Please try again."
                        showErrorAlert = true
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            } else {
                withAnimation { 
                    animState = .idle 
                    self.pdfDocument = nil
                    self.currentThumbnail = nil
                }
                errorMessage = "Unable to open PDF file. The file may be corrupted or password-protected."
                showErrorAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
    
    // 完成轉換後的處理邏輯
    func finishConversion(epubURL: URL) {
        libraryStore.addItem(
            url: epubURL,
            title: epubURL.deletingPathExtension().lastPathComponent,
            thumbnail: self.currentThumbnail,
            diagnosticsSummary: ""
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            withAnimation(.easeInOut(duration: 0.5)) {
                animState = .idle
                currentThumbnail = nil
                
                if !settings.debugMode {
                    pdfDocument = nil
                    batchProcessor.exportedFileURL = nil
                    showSuccessHUD = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    scheduleHUDDismiss()
                }
            }
        }
    }
    

    
    private func scheduleHUDDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) {
                self.showSuccessHUD = false
            }
        }
    }
    
    // 取消當前處理作業
    func cancelProcessing() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        batchProcessor.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            animState = .idle
            currentThumbnail = nil
            pdfDocument = nil
            batchProcessor.exportedFileURL = nil
        }
    }
    
    // 從 PDF 產生縮圖
    nonisolated func generatePDFThumbnail(from url: URL) -> UIImage? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
        
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        let thumbnailWidth: CGFloat = 300
        let scale = thumbnailWidth / pageRect.width
        let thumbnailSize = CGSize(width: thumbnailWidth, height: pageRect.height * scale)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        return renderer.image { ctx in
            UIColor.white.set(); ctx.fill(CGRect(origin: .zero, size: thumbnailSize))
            ctx.cgContext.translateBy(x: 0.0, y: thumbnailSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}
