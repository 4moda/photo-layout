import PhotoLayoutCore

/// アスペクト比選択UIの共有ラベル・並び順定義。新規作成シート（S01 `ProjectListView`）・
/// 比率メニュー（S03 `PageOverviewView`）・枠比率シート（S02 `PageEditorView`）の3画面が
/// 同じ比率に同じラベル・同じ相対順序で参照する（ラベル表記や並び順がバラバラだった問題の解消）。
enum AspectRatioOption: String, CaseIterable {
    case portrait916
    case portrait34
    case portrait45
    case square
    case landscape169
    case landscape191

    var aspect: AspectRatio {
        switch self {
        case .portrait916: return AspectRatio(width: 9, height: 16)
        case .portrait34: return AspectRatio(width: 3, height: 4)
        case .portrait45: return AspectRatio(width: 4, height: 5)
        case .square: return AspectRatio(width: 1, height: 1)
        case .landscape169: return AspectRatio(width: 16, height: 9)
        case .landscape191: return AspectRatio(width: 1.91, height: 1)
        }
    }

    var label: String {
        switch self {
        case .portrait916: return "9:16"
        case .portrait34: return "3:4"
        case .portrait45: return "4:5"
        case .square: return "1:1"
        case .landscape169: return "16:9"
        case .landscape191: return "1.91:1"
        }
    }

    /// SNS用途キャプション（サービス名/機能の2行）。S01用紙サイズシートとS03比率メニューで
    /// スウォッチの下に表示する（S02枠比率シートは写真単体のクロップ窓なので使わない）。
    /// SNS側の仕様変更に追従するのはこの2プロパティの文字列だけ。
    var captionService: String {
        switch self {
        case .portrait916: return "Instagram"
        case .portrait34: return "X"
        case .portrait45: return "Instagram"
        case .square: return "Instagram"
        case .landscape169: return "X"
        case .landscape191: return "Instagram"
        }
    }

    var captionUsage: String {
        switch self {
        case .portrait916: return "Story"
        case .portrait34: return "縦"
        case .portrait45: return "投稿(縦)"
        case .square: return "投稿"
        case .landscape169: return "横"
        case .landscape191: return "横"
        }
    }

    /// 統一並び順（縦系 → 正方形 → 横系、各グループ内は比率の昇順）。
    /// S01・S03はこの6つ全部をこの順で表示し、S02は`landscape191`を除いた5つをこの順で使う。
    static let orderedAll: [AspectRatioOption] = [
        .portrait916, .portrait34, .portrait45, .square, .landscape169, .landscape191
    ]
}
