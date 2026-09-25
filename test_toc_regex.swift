import Foundation

let texts = [
    "PART II",
    "PART III LOOKING BACK",
    "Chapter 1",
    "Section 4",
    "Table of Contents",
    "目錄",
    "第一章 什麼是",
    "第二部",
    "9 From 1865 to 1945 in a Tiny Nutshell", // This won't match, but PART II will match in the same region
    "Introduction ........... 5",
    "Part No. 12345", // Should not match
    "department" // Should not match
]

let pattern = "^(chapter|part|section)\\s+[ivx0-9]+\\b|\\b(table of contents|contents|目錄|目录)\\b|^第[一二三四五六七八九十百千萬萬0-9\\s]+[章部节]|\\.{4,}|…{2,}"

for text in texts {
    let lowerText = text.lowercased()
    let isMatch = lowerText.range(of: pattern, options: .regularExpression) != nil
    print("\(text): \(isMatch)")
}
