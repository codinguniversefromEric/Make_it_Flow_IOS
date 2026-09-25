import re

filepath = "Flow_CLI/Sources/RobustnessBenchmark/main.swift"
with open(filepath, "r") as f:
    content = f.read()

new_test = """// 5. Two-Column Reading Order
func testTwoColumnReadingOrder() {
    let pageWidth: CGFloat = 600
    let pageHeight: CGFloat = 800
    
    // Spanning title
    let t1 = frag("Title", CGRect(x: 50, y: 50, width: 500, height: 40), 24, true)
    // Left column
    let l1 = frag("Left 1", CGRect(x: 50, y: 120, width: 200, height: 20), 12, false)
    let l2 = frag("Left 2", CGRect(x: 50, y: 150, width: 200, height: 20), 12, false)
    // Right column
    let r1 = frag("Right 1", CGRect(x: 350, y: 120, width: 200, height: 20), 12, false)
    let r2 = frag("Right 2", CGRect(x: 350, y: 150, width: 200, height: 20), 12, false)
    // Spanning footer
    let f1 = frag("Footer", CGRect(x: 50, y: 200, width: 500, height: 20), 10, false)
    
    // YOLO blocks
    let bt1 = yolo("Title", CGRect(x: 50, y: 50, width: 500, height: 40))
    let bl1 = yolo("Text", CGRect(x: 50, y: 120, width: 200, height: 50)) // Covers L1, L2
    let br1 = yolo("Text", CGRect(x: 350, y: 120, width: 200, height: 50)) // Covers R1, R2
    let bf1 = yolo("Text", CGRect(x: 50, y: 200, width: 500, height: 20))
    
    // The reading order MUST be: Title, L1, L2, R1, R2, Footer
    runner.runSyntheticTest(
        name: "Two-Column Reading Order",
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        fragments: [l2, r1, t1, r2, f1, l1], // Shuffle input
        blocks: [br1, bf1, bt1, bl1], // Shuffle yolo
        expected: [
            ExpectedBlock(role: .title, expectedText: "Title"),
            ExpectedBlock(role: .body, expectedText: "Left 1 Left 2"),
            ExpectedBlock(role: .body, expectedText: "Right 1 Right 2"),
            ExpectedBlock(role: .body, expectedText: "Footer")
        ]
    )
}

// Run all
testScaleInvariance()
testFragmentOrdering()
testHeaderFalsePositive()
testCrossPageStitching()
testTwoColumnReadingOrder()

runner.report()
"""

# Replace the end of the file
pattern = re.compile(r'// Run all\n.*', re.DOTALL)
content = pattern.sub(new_test, content)

with open(filepath, "w") as f:
    f.write(content)

