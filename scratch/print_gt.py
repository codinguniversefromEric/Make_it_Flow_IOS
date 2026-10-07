import json
from datasets import load_dataset

ds = load_dataset("datalab-to/marker_benchmark", split="train")
gt_blocks_str = ds[0]['gt_blocks']
gt_blocks = json.loads(gt_blocks_str)
print(json.dumps(gt_blocks[0:3], indent=2))
