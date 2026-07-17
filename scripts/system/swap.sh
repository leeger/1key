#!/usr/bin/env bash
# Swap 文件创建 / 调整 / 删除
# 独立运行: sudo bash scripts/system/swap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

DEFAULT_SWAP_PATH="/swapfile"
FSTAB="/etc/fstab"

show_status() {
  echo ""
  info "当前内存 / Swap"
  free -h 2>/dev/null || free
  echo ""
  swapon --show 2>/dev/null || true
  if [[ -f /proc/sys/vm/swappiness ]]; then
    echo "swappiness: $(cat /proc/sys/vm/swappiness)"
  fi
  echo ""
}

# 解析大小: 1G / 2g / 512M / 数字(默认 GiB)
parse_size_to_mib() {
  local raw="$1"
  local num unit
  raw="$(echo "${raw}" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
  if [[ "${raw}" =~ ^([0-9]+)([KMG]?I?B?)$ ]]; then
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
  else
    err "无法解析大小: $1（示例: 1G / 2G / 512M）"
    return 1
  fi
  case "${unit}" in
    ""|G|GB|GIB) echo $((num * 1024)) ;;
    M|MB|MIB) echo "${num}" ;;
    K|KB|KIB) echo $(( (num + 1023) / 1024 )) ;;
    *)
      err "不支持的单位: ${unit}"
      return 1
      ;;
  esac
}

ensure_not_on_swapfile() {
  local path="$1"
  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "${path}"; then
    return 0
  fi
  return 1
}

create_swap() {
  local size_arg="${1:-}"
  local path="${2:-${DEFAULT_SWAP_PATH}}"
  local mib

  if [[ -z "${size_arg}" ]]; then
    if is_tty; then
      local choice
      echo "选择 Swap 大小:"
      echo "  1) 1G"
      echo "  2) 2G（推荐小内存机器）"
      echo "  3) 4G"
      echo "  4) 自定义"
      read_choice "请选择" choice || return 1
      case "${choice}" in
        1) size_arg="1G" ;;
        2) size_arg="2G" ;;
        3) size_arg="4G" ;;
        4)
          read -r -p "输入大小 (如 2G / 512M): " size_arg
          ;;
        *)
          warn "无效选项"
          return 1
          ;;
      esac
    else
      size_arg="2G"
    fi
  fi

  mib="$(parse_size_to_mib "${size_arg}")" || return 1

  if [[ -e "${path}" ]]; then
    if ensure_not_on_swapfile "${path}"; then
      err "已存在并已挂载的 swap: ${path}。请先删除或选用其他路径。"
      return 1
    fi
    if is_tty && ! confirm "文件已存在 ${path}，删除并重建?"; then
      warn "已取消"
      return 1
    fi
    rm -f "${path}"
  fi

  # 检查磁盘空间（粗略）
  local avail_kib
  avail_kib="$(df -Pk "$(dirname "${path}")" | awk 'NR==2{print $4}')"
  if [[ -n "${avail_kib}" && "${avail_kib}" -lt $((mib * 1024 + 102400)) ]]; then
    err "磁盘可用空间不足（需要约 ${mib}MiB + 余量）"
    return 1
  fi

  info "创建 ${path} (${mib} MiB)..."
  # fallocate 更快；不支持时用 dd
  if command -v fallocate >/dev/null 2>&1 && fallocate -l "${mib}M" "${path}" 2>/dev/null; then
    ok "fallocate 完成"
  else
    warn "fallocate 不可用，改用 dd（较慢）..."
    dd if=/dev/zero of="${path}" bs=1M count="${mib}" status=progress 2>/dev/null \
      || dd if=/dev/zero of="${path}" bs=1M count="${mib}"
  fi

  chmod 600 "${path}"
  mkswap "${path}"
  swapon "${path}"

  # fstab
  if ! grep -qE "^[^#]*[[:space:]]${path}[[:space:]]" "${FSTAB}" 2>/dev/null; then
    # 去掉旧的同 path 注释行外的重复
    cp -a "${FSTAB}" "${FSTAB}.1key.bak.$(date +%s)" 2>/dev/null || true
    echo "${path} none swap sw 0 0" >>"${FSTAB}"
    ok "已写入 ${FSTAB}"
  else
    info "fstab 中已有 ${path} 条目"
  fi

  ok "Swap 已启用"
  show_status
}

remove_swap() {
  local path="${1:-${DEFAULT_SWAP_PATH}}"

  if ensure_not_on_swapfile "${path}" || swapon --show=NAME --noheadings 2>/dev/null | grep -q "${path}"; then
    info "关闭 swap: ${path}"
    swapoff "${path}" 2>/dev/null || swapoff -a
  fi

  if [[ -f "${path}" ]]; then
    rm -f "${path}"
    ok "已删除 ${path}"
  else
    warn "文件不存在: ${path}"
  fi

  if [[ -f "${FSTAB}" ]] && grep -qE "^[^#]*[[:space:]]${path}[[:space:]]+none[[:space:]]+swap" "${FSTAB}"; then
    cp -a "${FSTAB}" "${FSTAB}.1key.bak.$(date +%s)" 2>/dev/null || true
    # 删除匹配行
    local tmp
    tmp="$(mktemp)"
    grep -vE "^[^#]*[[:space:]]${path}[[:space:]]+none[[:space:]]+swap" "${FSTAB}" >"${tmp}" || true
    cat "${tmp}" >"${FSTAB}"
    rm -f "${tmp}"
    ok "已从 fstab 移除 ${path}"
  fi

  show_status
}

set_swappiness() {
  local val="${1:-}"
  if [[ -z "${val}" ]]; then
    if is_tty; then
      read -r -p "swappiness (0-100，推荐 10-30): " val
    else
      val=10
    fi
  fi
  if ! [[ "${val}" =~ ^[0-9]+$ ]] || [[ "${val}" -gt 100 ]]; then
    err "无效 swappiness: ${val}"
    return 1
  fi

  sysctl -w "vm.swappiness=${val}" >/dev/null
  cat >/etc/sysctl.d/99-1key-swappiness.conf <<EOF
# managed by 1key
vm.swappiness = ${val}
EOF
  ok "swappiness = ${val}（已持久化 /etc/sysctl.d/99-1key-swappiness.conf）"
}

menu() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "Swap 管理"
    print_distro_info
    show_status
    echo "  1) 创建 / 启用 swap 文件（默认 ${DEFAULT_SWAP_PATH}）"
    echo "  2) 删除 swap 文件"
    echo "  3) 设置 swappiness"
    echo "  4) 仅查看状态"
    echo ""
    menu_footer_back "返回 / 退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1) create_swap || true; pause ;;
      2)
        if is_tty && ! confirm "确认删除 ${DEFAULT_SWAP_PATH}?"; then
          warn "已取消"; pause; continue
        fi
        remove_swap || true
        pause
        ;;
      3) set_swappiness || true; pause ;;
      4) show_status; pause ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项: ${choice}"; sleep 1 ;;
    esac
  done
}

main() {
  case "${1:-}" in
    -h|--help)
      cat <<EOF
用法:
  bash swap.sh                  # 交互菜单
  bash swap.sh create [2G]      # 创建 swap
  bash swap.sh remove           # 删除默认 /swapfile
  bash swap.sh swappiness 10
  bash swap.sh status
EOF
      return 0
      ;;
    status|--status)
      show_status
      return 0
      ;;
  esac

  require_root "$@"
  detect_distro

  case "${1:-}" in
    create|--create)
      create_swap "${2:-}" "${3:-}"
      ;;
    remove|--remove|delete|--delete)
      remove_swap "${2:-}"
      ;;
    swappiness|--swappiness)
      set_swappiness "${2:-}"
      ;;
    "")
      menu
      ;;
    *)
      err "未知参数: $1"
      exit 1
      ;;
  esac
}

main "$@"
