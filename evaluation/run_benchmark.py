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

def extract_text_from_epub(epub_path):
    text_chunks = []
    try:
        with zipfile.ZipFile(epub_path, 'r') as z:
            # We want to iterate through spine order or just all html/xhtml
            # for simplicity we grab all html/xhtml and sort them
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
    import json
    # gt_blocks is a json string of a list of dictionaries with 'html' key
    try:
        gt_blocks = json.loads(gt_blocks_str)
    except Exception as e:
        print("JSON parse error:", e)
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
    # Normalize strings a bit
    t1 = re.sub(r'\s+', ' ', text1).strip()
    t2 = re.sub(r'\s+', ' ', text2).strip()
    
    if not t1 and not t2:
        return 1.0
    if not t1 or not t2:
        return 0.0
    
    # Use SequenceMatcher ratio (which gives similarity between 0 and 1)
    sm = difflib.SequenceMatcher(None, t1, t2)
    return sm.ratio()

def main():
    print("Loading marker_benchmark dataset...")
    # Load 50 samples for speed
    num_samples = 50
    try:
        ds = load_dataset("datalab-to/marker_benchmark", split=f"train[:{num_samples}]")
    except Exception as e:
        print(f"Failed to load dataset: {e}")
        return

    cli_path = "/Users/giyoshimiken/Documents/Make_it_Flow_IOS/Flow_CLI/.build/release/Flow_CLI"
    
    if not os.path.exists(cli_path):
        print(f"Error: CLI not found at {cli_path}")
        return

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
                
            # Run CLI
            # swift run Flow_CLI input.pdf output.epub medium
            cmd = [cli_path, pdf_path, epub_path, "medium"]
            res = subprocess.run(cmd, capture_output=True, text=True)
            
            if not os.path.exists(epub_path):
                print(f"Sample {i}: Failed to generate EPUB. Output: {res.stdout}")
                continue
                
            epub_text = extract_text_from_epub(epub_path)
            gt_text = extract_gt_text(gt_blocks)
            
            # Retention rate (Layout Similarity proxy)
            epub_len = len(epub_text.replace(" ", ""))
            gt_len = len(gt_text.replace(" ", ""))
            retention_rate = (epub_len / gt_len) if gt_len > 0 else 0
            retention_rate = min(1.0, retention_rate) # Cap at 1.0
            
            # Edit distance similarity
            edit_sim = calculate_edit_distance_similarity(epub_text, gt_text)
            
            total_edit_sim += edit_sim
            total_retention += retention_rate
            valid_samples += 1
            
            print(f"Sample {i}: Edit Sim={edit_sim:.3f}, Retention={retention_rate:.3f}")
            
    if valid_samples > 0:
        avg_edit_sim = total_edit_sim / valid_samples
        avg_retention = total_retention / valid_samples
        # Convert similarities back to standard reported format
        # In README: Edit distance is ~0.612, Layout Sim is ~0.68
        # Since difflib ratio is similarity (1 - distance), let's report distance as 1 - ratio
        avg_edit_distance = 1.0 - avg_edit_sim
        
        print("\n--- Benchmark Results ---")
        print(f"Valid Samples: {valid_samples}/{num_samples}")
        print(f"Layout Similarity (Retention Proxy): {avg_retention:.3f}")
        print(f"Edit Distance (1 - Similarity): {avg_edit_distance:.3f}")
        print(f"Total Time: {time.time() - start_time:.2f} seconds")
    else:
        print("No valid samples processed.")

if __name__ == '__main__':
    main()
