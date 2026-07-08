import UIKit
import PhotoLayoutCore

/// `--seed-demo`起動引数用: 生成画像入りのデモプロジェクトを作る。
/// UIテスト・CIスクリーンショットがPhotosPickerに依存せず編集画面まで到達するための足場。
struct DemoProjectSeeder {
    let createProject: CreateProjectUseCase
    let addPhoto: AddPhotoUseCase
    let createXPost: CreateXPostUseCase
    let listProjects: ListProjectsUseCase

    func seedIfNeeded() async {
        do {
            let existing = try await listProjects.execute()
            // 単ページデモ（フェーズ2スクショ用）
            if !existing.contains(where: { $0.title == "デモ" }) {
                let project = try await createProject.execute(
                    title: "デモ",
                    preset: .instagram(aspect: .portrait, pageCount: 1),
                    framePreset: .whiteMargin
                )
                _ = try await addPhoto.execute(project: project, imageData: Self.demoImageData(variant: 0))
            }
            // X 3枚デモ（フェーズ3スクショ用: 8:9 + 16:9 x 2 のページ自動生成）
            if !existing.contains(where: { $0.title == "X投稿（3枚）" }) {
                _ = try await createXPost.execute(
                    imageDataList: (0..<3).map { Self.demoImageData(variant: $0) },
                    framePreset: .whiteMargin
                )
            }
        } catch {
            // デモシードの失敗はアプリ動作に影響させない
        }
    }

    /// 3000x2000の生成画像（グラデーション＋円）。variantで配色を変えて区別できるようにする。
    private static func demoImageData(variant: Int) -> Data {
        let palettes: [(UIColor, UIColor)] = [
            (.systemIndigo, .systemOrange),
            (.systemTeal, .systemPink),
            (.systemGreen, .systemPurple)
        ]
        let (start, end) = palettes[variant % palettes.count]
        let size = CGSize(width: 3000, height: 2000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [start.cgColor, end.cgColor] as CFArray
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
