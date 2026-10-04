---
name: pdflux-architecture
description: 確保 PDFlux 的排版引擎、EPUB 打包與視覺區塊處理的架構完整性與設計準則
trigger: always_on
---

# PDFlux Architecture & Guidelines

這份規則記錄了我們為了讓 `PDFlux` 達到「Publisher-Grade Output (出版社級別的電子書)」所確立的核心架構與設計決策。
任何對 PDF 解析、排版引擎、或是 EPUB 打包的修改，都必須遵守以下準則：

## 1. 視覺區塊 (Visual Regions) 的生命週期與排序
- **嚴禁在最後階段切割與附加圖片**：所有的視覺區塊 (`.picture`, `.table`, `.formula`, `.figure`) 必須在 `BatchProcessor.swift` 的 STAGE 2.6 被轉換為 `TextFragment`（`fontName` 設為 `nil`）。
- **交由引擎排序**：將圖片轉為 `TextFragment` 後，必須讓 `LayoutEngine` 透過原生幾何演算法統一進行 Y 軸排序，確保圖片、表格能正確穿插在文字段落之間，而不是全部擠在頁首。

## 2. 跨頁段落的無縫縫合 (Cross-Page Stitching)
- 處理跨頁的句子斷裂，**不要**在區塊 (Block) 層級維護狀態機，這太複雜且容易出錯。
- **統一交給字串替換**：在 `BatchProcessor.swift` 結束所有頁面處理後，呼叫 `LayoutEngine.stitchCrossPageParagraphs(html: fullHTML)`。
- **啟發式法則**：利用正則表達式，若前一頁最後一個字元不是終結標點符號 (`. ! ? 。 ！ ？ ： ； " '`)，且下一頁第一個字元是字母或中文，則移除換頁所產生的 `</p> <p class="doc-body">` 進行無縫合併。

## 3. EPUB 樣式與排版美學 (Apple Books Native Style)
- **CSS 準則**：在 `EPUBSynthesizer` 內產生的 XHTML 必須使用無襯線字體 (`font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;`)，並且實作響應式的 `@media (prefers-color-scheme: dark)`。
- **字體大小適應性 (Relative Sizing)**：
  - 絕對禁止在 HTML `style` 寫死絕對字體大小 (例如 `font-size: 14px;`)，因為這會破壞電子書閱讀器讓讀者自行調整字體的權利。
  - 必須將 `TextFragment.fontSize` 除以 PDF 的基礎字體大小 (`baseFontSize`) 轉換為相對單位 (例如 `font-size: 1.25em;`)。
- **原始字體名稱還原**：
  - `TextFragment` 應盡量保存從 PDFKit 抽取的 `fontName`。
  - 在 `LayoutEngine.toHTML` 中，若 `fontName` 存在且非系統字體 (不含 `System` 或 `UI`)，則以 `font-family: 'OriginalName', sans-serif;` 寫入，讓有支援的閱讀器 (如 Apple Books 的 Publisher Font 模式) 能夠完美還原原始字體。

## 4. 多層級精準目錄 (TOC Generation)
- **依賴 HTML 標籤而非外部陣列**：不要手動維護目錄陣列。只要確保 `.title` 被輸出為 `<h1>`，`.heading` 被輸出為 `<h2>`，`EPUBSynthesizer.injectHeadingIDs` 就會自動掃描整份 HTML，自動注入 `id` 並生成合規的 `toc.ncx` 與 `nav.xhtml` 多層級大綱。

## 5. EPUB 檔案合規性 (Stored-ZIP)
- Apple Books 對 EPUB 格式極度嚴格。必須確保 `mimetype` 是 ZIP 壓縮檔的**第一個檔案**，而且絕對**不可被壓縮 (Stored-Mode)**，且不能包含 Extra Field。
- 請勿隨意更換 `EPUBSynthesizer` 底層的 `StoredZIPArchive` 實作。

## 6. CLI 批次處理管線 (CLI Pipeline)
- **獨立的 Target**：CLI 是一個獨立的 Swift Executable Target (`Flow_CLI`)，與 iOS App 共用相同的核心引擎 (如 `BatchProcessor`, `VisionEngine`)。
- **參數與資源綁定**：CLI 模式下，必須正確解析引數 `[nano|small|medium]`，並且 CoreML 模型權重已經透過 `Package.swift` 與實體資料夾複製 (`Models/`) 完整封裝進 CLI，確保 100% 離線可用。
- **無縫產出 EPUB**：CLI 的輸出應與 iOS App 一致，直接調用 `BatchProcessor` 並將最終的 `exportedFileURL` (EPUB) 搬移至使用者指定的 `output.epub` 路徑。

## 7. AI 模型選擇與 Benchmark 評估準則 (Model Selection & Benchmarking)
- **預設模型 (Default Model)**：無論是 iOS App 或是 CLI 模式，**皆必須將 `Nano` (`yoloFast`) 設為系統預設模型**。根據大規模基準測試，Nano 在維持最低錯誤率與最高排版保留率的同時，具備最快的執行速度與最低的硬體消耗。
- **全資料集測試防呆 (Avoid Small-Sample Bias)**：過去在開發時曾因僅隨機抽取 50 筆樣本進行測試，導致嚴重的統計偏見（誤以為 Medium 模型準確度遠勝 Nano）。未來的任何架構改動，若需進行模型性能評估，**必須強制跑完完整的 `marker_benchmark` (2,138 筆) 資料集**，嚴禁依賴小樣本子集來做出架構決策。
