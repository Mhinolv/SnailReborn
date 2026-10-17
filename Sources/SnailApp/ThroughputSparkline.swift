import SwiftUI
import SnailCore

/// Last-minute download throughput as a single area line, right-aligned so new samples enter at the right.
/// When a total cap is active, it's drawn as a dashed reference line.
struct ThroughputSparkline: View {
    let samples: [Double]
    let capacity: Int
    let limitKbps: Double?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let top = max((samples.max() ?? 0) * 1.15, (limitKbps ?? 0) * 1.25, 100)

            ZStack(alignment: .topLeading) {
                // Baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height - 0.5))
                    p.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                if samples.count > 1 {
                    area(in: size, top: top)
                        .fill(Color.accentColor.opacity(0.15))
                    line(in: size, top: top)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                if let limitKbps {
                    let y = size.height * (1 - limitKbps / top)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text("limit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                        .background(.background)
                        .position(x: 14, y: max(y - 8, 6))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Download throughput, last minute")
        .accessibilityValue(samples.last.map { Rate.format(kbps: $0) } ?? "No data")
    }

    private func points(in size: CGSize, top: Double) -> [CGPoint] {
        let step = size.width / CGFloat(max(capacity - 1, 1))
        let start = size.width - step * CGFloat(samples.count - 1)
        return samples.enumerated().map { i, v in
            CGPoint(x: start + step * CGFloat(i), y: size.height * (1 - min(v / top, 1)))
        }
    }

    private func line(in size: CGSize, top: Double) -> Path {
        Path { p in p.addLines(points(in: size, top: top)) }
    }

    private func area(in size: CGSize, top: Double) -> Path {
        Path { p in
            let pts = points(in: size, top: top)
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}
