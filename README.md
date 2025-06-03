# ZTerm - Zig ターミナルエミュレータ

Zig と ncurses ライブラリを使用した軽量なターミナルエミュレータです。Docker 環境での開発に最適化されており、zsh/bash のような基本的なシェル機能を提供します。

## 特徴

- 🚀 **高性能**: Zig で実装された高速なターミナルエミュレータ
- 🐳 **Docker 対応**: 完全にコンテナ化された開発環境
- 📚 **最新技術**: Zig 0.12.0 と最新の Ubuntu 22.04 LTS ベース
- 🎯 **軽量**: 最小限の依存関係で効率的な動作
- 🔧 **カスタマイズ可能**: 拡張しやすいモジュラー設計

## 機能

### 内蔵コマンド

- `cd [dir]` - ディレクトリの変更
- `pwd` - 現在のディレクトリを表示
- `ls [dir]` - ディレクトリの内容を表示
- `echo [text]` - テキストを表示
- `help` - ヘルプを表示
- `exit` - ターミナルを終了

### キーバインド

- `Ctrl+C`, `Ctrl+D`, `ESC` - ターミナル終了
- `↑/↓` - コマンド履歴の閲覧
- `←/→` - カーソル移動
- `Backspace` - 文字削除

### 外部コマンド

- システムにインストールされた任意のコマンドを実行可能

## システム要件

- Docker
- Docker Compose
- Git

## セットアップ

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd zterm
```

### 2. Docker 環境の構築

```bash
# 開発環境の起動
docker-compose up -d zterm-dev

# コンテナに接続
docker-compose exec zterm-dev bash
```

### 3. ビルドと実行

```bash
# 開発ビルド
zig build

# リリースビルド
zig build --release=fast

# 実行
zig run src/main.zig

# または
./zig-out/bin/zterm
```

## Docker 環境

### 利用可能なサービス

#### zterm-dev (開発環境)

- インタラクティブな開発環境
- デバッグツール付き (gdb, valgrind, strace)
- ポート 3000 が開放済み

```bash
docker-compose up -d zterm-dev
docker-compose exec zterm-dev bash
```

#### zterm-build (ビルド専用)

- プロダクションビルド用
- 最小限の環境

```bash
docker-compose run --rm zterm-build
```

#### zterm-runtime (実行専用)

- 最小限のランタイム環境
- セキュリティ重視

```bash
docker-compose run --rm zterm-runtime
```

## 開発

### プロジェクト構造

```
zterm/
├── src/
│   ├── main.zig          # メインエントリーポイント
│   ├── terminal.zig      # ターミナルエミュレータ
│   └── shell.zig         # シェル機能
├── build.zig             # ビルド設定
├── Dockerfile            # マルチステージDockerfile
├── docker-compose.yml    # Docker Compose設定
└── README.md            # このファイル
```

### ビルドオプション

```bash
# デバッグビルド
zig build debug

# テスト実行
zig build test

# 実行（引数付き）
zig build run -- --help
```

### デバッグ

```bash
# gdbでのデバッグ
gdb ./zig-out/bin/zterm

# valgrindでのメモリチェック
valgrind ./zig-out/bin/zterm

# straceでのシステムコール追跡
strace ./zig-out/bin/zterm
```

## 拡張

### 新しいコマンドの追加

1. `src/shell.zig`の`execute`関数に新しいコマンドを追加
2. ハンドラー関数を実装
3. テストを追加

### 新しいキーバインドの追加

1. `src/main.zig`の`runMainLoop`関数にキーハンドリングを追加
2. `src/terminal.zig`に対応するハンドラーを実装

## トラブルシューティング

### よくある問題

#### 1. ncurses ライブラリが見つからない

```bash
# Ubuntu/Debian
apt-get install libncurses5-dev libncursesw5-dev

# Alpine Linux
apk add ncurses-dev

# CentOS/RHEL/Fedora
yum install ncurses-devel
```

#### 2. 文字化け

環境変数`TERM`を設定してください：

```bash
export TERM=xterm-256color
```

#### 3. コンパイルエラー

依存関係を確認してください：

```bash
# Ubuntu/Debian
apt-get install build-essential libc6-dev
```

## ライセンス

MIT License

## 貢献

1. このリポジトリをフォーク
2. 機能ブランチを作成 (`feature/amazing-feature`)
3. 変更をコミット (`feat: 素晴らしい機能を追加`)
4. ブランチをプッシュ
5. プルリクエストを作成

## 関連リンク

- [Zig 公式サイト](https://ziglang.org/)
- [ncurses ライブラリ](https://invisible-island.net/ncurses/)
- [Docker 公式サイト](https://www.docker.com/)
