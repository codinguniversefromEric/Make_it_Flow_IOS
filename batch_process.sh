#!/bin/bash
cd Flow_CLI || exit
echo "🏗 Building Make it Flow CLI (Release mode)..."
swift build -c release

CLI_PATH="$(swift build -c release --show-bin-path)/Flow_CLI"
cd ..

if [ ! -f "$CLI_PATH" ]; then
    echo "❌ 編譯失敗，找不到 $CLI_PATH"
    exit 1
fi

echo "✅ 編譯成功！開始批次轉換..."
echo "🧠 使用模型: YOLOv26m (medium)"

process_folder() {
    local DIR=$1
    local TITLE=$2
    echo "----------------------------------------"
    echo "📚 處理 $TITLE"
    echo "----------------------------------------"
    mkdir -p "$DIR/EPUBs"
    mkdir -p "$DIR/Reports"

    local success=0
    local fail=0

    for pdf in "$DIR"/*.pdf; do
        if [ -f "$pdf" ]; then
            filename=$(basename "$pdf" .pdf)
            echo "⏳ 轉換中: $filename"
            
            if "$CLI_PATH" "$pdf" "$DIR/EPUBs/$filename.epub" medium; then
                python3 generate_report.py "$pdf" "$DIR/EPUBs/$filename.epub" "$DIR/Reports/${filename}_report.html"
                success=$((success + 1))
            else
                echo "  ❌ 轉換失敗: $filename"
                fail=$((fail + 1))
            fi
        fi
    done

    echo "📊 $TITLE 結果: ✅ $success 成功, ❌ $fail 失敗"
}

process_folder "/Users/giyoshimiken/Documents/test journal" "學術論文 (test journal)"
process_folder "/Users/giyoshimiken/Documents/test report" "一般報告 (test report)"

echo "========================================"
echo "🎉 所有轉換任務已完成！"
echo "📂 EPUB 儲存於各資料夾的 EPUBs/"
echo "📊 報告儲存於各資料夾的 Reports/"
echo "========================================"
