#!/usr/bin/env bash
# shellcheck disable=SC2034
# 公共函数：日志、确认、菜单、root 检查

# 颜色
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

info()  { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()   { echo -e "${C_RED}[ERR]${C_RESET} $*" >&2; }
title() { echo -e "\n${C_BOLD}${C_CYAN}==> $*${C_RESET}\n"; }

# 脚本根目录（调用方应在 source 前设置 OPS_KIT_ROOT，否则自动推断）
if [[ -z "${OPS_KIT_ROOT:-}" ]]; then
  _common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  OPS_KIT_ROOT="$(cd "${_common_dir}/.." && pwd)"
fi

# 是否交互式终端
is_tty() { [[ -t 0 && -t 1 ]]; }

# root 检查：非 root 时尝试 sudo 重跑当前脚本
require_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    warn "需要 root 权限，尝试使用 sudo 重新执行..."
    exec sudo -E bash "$0" "$@"
  fi
  err "此操作需要 root 权限，请使用: sudo bash $0"
  exit 1
}

# 确认提示，默认 N
confirm() {
  local prompt="${1:-确认继续?}"
  local ans
  if ! is_tty; then
    return 0
  fi
  read -r -p "$(echo -e "${C_YELLOW}${prompt} [y/N]: ${C_RESET}")" ans
  [[ "${ans}" =~ ^[Yy]$ ]]
}

# 暂停，便于查看输出
pause() {
  if is_tty; then
    read -r -p "按回车继续..." _
  fi
}

# 读取菜单选项
# 用法: read_choice "提示" choice_var
# 用户输入写入变量名 $2
read_choice() {
  local prompt="${1:-请选择}"
  local __var="${2:-REPLY}"
  local __input
  if ! is_tty; then
    err "非交互环境，无法读取菜单选项"
    return 1
  fi
  read -r -p "$(echo -e "${C_CYAN}${prompt}: ${C_RESET}")" __input
  printf -v "${__var}" '%s' "${__input}"
}

# 打印菜单头
menu_header() {
  local name="$1"
  echo ""
  echo -e "${C_BOLD}========================================${C_RESET}"
  echo -e "${C_BOLD}  ${name}${C_RESET}"
  echo -e "${C_BOLD}========================================${C_RESET}"
}

# 打印返回提示（0 = 返回 / 退出）
menu_footer_back() {
  local label="${1:-返回上级}"
  echo "----------------------------------------"
  echo -e "  ${C_YELLOW}0)${C_RESET} ${label}"
  echo "========================================"
}

# 确保有 curl 或 wget（优先 curl）
ensure_downloader() {
  if command -v curl >/dev/null 2>&1; then
    export OPS_DOWNLOADER=curl
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    export OPS_DOWNLOADER=wget
    return 0
  fi

  # 尝试安装
  # shellcheck source=/dev/null
  source "${OPS_KIT_ROOT}/lib/distro.sh"
  detect_distro
  info "未检测到 curl/wget，尝试安装 curl..."
  case "${DISTRO_FAMILY}" in
    debian|ubuntu)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y && apt-get install -y curl ca-certificates
      ;;
    alpine)
      apk update && apk add --no-cache curl ca-certificates
      ;;
    rhel|centos|fedora)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y curl ca-certificates
      else
        yum install -y curl ca-certificates
      fi
      ;;
    *)
      err "无法自动安装 curl，请手动安装后重试"
      return 1
      ;;
  esac

  if command -v curl >/dev/null 2>&1; then
    export OPS_DOWNLOADER=curl
    return 0
  fi
  err "curl 安装失败"
  return 1
}

# 远程执行 bash 脚本（curl 优先，wget 兜底）
# 用法: run_remote_bash "https://example.com/install.sh"
run_remote_bash() {
  local url="$1"
  ensure_downloader || return 1
  info "执行远程脚本: ${url}"
  if command -v curl >/dev/null 2>&1; then
    bash -c "$(curl -fsSL "${url}")"
  elif command -v wget >/dev/null 2>&1; then
    bash <(wget -qO- "${url}")
  else
    err "需要 curl 或 wget"
    return 1
  fi
}

# 以 process substitution 方式执行（兼容 233boy 风格）
# 用法: run_remote_bash_ps "https://example.com/install.sh"
run_remote_bash_ps() {
  local url="$1"
  ensure_downloader || return 1
  info "执行远程脚本: ${url}"
  if command -v curl >/dev/null 2>&1; then
    bash <(curl -fsSL "${url}")
  elif command -v wget >/dev/null 2>&1; then
    bash <(wget -qO- -o- "${url}")
  else
    err "需要 curl 或 wget"
    return 1
  fi
}
