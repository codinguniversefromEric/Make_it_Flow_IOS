import sys

def add_meta(filename, is_zh):
    with open(filename, 'r') as f:
        content = f.read()

    title = "ePdfUB - OS Simulator"
    desc = "100% On-device. Fast, private, and brutalist PDF to EPUB Engine."
    if is_zh:
        desc = "極速、離線且硬派的 PDF 轉 EPUB 引擎。完全保障隱私。"
        
    meta_tags = f"""
    <meta property="og:title" content="{title}">
    <meta property="og:description" content="{desc}">
    <meta property="og:image" content="https://codinguniversefromeric.github.io/ePdfUB_IOS/assets/logo.jpg">
    <meta property="og:url" content="https://codinguniversefromeric.github.io/ePdfUB_IOS/">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="{title}">
    <meta name="twitter:description" content="{desc}">
    <meta name="twitter:image" content="https://codinguniversefromeric.github.io/ePdfUB_IOS/assets/logo.jpg">
"""
    
    # Insert right before </head>
    content = content.replace('</head>', meta_tags + '</head>')
    
    with open(filename, 'w') as f:
        f.write(content)

add_meta('index.html', False)
add_meta('index_zh.html', True)
