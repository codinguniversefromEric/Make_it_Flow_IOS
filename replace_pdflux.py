import os

root_dir = '/Users/giyoshimiken/Documents/Make_it_Flow_IOS'
ignore_dirs = {'.git', '.build', 'DerivedData', 'scratch', 'Flow_CLI', '.swiftpm'}
ignore_exts = {'.png', '.jpg', '.jpeg', '.pdf', '.mlmodel', '.bin', '.pack', '.idx'}

for dirpath, dirnames, filenames in os.walk(root_dir):
    dirnames[:] = [d for d in dirnames if d not in ignore_dirs]
    for filename in filenames:
        if any(filename.endswith(ext) for ext in ignore_exts):
            continue
        if filename == 'replace_pdflux.py':
            continue
        filepath = os.path.join(dirpath, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            if 'PDFlux' in content or 'pdflux' in content:
                # Replace PDFlux to ePdfUB (match case for exact match, but let's just do normal)
                content = content.replace('PDFlux', 'ePdfUB')
                content = content.replace('pdflux', 'epdfub')
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"Replaced in {filepath}")
        except Exception:
            pass
