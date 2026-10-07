//
//  VisionEngine.swift
//  ePdfUB
//
//  Created by 魏嘉賢 on 2026/6/13.
//

import Foundation
import CoreML
import Vision
import Combine

// MARK: - 可用的 AI 模型清單

/// 定義可用的視覺辨識模型
public enum VisionModelType: String, CaseIterable, Identifiable {
    case yoloMedium = "YOLOv26 Medium (yolo26m-doclaynet)"
    case yoloStandard = "YOLOv26 Small (yolo26s-doclaynet)"
    case yoloFast = "YOLOv26 Nano (yolo26n-doclaynet)"
    
    public var id: String { self.rawValue }
}

// MARK: - Layout Block 資料結構

/// 代表單個排版區塊的幾何與語意資訊
public struct LayoutBlock: Identifiable {
    public let id = UUID()
    public let boundingBox: CGRect // 全域正規化座標 (0~1)，原點位於左下角 (遵循 Vision 標準)
    public let label: String
    public let confidence: Float
}

// MARK: - 抽象解析器介面

/// 所有版面解析器必須實作的共用介面
public protocol LayoutParser {
    func detectLayout(in cgImage: CGImage) async -> [LayoutBlock]
}

// MARK: - AI 視覺辨識引擎工廠 (Dynamic Dual-Engine)

/// 管理與切換視覺解析引擎
public class LayoutVisionManager: ObservableObject {
    public static let shared = LayoutVisionManager()
    
    @Published public var currentParserName: String = "Unknown"
    private var activeParser: LayoutParser?
    
    private init() {
        setupEngine()
    }
    
    /// 初始化或切換目前的視覺模型
    public func setupEngine() {
        let selectedModel = AppSettings.shared.selectedModel
        
        switch selectedModel {
        case .yoloMedium:
            self.activeParser = YOLOLayoutParser(modelName: "yolo26m-doclaynet")
            self.currentParserName = "Manual: YOLOv26m"
            AppLogger.shared.info("✅ 視覺引擎已切換為：YOLOv26m (Manual)")
        case .yoloStandard:
            self.activeParser = YOLOLayoutParser(modelName: "yolo26s-doclaynet")
            self.currentParserName = "Manual: YOLOv26s"
            AppLogger.shared.info("✅ 視覺引擎已切換為：YOLOv26s (Manual)")
        case .yoloFast:
            self.activeParser = YOLOLayoutParser(modelName: "yolo26n-doclaynet")
            self.currentParserName = "Manual: YOLOv26n"
            AppLogger.shared.info("✅ 視覺引擎已切換為：YOLOv26n (Manual)")
        }
    }
    
    /// 偵測影像中的排版區塊
    public func detectLayout(in cgImage: CGImage) async -> [LayoutBlock] {
        guard let parser = activeParser else { return [] }
        return await parser.detectLayout(in: cgImage)
    }
}

// MARK: - YOLOLayoutParser (Fallback Engine)

/// 基於 YOLO 模型的版面解析器，包含影像切片處理
class YOLOLayoutParser: LayoutParser {
    private var visionModel: VNCoreMLModel?
    private var targetSize: CGFloat = 640.0
    private let modelQueue = DispatchQueue(label: "com.flow.visionmodel.yolo")
    
    /// 初始化並載入指定的 YOLO 模型
    init(modelName: String) {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
#if !CLI_MODE
            let coreMLModel: MLModel
            let bundle = Bundle.main
            if let compiledURL = bundle.url(forResource: modelName, withExtension:"mlmodelc") {
                coreMLModel = try MLModel(contentsOf: compiledURL, configuration: config)
            } else if let packageURL = bundle.url(forResource: modelName, withExtension:"mlpackage") {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                coreMLModel = try MLModel(contentsOf: compiledURL, configuration: config)
            } else {
                fatalError("CoreML Model '\(modelName)' not found! Please ensure it is compiled via Xcode Build Phase.")
            }
#else
            // CLI 動態載入
            var actualModelName = modelName
            if modelName == "yolov11s-doclaynet" {
                actualModelName = "yolov10s_best"
            }
            
            guard let packageURL = Bundle.module.url(forResource: actualModelName, withExtension:"mlpackage") ??
                                   Bundle.module.url(forResource: actualModelName, withExtension:"mlpackage", subdirectory: "Models") else {
                fatalError("CoreML Model '\(actualModelName)' not found in CLI Bundle!")
            }
            let compiledURL = try MLModel.compileModel(at: packageURL)
            let coreMLModel = try MLModel(contentsOf: compiledURL, configuration: config)
#endif
            
            // 讀取模型的影像輸入限制
            if let imgConstraint = coreMLModel.modelDescription.inputDescriptionsByName["image"]?.imageConstraint {
                self.targetSize = CGFloat(imgConstraint.pixelsWide)
            }
            
            let newModel = try VNCoreMLModel(for: coreMLModel)
            
            var featureDict: [String: Any] = [:]
            if coreMLModel.modelDescription.inputDescriptionsByName["iouThreshold"] != nil {
                featureDict["iouThreshold"] = 0.45
            }
            if coreMLModel.modelDescription.inputDescriptionsByName["confidenceThreshold"] != nil {
                featureDict["confidenceThreshold"] = 0.25
            }
            
            if !featureDict.isEmpty {
                newModel.featureProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            }
            modelQueue.sync {
                self.visionModel = newModel
            }
        } catch {
            AppLogger.shared.error("❌ YOLO 模型載入失敗: \(error)")
        }
    }
    
    /// 執行版面偵測，支援對長圖進行自動切片
    func detectLayout(in cgImage: CGImage) async -> [LayoutBlock] {
        let currentModel = modelQueue.sync { self.visionModel }
        guard let model = currentModel else { return [] }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        let blocks = await self.processTile(tileImage: cgImage, tileRect: fullRect, fullWidth: width, fullHeight: height, model: model)
        
        // 執行 NMS 過濾重複框
        return applyNMS(blocks: blocks, iouThreshold: 0.5)
    }
    
    /// 處理單一影像切片的推論與座標轉換
    private func processTile(tileImage: CGImage, tileRect: CGRect, fullWidth: CGFloat, fullHeight: CGFloat, model: VNCoreMLModel) async -> [LayoutBlock] {
        return await withCheckedContinuation { continuation in
            let safeContinuation = SafeContinuation(continuation)
            let request = VNCoreMLRequest(model: model) { request, error in
                print("--- YOLO Request Finished ---")
                print("Error: \(String(describing: error))")
                print("Results count: \(request.results?.count ?? 0)")
                guard let results = request.results else {
                    safeContinuation.resume(returning: [])
                    return
                }
                
                var blocks: [LayoutBlock] = []
                
                // Case 1: Model has built-in NMS (VNRecognizedObjectObservation)
                if let objectResults = results as? [VNRecognizedObjectObservation] {
                    for obs in objectResults {
                        let localRect = obs.boundingBox // 0~1, origin bottom-left
                        let globalBoundingBox = self.toGlobalBoundingBox(localRect: localRect, tileRect: tileRect, fullWidth: fullWidth, fullHeight: fullHeight)
                        
                        if let topLabel = obs.labels.first {
                            blocks.append(LayoutBlock(boundingBox: globalBoundingBox, label: topLabel.identifier, confidence: topLabel.confidence))
                        }
                    }
                }
                // Case 2: Raw tensor output (nms=False)
                else if let featureResults = results as? [VNCoreMLFeatureValueObservation] {
                    var yolo10MultiArray: MLMultiArray?
                    var confArray: MLMultiArray?
                    var coordArray: MLMultiArray?
                    
                    for feature in featureResults {
                        guard let multiArray = feature.featureValue.multiArrayValue else { continue }
                        if multiArray.shape.count == 3 && multiArray.shape[2].intValue == 6 {
                            // YOLOv10 NMS-Free format: [1, 300, 6]
                            yolo10MultiArray = multiArray
                        } else if multiArray.shape.count >= 2 {
                            if multiArray.shape.last?.intValue == 4 {
                                coordArray = multiArray
                            } else {
                                confArray = multiArray
                            }
                        }
                    }
                    
                    let classes = ["Caption", "Footnote", "Formula", "List-item", "Page-footer", "Page-header", "Picture", "Section-header", "Table", "Text", "Title"]
                    
                    if let yolo10 = yolo10MultiArray {
                        // YOLOv10 processing
                        let numBoxes = yolo10.shape[1].intValue
                        let pointer = UnsafeMutablePointer<Float32>(OpaquePointer(yolo10.dataPointer))
                        let strideBox = yolo10.strides[1].intValue
                        let confThreshold: Float32 = 0.25
                        
                        // Vision's .scaleFit pads the image to fit targetSize.
                        // Coordinates (x1, y1, x2, y2) are in the targetSize space.
                        // We must map them back to the original tileImage coordinate space [0, 1].
                        let tileW = CGFloat(tileImage.width)
                        let tileH = CGFloat(tileImage.height)
                        let scale = min(self.targetSize / tileW, self.targetSize / tileH)
                        let scaledW = tileW * scale
                        let scaledH = tileH * scale
                        let padX = (self.targetSize - scaledW) / 2.0
                        let padY = (self.targetSize - scaledH) / 2.0
                        
                        for b in 0..<numBoxes {
                            let conf = pointer[b * strideBox + 4]
                            if conf > confThreshold {
                                let x1 = pointer[b * strideBox + 0]
                                let y1 = pointer[b * strideBox + 1]
                                let x2 = pointer[b * strideBox + 2]
                                let y2 = pointer[b * strideBox + 3]
                                let classIdx = Int(pointer[b * strideBox + 5])
                                
                                // Remove padding and normalize to [0, 1] relative to tileImage
                                let nx1 = CGFloat(x1 - Float32(padX)) / scaledW
                                let ny1 = CGFloat(y1 - Float32(padY)) / scaledH
                                let nx2 = CGFloat(x2 - Float32(padX)) / scaledW
                                let ny2 = CGFloat(y2 - Float32(padY)) / scaledH
                                
                                // Clamp to valid area
                                let minX_norm = max(0.0, min(1.0, nx1))
                                let maxX_norm = max(0.0, min(1.0, nx2))
                                let minY_norm = max(0.0, min(1.0, ny1))
                                let maxY_norm = max(0.0, min(1.0, ny2))
                                
                                let nw = maxX_norm - minX_norm
                                let nh = maxY_norm - minY_norm
                                
                                // Ignore invalid boxes
                                if nw <= 0 || nh <= 0 { continue }
                                
                                // Convert to Core Graphics coordinate system (Y inverted)
                                let minY = 1.0 - maxY_norm
                                let localRect = CGRect(x: minX_norm, y: minY, width: nw, height: nh)
                                
                                let globalBoundingBox = self.toGlobalBoundingBox(localRect: localRect, tileRect: tileRect, fullWidth: fullWidth, fullHeight: fullHeight)
                                
                                let label = classIdx < classes.count ? classes[classIdx] : "Unknown"
                                blocks.append(LayoutBlock(boundingBox: globalBoundingBox, label: label, confidence: conf))
                            }
                        }
                    }
                    else if let confArray = confArray, let coordArray = coordArray {
                        let numAnchors = confArray.shape[0].intValue
                        let numClasses = min(confArray.shape[1].intValue, 11)
                        
                        let confPointer = UnsafeMutablePointer<Float32>(OpaquePointer(confArray.dataPointer))
                        let coordPointer = UnsafeMutablePointer<Float32>(OpaquePointer(coordArray.dataPointer))
                        
                        let confStrideAnchor = confArray.strides[0].intValue
                        let confStrideClass = confArray.strides[1].intValue
                        
                        let coordStrideAnchor = coordArray.strides[0].intValue
                        let coordStrideDim = coordArray.strides[1].intValue
                        
                        let confThreshold: Float32 = 0.25
                        
                        for a in 0..<numAnchors {
                            var maxConf: Float32 = 0
                            var maxClassIdx: Int = 0
                            
                            for c in 0..<numClasses {
                                let conf = confPointer[a * confStrideAnchor + c * confStrideClass]
                                if conf > maxConf {
                                    maxConf = conf
                                    maxClassIdx = c
                                }
                            }
                            
                            if maxConf > confThreshold {
                                let cx = coordPointer[a * coordStrideAnchor + 0 * coordStrideDim]
                                let cy = coordPointer[a * coordStrideAnchor + 1 * coordStrideDim]
                                let w  = coordPointer[a * coordStrideAnchor + 2 * coordStrideDim]
                                let h  = coordPointer[a * coordStrideAnchor + 3 * coordStrideDim]
                                
                                let nx = cx > 2.0 ? cx / Float32(self.targetSize) : cx
                                let ny = cy > 2.0 ? cy / Float32(self.targetSize) : cy
                                let nw = w > 2.0 ? w / Float32(self.targetSize) : w
                                let nh = h > 2.0 ? h / Float32(self.targetSize) : h
                                
                                let minX = CGFloat(nx - nw / 2)
                                let minY = CGFloat(1.0 - (ny + nh / 2))
                                let localRect = CGRect(x: minX, y: minY, width: CGFloat(nw), height: CGFloat(nh))
                                let globalBoundingBox = self.toGlobalBoundingBox(localRect: localRect, tileRect: tileRect, fullWidth: fullWidth, fullHeight: fullHeight)
                                
                                let label = maxClassIdx < classes.count ? classes[maxClassIdx] : "Unknown"
                                blocks.append(LayoutBlock(boundingBox: globalBoundingBox, label: label, confidence: maxConf))
                            }
                        }
                        blocks = self.applyNMS(blocks: blocks, iouThreshold: 0.45)
                    }
                }
                
                safeContinuation.resume(returning: blocks)
            }
            
            request.imageCropAndScaleOption = .scaleFit
            
            let handler = VNImageRequestHandler(cgImage: tileImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                AppLogger.shared.error("YOLO 切片推論失敗: \(error)")
                safeContinuation.resume(returning: [])
            }
        }
    }
    
    /// 將切片的區域座標轉換回全圖的正規化座標
    private func toGlobalBoundingBox(localRect: CGRect, tileRect: CGRect, fullWidth: CGFloat, fullHeight: CGFloat) -> CGRect {
        let localPixelWidth = localRect.width * tileRect.width
        let localPixelHeight = localRect.height * tileRect.height
        let localPixelX = localRect.minX * tileRect.width
        let localPixelY = localRect.minY * tileRect.height
        
        let tileBottomYFromTop = tileRect.maxY
        let tileBottomYFromBottom = fullHeight - tileBottomYFromTop
        
        let globalPixelX = tileRect.minX + localPixelX
        let globalPixelY = tileBottomYFromBottom + localPixelY
        
        let globalNormalizedX = globalPixelX / fullWidth
        let globalNormalizedY = globalPixelY / fullHeight
        let globalNormalizedWidth = localPixelWidth / fullWidth
        let globalNormalizedHeight = localPixelHeight / fullHeight
        
        return CGRect(x: globalNormalizedX, y: globalNormalizedY, width: globalNormalizedWidth, height: globalNormalizedHeight)
    }
    
    /// 執行非極大值抑制 (NMS) 過濾重疊的偵測框
    private func applyNMS(blocks: [LayoutBlock], iouThreshold: Float) -> [LayoutBlock] {
        let sortedBlocks = blocks.sorted { $0.confidence > $1.confidence }
        var keep: [LayoutBlock] = []
        
        for block in sortedBlocks {
            var shouldKeep = true
            for keptBlock in keep {
                if block.label == keptBlock.label {
                    let intersection = block.boundingBox.intersection(keptBlock.boundingBox)
                    if !intersection.isNull {
                        let intersectionArea = intersection.width * intersection.height
                        let area1 = block.boundingBox.width * block.boundingBox.height
                        let area2 = keptBlock.boundingBox.width * keptBlock.boundingBox.height
                        let unionArea = area1 + area2 - intersectionArea
                        let iou = intersectionArea / unionArea
                        
                        if iou > CGFloat(iouThreshold) {
                            shouldKeep = false
                            break
                        }
                    }
                }
            }
            if shouldKeep {
                keep.append(block)
            }
        }
        
        return keep
    }
}

fileprivate class SafeContinuation<T> {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()
    
    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }
    
    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        if let c = continuation {
            c.resume(returning: value)
            continuation = nil
        }
    }
}
