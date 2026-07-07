import Foundation
import Observation
import UIKit
import PhotoLayoutCore

@Observable
@MainActor
final class PageEditorViewModel {
    private(set) var project: ProjectEntity
    private(set) var previewImages: [UUID: UIImage] = [:]
    var isExporting = false
    var exportMessage: String?
    var errorMessage: String?

    private let saveProject: SaveProjectUseCase
    private let addPhoto: AddPhotoUseCase
    private let exportPage: ExportPageUseCase
    private let imageProvider: any PreviewImageProviding

    init(
        project: ProjectEntity,
        saveProject: SaveProjectUseCase,
        addPhoto: AddPhotoUseCase,
        exportPage: ExportPageUseCase,
        imageProvider: any PreviewImageProviding
    ) {
        self.project = project
        self.saveProject = saveProject
        self.addPhoto = addPhoto
        self.exportPage = exportPage
        self.imageProvider = imageProvider
    }

    var page: PageEntity? { project.orderedPages.first }
    var hasPhoto: Bool { !project.placements.isEmpty }

    func onAppear() async {
        await refreshImages()
    }

    func addPhotoData(_ data: Data) async {
        do {
            project = try await addPhoto.execute(project: project, imageData: data)
            await refreshImages()
        } catch {
            errorMessage = "写真を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func setAspect(_ aspect: AspectRatio) async {
        project.setPageAspect(aspect)
        await persistAndRefresh()
    }

    /// 全面配置（ワンタップ配置アクション。永続モードではない）
    func placeFill() async {
        project.placeAllFillingPage()
        await persistAndRefresh()
    }

    /// マット配置（写真全体を余白付きで見せる）
    func placeMat() async {
        project.placeAllMatted()
        await persistAndRefresh()
    }

    func applyPreset(_ preset: FramePreset) async {
        project.applyFramePreset(preset)
        await persistAndRefresh()
    }

    func export() async {
        guard hasPhoto else {
            exportMessage = "写真を追加してください"
            return
        }
        isExporting = true
        defer { isExporting = false }
        do {
            let result = try await exportPage.execute(project: project, pageIndex: 0)
            let mb = Double(result.byteCount) / 1_000_000
            exportMessage = String(
                format: "書き出し完了: %.0f×%.0fpx / %.1fMB\nカメラロールに保存しました",
                result.pixelSize.width, result.pixelSize.height, mb
            )
        } catch {
            exportMessage = "書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    private func persistAndRefresh() async {
        do {
            project = try await saveProject.execute(project)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshImages()
    }

    private func refreshImages() async {
        previewImages = await imageProvider.previewImages(project: project)
    }
}
