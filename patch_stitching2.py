filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

bad = 'let pattern = "([^.!?:;。！？：；>\\”\\"\\\'\'])\\s*</span>\\s*</p>\\s*<p class=\\"doc-body\\">\\s*(<span[^>]*>\\s*[a-z0-9\\p{Han}])"'
good = 'let pattern = "[^.!?:;。！？：；>\\\\”\\\\\"\\\'\']\\\\s*</span>\\\\s*</p>\\\\s*<p class=\\\\"doc-body\\\\">\\\\s*<span[^>]*>\\\\s*[a-z0-9\\\\p{Han}]"'
# actually, let's just use raw strings correctly
good = 'let pattern = "([^.!?:;。！？：；>\\\\”\\\\\"\\\'\'])\\\\s*</span>\\\\s*</p>\\\\s*<p class=\\\\"doc-body\\\\">\\\\s*(<span[^>]*>\\\\s*[a-z0-9\\\\p{Han}])"'
content = content.replace(bad, good)
with open(filepath, "w") as f:
    f.write(content)
