/// 取り込み済み写真への参照。PHAsset識別子ではなく、アプリ内SourceImages/への
/// ローカルコピーのファイル名を保持する（フルライブラリ読み取り権限を不要にするため）。
public struct PhotoRef: Hashable, Codable, Sendable {
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(fileName: String, pixelWidth: Int, pixelHeight: Int) {
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var aspectRatio: AspectRatio {
        AspectRatio(width: Double(pixelWidth), height: Double(pixelHeight))
    }
}
