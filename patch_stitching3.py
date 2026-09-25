import re

filepath = "Flow_1/Engines/LayoutEngine.swift"
with open(filepath, "r") as f:
    content = f.read()

pattern_code = r'''    nonisolated static func stitchCrossPageParagraphs\(html: String\) -> String \{
        let pattern = .*?
        
        guard let regex'''

new_pattern = r'''    nonisolated static func stitchCrossPageParagraphs(html: String) -> String {
        let pattern = "([^.!?:;。！？：；>\\”\\\"\\\''])\\s*</span>\\s*</p>\\s*<p class=\\\"doc-body\\\">\\s*(<span[^>]*>\\s*[a-z0-9\\p{Han}])"
        
        guard let regex'''

content = re.sub(pattern_code, new_pattern, content, flags=re.DOTALL)
with open(filepath, "w") as f:
    f.write(content)
