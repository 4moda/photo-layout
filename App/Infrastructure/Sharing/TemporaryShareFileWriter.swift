import Foundation
import PhotoLayoutCore

/// ShareFileWritingの実装。共有シートに渡すため、書き出し済みDataを一時ディレクトリへ
/// ファイルとして書き出す。クリーンアップはOSの一時ディレクトリ管理に委ねる。
final class TemporaryShareFileWriter: ShareFileWriting {
    func writeTemporaryFiles(_ dataList: [Data], format: ExportFormat) async throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = fileExtension(for: format)
        var urls: [URL] = []
        for (index, data) in dataList.enumerated() {
            let url = directory.appendingPathComponent("page-\(index + 1).\(ext)")
            try data.write(to: url)
            urls.append(url)
        }
        return urls
    }

    private func fileExtension(for format: ExportFormat) -> String {
        switch format {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}
