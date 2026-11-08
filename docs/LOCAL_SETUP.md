# 開発者・コードレビュー向けのローカル起動

通常の利用と実演は[公開サイト](https://recsort-studio.alikemerit.chatgpt.site/)から行います。
以下は先生がダウンロードしたソースを手元で確認する場合の補足です。

2026年11月8日のmainのWebソースはv0.6.0開発版で、公開サイトv0.5.0より先の機能を含みます。iPhone試作は別の[Mac / Xcode起動手順](../native/RecSort-iOS/README.md)に従ってください。学校提出版v0.3.3は`dist/school-demo/`に保持しています。

## ローカル起動に必要な環境

- Python 3.12以降を推奨（ローカル配信用。今回の起動確認は3.12.14）
- JavaScript・ES Modules・HTML dialogに対応したブラウザ（Chrome / Edge / Safariなどを想定。すべての組み合わせは未検証）
- Web版には追加のPythonライブラリ、npmパッケージ、APIキー、データベースは不要です。

Windows/macOS向けの起動手順を用意しています。全OS・全ブラウザの動作保証はしていません。iPhoneの写真ライブラリ選択は実機未検証です。

## 起動方法

GitHubの「Code」から「Download ZIP」で取得し、ZIPを解凍してください。README.mdのあるフォルダでターミナルを開きます。HTMLファイルの直接ダブルクリックではなく、次のHTTPサーバー経由で開きます。

### Windows

Python未導入の場合は https://www.python.org/downloads/ からPython 3を導入します。

```powershell
py -3 --version
py -3 start.py
```

`py`が使えず`python`でPython 3が起動できる場合は、`python start.py`でも構いません。

### macOS

Python 3がなければ上記の公式サイトから導入してください。

```sh
python3 --version
python3 start.py
```

起動後、ブラウザで **http://127.0.0.1:8765** を開きます。このURLは自分のPC専用で、サーバー起動中だけ開けます。公開デモを使うだけならPythonの導入は不要です。停止はターミナルでCtrl+C。8765番が使用中なら `python3 start.py --port 8766`（Windowsは `py -3 start.py --port 8766`）を実行し、表示されたURLを開きます。

標準機能だけで起動する代替コマンド：`python3 -m http.server 8765 --bind 127.0.0.1 --directory dist`。

