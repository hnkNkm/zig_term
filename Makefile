# ZTerm Makefile
.PHONY: help build run test clean docker-build docker-dev docker-run install

# デフォルトターゲット
all: build

# ヘルプ表示
help:
	@echo "ZTerm - Zigターミナルエミュレータ"
	@echo ""
	@echo "利用可能なコマンド:"
	@echo "  build        - プロジェクトをビルド"
	@echo "  run          - ターミナルを実行"
	@echo "  test         - テストを実行"
	@echo "  clean        - ビルドファイルを削除"
	@echo "  docker-build - Dockerイメージをビルド"
	@echo "  docker-dev   - 開発環境を起動"
	@echo "  docker-run   - 本番環境でコンテナを実行"
	@echo "  install      - バイナリをシステムにインストール"

# ビルド
build:
	zig build

# リリースビルド
release:
	zig build --release=fast

# デバッグビルド
debug:
	zig build debug

# 実行
run:
	zig build run

# テスト実行
test:
	zig build test

# クリーンアップ
clean:
	rm -rf zig-cache zig-out .zig-cache

# Docker開発環境のビルド
docker-build:
	docker-compose build

# Docker開発環境の起動
docker-dev:
	docker-compose up -d zterm-dev
	@echo "開発環境が起動しました。以下のコマンドで接続してください:"
	@echo "docker-compose exec zterm-dev bash"

# Docker開発環境の停止
docker-stop:
	docker-compose down

# Docker本番環境での実行
docker-run:
	docker-compose run --rm zterm-runtime

# システムへのインストール（要sudo権限）
install: release
	sudo cp zig-out/bin/zterm /usr/local/bin/

# アンインストール
uninstall:
	sudo rm -f /usr/local/bin/zterm

# 開発環境のセットアップ
setup: docker-build
	@echo "開発環境のセットアップが完了しました"
	@echo "make docker-dev でコンテナを起動してください"

# フォーマット（将来的にzig fmtが利用可能になった場合）
format:
	@echo "Zigのフォーマッタは今後のリリースで利用可能になります"

# プロジェクトの統計情報
stats:
	@echo "=== プロジェクト統計 ==="
	@echo "ソースファイル数:"
	@find src -name "*.zig" | wc -l
	@echo "総行数:"
	@find src -name "*.zig" -exec wc -l {} + | tail -n 1

# Docker環境での開発用シェル
shell:
	docker-compose exec zterm-dev bash

# ログ確認
logs:
	docker-compose logs -f

# Dockerイメージの削除
docker-clean:
	docker-compose down --rmi all --volumes --remove-orphans 