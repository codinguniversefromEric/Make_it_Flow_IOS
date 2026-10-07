import SwiftUI

/// 流暢水波紋進度條
/// - 波浪使用固定 Path
/// - 動畫只負責水平平移
/// - 前後兩層波浪使用不同 phase
/// - 水位變化使用 spring
/// - 波浪循環不會產生接縫
struct GlassLiquidView: View {

    var progress: Double       // 0.0 ~ 1.0
    var islandY: CGFloat

    @State private var animatedProgress: Double = 0
    @State private var waveOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in

            let width = geo.size.width
            let height = geo.size.height

            // 水位最低位置
            let targetMaxY = height + 40

            // 實際水位
            let currentY =
                islandY +
                (targetMaxY - islandY) *
                CGFloat(animatedProgress)

            // 畫 3 個完整波長
            //
            // 這樣 waveOffset 往左移動一個完整波長時，
            // 右側仍然有完整波形可以接上，不會穿幫。
            let waveWidth = width * 3

            ZStack(alignment: .leading) {

                // =====================================================
                // 後方波浪
                // =====================================================

                WaveShape(
                    yOffset: currentY,
                    amplitude: 12,
                    waveLength: width,
                    phase: .pi / 2
                )
                .fill(
                    Color.accentColor.opacity(0.15)
                )
                .offset(x: waveOffset)


                // =====================================================
                // 前方波浪
                // =====================================================

                WaveShape(
                    yOffset: currentY,
                    amplitude: 18,
                    waveLength: width,
                    phase: 0
                )
                .fill(.ultraThinMaterial)
                .overlay {

                    WaveShape(
                        yOffset: currentY,
                        amplitude: 18,
                        waveLength: width,
                        phase: 0
                    )
                    .stroke(
                        Color.primary.opacity(0.15),
                        lineWidth: 1.5
                    )
                }
                .shadow(
                    color: .black.opacity(0.1),
                    radius: 10,
                    y: 5
                )
                .offset(x: waveOffset)
            }
            .frame(
                width: waveWidth,
                height: height,
                alignment: .leading
            )
            .position(
                x: waveWidth / 2,
                y: height / 2
            )
            .clipped()
            .onAppear {

                startWaveAnimation(
                    waveLength: width
                )
            }
            .onChange(of: width) { newWidth in

                // 避免旋轉螢幕或 GeometryReader 尺寸改變
                // 導致波浪突然跳動
                startWaveAnimation(
                    waveLength: newWidth
                )
            }
        }

        // =============================================================
        // 初始水位
        // =============================================================

        .onAppear {
            animatedProgress = progress
        }

        // =============================================================
        // 水位變化
        // =============================================================

        .onChange(of: progress) { newValue in

            withAnimation(
                .interactiveSpring(
                    response: 0.7,
                    dampingFraction: 0.78,
                    blendDuration: 0.15
                )
            ) {
                animatedProgress = newValue
            }
        }
    }


    // =============================================================
    // 波浪動畫
    // =============================================================

    private func startWaveAnimation(
        waveLength: CGFloat
    ) {

        guard waveLength > 0 else {
            return
        }

        // 從固定位置開始
        waveOffset = 0

        // 一個完整波長 = 一個完整循環
        //
        // 因為正弦波在移動一個完整 waveLength 後
        // 會回到完全相同的狀態，
        // 所以 repeatForever 時肉眼看不到跳接。
        withAnimation(
            .linear(
                duration: 2.0
            )
            .repeatForever(
                autoreverses: false
            )
        ) {
            waveOffset = -waveLength
        }
    }
}


// MARK: - WaveShape

struct WaveShape: Shape {

    var yOffset: CGFloat
    var amplitude: CGFloat
    var waveLength: CGFloat
    var phase: CGFloat


    // =============================================================
    // 只讓水位 yOffset 可以被 SwiftUI 插值
    //
    // 波浪本身不透過 animatableData 每幀重新計算
    // =============================================================

    var animatableData: CGFloat {

        get {
            yOffset
        }

        set {
            yOffset = newValue
        }
    }


    // =============================================================
    // 建立波浪 Path
    // =============================================================

    func path(
        in rect: CGRect
    ) -> Path {

        var path = Path()

        guard rect.width > 0,
              rect.height > 0,
              waveLength > 0
        else {
            return path
        }


        // ---------------------------------------------------------
        // 左上角
        // ---------------------------------------------------------

        path.move(
            to: CGPoint(
                x: 0,
                y: 0
            )
        )


        // ---------------------------------------------------------
        // 左邊往下到水面
        // ---------------------------------------------------------

        path.addLine(
            to: CGPoint(
                x: 0,
                y: yOffset
            )
        )


        // ---------------------------------------------------------
        // 波浪取樣
        //
        // 每個 waveLength 約 100 個點
        // 在手機螢幕上已經足夠平滑。
        //
        // 不使用非常密集的 1~2 px sampling，
        // 避免不必要的 CPU Path 建立成本。
        // ---------------------------------------------------------

        let step = max(
            4,
            waveLength / 100
        )

        var x: CGFloat = 0

        while x <= rect.width {

            let angle =
                (x / waveLength) *
                (.pi * 2)
                + phase

            let wave =
                CGFloat(
                    sin(angle)
                )

            let y =
                yOffset +
                amplitude * wave

            path.addLine(
                to: CGPoint(
                    x: x,
                    y: y
                )
            )

            x += step
        }


        // ---------------------------------------------------------
        // 右側補齊
        // ---------------------------------------------------------

        path.addLine(
            to: CGPoint(
                x: rect.width,
                y: yOffset
            )
        )


        // ---------------------------------------------------------
        // 右上角
        // ---------------------------------------------------------

        path.addLine(
            to: CGPoint(
                x: rect.width,
                y: 0
            )
        )


        // ---------------------------------------------------------
        // 關閉 Path
        // ---------------------------------------------------------

        path.closeSubpath()

        return path
    }
}
