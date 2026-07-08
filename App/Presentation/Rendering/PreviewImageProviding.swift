import UIKit
import PhotoLayoutCore

/// プレビュー用に各配置のフル画像（EXIF向き適用済み・縮小上限あり）を供給する。
/// sourceRect（クロップ）の適用はCanvasRenderViewが描画時に幾何学的に行う —
/// クロップ操作中に再デコードせず60fpsで追従させるため。
protocol PreviewImageProviding: Sendable {
    func previewImages(project: ProjectEntity) async -> [UUID: UIImage]
}
