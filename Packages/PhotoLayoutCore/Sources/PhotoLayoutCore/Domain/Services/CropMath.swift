/// クロップ矩形の共通計算。配置ヘルパ（ProjectEntity+Mutations）と
/// RenderPlanBuilderの防御的正規化の両方から使う。
public enum CropMath {
    /// crop（元画像に対する正規化矩形）を、実ピクセルアスペクトがtargetPixelAspectに
    /// なるよう中央でさらに絞り込む。すでに一致していればそのまま返す。
    public static func subCrop(
        _ crop: LayoutRect,
        photo: PhotoRef,
        targetPixelAspect: Double
    ) -> LayoutRect {
        let cropPxW = crop.width * Double(photo.pixelWidth)
        let cropPxH = crop.height * Double(photo.pixelHeight)
        guard cropPxW > 0, cropPxH > 0, targetPixelAspect > 0 else { return crop }
        let sourceAspect = cropPxW / cropPxH

        if sourceAspect > targetPixelAspect {
            let scale = targetPixelAspect / sourceAspect
            let newWidth = crop.width * scale
            return LayoutRect(x: crop.midX - newWidth / 2, y: crop.y, width: newWidth, height: crop.height)
        } else if sourceAspect < targetPixelAspect {
            let scale = sourceAspect / targetPixelAspect
            let newHeight = crop.height * scale
            return LayoutRect(x: crop.x, y: crop.midY - newHeight / 2, width: crop.width, height: newHeight)
        }
        return crop
    }
}
