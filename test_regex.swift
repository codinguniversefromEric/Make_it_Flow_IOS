import Foundation

let tests = [
    ("hello", "world"),
    ("hello,", "world"),
    ("hello.", "world"),
    ("Mg==", "&mid"),
    ("https://example.com/", "path"),
    ("Hello", "123")
]

for (a, b) in tests {
    let cLast = a.last!
    let nFirst = b.first!
    
    // Only add space if:
    // 1. Both are alphanumeric
    // 2. cLast is a punctuation that is normally followed by space (.,!?:;]) AND nFirst is alphanumeric
    // 3. nFirst is an opening parenthesis/bracket ([( ) AND cLast is alphanumeric
    
    let cAlphanumeric = cLast.isLetter || cLast.isNumber
    let nAlphanumeric = nFirst.isLetter || nFirst.isNumber
    
    let cPunctuation = [".", ",", "!", "?", ":", ";", "]", ")", "”", "\""].contains(cLast)
    let nOpening = ["[", "(", "“", "\""].contains(nFirst)
    
    var addSpace = false
    if cAlphanumeric && nAlphanumeric { addSpace = true }
    else if cPunctuation && nAlphanumeric { addSpace = true }
    else if cAlphanumeric && nOpening { addSpace = true }
    
    print("\(a) + \(b) -> addSpace: \(addSpace)")
}
