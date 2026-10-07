import json
from datasets import load_dataset
from bs4 import BeautifulSoup

ds = load_dataset("datalab-to/marker_benchmark", split="train")

total_chars = 0
visual_chars = 0

for i in range(500):
    gt_blocks = json.loads(ds[i]['gt_blocks'])
    for block in gt_blocks:
        if isinstance(block, dict) and 'html' in block:
            soup = BeautifulSoup(block['html'], 'html.parser')
            text = soup.get_text(separator=' ')
            
            # Also extract alt text from images because marker sometimes puts math in alt
            for img in soup.find_all('img'):
                if img.get('alt'):
                    text += " " + img.get('alt')
                    
            text = " ".join(text.split())
            char_count = len(text.replace(" ", ""))
            total_chars += char_count
            
            block_type = block.get('block_type', '').lower()
            if block_type in ['table', 'figure', 'picture', 'equation', 'formula']:
                visual_chars += char_count

print(f"Total Chars: {total_chars}")
print(f"Visual Chars: {visual_chars}")
if total_chars > 0:
    print(f"Visual Region Text Ratio: {visual_chars/total_chars:.2%}")
