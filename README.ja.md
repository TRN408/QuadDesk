# QuadDesk

Macの4つのアプリを、通常サイズの内容のまま1枚の画面へ縮小表示する無料のオープンソースアプリです。
1つを拡大すると通常の文字サイズへ戻り、作業後は4画面へ戻せます。

[English](README.md) · [試験版0.7.10をダウンロード](https://github.com/TRN408/QuadDesk/releases/tag/v0.7.10-alpha.1) · [MITライセンス](LICENSE)

## 現在の状態

**v0.7.10-alpha.1の試験版です。** コード上の要件はmacOS 14以降ですが、実機確認はmacOS 15.6・Apple Silicon・内蔵画面1枚です。
配布アプリはApple Silicon用です。Intel・他のOS・長時間利用・スリープ復帰・すべての日本語IME操作は未確認です。
外部ディスプレイや既存のミラーリングがある構成では開始しません。
検証したMacではFinderの元状態取得に失敗しているため、現在はFinder以外の通常ウィンドウを選んでください。

仮想ディスプレイの非公開APIを使うため、macOSの更新で動かなくなる場合があります。
4画面中はMac全体の表示倍率が変わり、メニューバー・Dock・他のウィンドウも小さくなります。
切り替え時に暗転やウィンドウ移動が発生する場合があります。

## インストール

1. [Releases](https://github.com/TRN408/QuadDesk/releases/tag/v0.7.10-alpha.1)から `QuadDesk-0.7.10-alpha.1-macos-arm64.zip` を取得します。
2. 展開し、QuadDesk.appを「アプリケーション」へ移動してから起動します。
3. アプリ内の設定ボタンからmacOSの「画面収録」「アクセシビリティ」を許可します。必要に応じてアプリを再起動し、アプリ内で両方が「許可済み」になったことを確認します。

0.7.10では権限設定ボタン・状態の自動確認・開始条件の確認を追加しました。
[初回導入の確認手順](docs/FIRST_RUN.md)には、更新後に設定がオンでも未許可になる場合の登録し直し方も記載しています。

配布アプリはアドホック署名で、Appleの公証は受けていません。初回起動時にmacOSが停止する場合があります。
利用を判断する際は[Appleの案内](https://support.apple.com/ja-jp/102445)を確認するか、ソースからビルドしてください。
GatekeeperやSIPを無効にする必要はありません。

## 使い方

4枠に異なるウィンドウを選択します。最小化・フルスクリーンは開始時に自動解除し、その後の通常配置を保存します。
初期設定は、4枠の配置が完了してから15秒のプレビューです。
準備にも別に25秒の復帰監視上限があります。
連続利用は「作業モード」を選びます。

- 緑ボタンなどで選択中の画面を拡大すると、通常の表示倍率・文字サイズへ戻ります。Chromeでも確認済みです。
- Control + Option + 1〜4：各枠を1画面にする。
- Control + Option + 0、格子メニュー、1画面中のDock：4画面へ戻る。
- Control + Option + Esc、格子メニュー、終了：元の表示と通常ウィンドウの配置へ戻る。

4画面中にDockのQuadDeskを押すと停止します。開始前から同じアプリの複数画面が別Spaceにある場合は、
同じ通常デスクトップへ揃える必要があります。対象を閉じた場合はその枠だけ選び直します。
終了後は保存した通常配置へ戻り、元のフルスクリーンSpace・最小化状態そのものは復元しません。

## ビルド

Xcode / Command Line ToolsとSwift 5.9以降が必要です。開発時のツールチェーンはSwift 6.2.4です。

```sh
git clone https://github.com/TRN408/QuadDesk.git
cd QuadDesk
bash scripts/validate_native_windows.sh "$PWD/dist/QuadDesk.app"
python3 scripts/verify_package.py dist/QuadDesk.app
```

その後 `dist/QuadDesk.app` を開きます。テスト・ビルド自体は表示構成を変更しません。
既定の署名はアドホックです。自分の署名証明書を使う場合だけ `QUADDESK_SIGN_IDENTITY` を指定します。
詳しい[検証範囲](docs/TESTING.md)・[プライバシー](PRIVACY.md)・[貢献方法](CONTRIBUTING.md)も確認できます。

MITライセンスで無料利用・改変・再配布できます。商用利用も可能ですが、ライセンス表示を残してください。
