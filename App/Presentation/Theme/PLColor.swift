import SwiftUI
import UIKit

/// デザイン刷新（暗室/フィルムモチーフ）のカラートークン。
/// 素材色（primitive）と、ライト/ダークで意味が変わる役割色（semantic）を分ける。
/// 役割色はダークモードで「暗室」（graphite基調）、ライトモードで「印画紙」（print基調）に切り替わる。
enum PLColor {

    // MARK: - Primitive（素材色。直接は使わずsemanticの定義にのみ使う）

    static let graphite = plColor(0x17, 0x18, 0x1A)
    static let graphite2 = plColor(0x1F, 0x20, 0x23)
    static let graphite3 = plColor(0x26, 0x27, 0x2B)

    /// `LayoutColor.cream`（写真の縁色プリセット）と同系統だが同一値ではない。
    /// creamをそのまま画面全体の背景など大面積に敷くと彩度が強く出すぎるため、
    /// UI面用に少し落ち着かせた別トークンとして独立させている
    static let print = plColor(0xED, 0xE6, 0xD6)
    static let print2 = plColor(0xE3, 0xD9, 0xC3)
    static let print3 = plColor(0xF6, 0xF1, 0xE6)

    /// セーフライト色。唯一のアクセント。選択中・操作可能な状態にのみ使う（装飾には使わない）。
    /// 小さい本文サイズのテキスト色としては使わない（背景とのコントラストが4.5:1を割るため。
    /// 18pt以上の大きな/太い文字か、リング・塗り・アイコンの用途に限定する）
    static let safelight = plColor(0xC2, 0x4A, 0x2C)
    static let safelightPressed = plColor(0xA8, 0x3D, 0x22)

    static let ink = plColor(0x21, 0x1D, 0x18)
    static let paperInk = plColor(0xF2, 0xEF, 0xE9)

    /// print面用の中間色（本文以外のラベル用途で4.5:1以上を確保。#8B8478は3:1を割るため不採用）
    static let fog = plColor(0x65, 0x5E, 0x52)
    /// graphite面用の中間色
    static let mist = plColor(0x8B, 0x90, 0x96)

    // MARK: - Semantic（画面から使うのはこちら。ライト/ダークで自動的に切り替わる）

    /// アプリの基調背景。ライト=印画紙、ダーク=暗室
    static let background = adaptive(light: print, dark: graphite)
    /// カード・シートなどの一段上の面
    static let surface = adaptive(light: print3, dark: graphite2)
    /// surfaceよりさらに一段（セグメントコントロールの溝など）
    static let surfaceSecondary = adaptive(light: print2, dark: graphite3)

    static let textPrimary = adaptive(light: ink, dark: paperInk)
    static let textSecondary = adaptive(light: fog, dark: mist)

    /// 唯一のアクセント。ライト/ダークで色自体は変えない（セーフライトは暗室でも印画紙の上でも同じ色で機能する）
    static let accent = safelight
    static let accentPressed = safelightPressed
    /// アクセントで塗った面（ボタン等）の上のテキスト・アイコン色。
    /// accent自体がライト/ダークで変わらないため、こちらも固定色にする
    /// （以前はadaptiveにしていたが、safelight上ではダーク側の暗い色より白の方が
    /// コントラストが高い＝ライト/ダークで変える理由がないミスだった。白地4.87:1 vs 旧ダーク値3.57:1）
    static let accentText = Color.white

    static let hairline = adaptive(
        light: plColor(0x21, 0x1D, 0x18, opacity: 0.13),
        dark: plColor(0xF2, 0xEF, 0xE9, opacity: 0.14)
    )

    /// ライト/ダークで異なる色を返すDynamic Color。Asset Catalogを持たないため、UIColorのtraitベース解決を使う
    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// 0...255の整数から`Color`を作る（`Double`除算の型推論に頼らず明示的に変換する）
    private static func plColor(_ red: Int, _ green: Int, _ blue: Int, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: opacity
        )
    }
}
