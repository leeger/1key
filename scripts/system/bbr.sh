#!/usr/bin/env bash
# 全系统通用 BBR / 队列 / TCP 调优（1key）
# 默认使用内核原生 BBR，不强制换第三方内核。
# Debian/Ubuntu 可选调用 byJoey BBRv3 内核安装脚本。
#
# 独立运行:
#   sudo bash scripts/system/bbr.sh
#   sudo bash scripts/system/bbr.sh onekey
#   sudo bash scripts/system/bbr.sh enable
#   sudo bash scripts/system/bbr.sh status
#
# 远程一键:
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr onekey

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

SYSCTL_BBR="/etc/sysctl.d/99-1key-bbr.conf"
SYSCTL_TUNE="/etc/sysctl.d/99-1key-bbr-tune.conf"
MODULES_CONF="/etc/modules-load.d/1key-qdisc.conf"
# byJoey 官方 BBRv3 内核安装（仅 Debian/Ubuntu + .deb）
BYJOEY_INSTALL_URL="https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/main/install.sh"

# ---------- 依赖 ----------
ensure_tools() {
  local need=()
  command -v sysctl >/dev/null 2>&1 || need+=(procps)
  command -v awk >/dev/null 2>&1 || need+=(gawk)
  command -v sed >/dev/null 2>&1 || need+=(sed)
  command -v ip >/dev/null 2>&1 || need+=(iproute2)
  command -v tc >/dev/null 2>&1 || {
    # alpine: iproute2 含 tc；部分系统包名不同
    case "${PKG_MGR:-}" in
      apk) need+=(iproute2) ;;
      apt) need+=(iproute2) ;;
      dnf|yum) need+=(iproute) ;;
      pacman) need+=(iproute2) ;;
      zypper) need+=(iproute2) ;;
      *) need+=(iproute2) ;;
    esac
  }

  # 去重并安装
  if [[ ${#need[@]} -gt 0 ]]; then
    local uniq=() p
    for p in "${need[@]}"; do
      local seen=0 u
      for u in "${uniq[@]+"${uniq[@]}"}"; do
        [[ "$u" == "$p" ]] && seen=1 && break
      done
      [[ $seen -eq 0 ]] && uniq+=("$p")
    done
    if [[ ${#uniq[@]} -gt 0 ]]; then
      info "安装依赖: ${uniq[*]}"
      pkg_install "${uniq[@]}" || warn "部分依赖安装失败，将尽量继续"
    fi
  fi
}

# ---------- 状态 ----------
get_cc() {
  cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "n/a"
}

get_qdisc() {
  cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "n/a"
}

get_available_cc() {
  cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo ""
}

get_bbr_module_version() {
  if command -v modinfo >/dev/null 2>&1; then
    modinfo tcp_bbr 2>/dev/null | awk '/^version:/ {print $2; exit}'
  fi
}

show_status() {
  echo ""
  info "当前状态"
  echo "  内核:     $(uname -r)  ($(uname -m))"
  print_distro_info
  echo "  拥塞控制: $(get_cc)"
  echo "  默认队列: $(get_qdisc)"
  echo "  可用算法: $(get_available_cc)"
  local ver
  ver="$(get_bbr_module_version || true)"
  if [[ -n "${ver}" ]]; then
    if [[ "${ver}" == "3" ]]; then
      echo "  BBR 模块: version ${ver} (BBRv3)"
    else
      echo "  BBR 模块: version ${ver}"
    fi
  else
    if grep -qw bbr <<<"$(get_available_cc)"; then
      echo "  BBR 模块: 可用（无 version 字段，多为内核内建/发行版原生）"
    else
      echo "  BBR 模块: 不可用"
    fi
  fi
  if command -v lsmod >/dev/null 2>&1 && lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
    echo "  tcp_bbr:  已加载为模块"
  fi
  [[ -f "${SYSCTL_BBR}" ]] && echo "  持久 BBR: ${SYSCTL_BBR}" || echo "  持久 BBR: 无"
  [[ -f "${SYSCTL_TUNE}" ]] && echo "  持久调优: ${SYSCTL_TUNE}" || echo "  持久调优: 无"
  [[ -f "${MODULES_CONF}" ]] && echo "  模块加载: ${MODULES_CONF}" || true
  echo ""
}

# ---------- 能力检测 ----------
kernel_supports_bbr() {
  if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    return 0
  fi
  if command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null; then
    grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
    return $?
  fi
  return 1
}

can_install_byjoey_kernel() {
  detect_distro
  # 仅 apt + dpkg 体系可装 .deb 内核
  if [[ "${PKG_MGR}" == "apt" ]] && command -v dpkg >/dev/null 2>&1; then
    case "${DISTRO_FAMILY}" in
      debian|ubuntu) return 0 ;;
    esac
    # 其他 apt 系（如 deepin）也尝试
    return 0
  fi
  return 1
}

# ---------- 模块 / 队列 ----------
load_qdisc_module() {
  local qdisc_name="$1"
  local module_name="sch_${qdisc_name}"

  if ! command -v modprobe >/dev/null 2>&1; then
    return 0
  fi
  if lsmod 2>/dev/null | grep -q "^${module_name//-/_}"; then
    return 0
  fi
  modprobe "${module_name}" 2>/dev/null || true
}

persist_qdisc_module() {
  local qdisc_name="$1"
  local module_name="sch_${qdisc_name}"

  # fq 多为内建，不必写 modules-load
  if [[ "${qdisc_name}" == "fq" ]]; then
    rm -f "${MODULES_CONF}" 2>/dev/null || true
    return 0
  fi

  if ! command -v modprobe >/dev/null 2>&1; then
    return 0
  fi

  if modinfo "${module_name}" >/dev/null 2>&1 || lsmod 2>/dev/null | grep -q "^${module_name//-/_}"; then
    mkdir -p "$(dirname "${MODULES_CONF}")"
    echo "${module_name}" >"${MODULES_CONF}"
    ok "开机将自动加载 ${module_name}"
  else
    rm -f "${MODULES_CONF}" 2>/dev/null || true
  fi
}

get_default_route_ifaces() {
  {
    ip -o route show default 2>/dev/null || true
    ip -o -6 route show default 2>/dev/null || true
  } | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1)}' | sort -u
}

apply_qdisc_to_ifaces() {
  local qdisc_name="$1"
  local iface applied=0

  if ! command -v tc >/dev/null 2>&1; then
    warn "无 tc 命令，仅设置 default_qdisc，当前网卡队列可能需新建连接后生效"
    return 0
  fi

  while IFS= read -r iface; do
    [[ -z "${iface}" ]] && continue
    if tc qdisc replace dev "${iface}" root "${qdisc_name}" 2>/dev/null; then
      ok "网卡 ${iface} → ${qdisc_name}"
      applied=1
    else
      warn "网卡 ${iface} 切换 ${qdisc_name} 失败（可能不支持）"
    fi
  done < <(get_default_route_ifaces)

  if [[ ${applied} -eq 0 ]]; then
    warn "未找到默认可切换网卡，已仅写入 default_qdisc"
  fi
}

sysctl_apply_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if sysctl -p "$f" >/dev/null 2>&1; then
    return 0
  fi
  # 逐行兼容：忽略不支持的键
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    local key val
    key="$(echo "${line}" | sed -E 's/[[:space:]]*=[[:space:]]*/=/; s/[[:space:]]+$//')"
    sysctl -w "${key}" >/dev/null 2>&1 || true
  done <"$f"
}

# ---------- 启用 / 关闭 BBR ----------
enable_bbr_qdisc() {
  local algo="${1:-bbr}"
  local qdisc="${2:-fq}"
  local persist="${3:-1}"

  if [[ "${algo}" == "bbr" ]] && ! kernel_supports_bbr; then
    err "当前内核似乎不支持 BBR（通常需 Linux 4.9+）"
    err "可升级系统内核；或在 Debian/Ubuntu 上使用菜单「安装 byJoey BBRv3 内核」"
    return 1
  fi

  load_qdisc_module "${qdisc}"
  modprobe tcp_bbr 2>/dev/null || true

  if [[ "${algo}" == "bbr" ]] && ! grep -qw bbr <<<"$(get_available_cc)"; then
    err "BBR 不在可用列表: $(get_available_cc)"
    return 1
  fi

  if ! sysctl -w "net.core.default_qdisc=${qdisc}" >/dev/null 2>&1; then
    err "无法设置 default_qdisc=${qdisc}"
    return 1
  fi
  if ! sysctl -w "net.ipv4.tcp_congestion_control=${algo}" >/dev/null 2>&1; then
    err "无法设置 tcp_congestion_control=${algo}"
    return 1
  fi

  apply_qdisc_to_ifaces "${qdisc}" || true

  local new_cc new_q
  new_cc="$(get_cc)"
  new_q="$(get_qdisc)"
  if [[ "${new_cc}" != "${algo}" ]]; then
    err "启用失败：拥塞控制仍为 ${new_cc}"
    return 1
  fi
  ok "已启用 ${algo} + ${qdisc}（当前 qdisc=${new_q}）"

  if [[ "${persist}" == "1" ]]; then
    mkdir -p "$(dirname "${SYSCTL_BBR}")"
    cat >"${SYSCTL_BBR}" <<EOF
# managed by 1key — BBR / qdisc
net.core.default_qdisc = ${qdisc}
net.ipv4.tcp_congestion_control = ${algo}
EOF
    persist_qdisc_module "${qdisc}"
    sysctl_apply_file "${SYSCTL_BBR}"
    ok "已永久写入 ${SYSCTL_BBR}"
  else
    warn "仅当前会话生效，未写入持久配置"
  fi
}

disable_bbr() {
  local cc="cubic"
  local qdisc="fq_codel"

  if ! grep -qw cubic <<<"$(get_available_cc)"; then
    cc="$(awk '{print $1}' /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo reno)"
  fi

  rm -f "${SYSCTL_BBR}" "${MODULES_CONF}" 2>/dev/null || true
  sysctl -w "net.ipv4.tcp_congestion_control=${cc}" >/dev/null 2>&1 || true
  sysctl -w "net.core.default_qdisc=${qdisc}" >/dev/null 2>&1 || true
  apply_qdisc_to_ifaces "${qdisc}" 2>/dev/null || true
  ok "已关闭 BBR 持久配置，当前: $(get_cc) / $(get_qdisc)"
}

# ---------- TCP 调优 ----------
get_tcp_buffer_cap_mb() {
  local mem_kb
  mem_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  if ! [[ "${mem_kb}" =~ ^[0-9]+$ ]]; then
    echo 64
  elif (( mem_kb < 524288 )); then
    echo 16
  elif (( mem_kb < 1048576 )); then
    echo 32
  else
    echo 64
  fi
}

# region: asia | overseas
calculate_buffer_mb() {
  local bandwidth="$1"
  local region="$2"
  local cap_mb="$3"
  local buffer_mb=16

  bandwidth="${bandwidth%.*}"
  if ! [[ "${bandwidth}" =~ ^[0-9]+$ ]] || (( bandwidth <= 0 )); then
    bandwidth=1000
  fi

  if [[ "${region}" == "overseas" ]]; then
    if (( bandwidth < 500 )); then buffer_mb=16
    elif (( bandwidth < 1000 )); then buffer_mb=48
    else buffer_mb=64
    fi
  else
    if (( bandwidth < 500 )); then buffer_mb=8
    elif (( bandwidth < 1000 )); then buffer_mb=12
    elif (( bandwidth < 2000 )); then buffer_mb=16
    elif (( bandwidth < 5000 )); then buffer_mb=24
    elif (( bandwidth < 10000 )); then buffer_mb=28
    else buffer_mb=32
    fi
  fi

  if (( buffer_mb > cap_mb )); then
    buffer_mb="${cap_mb}"
  fi
  echo "${buffer_mb}"
}

write_and_apply_tune() {
  local content="$1"
  mkdir -p "$(dirname "${SYSCTL_TUNE}")"
  {
    echo "# managed by 1key — TCP tune"
    echo "${content}"
  } >"${SYSCTL_TUNE}"
  sysctl_apply_file "${SYSCTL_TUNE}"
  ok "调优已写入 ${SYSCTL_TUNE}"
}

apply_apac_tuning() {
  info "应用亚太 TCP 调优..."
  write_and_apply_tune "$(cat <<'EOF'
net.ipv4.tcp_wmem = 4096 16384 12582912
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_limit_output_bytes = 4194304
net.ipv4.tcp_slow_start_after_idle = 0
EOF
)"
  echo "  tcp_wmem: $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo n/a)"
  echo "  tcp_rmem: $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo n/a)"
}

apply_smart_tuning() {
  local upload_mbps="${1:-}"
  local region="${2:-asia}"
  local cap_mb buffer_mb buffer_bytes

  if [[ -z "${upload_mbps}" ]]; then
    if is_tty; then
      read -r -p "$(echo -e "${C_CYAN}上传带宽 Mbit/s（默认 1000）: ${C_RESET}")" upload_mbps
    fi
    upload_mbps="${upload_mbps:-1000}"
  fi
  upload_mbps="${upload_mbps%.*}"
  if ! [[ "${upload_mbps}" =~ ^[0-9]+$ ]] || (( upload_mbps <= 0 )); then
    upload_mbps=1000
  fi

  if [[ -z "${2:-}" ]] && is_tty; then
    local rc
    echo "buffer 档位: 1) 亚太  2) 美欧"
    read_choice "请选择" rc || return 1
    case "${rc}" in
      2) region="overseas" ;;
      *) region="asia" ;;
    esac
  fi

  cap_mb="$(get_tcp_buffer_cap_mb)"
  buffer_mb="$(calculate_buffer_mb "${upload_mbps}" "${region}" "${cap_mb}")"
  buffer_bytes=$((buffer_mb * 1024 * 1024))

  info "智能调优: 带宽=${upload_mbps}M  region=${region}  buffer=${buffer_mb}MB (cap=${cap_mb}MB)"
  enable_bbr_qdisc bbr fq 1 || return 1

  write_and_apply_tune "$(cat <<EOF
net.core.rmem_max = ${buffer_bytes}
net.core.wmem_max = ${buffer_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buffer_bytes}
net.ipv4.tcp_rmem = 4096 87380 ${buffer_bytes}
net.ipv4.tcp_limit_output_bytes = 4194304
net.ipv4.tcp_slow_start_after_idle = 0
EOF
)"
  ok "智能带宽优化完成"
}

apply_extreme_tuning() {
  warn "疯批模式仅适合自有链路极限测速，可能增加延迟/重传/内存占用"
  if is_tty && ! confirm "确认启用极限测速参数?"; then
    warn "已取消"
    return 0
  fi

  enable_bbr_qdisc bbr fq 1 || return 1

  local buffer_bytes=1073741824
  local output_bytes=268435456
  local backlog=1000000
  local iface

  if command -v ip >/dev/null 2>&1; then
    while IFS= read -r iface; do
      [[ -z "${iface}" ]] && continue
      ip link set dev "${iface}" txqueuelen 100000 2>/dev/null \
        && ok "txqueuelen ${iface}=100000" || true
    done < <(get_default_route_ifaces)
  fi

  write_and_apply_tune "$(cat <<EOF
net.core.rmem_max = ${buffer_bytes}
net.core.wmem_max = ${buffer_bytes}
net.core.optmem_max = ${buffer_bytes}
net.core.netdev_max_backlog = ${backlog}
net.core.somaxconn = 65535
net.ipv4.tcp_wmem = 4096 1048576 ${buffer_bytes}
net.ipv4.tcp_rmem = 4096 1048576 ${buffer_bytes}
net.ipv4.tcp_limit_output_bytes = ${output_bytes}
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 4294967295
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_ecn = 0
EOF
)"
  ok "极限测速参数已写入（重启后 txqueuelen 可能恢复默认）"
}

clear_tuning() {
  rm -f "${SYSCTL_TUNE}" 2>/dev/null || true
  ok "已删除 TCP 调优文件 ${SYSCTL_TUNE}"
  warn "运行态参数可能需重启后完全恢复默认"
}

clear_all_1key_bbr() {
  disable_bbr
  clear_tuning
  ok "已清空 1key BBR / 调优相关持久配置"
}

# ---------- 一键 ----------
onekey() {
  title "一键启用 BBR + FQ + 亚太 TCP 调优"
  print_distro_info
  ensure_tools

  if ! kernel_supports_bbr; then
    err "当前内核不支持 BBR"
    if can_install_byjoey_kernel; then
      warn "本机为 Debian/Ubuntu 系，可运行: bash bbr.sh byjoey"
      warn "或菜单选择安装 byJoey BBRv3 内核后再执行 onekey"
    else
      warn "请升级系统内核后再试（Alpine: apk upgrade；RHEL: 新内核包）"
    fi
    return 1
  fi

  enable_bbr_qdisc bbr fq 1 || return 1
  apply_apac_tuning || true
  show_status
  ok "一键完成"
}

# ---------- byJoey 内核（仅 deb 系）----------
install_byjoey_kernel() {
  if ! can_install_byjoey_kernel; then
    err "byJoey BBRv3 内核包为 .deb，仅支持 Debian/Ubuntu（apt + dpkg）"
    err "当前: family=${DISTRO_FAMILY} pkg=${PKG_MGR}"
    err "其他系统请使用本脚本的「内核原生 BBR」一键 / 启用功能"
    return 1
  fi

  warn "将调用上游 byJoey 安装脚本（会下载并安装第三方内核 .deb）"
  warn "URL: ${BYJOEY_INSTALL_URL}"
  warn "风险: 内核升级可能导致无法启动，请确保有 VPS 控制台/救援模式"
  if is_tty && ! confirm "确认继续?"; then
    warn "已取消"
    return 0
  fi

  ensure_downloader || return 1
  export BBRV3_SKIP_QUICK_COMMAND="${BBRV3_SKIP_QUICK_COMMAND:-1}"
  run_remote_bash_ps "${BYJOEY_INSTALL_URL}"
}

# ---------- 交互选择队列 ----------
pick_and_enable_qdisc() {
  local qdisc="$1"
  local label="$2"
  if is_tty && ! confirm "启用 BBR + ${label}?"; then
    warn "已取消"
    return 0
  fi
  enable_bbr_qdisc bbr "${qdisc}" 1
}

menu() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "BBR / 网络加速（全系统）"
    print_distro_info
    show_status
    echo "  1) ⚡ 一键启用（BBR + FQ + 亚太调优）  [推荐]"
    echo "  2) 启用 BBR + FQ"
    echo "  3) 启用 BBR + FQ_CODEL"
    echo "  4) 启用 BBR + FQ_PIE"
    echo "  5) 启用 BBR + CAKE"
    echo "  6) 亚太 TCP 调优"
    echo "  7) 智能带宽优化（按带宽选 buffer）"
    echo "  8) 极限测速模式（慎用）"
    echo "  9) 查看状态"
    echo " 10) 关闭 BBR / 恢复默认拥塞控制"
    echo " 11) 清空 TCP 调优配置"
    echo " 12) 清空全部 1key BBR 配置"
    if can_install_byjoey_kernel; then
      echo ""
      echo " 13) 安装 byJoey BBRv3 内核（仅 Debian/Ubuntu .deb）"
    else
      echo ""
      echo "  （当前系统不可装 byJoey .deb 内核，使用原生 BBR 即可）"
    fi
    echo ""
    menu_footer_back "返回 / 退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1)
        onekey || true
        pause
        ;;
      2) pick_and_enable_qdisc fq "FQ"; pause ;;
      3) pick_and_enable_qdisc fq_codel "FQ_CODEL"; pause ;;
      4) pick_and_enable_qdisc fq_pie "FQ_PIE"; pause ;;
      5) pick_and_enable_qdisc cake "CAKE"; pause ;;
      6)
        if is_tty && ! confirm "应用亚太 TCP 调优?"; then warn "已取消"; pause; continue; fi
        apply_apac_tuning || true
        pause
        ;;
      7)
        apply_smart_tuning || true
        pause
        ;;
      8)
        apply_extreme_tuning || true
        pause
        ;;
      9)
        show_status
        pause
        ;;
      10)
        if is_tty && ! confirm "确认关闭 BBR?"; then warn "已取消"; pause; continue; fi
        disable_bbr || true
        pause
        ;;
      11)
        if is_tty && ! confirm "清空 TCP 调优?"; then warn "已取消"; pause; continue; fi
        clear_tuning || true
        pause
        ;;
      12)
        if is_tty && ! confirm "清空全部 1key BBR 配置?"; then warn "已取消"; pause; continue; fi
        clear_all_1key_bbr || true
        pause
        ;;
      13)
        install_byjoey_kernel || true
        pause
        ;;
      0|q|Q)
        return 0
        ;;
      *)
        warn "无效选项: ${choice}"
        sleep 1
        ;;
    esac
  done
}

usage() {
  cat <<EOF
用法:
  bash bbr.sh                 # 交互菜单
  bash bbr.sh onekey          # 一键: BBR+FQ + 亚太调优
  bash bbr.sh enable [qdisc]  # 启用 BBR + 队列 (默认 fq)
  bash bbr.sh disable         # 关闭 BBR
  bash bbr.sh status          # 查看状态
  bash bbr.sh apac            # 亚太 TCP 调优
  bash bbr.sh smart [Mbps] [asia|overseas]
  bash bbr.sh extreme         # 极限测速参数
  bash bbr.sh clear           # 清空调优
  bash bbr.sh clear-all       # 清空 BBR+调优
  bash bbr.sh byjoey          # Debian/Ubuntu 调用 byJoey 内核安装

支持系统: Ubuntu / Debian / Alpine / RHEL / Rocky / Alma / Fedora 等
  - 全系统: 内核原生 BBR + sysctl / qdisc
  - 仅 deb 系: 可选 byJoey BBRv3 第三方内核

远程:
  bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr
  bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr onekey
EOF
}

main() {
  case "${1:-}" in
    -h|--help|help)
      usage
      return 0
      ;;
    status|--status)
      detect_distro
      show_status
      return 0
      ;;
  esac

  require_root "$@"
  detect_distro
  ensure_tools

  case "${1:-}" in
    onekey|1key|--onekey)
      onekey
      ;;
    enable|--enable)
      enable_bbr_qdisc bbr "${2:-fq}" 1
      ;;
    disable|--disable)
      disable_bbr
      ;;
    apac|--apac)
      apply_apac_tuning
      ;;
    smart|--smart)
      apply_smart_tuning "${2:-}" "${3:-asia}"
      ;;
    extreme|--extreme)
      apply_extreme_tuning
      ;;
    clear|--clear)
      clear_tuning
      ;;
    clear-all|--clear-all)
      clear_all_1key_bbr
      ;;
    byjoey|joey|bbrv3-kernel)
      install_byjoey_kernel
      ;;
    "")
      menu
      ;;
    *)
      err "未知参数: $1"
      usage
      exit 1
      ;;
  esac
}

main "$@"
