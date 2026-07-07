/// 書き出しフォーマット。写真主体はJPEG既定、PNGはサイズ保証なしのオプトイン。
public enum ExportFormat: Hashable, Codable, Sendable {
    case jpeg(quality: Double)
    case png

    public static let defaultJPEG = ExportFormat.jpeg(quality: 0.92)
}
