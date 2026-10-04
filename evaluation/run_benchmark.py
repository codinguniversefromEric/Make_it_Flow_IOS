import sys
import subprocess
import tempfile
import os
import re
import zipfile
import difflib
from datasets import load_dataset
from bs4 import BeautifulSoup
import time
import json

def extract_text_from_epub(epub_path):
    text_chunks = []
    try:
        with zipfile.ZipFile(epub_path, 'r') as z:
            html_files = sorted([f for f in z.namelist() if f.endswith('.xhtml') or f.endswith('.html')])
            for item in html_files:
                content = z.read(item).decode('utf-8')
                text = BeautifulSoup(content, 'html.parser').get_text(separator=' ')
                text = re.sub(r'\s+', ' ', text).strip()
                if text:
                    text_chunks.append(text)
    except Exception as e:
        return f"Error reading EPUB: {e}"
    return "\n".join(text_chunks)

def extract_gt_text(gt_blocks_str):
    try:
        gt_blocks = json.loads(gt_blocks_str)
    except Exception as e:
        return ""
        
    text_chunks = []
    for block in gt_blocks:
        if isinstance(block, dict) and 'html' in block:
            text = BeautifulSoup(block['html'], 'html.parser').get_text(separator=' ')
            text = re.sub(r'\s+', ' ', text).strip()
            if text:
                text_chunks.append(text)
    return "\n".join(text_chunks)

def calculate_edit_distance_similarity(text1, text2):
    t1 = re.sub(r'\s+', ' ', text1).strip()
    t2 = re.sub(r'\s+', ' ', text2).strip()
    
    if not t1 and not t2: return 1.0
    if not t1 or not t2: return 0.0
    
    sm = difflib.SequenceMatcher(None, t1, t2)
    return sm.ratio()

def main():
    print("Loading full marker_benchmark dataset...")
    try:
        # Load the full train split
        ds = load_dataset("datalab-to/marker_benchmark", split="train")
    except Exception as e:
        print(f"Failed to load dataset: {e}")
        return

    cli_path = "/Users/giyoshimiken/Documents/Make_it_Flow_IOS/Flow_CLI/.build/release/Flow_CLI"
    if not os.path.exists(cli_path):
        print(f"Error: CLI not found at {cli_path}. Please build it first.")
        return

    models = ["nano", "small", "medium"]
    results_report = {}

    for model in models:
        print(f"\n=========================================")
        print(f"Starting evaluation for model: {model.upper()}")
        print(f"=========================================")
        
        total_edit_sim = 0
        total_retention = 0
        valid_samples = 0
        
        start_time = time.time()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            for i, item in enumerate(ds):
                pdf_bytes = item['pdf']
                gt_blocks = item['gt_blocks']
                
                pdf_path = os.path.join(tmpdir, f"test_{i}.pdf")
                epub_path = os.path.join(tmpdir, f"test_{i}.epub")
                
                with open(pdf_path, 'wb') as f:
                    f.write(pdf_bytes)
                    
                cmd = [cli_path, pdf_path, epub_path, model]
                res = subprocess.run(cmd, capture_output=True, text=True)
                
                if not os.path.exists(epub_path):
                    print(f"[{model}] Sample {i}: Failed to generate EPUB.")
                    continue
                    
                epub_text = extract_text_from_epub(epub_path)
                gt_text = extract_gt_text(gt_blocks)
                
                epub_len = len(epub_text.replace(" ", ""))
                gt_len = len(gt_text.replace(" ", ""))
                retention_rate = (epub_len / gt_len) if gt_len > 0 else 0
                retention_rate = min(1.0, retention_rate)
                
                edit_sim = calculate_edit_distance_similarity(epub_text, gt_text)
                
                total_edit_sim += edit_sim
                total_retention += retention_rate
                valid_samples += 1
                
                if (i + 1) % 10 == 0 or (i + 1) == len(ds):
                    print(f"[{model}] Processed {i + 1}/{len(ds)} samples...")
                
        elapsed_time = time.time() - start_time
        
        if valid_samples > 0:
            avg_edit_sim = total_edit_sim / valid_samples
            avg_retention = total_retention / valid_samples
            avg_edit_distance = 1.0 - avg_edit_sim
            
            results_report[model] = {
                "valid_samples": valid_samples,
                "total_samples": len(ds),
                "layout_similarity": round(avg_retention, 4),
                "edit_distance": round(avg_edit_distance, 4),
                "time_seconds": round(elapsed_time, 2)
            }
            
            print(f"\n--- {model.upper()} Results ---")
            print(f"Valid Samples: {valid_samples}/{len(ds)}")
            print(f"Layout Similarity: {avg_retention:.3f}")
            print(f"Edit Distance: {avg_edit_distance:.3f}")
            print(f"Total Time: {elapsed_time:.2f} seconds")
        else:
            print(f"No valid samples processed for {model}.")
            results_report[model] = {"error": "No valid samples processed."}

    # Save consolidated report
    report_path = os.path.join(os.getcwd(), "evaluation", "benchmark_report.json")
    with open(report_path, "w") as f:
        json.dump(results_report, f, indent=4)
        
    print(f"\nConsolidated report saved to {report_path}")

if __name__ == '__main__':
    main()
