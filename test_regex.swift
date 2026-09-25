import Foundation

let texts = [
    "第一章 相信自己",
    "第 八章 挑战自我",
    "第12章",
    "第一千二百三十四章",
    "当你正在忍受别人不愿忍受的磨难时，脑海里也许会浮现两个问题。第一个问题是：“这么做值得吗？”尼采说过：“一个人知道自己为什么而活，就能够忍受任何生活。”请你认真想一想，你现在为什么在做这件事？当初又是什么促使你做出这个决定？其实，这是因为文章",
    "Chapter 1",
    "CHAPTER 12: Hello",
    "This is chapter 5"
]

let pattern = "^第[一二三四五六七八九十百千萬萬0-9\\s]+章|^chapter\\s+\\d+"

for text in texts {
    let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    print("\(text.prefix(20))... -> \(range != nil)")
}
