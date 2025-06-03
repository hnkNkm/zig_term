# Zig Terminal Emulator Development Environment
FROM ubuntu:22.04 AS zig-base

# タイムゾーンの設定（インタラクティブな入力を避けるため）
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

# 必要なパッケージをインストール
RUN apt-get update && apt-get install -y \
    curl \
    tar \
    xz-utils \
    build-essential \
    libc6-dev \
    linux-libc-dev \
    git \
    ca-certificates \
    bash \
    zsh \
    fish \
    libncurses5-dev \
    libncursesw5-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 最新のZigをインストール（バージョン0.14.1）
ARG ZIG_VERSION=0.14.1
ENV ZIG_VERSION=${ZIG_VERSION}

# アーキテクチャの検出とZigのダウンロード
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        ZIG_ARCH="aarch64"; \
    elif [ "$ARCH" = "amd64" ]; then \
        ZIG_ARCH="x86_64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading Zig ${ZIG_VERSION} for ${ZIG_ARCH}..." && \
    curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" -o zig.tar.xz && \
    echo "Extracting Zig..." && \
    tar -xf zig.tar.xz && \
    mv zig-${ZIG_ARCH}-linux-${ZIG_VERSION} /opt/zig && \
    rm zig.tar.xz && \
    echo "Zig installation completed"

# Zigをパスに追加
ENV PATH="/opt/zig:${PATH}"

# 開発環境
FROM zig-base AS dev-env

# 開発に必要な追加ツール
RUN apt-get update && apt-get install -y \
    vim \
    nano \
    tmux \
    htop \
    valgrind \
    gdb \
    strace \
    lsof \
    procps \
    tree \
    && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリを設定
WORKDIR /workspace

# Zigのバージョン確認とキャッシュディレクトリ作成
RUN zig version && \
    mkdir -p /workspace/.zig-cache && \
    mkdir -p /workspace/zig-out

# ポート3000を開放（デバッグサーバー用）
EXPOSE 3000

# 開発用エントリーポイント
ENTRYPOINT ["/bin/bash"]

# プロダクション用ビルド
FROM zig-base AS builder

COPY . /workspace
WORKDIR /workspace

# 環境変数を設定してマクロ定義を制御
ENV CC="zig cc"
ENV CXX="zig c++"

# 依存関係の解決とビルド（マクロ定義なしでビルド）
RUN zig build --release=fast -Dcpu=baseline

# 最小限のランタイム環境
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libncurses5 \
    libncursesw5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /workspace/zig-out/bin/zterm /usr/local/bin/zterm

ENTRYPOINT ["/usr/local/bin/zterm"] 