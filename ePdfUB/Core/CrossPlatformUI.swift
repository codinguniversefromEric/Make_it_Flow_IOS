//
//  CrossPlatformUI.swift
//  ePdfUB
//
//  Created by Libri-AI on 2026/07/08.
//

import Foundation

// MARK: - iOS Platform

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
public typealias AppColor = UIColor
public typealias AppImage = UIImage
public typealias AppFont = UIFont

extension AppFont {
    public var isAppFontBold: Bool {
        return self.fontDescriptor.symbolicTraits.contains(.traitBold)
    }
}

extension AppImage {
    public convenience init(cgImage: CGImage, size: CGSize) {
        self.init(cgImage: cgImage)
    }

    public func appJPEGData(compressionQuality: CGFloat) -> Data? {
        return self.jpegData(compressionQuality: compressionQuality)
    }
}
// MARK: - macOS Platform

#elseif os(macOS)
import AppKit
public typealias AppColor = NSColor
public typealias AppImage = NSImage
public typealias AppFont = NSFont

extension AppFont {
    public var isAppFontBold: Bool {
        return self.fontDescriptor.symbolicTraits.contains(.bold)
    }
}

extension NSImage {
    public var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    
    public func appJPEGData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage = self.cgImage else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: compressionQuality]
        return bitmapRep.representation(using: .jpeg, properties: properties)
    }
}
#endif
