import SwiftUI

struct FaceIDCheckmarkView: View {
    @State private var drawCircle: CGFloat = 0.0
    @State private var drawCheck: CGFloat = 0.0
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // 底層圓軌道
                Circle()
                    .stroke(Color.gray.opacity(0.15), style: StrokeStyle(lineWidth: 6))
                
                // 動畫圓軌道
                Circle()
                    .trim(from: 0, to: drawCircle)
                    .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                // 動畫打勾
                Path { path in
                    path.move(to: CGPoint(x: 28, y: 50))
                    path.addLine(to: CGPoint(x: 42, y: 64))
                    path.addLine(to: CGPoint(x: 72, y: 34))
                }
                .trim(from: 0, to: drawCheck)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 100, height: 100)
            
            Text("Done")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .opacity(drawCheck == 1.0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: drawCheck)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4)) {
                drawCircle = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.35)) {
                drawCheck = 1.0
            }
        }
    }
}
