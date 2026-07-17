#!/usr/bin/env bash
# sing-box yoyo (yyds) 一键安装包装脚本
# 原始命令:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/caigouzi121380/singbox-deploy/main/install-singbox-yyds.sh)"
#
# 独立运行:
#   sudo bash scripts/singbox/yoyo.sh
#   或: sudo ./scripts/singbox/yoyo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

YOYO_URL="https://raw.githubusercontent.com/caigouzi121380/singbox-deploy/main/install-singbox-yyds.sh"

main() {
  title "sing-box yoyo (yyds) 安装"

  print_distro_info

  if ! is_supported_distro; then
    warn "当前系统 (${DISTRO_FAMILY}) 未在本工具声明支持列表中，将继续尝试调用上游脚本"
  fi

  require_root "$@"
  ensure_downloader || exit 1

  info "上游脚本: ${YOYO_URL}"
  info "说明: 上游脚本支持 Alpine / Debian(Ubuntu) / RedHat 等，安装过程为交互式"
  echo ""

  if is_tty; then
    if ! confirm "确认拉取并执行 yoyo 安装脚本?"; then
      warn "已取消"
      return 1
    fi
  fi

  # 与官方推荐命令一致: bash -c "$(curl -fsSL ...)"
  if command -v curl >/dev/null 2>&1; then
    bash -c "$(curl -fsSL "${YOYO_URL}")"
  else
    run_remote_bash "${YOYO_URL}"
  fi
}

main "$@"
