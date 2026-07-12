import Foundation
import PhotoLayoutCore

/// 共有シート用に書き出し画像Dataを一時ファイルへ書き出す。
/// カメラロールへの保存（PhotoLibrarySaving）とは独立した経路。
protocol ShareFileWriting: Sendable {
    func writeTemporaryFiles(_ dataList: [Data], format: ExportFormat) async throws -> [URL]
}
