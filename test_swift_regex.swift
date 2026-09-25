import Foundation
let text = "一 鉴俄之史"
let pattern = "^[一二三四五六七八九十]+\\s*[、\\.\\s]"
let isMatch = text.range(of: pattern, options: .regularExpression) != nil
print(isMatch)
