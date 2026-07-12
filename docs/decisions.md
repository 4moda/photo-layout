# 設計判断の記録

主要な設計判断と、その理由。実装の詳細は [design.md](design.md)。

## 採用した設計

### 統一「汎用プロジェクト」モデル（2026-07-09 確定）

枠付けとレイアウトを別機能にせず、同じ汎用プロジェクト（キャンバス＋画像＋書き出し）の2つの使い方として設計。

- **理由**: 「枠付き画像を作る」→「それを並べる」というワークフローが、同じ編集・描画・書き出し機構で表現でき、機能の二重実装を避けられる。SNS別モードを持たないことで分岐が消え、拡張が容易。
- **帰結**: 新規作成は「用紙サイズ（アスペクト）」を選ぶだけ。写真は後からエディタで追加する（作成時に写真選択を誘導しない）。

### プレビュー＝書き出し一致を構造で保証

`RenderPlanBuilder` が生成する `[DrawCommand]` を、プレビュー（SwiftUI Canvas）も書き出し（CoreGraphics）も解釈するだけにする。

- **理由**: 競合アプリ（SCRL 等）の低解像度・プレビュー不一致を避けることが本アプリ最大の差別化点。描画ロジックが1箇所なら乖離しえない。
- **テスト**: 400px と 4096px で枠太さ比率が一致することを定量テストで保証。

### 実解像度ベースの書き出し（`ImageRenderer.scale` 不使用）

出力は元画像の実クロップ解像度から決め、長辺4096pxにクランプ、`scale=1` の CGContext で描く。

- **理由**: `ImageRenderer(content:).scale` は画面ポイント×定数倍で実解像度を見ておらず、低解像度出力の温床。

### 自由変形モデル（cropRect + destRect）

写真は cropRect（元画像のどこを見せるか）と destRect（表示矩形）だけで表現し、fill/fit の永続モードを持たない。

- **理由**: Canva/SCRL 型の直感的操作（自由移動・アスペクト固定拡縮・枠内クロップ）を、永続状態を増やさず表現できる。
- **不変条件**: destRect の px アスペクト == cropRect の px アスペクト。画像は決して歪まない。枠アスペクトを変えると見せる範囲（クロップ窓）が変わるだけ。

### プロジェクト配置モデル（placement は Project 直下・スライドを跨げる）

写真（placement）はページの子ではなく `ProjectEntity` 直下に持ち、`pageIndex` と `destRect` で所属と位置を表す。`SpreadGeometry.visiblePlacements` が隣スライドへはみ出した分も描画する。

- **理由**: 「写真はページに乗る」より「プロジェクトに配置される」ほうが、パノラマ（1枚を複数スライドに跨がせる）やテンプレのはみ出しで写真が消えないため（ユーザー指摘）。

### スロット先行テンプレート

テンプレートは写真ではなく**空スロット（矩形）**を先に敷き、あとから空スロットへ写真を充填する。

- **理由**: 「1ページにテンプレートを割り付け、そこへ写真を当てはめる」という操作イメージに一致。カルーセルを基本に、必要なスライドだけ分割できる。

### フッターは2状態（写真選択か否か）

「写真選択 / 何も選択なし」の2状態だけで、"ページ選択" 状態は持たない。

- **理由**: ページに写真が乗ると「ページ選択」ができず操作が不明瞭になった。状態を減らし、文字説明の要らない直感的UIにする（ユーザー判断）。
- **帰結**: 背景色は写真選択と無関係な「プロジェクト共通設定」へ退避（俯瞰・新規作成）。並べ替え・複製は俯瞰へ集約。

### CIスクショ撮影の機種matrix化（2026-07-12）

`ios-ci.yml` の `fastlane snapshot` ステップを、機種ごとに独立したGitHub Actions matrixジョブ（`screenshots`）へ分割。`build-test` ジョブが1回だけ行う `build-for-testing` の成果物（`DerivedData/Build/Products`）を tar化して `actions/upload-artifact` 経由で共有し、machineジョブ側は `xcodegen generate`（再コンパイルなし）だけ行って再利用する。各ジョブは自分の機種の `screenshots-<slug>` artifactを出力し、最後に `screenshots-index` ジョブ（ubuntu-latest）が全artifactを1つの `screenshots` ディレクトリへマージして `build_screenshot_index.py` を1回実行、既存と同じ単一の `screenshots` artifact名で再アップロードする。

- **理由**: 機種を増やすたびに撮影が逐次に伸びる構成だった（[#31](https://github.com/4moda/photo-layout/issues/31)、[#27](https://github.com/4moda/photo-layout/issues/27) でのオーナー指摘）。Swiftの再コンパイルはmatrixレグごとに数分かかるため、成果物を artifact 経由で共有して「ビルドは1回・撮影だけ並列」にした（各matrixレグでの再ビルドは不採用）。
- **artifact共有の実装判断**: GitHub標準のzip実装は実行ビット・シンボリックリンクの保持に不安があるため、`tar czf` で自前アーカイブしてから1ファイルとしてアップロード／ダウンロード時に展開する。共有するのは `DerivedData/Build/Products`（`.app`/`.xctest`/`.xctestrun`）のみで、容量の大きい `Build/Intermediates.noindex` は含めない。
- **Snapfile**: `devices([...])` を固定配列からやめ、`ENV["SNAPSHOT_DEVICES"]`（カンマ区切り）で絞り込む形にした。未設定時（ローカル実行）は全機種を逐次撮影する既存動作を維持。
- **既知のトレードオフ**: fastlane標準の `screenshots.html`（機種横断の素朴な一覧）は各matrixレグが機種単体分しか生成しないため、`merge-multiple` でのマージ時にどちらか一方の内容で上書きされる。実際に運用しているのは `build_screenshot_index.py` が生成する `index.html`（画面ID/機能ID/言語/端末で絞り込み可能）であり、これはマージ後に全機種分のデータで再生成するため影響なし。
- **拡張性**: 将来テーマ軸（ライト/ダーク）を追加する際は `matrix.device` を `matrix.device × matrix.theme` に拡張する想定だった。[#30](https://github.com/4moda/photo-layout/issues/30) で実際に拡張した（次項）。

### CIスクショ撮影にテーマ軸（ライト/ダーク）を追加・machine×themeへmatrix拡張（2026-07-12）

`ScreenshotSmokeTests.swift` にダークモード専用の1テストメソッド `testDarkModeSpotCheck`（S01〜S04を各1枚、`XCUIDevice.shared.appearance = .dark` でシミュレータの外観を切り替えて起動。App層には手を入れない）を追加。スクショ名は既存のライト版と同じベース名に `-dark` サフィックスを付けるだけ（例: `S01-F01-project-list-populated-dark`）で、`ja-JP/` フラットのまま既存の命名規約に乗せる。

- **並列化**: 当初は同じ `fastlane snapshot` 1回の実行にダークテストも含める案（ワークフロー変更なし）を検討したが、実行時間を鑑みてオーナーから「機種と同様に並列にしてほしい」という指示があり、`screenshots` ジョブの matrix を `device` だけから `device × theme` に拡張した（2機種×2テーマ=4並列ジョブ）。GitHub Actionsは複数のmatrix軸を書くと自動でクロス積になる。
- **テストの絞り込み**: `Snapfile` に `SNAPSHOT_ONLY_TESTING` / `SNAPSHOT_SKIP_TESTING`（カンマ区切り、空文字は未指定扱い）を追加。light legは `testDarkModeSpotCheck` だけを `skip_testing` で除外して残り全部を撮り、dark legは逆に `only_testing` でそのメソッドだけに絞る。ビルド成果物（`build-products` artifact）はテーマに依存しないため、4 leg 全てが同じものを再利用する（再ビルドなし）。
- **artifact名**: `screenshots-<device-slug>-<theme>`（例: `screenshots-iphone-16-dark`）で機種単体時と対称にした。最終的な統合は既存の `screenshots-index` ジョブがそのまま面倒を見る（パターンマッチなので軸が増えても変更不要）。
- **index.htmlのテーマフィルタ**: `build_screenshot_index.py` はスナップ名の末尾 `-dark` を見てテーマを判定し（ディレクトリ分離はしない）、`f-theme` セレクトを追加した。ディレクトリで分離する案（`ja-JP/dark/`）も検討したが、同一テストターゲット内の1メソッドとして扱えるフラット命名の方が実装・CIとも単純なため不採用。
- **見送った項目**（[#30](https://github.com/4moda/photo-layout/issues/30) 内でオーナーと合意）:
  - S02-j（書き出し中スピナー）: `isExporting` は `PreviewView`（`.fullScreenCover`）経由でしかtrueにならず、S02編集画面のツールバーは書き出し中は画面に出ないため現在のナビゲーションでは到達不能と判明。相当する状態（S04-cのPreviewView保存ボタンのスピナー）も含め今回は見送り。
  - S02-h（スナップガイド表示中）: ドラッグ中の一瞬だけ表示され指を離すと同期的に消えるため、標準のXCUITest APIでは撮れない。バックグラウンドスレッドからの撮影など実装コスト・タイミング調整のCI往復が見合わないため見送り。

### CIスクショをGitHub Actions artifactからCloudflare PagesのPRプレビューへ完全移行（2026-07-12）

`ios-ci.yml` の `screenshots-index` ジョブから `actions/upload-artifact` によるスクショartifactアップロードを廃止し、代わりに同ジョブ内でマージ済みディレクトリをそのまま `cloudflare/pages-action@v1` でCloudflare Pagesへデプロイする（PRイベント時のみ）。PRクローズ（マージ含む）時は別ワークフロー `screenshots-preview-cleanup.yml` がそのPR用デプロイをCloudflare REST APIで削除する。

- **理由**（[#32](https://github.com/4moda/photo-layout/issues/32)）: レビュアーがartifactを手動ダウンロード・展開してindex.htmlを開く手間をなくす。オーナー承認: (1) Cloudflareアカウントは既存・Pagesプロジェクトは今後作成、Secretsは登録済み前提で実装してよい、(2) 保護方式はCloudflare Access（Zero Trust）+ GitHub OAuth SSO、(3) 削除トリガーはPRクローズ時、(4) 既存artifactアップロードは廃止し完全移行。
  - **のちに一部撤回**: Cloudflare Access配下のページはSSOログインが要るため、AIエージェント（Claude Code等）は`WebFetch`/`curl`では中身を見られない（ログイン画面へリダイレクトされるだけ）。人間向け（Cloudflare Pages）とは別に、AIエージェントが`gh run download`で直接参照できる経路としてマージ後の単一`screenshots` artifactを復活させた（保持期間はリポジトリ既定のまま。オーナー判断）。(4)の「完全移行」は人間向け導線についてのみ有効とし、AI向けの経路は残す。
- **デプロイ先を`screenshots-index`ジョブ内に統合**（Appetizeのような別workflow+`workflow_run`構成は不採用）: Appetizeは毎回Xcodeビルドが要る＋mainプッシュ後のみ実行なので別ワークフローで自然だが、こちらは`screenshots-index`ジョブの時点で静的ファイルが既にディスク上に揃っており、`workflow_run`で受け渡すには結局artifactを一度アップロードする必要が生じ「成果物を一切残さない」という受け入れ条件と矛盾する。ジョブ内で直接デプロイすれば、そもそもartifactを作らずに済む。
- **PRごとのURL**: 同一Cloudflare Pagesプロジェクト（`photolayout-screenshots`）内で `branch=pr-<PR番号>` を指定してデプロイし、`https://pr-<番号>.photolayout-screenshots.pages.dev` が常に最新を指す（pushのたびに上書き）。Zero Trust Accessは `*.photolayout-screenshots.pages.dev` に対して一度だけ設定すれば、PRごとに新規Access設定は不要（人間が事前に1回だけダッシュボードで設定する前提。CIでは完結しない）。
- **Secrets未設定時の挙動**: Appetizeの前例（`APPETIZE_API_TOKEN`未設定ならジョブを失敗させる）とは異なり、こちらは`screenshots-index`が全PRで毎回走るジョブのため、未設定のまま即失敗にすると人間がCloudflareを用意するまで全PRのCIが赤くなってしまう。そのため「Secretsが空なら`::notice::`を出してデプロイ・削除ステップだけを静かにスキップ」する設計にした。Secrets設定後に発生する本物のエラー（トークン誤りなど）はステップ自体が失敗するため見逃さない。
- **削除の実装**: `cloudflare/pages-action`にはデプロイ削除機能が無いため、`screenshots-preview-cleanup.yml`でCloudflare REST API（`GET .../deployments`一覧を`deployment_trigger.metadata.branch`で自前フィルタ→`DELETE .../deployments/{id}?force=true`）を直接叩く。
- **未確定事項**: Cloudflareアカウントでのプロジェクト作成・Zero Trust Access設定・`CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` Secretsの登録は人間側の作業として残っている。設定が完了するまでデプロイ・削除は静かにスキップされる。
- **実CI検証で判明した問題と修正**（Secrets登録後の初回実機デプロイで発覚）:
  - matrixの全leg（機種×テーマ）がconcurrency cancel等で空振りすると`screenshots`ディレクトリが作られず、`cloudflare/pages-action`のwranglerが存在しないディレクトリを`scandir`してcrashしていた。`screenshots`配下に最低1枚のpngがあるかを事前チェックし、無ければデプロイをスキップするよう修正。
  - `cloudflare/pages-action`の`outputs.alias`は、direct uploadデプロイでは期待していたブランチエイリアス（`pr-<番号>.<project>.pages.dev`、安定URL）ではなく、デプロイ個別のハッシュURL（pushのたびに変わる）を返すことがあると判明。PRコメントに載せるURLはactionの出力に頼らず`https://pr-<PR番号>.photolayout-screenshots.pages.dev`を自前で組み立てる形にした（ブランチエイリアス自体は実在し安定して同じ内容を指すことをcurlで確認済み）。
  - `screenshots-preview-cleanup.yml`の削除ループが、ページ走査中にその場で`DELETE`していたため一部デプロイを削除し損ねていた（[#41](https://github.com/4moda/photo-layout/issues/41)）。あるページで削除すると、Cloudflare側の残存一覧では後続要素が前方へ繰り上がり、次に要求する`page+1`はその繰り上がり後の一覧を返すため、繰り上がった分の要素が一度もどのページ取得にも現れず削除されない。全ページを削除なしで走査してid一覧を収集し終えてから、まとめて削除する二段階へ分離して修正。
  - `cloudflare/pages-action`に`gitHubToken`を渡しているため、Cloudflare側のPages Deploymentとは別に、GitHub純正のDeploymentsオブジェクト（`repos/.../deployments`、PRタイムラインの小さな行）もpushのたびに作られる。上記のCloudflare REST API削除では一切消えないため、`screenshots-preview-cleanup.yml`にGitHub Deployments API（`GET .../deployments?ref=<branch>`でサーバー側フィルタ→各idを`inactive`ステータス化してから`DELETE .../deployments/{id}`）で独立して片付けるステップを追加した。GitHubは削除対象のdeploymentがinactive/error/failureのいずれかでないと削除を拒否するため、削除前に必ずinactive化する。こちらもページング中の削除は同種の読み飛ばしを起こしうるため、Cloudflare側と同じく収集→削除の二段階にしている。

### trunk ベース開発（2026-07-08 改定）

Issue/PR 単位をやめ、動く段階まで仕上げて main へ直接コミット。詳細は [../CLAUDE.md](../CLAUDE.md)。

- **理由**: Macなし＋CI往復10分の制約下では、レビュー往復より「シミュレータ（Appetize）/実機での動作確認」を早く回すほうが速い、というユーザー判断。

## 廃止した設計（復活させないこと）

| 廃止したもの | 置き換え | 復活させない理由 |
|---|---|---|
| SNS別モード（X編集専用ビュー、`isXPost` 分岐） | 汎用プロジェクト＋テンプレート＋汎用書き出し | モードは分岐を増やし拡張を妨げる。SNSはラベル/プリセットで十分 |
| fill/fit の永続モード（`ContentMode`） | 自由変形（cropRect + destRect） | 永続状態が増え、自由な配置と両立しない |
| ページ送りUI（`< 1/N >`） | シームレス連結キャンバス | Instagramカルーセルの「繋がって見える」体験に必要 |
| `ImageRenderer(content:).scale` | 目標px・`scale=1` の CGContext | 実解像度を見ておらず低解像度化する |
| 一覧での写真選択誘導 | 作成は用紙サイズ選択のみ、写真は [+] で後追加 | 作成と素材追加は別ステップ（ユーザー要望） |
| 3状態メニュー（写真/ページ/無選択を区別） | 2状態（写真選択か否か） | 写真が乗ったページは選択できず操作が不明瞭。状態を減らし直感性優先 |
| 写真メニューの多項目（全面/マット等） | 枠比率 / クロップ / 枠 / 削除 に集約 | 文字説明が要るUIを避ける。前面/背面はレイヤー順シートへ、差し替えは廃止 |
| ページ単位の背景設定UI | プロジェクト共通背景（俯瞰・新規作成） | 「枠＝写真単位」「背景＝プロジェクト単位」で責務分離。混在をやめる |
| 一覧のレイアウト名表示 | サムネイルのみ（SCRL 風グリッド） | 名前より中身（1ページ目プレビュー）で識別するほうが速い |
| ダウンロード即保存 | プレビュー画面（`PreviewView`）を挟む | 書き出し前に全スライドの仕上がりを確認できるようにする |

## 経緯（Issue）

エディタ刷新の各機能は GitHub Issue #8〜#16（トラッキング #17）に、背景・仕様・受け入れ条件つきで記録されている。
