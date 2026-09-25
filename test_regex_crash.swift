import Foundation

let texts = ["Test string", "1.1", "壹、測試", "[1] 測試", "測試,"]

for text in texts {
    _ = text.range(of: "^第[一二三四五六七八九十百千萬萬0-9\\s]+[章部节]|^chapter\\s+\\d+|^[壹貳參肆伍陸柒捌玖拾]+\\s*、", options: [.regularExpression, .caseInsensitive]) != nil
    
    _ = text.range(of: "^[一二三四五六七八九十]+\\s*、", options: [.regularExpression, .caseInsensitive]) != nil
    
    _ = text.range(of: "[.!?。！？,，;；]$", options: .regularExpression) != nil
    
    _ = text.range(of: "^\\[\\d+\\]", options: .regularExpression) != nil
}
print("All Regexes passed without crashing.")
