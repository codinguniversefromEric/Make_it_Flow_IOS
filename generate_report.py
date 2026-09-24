import sys
import zipfile
import re
import subprocess
import difflib

def extract_text_from_epub(epub_path):
    text_chunks = []
    try:
        with zipfile.ZipFile(epub_path, 'r') as z:
            for item in z.namelist():
                if item.endswith('.xhtml') or item.endswith('.html'):
                    content = z.read(item).decode('utf-8')
                    text = re.sub(r'<[^>]+>', ' ', content)
                    text = re.sub(r'\s+', ' ', text).strip()
                    if text:
                        text_chunks.append(text)
    except Exception as e:
        return f"Error reading EPUB: {e}"
    return "\n\n".join(text_chunks)

def extract_text_from_pdf(pdf_path):
    swift_code = """
import Foundation
import PDFKit
let pdfURL = URL(fileURLWithPath: CommandLine.arguments[1])
if let document = PDFDocument(url: pdfURL) {
    var fullText = ""
    for i in 0..<document.pageCount {
        if let page = document.page(at: i), let string = page.string {
            fullText += string + " "
        }
    }
    print(fullText)
}
    """
    with open("temp_extractor.swift", "w") as f:
        f.write(swift_code)
    
    result = subprocess.run(["swift", "temp_extractor.swift", pdf_path], capture_output=True, text=True)
    text = re.sub(r'\s+', ' ', result.stdout).strip()
    return text

def generate_report(pdf_path, epub_path, report_path):
    print(f"Analyzing {pdf_path}...")
    epub_text = extract_text_from_epub(epub_path)
    pdf_text = extract_text_from_pdf(pdf_path)
    
    epub_len = len(epub_text.replace(" ", ""))
    pdf_len = len(pdf_text.replace(" ", ""))
    
    # Calculate text retention rate (avoiding division by zero)
    retention_rate = (epub_len / pdf_len * 100) if pdf_len > 0 else 0
    
    # Determine color
    color = "green" if retention_rate >= 90 else "orange" if retention_rate >= 75 else "red"
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='utf-8'>
        <title>EPUB 檢查報告 - {epub_path}</title>
        <style>
            body {{ font-family: -apple-system, sans-serif; padding: 20px; max-width: 800px; margin: 0 auto; line-height: 1.6; }}
            h1 {{ border-bottom: 2px solid #eaecef; padding-bottom: 10px; }}
            .stats {{ background: #f6f8fa; padding: 15px; border-radius: 6px; margin-bottom: 20px; }}
            .content-box {{ border: 1px solid #d0d7de; padding: 20px; border-radius: 6px; white-space: pre-wrap; font-size: 14px; color: #24292f; }}
            .metric {{ font-size: 1.2em; font-weight: bold; color: {color}; }}
        </style>
    </head>
    <body>
        <h1>EPUB 漏字與順序檢查報告</h1>
        <div class="stats">
            <p><strong>檔案：</strong> {epub_path}</p>
            <p><strong>PDF 原文總字元 (Ground Truth)：</strong> {pdf_len:,} 字</p>
            <p><strong>EPUB 產出總字元：</strong> {epub_len:,} 字</p>
            <p><strong>字元保留率 (Retention Rate)：</strong> <span class="metric">{retention_rate:.1f}%</span></p>
            <p style="font-size: 12px; color: #666;">*保留率通常不會是 100%，因為 PDFKit 會抽出頁首、頁尾、隱藏浮水印等被系統過濾掉的雜訊，只要保持在 85% 以上通常代表內文完整。</p>
        </div>
        <h2>EPUB 純文字預覽 (閱讀順序檢驗)</h2>
        <div class="content-box">{epub_text}</div>
    </body>
    </html>
    """
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f"Generated report: {report_path}")

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python3 generate_report.py <pdf_path> <epub_path> <output_report_path>")
        sys.exit(1)
    generate_report(sys.argv[1], sys.argv[2], sys.argv[3])
