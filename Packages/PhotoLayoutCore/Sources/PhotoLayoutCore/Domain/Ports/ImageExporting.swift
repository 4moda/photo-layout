import Foundation

/// DrawCommand列を実ピクセルで描画し、エンコード済み画像データを返すPort。
public protocol ImageExporting: Sendable {
    func render(plan: [DrawCommand], pixelSize: LayoutSize, format: ExportFormat) async throws -> Data
}
