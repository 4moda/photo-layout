import UIKit
import PhotoLayoutCore

/// プレビュー用に「sourceRect適用済み」のUIImageを供給する。
/// 実装はInfrastructure（ImageIODecoder）— sourceRectの解釈を書き出しと共有するための境界。
protocol PreviewImageProviding: Sendable {
    func previewImages(project: ProjectEntity) async -> [UUID: UIImage]
}
