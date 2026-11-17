//
//  LibraryStore.swift
//  ePdfUB
//
//  Persistent library storage for converted EPUB files.
//

import UIKit
import Combine

// MARK: - 資料模型
// 書庫項目資料模型
struct LibraryItem: Codable, Identifiable {
    let id: UUID
    var url: URL
    let title: String
    let createdAt: Date
    let diagnosticsSummary: String
    var thumbnailFilename: String?

    static func readingPositionKey(_ id: UUID) -> String {
        "epubReadingPosition.\(id.uuidString)"
    }
}

// MARK: - 持久化書庫
// 負責管理與持久化 EPUB 書庫
class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var items: [LibraryItem] = []
    
    private var thumbnailCache: [UUID: UIImage] = [:]

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var libraryFileURL: URL {
        documentsDirectory.appendingPathComponent("library.json")
    }

    private var thumbnailsDirectory: URL {
        documentsDirectory.appendingPathComponent("thumbnails")
    }

    private init() {
        ensureThumbnailsDirectory()
        load()
    }

    // MARK: - Public

    func addItem(url: URL, title: String, thumbnail: UIImage?, diagnosticsSummary: String) throws -> LibraryItem {
        var thumbnailFilename: String? = nil
        let newId = UUID()
        let storedURL = try storeBook(at: url, id: newId)

        if let thumbnail = thumbnail,
           let data = thumbnail.jpegData(compressionQuality: 0.7) {
            let filename = newId.uuidString + ".jpg"
            let fileURL = thumbnailsDirectory.appendingPathComponent(filename)
            if (try? data.write(to: fileURL, options: .atomic)) != nil {
                thumbnailFilename = filename
                thumbnailCache[newId] = thumbnail
            }
        }

        let item = LibraryItem(
            id: newId,
            url: storedURL,
            title: title,
            createdAt: Date(),
            diagnosticsSummary: diagnosticsSummary,
            thumbnailFilename: thumbnailFilename
        )

        let updatedItems = items + [item]
        do {
            try save(updatedItems)
        } catch {
            removeFiles(for: item)
            throw error
        }
        items = updatedItems
        return item
    }

    func loadThumbnail(for item: LibraryItem) -> UIImage? {
        if let cached = thumbnailCache[item.id] {
            return cached
        }
        guard let filename = item.thumbnailFilename else { return nil }
        let fileURL = thumbnailsDirectory.appendingPathComponent(filename)
        if let image = UIImage(contentsOfFile: fileURL.path) {
            thumbnailCache[item.id] = image
            return image
        }
        return nil
    }

    func deleteItem(_ item: LibraryItem) throws {
        let updatedItems = items.filter { $0.id != item.id }
        try save(updatedItems)
        items = updatedItems
        removeFiles(for: item)
        UserDefaults.standard.removeObject(forKey: LibraryItem.readingPositionKey(item.id))
    }

    // MARK: - Private

    private func bookDirectory(for id: UUID) -> URL {
        documentsDirectory
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func storeBook(at url: URL, id: UUID) throws -> URL {
        let directory = bookDirectory(for: id)
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: url, to: destination)
            return destination
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    private func removeFiles(for item: LibraryItem) {
        if let filename = item.thumbnailFilename {
            try? fileManager.removeItem(at: thumbnailsDirectory.appendingPathComponent(filename))
        }
        try? fileManager.removeItem(at: bookDirectory(for: item.id))
        thumbnailCache.removeValue(forKey: item.id)
    }

    private func save(_ items: [LibraryItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: libraryFileURL, options: .atomic)
    }

    private func load() {
        guard fileManager.fileExists(atPath: libraryFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: libraryFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let savedItems = try decoder.decode([LibraryItem].self, from: data)
            items = savedItems.map { item in
                var item = item
                let storedURL = bookDirectory(for: item.id).appendingPathComponent(item.url.lastPathComponent)
                let legacyURL = fileManager.temporaryDirectory.appendingPathComponent(item.url.lastPathComponent)
                if fileManager.fileExists(atPath: storedURL.path) {
                    item.url = storedURL
                } else if item.url.deletingLastPathComponent().lastPathComponent == "tmp",
                          let migratedURL = try? storeBook(at: legacyURL, id: item.id) {
                    item.url = migratedURL
                }
                return item
            }
        } catch {
            print("LibraryStore: Failed to load — \(error)")
        }
    }

    private func ensureThumbnailsDirectory() {
        if !fileManager.fileExists(atPath: thumbnailsDirectory.path) {
            try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        }
    }
}
