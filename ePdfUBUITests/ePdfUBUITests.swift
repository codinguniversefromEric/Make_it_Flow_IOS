import XCTest

class ePdfUBUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        // 傳入 Launch Argument，讓你的 App 知道現在是 UI 測試，可以載入假資料
        app.launchArguments.append("-isUITesting")
        
        // Fastlane Snapshot 注入設定
        setupSnapshot(app)
        
        app.launch()
    }

    func testTakeScreenshots() throws {
        let app = XCUIApplication()
        
        // 等待 App 啟動完成
        _ = app.wait(for: .runningForeground, timeout: 5.0)
        
        // --- 截圖 1：首頁 ---
        // 為了確保畫面已經算繪完成，給一點緩衝時間
        sleep(2)
        snapshot("01_Home")

        // --- 截圖 2：編輯選取模式 ---
        let editButton = app.buttons["Edit"]
        if editButton.waitForExistence(timeout: 2.0) {
            editButton.tap()
            // 等待動畫與狀態切換
            sleep(1)
            snapshot("02_EditMode")
            
            // 結束編輯模式
            let doneButton = app.buttons["Done"]
            if doneButton.exists {
                doneButton.tap()
            }
        }

        // --- 截圖 3：動作選單 ---
        // 根據你的截圖，我們長按畫面上的文件來呼叫 Context Menu
        // 這裡尋找第一個圖片(通常是縮圖)或直接點擊特定 Identifier
        let documentItem = app.images.firstMatch
        if documentItem.waitForExistence(timeout: 2.0) {
            documentItem.press(forDuration: 1.5)
            // 等待選單彈出
            sleep(1)
            snapshot("03_ContextMenu")
        }
    }
}
