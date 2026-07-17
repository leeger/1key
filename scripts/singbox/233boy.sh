#!/usr/bin/env bash
# sing-box 233boy 一键安装包装脚本
# 原始命令:
#   bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)
#
# 独立运行:
#   sudo bash scripts/singbox/233boy.sh
#   或: sudo ./scripts/singbox/233boy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

BOY233_URL="https://github.com/233boy/sing-box/raw/main/install.sh"
# raw 直链（部分环境 github.com 跳转不稳定时可作备选）
BOY233_RAW_URL="https://raw.githubusercontent.com/233boy/sing-box/main/install.sh"

main() {
  title "sing-box 233boy 安装"

  print_distro_info

  if ! is_supported_distro; then
    warn "当前系统 (${DISTRO_FAMILY}) 未在本工具声明支持列表中，将继续尝试调用上游脚本"
  fi

  require_root "$@"
  ensure_downloader || exit 1

  info "上游脚本: ${BOY233_URL}"
  info "说明: 上游为 233boy sing-box 安装脚本，安装过程为交互式"
  echo ""

  if is_tty; then
    if ! confirm "确认拉取并执行 233boy 安装脚本?"; then
      warn "已取消"
      return 1
    fi
  fi

  # 优先 curl process substitution；无 curl 时用 wget（与官方一致）
  if command -v curl >/dev/null 2>&1; then
    if ! bash <(curl -fsSL "${BOY233_URL}"); then
      warn "主地址失败，尝试 raw.githubusercontent.com..."
      bash <(curl -fsSL "${BOY233_RAW_URL}")
    fi
  elif command -v wget >/dev/null 2>&1; then
    # 官方推荐写法
    bash <(wget -qO- -o- "${BOY233_URL}")
  else
    err "需要 curl 或 wget"
    exit 1
  fi
}

main "$@"
