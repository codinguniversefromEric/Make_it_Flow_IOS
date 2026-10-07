import json
from datasets import load_dataset
from bs4 import BeautifulSoup

def main():
    print("Loading marker_benchmark dataset...")
    ds = load_dataset("datalab-to/marker_benchmark", split="train")
    
    total_chars = 0
    visual_chars = 0
    
    # We will analyze the first 500 samples to save time, or all if it's fast
    limit = 500
    for i, item in enumerate(ds):
        if i >= limit: break
        
        gt_blocks_str = item['gt_blocks']
        try:
            gt_blocks = json.loads(gt_blocks_str)
        except:
            continue
            
        for block in gt_blocks:
            if isinstance(block, dict) and 'html' in block:
                text = BeautifulSoup(block['html'], 'html.parser').get_text(separator=' ')
                text = " ".join(text.split())
                char_count = len(text.replace(" ", ""))
                
                total_chars += char_count
                
                # Check if block label implies visual region
                label = block.get('label', '').lower()
                # Labels in doclaynet/marker might be: table, figure, equation, formula, picture
                if label in ['table', 'figure', 'picture', 'equation', 'formula']:
                    visual_chars += char_count

    if total_chars > 0:
        visual_ratio = visual_chars / total_chars
        print(f"Total Chars: {total_chars}")
        print(f"Visual Chars (Tables/Formulas/Figures): {visual_chars}")
        print(f"Visual Region Text Ratio: {visual_ratio:.2%}")
    else:
        print("No characters found.")

if __name__ == '__main__':
    main()
