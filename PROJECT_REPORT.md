# ePdfUB 專案結案報告

## 1. 專案概述與已完成項目 (What We Achieved)

在開發 ePdfUB 的過程中，我們成功打造了一套以「出版社級別 (Publisher-Grade Output)」為目標的 PDF 轉 EPUB 引擎，主要成就包含：

*   **雙平台共用核心架構：** 
    建立 iOS App 與獨立的 macOS CLI (`ePdfUB_CLI`) 雙端點，兩者共用核心解析引擎 (`BatchProcessor`, `VisionEngine`)，並將 CoreML 模型完整封裝，確保工具達到 100% 離線可用。
*   **智慧化視覺排版引擎 (Vision Layout Engine)：** 
    整合 CoreML 模型進行文件區塊 (Text, Picture, Table, Heading) 辨識。我們徹底改善了區塊的生命週期，將圖片與表格轉換為 `TextFragment` 並交由引擎進行嚴格的 Y 軸幾何排序，確保所有視覺元素能精準、合理地穿插於文字段落之間，解決了圖片全擠在頁首的問題。
*   **跨頁段落縫合 (Cross-Page Stitching)：** 
    實作了一套啟發式正則表達式，能自動判定並無縫合併因 PDF 實體換頁造成的段落截斷、英文單字斷字 (Hyphenation) 等問題，大幅提升電子書的閱讀流暢度。
*   **Apple Books 極致美學與 EPUB 標準合規：**
    *   **無縫適應性：** 產出的 HTML 完全支援響應式深色模式 `@media (prefers-color-scheme: dark)`。
    *   **相對字體與原始字體保留：** 放棄絕對字體大小 (px)，改用 `em` 相對單位，把調整字體的權力還給讀者；同時盡可能保留從 PDFKit 提取的原始 `fontName`。
    *   **檔案合規性與自動目錄：** 嚴格遵守 EPUB 規範（`mimetype` Stored-Mode ZIP 第一檔案限制），並透過 HTML Tag 掃描自動生成多層級的精準目錄 (TOC)。
*   **工程化發布管線 (DevOps & Marketing)：** 
    完成 Fastlane 自動化發布配置、App 版本的動態模型瘦身 (發布版鎖定 Nano 模型)，並建置了多語系 (中/英文) 的 Landing Page 與隱私權政策。

---

## 2. 目前限制與技術債 (Limitations)

儘管核心功能已經完備，目前系統仍有幾個明確的限制與待解決的技術債：

*   **表格儲存格 (Cell) 級別的辨識限制：** 
    目前的 DocLayNet 模型缺乏細粒度的表格儲存格辨識能力 (如 `TableReconstructor.swift` 中的已知 `FIXME`)。遇到複雜表格時，難以完美還原成精確的 HTML `<table>` 結構。
*   **跨頁縫合的極端邊界情況 (Edge Cases)：** 
    目前的跨頁縫合機制過度依賴字串正則表達式 (Regex)。如果下一頁的第一個字元是標點符號 (例如中文前引號 `「` 或英文括號 `(`)，或者跨頁段落之間剛好夾雜了一張圖片標籤，目前的 Regex 就會失效，導致段落無法完美縫合。
*   **模型效能評估的取樣成本：** 
    過去曾因抽樣過少 (50筆) 導致統計偏誤。我們確立了未來必須跑完完整的 `marker_benchmark` (2,138 筆) 才能進行決策。這意味著任何模型的抽換與測試，都需要耗費龐大的運算時間與硬體成本。

---

## 3. 未來展望 (Future Prospects)

基於上述限制與現有基礎，未來的產品演進方向可聚焦於：

*   **演算法升級與 DOM 級別的縫合：** 
    將跨頁縫合 (Cross-Page Stitching) 的邏輯從單純的字串 Regex，升級為基於 HTML DOM 結構的解析器，使其能智慧地繞過圖片標籤，並包容所有標點符號的邊界情況。
*   **導入進階表格重建模型：** 
    探索並整合具備 Cell 級別辨識能力的新一代輕量化模型 (如 LayoutLM 變體)，徹底解決複雜 PDF 表格轉譯為 EPUB 的排版痛點。
*   **CLI 管線與出版社工作流整合：** 
    擴充 `ePdfUB_CLI` 的功能，允許傳入自訂的 CSS 樣式表、字體映射檔 (Font Mapping)。這能讓此工具無縫嵌入傳統出版社的大型自動化排版系統 (Pipeline)，成為業界標準的轉換工具。
