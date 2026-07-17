#!/usr/bin/env bash
# 时区 + 时间同步（chrony / systemd-timesyncd / ntp）
# 独立运行: sudo bash scripts/system/timezone.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

COMMON_ZONES=(
  "Asia/Shanghai"
  "Asia/Hong_Kong"
  "Asia/Tokyo"
  "Asia/Singapore"
  "UTC"
  "America/Los_Angeles"
  "America/New_York"
  "Europe/London"
)

show_status() {
  echo ""
  info "当前时间 / 时区"
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl status 2>/dev/null || timedatectl
  else
    echo "  日期: $(date)"
    echo "  时区文件: $(readlink -f /etc/localtime 2>/dev/null || ls -l /etc/localtime 2>/dev/null || true)"
    [[ -f /etc/timezone ]] && echo "  /etc/timezone: $(cat /etc/timezone)"
  fi
  echo ""
}

set_timezone() {
  local tz="${1:-}"

  if [[ -z "${tz}" ]]; then
    if is_tty; then
      local i=1 choice
      echo "常用时区:"
      for z in "${COMMON_ZONES[@]}"; do
        echo "  ${i}) ${z}"
        i=$((i + 1))
      done
      echo "  ${i}) 自定义 IANA 时区名"
      read_choice "请选择" choice || return 1
      if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 && "${choice}" -le ${#COMMON_ZONES[@]} ]]; then
        tz="${COMMON_ZONES[$((choice - 1))]}"
      elif [[ "${choice}" == "${i}" ]]; then
        read -r -p "输入时区 (如 Asia/Shanghai): " tz
      else
        warn "无效选项"
        return 1
      fi
    else
      tz="Asia/Shanghai"
    fi
  fi

  if [[ ! -e "/usr/share/zoneinfo/${tz}" ]]; then
    err "时区数据不存在: ${tz}"
    err "Debian/Ubuntu 可安装: apt-get install -y tzdata"
    return 1
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone "${tz}"
  else
    ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
    echo "${tz}" >/etc/timezone 2>/dev/null || true
  fi

  ok "时区已设为 ${tz}"
  date
}

enable_timesync() {
  detect_distro

  # 优先 systemd-timesyncd / chrony
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true 2>/dev/null || true
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q 'systemd-timesyncd.service'; then
    systemctl enable --now systemd-timesyncd 2>/dev/null || true
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
      ok "systemd-timesyncd 已启用"
      show_status
      return 0
    fi
  fi

  info "尝试安装并启用 chrony..."
  case "${PKG_MGR}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y chrony
      systemctl enable --now chrony 2>/dev/null || systemctl enable --now chronyd 2>/dev/null || true
      ;;
    apk)
      apk update
      apk add --no-cache chrony
      if command -v rc-service >/dev/null 2>&1; then
        rc-update add chronyd default 2>/dev/null || true
        rc-service chronyd start 2>/dev/null || true
      fi
      ;;
    dnf)
      dnf install -y chrony
      systemctl enable --now chronyd
      ;;
    yum)
      yum install -y chrony
      systemctl enable --now chronyd
      ;;
    *)
      warn "无法自动安装时间同步服务（pkg=${PKG_MGR}）"
      return 1
      ;;
  esac

  ok "时间同步组件已处理"
  show_status
}

quick_shanghai() {
  set_timezone "Asia/Shanghai"
  enable_timesync
}

menu() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "时区 / 时间同步"
    print_distro_info
    show_status
    echo "  1) 一键：Asia/Shanghai + 开启 NTP"
    echo "  2) 设置时区"
    echo "  3) 启用时间同步（NTP）"
    echo "  4) 仅查看状态"
    echo ""
    menu_footer_back "返回 / 退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1) quick_shanghai || true; pause ;;
      2) set_timezone || true; pause ;;
      3) enable_timesync || true; pause ;;
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
  bash timezone.sh                 # 交互菜单
  bash timezone.sh shanghai        # Asia/Shanghai + NTP
  bash timezone.sh set Asia/Tokyo
  bash timezone.sh ntp
  bash timezone.sh status
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
    shanghai|--shanghai)
      quick_shanghai
      ;;
    set|--set)
      set_timezone "${2:-}"
      ;;
    ntp|--ntp|sync|--sync)
      enable_timesync
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
