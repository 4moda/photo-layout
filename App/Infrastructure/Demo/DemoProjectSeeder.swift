import UIKit
import PhotoLayoutCore

/// `--seed-demo`起動引数用: 生成画像入りのデモプロジェクトを1つ作る。
/// UIテスト・CIスクリーンショットがPhotosPickerに依存せず編集画面まで到達するための足場。
struct DemoProjectSeeder {
    let createProject: CreateProjectUseCase
    let addPhoto: AddPhotoUseCase
    let listProjects: ListProjectsUseCase

    func seedIfNeeded() async {
        do {
            let existing = try await listProjects.execute()
            guard !existing.contains(where: { $0.title == "デモ" }) else { return }
            let project = try await createProject.execute(
                title: "デモ",
                preset: .instagram(aspect: .portrait, pageCount: 1),
                framePreset: .whiteMargin
            )
            _ = try await addPhoto.execute(project: project, imageData: Self.demoImageData())
        } catch {
            // デモシードの失敗はアプリ動作に影響させない
        }
    }

    /// 3000x2000の生成画像（グラデーション＋円）。実写真の代わり。
    private static func demoImageData() -> Data {
        let size = CGSize(width: 3000, height: 2000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor.systemIndigo.cgColor, UIColor.systemOrange.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            cg.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            cg.fillEllipse(in: CGRect(x: 1900, y: 300, width: 700, height: 700))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
