#!/usr/bin/env bash
#
# Keyball 用 セットアップ + ビルド 一発スクリプト（超丁寧コメント付き）
#
# 対象OS:
#   - Windows: MSYS2(MINGW64) シェル想定（Start Menu から MSYS2 MinGW 64-bit を起動）
#   - macOS  : Terminal.app + Homebrew
#   - Ubuntu : 22.04/24.04 系（apt）
#
# できること:
#   1) 依存コマンドの有無を確認（無ければ各OSごとの導入コマンドを案内）
#   2) Python 仮想環境(.venv) + qmk CLI の導入
#   3) qmk_firmware / vial-qmk 側に keyboards/keyball のシンボリックリンクを作成
#   4) QMK 側で toxaO をビルド（39/44/61）
#   5) Vial 側で toxaO をビルド（例: 39）
#
# 注意:
#   - 本リポジトリ直下で実行してください（keyball/ と qmk_firmware/ と vial-qmk/ が並んでいる前提）。
#   - 依存の導入（arm-none-eabi など）は管理者権限が必要な場合があります。下記メッセージの通りに実行してください。
#   - ビルド成果物は qmk_firmware/.build/ および vial-qmk/.build/ に生成されます（.uf2 など）。

set -Eeuo pipefail

QMK_DIR="qmk_firmware"     # 公式QMKの固定ツリー（このリポ内の同名ディレクトリ）
VIAL_DIR="vial-qmk"         # Vial用のQMKツリー（このリポ内の同名ディレクトリ）
KEYBALL_DIR="keyball"       # 本リポのキーボード実装
VENV_DIR=".venv"            # qmk CLI を入れる仮想環境

say() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

# --- OS 判定（MSYS2 / macOS / Linux）-----------------------------------------
os_detect() {
  case "${MSYSTEM:-}" in
    MINGW64|UCRT64) echo "msys2"; return;;
  esac
  case "$(uname -s)" in
    Darwin) echo "mac"; return;;
    Linux)  echo "linux"; return;;
  esac
  echo "unknown"
}

OSKIND="$(os_detect)"
say "Detected OS: $OSKIND"

# --- ルート構成の確認 ---------------------------------------------------------
[ -d "$QMK_DIR" ]  || { err "$QMK_DIR が見つかりません。リポジトリ直下で実行してください"; exit 1; }
[ -d "$VIAL_DIR" ] || { err "$VIAL_DIR が見つかりません。リポジトリ直下で実行してください"; exit 1; }
[ -d "$KEYBALL_DIR" ] || { err "$KEYBALL_DIR が見つかりません"; exit 1; }

# --- 依存コマンドの有無を確認（入っていなければ導入コマンドを案内）-------------
need_cmds=("git" "make" "python3" "pip" "arm-none-eabi-gcc")
missing=()
for c in "${need_cmds[@]}"; do
  if ! command -v "$c" >/dev/null 2>&1; then missing+=("$c"); fi
done

if [ ${#missing[@]} -gt 0 ]; then
  err "不足しているコマンド: ${missing[*]}"
  echo "導入例:"
  if [ "$OSKIND" = "mac" ]; then
    echo "  brew install git make python3 arm-none-eabi-gcc"
  elif [ "$OSKIND" = "linux" ]; then
    echo "  sudo apt-get update && sudo apt-get install -y git make python3 python3-pip gcc-arm-none-eabi binutils-arm-none-eabi"
  elif [ "$OSKIND" = "msys2" ]; then
    echo "  pacman -S --needed git make python-pip"
    echo "  pacman -S --needed mingw-w64-ucrt-x86_64-arm-none-eabi-gcc mingw-w64-ucrt-x86_64-arm-none-eabi-binutils"
    echo "  （MSYS2はUCRT64またはMINGW64シェルで実行してください）"
  else
    echo "  お使いの環境に合わせて GNU Arm Embedded Toolchain 等を導入してください"
  fi
  exit 1
fi

# --- Python 仮想環境 ------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
  say "Create Python venv: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
# qmk CLI は使用しないのでインストール不要

# --- キーボード本体をQMKツリーへリンク ----------------------------------------
# 目的: 本リポの keyball/ を qmk_firmware から参照可能にするための symlink を作る
link_into_tree() {
  local tree_dir="$1"
  local from="$tree_dir/keyboards/keyball-rp"
  local to="../../$KEYBALL_DIR"
  mkdir -p "$tree_dir/keyboards"
  if [ -e "$from" ] || [ -L "$from" ]; then rm -rf "$from"; fi
  ln -s "$to" "$from"
  say "symlink: $from -> $to"
}

link_into_tree "$QMK_DIR"
link_into_tree "$VIAL_DIR"

# --- QMK 側ビルド --------------------------------------------------------------
# make を直接使用。公式の推奨手順に合わせて
#   -C qmk_firmware   : このディレクトリでMakeを実行
#   SKIP_GIT=yes  : インターネット接続前提のバージョン取得をスキップ（ローカルのみで完結）
#   最後の引数     : QMKのターゲット名（keyboard:keymap）

QMK_BUILDS=(
  "keyball-rp/keyball39:toxaO"
  "keyball-rp/keyball44:toxaO"
  "keyball-rp/keyball61:toxaO"
)

for pair in "${QMK_BUILDS[@]}"; do
  say "[QMK] build -> $pair"
  make -C "$QMK_DIR" SKIP_GIT=yes "$pair"
done

say "QMK build done. artifacts → $QMK_DIR/.build/"

# --- Vial 側ビルド -------------------------------------------------------------
# 公式の推奨手順に合わせて make を直接使用。
#   -C vial-qmk   : このディレクトリでMakeを実行
#   SKIP_GIT=yes  : インターネット接続前提のバージョン取得をスキップ（ローカルのみで完結）
#   VIAL_ENABLE=yes: Vial 機能を有効化
#   最後の引数     : QMKのターゲット名（keyboard:keymap）

say "[Vial] build -> keyball-rp/keyball39:toxaO (SKIP_GIT=yes VIAL_ENABLE=yes)"
make -C "$VIAL_DIR" SKIP_GIT=yes VIAL_ENABLE=yes keyball-rp/keyball39:toxaO

# 追加で他ターゲットを作る場合の例（必要ならコメント解除）
# make -C "$VIAL_DIR" SKIP_GIT=yes VIAL_ENABLE=yes keyball-rp/keyball44:toxaO
# make -C "$VIAL_DIR" SKIP_GIT=yes VIAL_ENABLE=yes keyball-rp/keyball61:toxaO

say "Vial build done. artifacts → $VIAL_DIR/.build/"
say "All done! 生成された .uf2 を各 .build/ ディレクトリで確認してください。"
