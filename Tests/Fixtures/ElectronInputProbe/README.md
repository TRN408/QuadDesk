# Electronの受信側を検証する

Discordで報告された不反応を、外部通信のない2ウィンドウで切り分けるためのfixtureです。画面はmain.cjs内の固定HTMLのみで、メッセージ送信・ネットワーク呼び出し・他アプリの読み取り・入力生成は行いません。Electron 42.11.15（このMacのDiscordのframeworkと同じ版）で検証します。

作業用フォルダにnpmから同版のElectronをインストールし、同パッケージのinstall.jsで公式バイナリを取得します。同じディレクトリのpackage.pyへ、配布元のElectron.appと新しい出力先.appの2引数を渡してパッケージします。runtimeの版を確認し、独立したbundle IDで複製と署名を行います。依存の導入・ダウンロード・パッケージはローカルの負荷調整を使用します。試験アプリの起動・操作は通常の画面操作ツールから行います。

標準タイトルバーのAと、hiddenInsetのBを比較します。

- 「Clicks」ボタンのクリックでカウントが増えること。
- 文字欄を縮小枠から選んだ後、直接のアクティブ化より先にDOMのmousedown/click、focused=editに加え、main processが記録するBrowserWindow.isFocused()（active）がtrueであることを確認すること。DOMの入力先だけでは実キーボードを受け取れるとは判定しない。
- その後の文字入力でlengthが増えること。
- 縮小枠のスクロールでscrollYが変わり、映像の行番号も変わること。
- 別アプリから戻る、同じアプリのA/Bを切り替える条件を含めること。

ログはOSの一時フォルダのquaddesk-electron-probe.jsonlへ追記します。自分のテストウィンドウ内で受信したイベント種類・isTrusted・座標・カウンタ・文字数・入力先ID・スクロール位置・アクティブ状態を記録し、入力文字列は記録しません。DOM受信と画面更新を別々に照合し、イベントを投稿しただけでは成功と扱いません。実キーボードと実際のDiscordでの利用者確認は別途必要です。

## Lifecycle regression and resource updates

This is a separate local test application. It reports input counts, focus and
scroll positions; it does not generate input or store typed text.

Run the lifecycle regression without installing or starting Electron:

```sh
node --test Tests/Fixtures/ElectronInputProbe/lifecycle.test.cjs
```

The tests execute the actual main-process source against lifecycle doubles whose
destroyed native getters throw. They cover closing the first window while the
second continues sending, late IPC, destroyed entries before cleanup, invalid
senders, closing before ready-to-show and shutdown.

To update an existing installed fixture after quitting it:

```sh
python3 scripts/update_electron_probe.py /absolute/path/QuadDeskElectronProbe.app /absolute/path/new-backup-directory
```

The updater checks the bundle ID, refuses a running fixture, backs up its
resources and Info.plist, retains the installed Electron runtime, and verifies
the updated ad hoc signature. It neither downloads software nor controls UI.

Version 1.0.1 removes closed windows from the registry and checks native-object
liveness before accessing webContents, recording metadata or showing a window.
