#!/usr/bin/env bash
# =============================================================================
#  NX 工具箱 · Linux VPS 常用脚本合集
#  项目: https://github.com/NX2406/nx-toolbox
#  集成: vps-PSL 端口限速 · ovhroot Root 登录 · LXC 切小鸡 · Realm 转发面板(nxr)
#  部分功能参考并改写自 kejilion/sh（Apache-2.0），详见 NOTICE
# =============================================================================
[ -z "${BASH_VERSION:-}" ] && { echo "请使用 bash 运行本脚本" >&2; exit 1; }
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then echo "需要 bash 4.0 及以上版本" >&2; exit 1; fi

NX_VERSION="1.1.1"
NX_REPO="NX2406/nx-toolbox"
NX_RAW_URL="https://raw.githubusercontent.com/${NX_REPO}/main/nx.sh"
NX_BIN="/usr/local/bin/nx"
NX_DIR="/etc/nx"
NXR_RAW_URL="https://raw.githubusercontent.com/NX2406/nx-realm/main/nxr.sh"
NXR_BIN="/usr/local/bin/nxr"
PSL_RAW_URL="https://raw.githubusercontent.com/NX2406/vps-PSL/refs/heads/main/speed%20limiting"
PSL_BIN="/usr/local/bin/PSL"
OVHROOT_RAW_URL="https://raw.githubusercontent.com/NX2406/ovhroot/refs/heads/main/OVHroot-install"

GH_PROXIES=("https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/")
GH_PROXY="auto"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'
  C_CYN=$'\e[36m'; C_GRY=$'\e[90m'; C_BLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_CYN=''; C_GRY=''; C_BLD=''; C_RST=''
fi

ASSUME_YES=0

ok()   { printf '%s[✓]%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
info() { printf '%s[*]%s %s\n' "$C_CYN" "$C_RST" "$*" >&2; }
warn() { printf '%s[!]%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; }
err()  { printf '%s[✗]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s%s%s\n' "$C_GRY" "  ──────────────────────────────────────────────────────────" "$C_RST"; }
clear_screen() { if [[ -t 1 ]]; then clear; fi; }
title() { clear_screen; printf '\n  %s%s%s\n' "$C_CYN$C_BLD" "$*" "$C_RST"; hr; }
item() { printf '  %s%-4s%s %s\n' "$C_CYN" "$1" "$C_RST" "$2"; }

pause() {
  [[ -t 0 ]] || return 0
  local _
  read -r -p "  按回车键继续..." _ || true
}

ask() {
  local __v=$1 __p=$2 __d=${3-} __a=""
  if [[ ! -t 0 ]]; then printf -v "$__v" '%s' "$__d"; return 0; fi
  if [[ -n $__d ]]; then
    read -r -e -p "  $__p [${__d}]: " __a || return 1
  else
    read -r -e -p "  $__p: " __a || return 1
  fi
  __a=${__a#"${__a%%[![:space:]]*}"}
  __a=${__a%"${__a##*[![:space:]]}"}
  [[ -z $__a ]] && __a=$__d
  printf -v "$__v" '%s' "$__a"
}

ask_secret() {
  local __v=$1 __a=""
  read -r -s -p "  $2: " __a || return 1
  echo
  printf -v "$__v" '%s' "$__a"
}

confirm() {
  local def=${2:-N} a hint='[y/N]'
  [[ $def == Y ]] && hint='[Y/n]'
  if [[ $ASSUME_YES == 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then [[ $def == Y ]]; return; fi
  read -r -p "  $1 $hint: " a || return 1
  a=${a:-$def}
  [[ $a == [Yy]* ]]
}

# 附带的可选操作（顺带删数据、更多设置等）：-y 只替用户确认主操作，这类问题仍按默认值
confirm_opt() {
  if [[ $ASSUME_YES == 1 ]]; then [[ ${2:-N} == Y ]]; return; fi
  confirm "$@"
}

read_choice() {
  local __v=$1 __a
  read -r -e -p "  ${2:-请输入选项}: " __a || { echo; exit 0; }
  printf -v "$__v" '%s' "$__a"
}

need_root() { [[ $EUID -eq 0 ]] || die "请使用 root 运行（sudo -i 后再执行，或 sudo bash nx.sh）"; }
has() { command -v "$1" >/dev/null 2>&1; }
ssq() { ss "$@" 2>/dev/null | awk 'NR > 1'; }

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }
is_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 )); }

# ver_gt A B：版本号 A 是否高于 B（按点分段比较数字）
ver_gt() {
  local -a va vb
  local i x y
  IFS=. read -ra va <<<"${1#v}"
  IFS=. read -ra vb <<<"${2#v}"
  for i in 0 1 2 3; do
    x=${va[i]//[!0-9]/}; y=${vb[i]//[!0-9]/}
    (( 10#${x:-0} > 10#${y:-0} )) && return 0
    (( 10#${x:-0} < 10#${y:-0} )) && return 1
  done
  return 1
}

# append_line 文件 内容：文件末尾没有换行时先补上，避免和上一行粘在一起
append_line() {
  if [[ -s $1 && -n $(tail -c 1 "$1") ]]; then echo >> "$1"; fi
  printf '%s\n' "$2" >> "$1"
}
is_ipv4() {
  [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local i
  for i in 1 2 3 4; do (( 10#${BASH_REMATCH[i]} <= 255 )) || return 1; done
}
is_ipv6() { [[ ( $1 == *:*:* || $1 == *::* ) && $1 =~ ^[0-9A-Fa-f:.]+$ ]]; }
is_ip() { is_ipv4 "$1" || is_ipv6 "$1"; }

rand_pass() { tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c "${1:-16}"; }

fmt_bytes() {
  awk -v b="${1:-0}" 'BEGIN{ split("B KB MB GB TB PB", u, " "); i = 1
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d%s", b, u[i]; else printf "%.2f%s", b, u[i] }'
}

# ------------------------------------------------------------------ 系统识别
OS_ID=""; OS_NAME=""; OS_CODENAME=""
detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    OS_ID=$(. /etc/os-release; echo "${ID:-}")
    OS_NAME=$(. /etc/os-release; echo "${PRETTY_NAME:-$ID}")
    OS_CODENAME=$(. /etc/os-release; echo "${VERSION_CODENAME:-}")
  fi
  [[ -z $OS_NAME ]] && OS_NAME=$(uname -s)
}

virt_type() {
  local v=""
  if has systemd-detect-virt; then v=$(systemd-detect-virt 2>/dev/null); fi
  if [[ -z $v || $v == none ]]; then
    if [[ -d /proc/vz && ! -d /proc/bc ]]; then v=openvz
    elif grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then v=lxc
    fi
  fi
  echo "${v:-none}"
}

pkg_mgr() {
  local m
  for m in apt-get dnf yum apk pacman zypper; do has "$m" && { echo "$m"; return 0; }; done
  return 1
}

APT_UPDATED=0
pkg_install() {
  local m
  m=$(pkg_mgr) || { err "未识别的包管理器"; return 1; }
  case $m in
    apt-get)
      if [[ $APT_UPDATED == 0 ]]; then apt-get update -y >/dev/null 2>&1; APT_UPDATED=1; fi
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
    apk) apk add --no-cache "$@" ;;
    pacman) pacman -Sy --noconfirm --needed "$@" ;;
    zypper) zypper -n install "$@" ;;
  esac
}

pkg_installed() {
  case $(pkg_mgr) in
    apt-get) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    dnf|yum|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    apk) apk info -e "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# 只卸载已安装的包：apt/dnf 遇到不存在的包名会整条命令失败
pkg_remove() {
  local p
  local -a list=()
  for p in "$@"; do pkg_installed "$p" && list+=("$p"); done
  [[ ${#list[@]} -gt 0 ]] || return 0
  case $(pkg_mgr) in
    apt-get) DEBIAN_FRONTEND=noninteractive apt-get purge -y "${list[@]}" ;;
    dnf) dnf remove -y "${list[@]}" ;;
    yum) yum remove -y "${list[@]}" ;;
    apk) apk del "${list[@]}" ;;
    pacman) pacman -Rns --noconfirm "${list[@]}" ;;
    zypper) zypper -n remove "${list[@]}" ;;
  esac
}

ensure_cmd() {
  local c=$1
  shift
  has "$c" && return 0
  info "安装依赖: ${*:-$c}"
  if [[ $# -gt 0 ]]; then pkg_install "$@" >/dev/null 2>&1; else pkg_install "$c" >/dev/null 2>&1; fi
  has "$c"
}

ensure_ss() {
  has ss && return 0
  case $(pkg_mgr) in dnf|yum) ensure_cmd ss iproute ;; *) ensure_cmd ss iproute2 ;; esac
}

svc_restart_any() { # 依次尝试重启给出的服务名
  local s
  for s in "$@"; do
    if has systemctl && systemctl list-unit-files "$s.service" 2>/dev/null | grep -q "^$s.service"; then
      systemctl restart "$s" && return 0
    elif has rc-service && [[ -f /etc/init.d/$s ]]; then
      rc-service "$s" restart && return 0
    fi
  done
  return 1
}

# ------------------------------------------------------------------ 网络 / 下载
dl() {
  local url=$1 out=$2 t=${3:-60}
  if has curl; then
    curl -fsSL --connect-timeout 8 --max-time "$t" -o "$out" "$url"
  elif has wget; then
    wget -q -T 15 -O "$out" "$url"
  else
    return 1
  fi
}

gh_dl() {
  local url=$1 out=$2 t=${3:-120} p
  case $GH_PROXY in
    none) dl "$url" "$out" "$t" ;;
    auto|"")
      dl "$url" "$out" "$t" && return 0
      for p in "${GH_PROXIES[@]}"; do
        info "GitHub 直连失败，尝试加速: $p"
        dl "${p}${url}" "$out" "$t" && return 0
      done
      return 1 ;;
    *) dl "${GH_PROXY%/}/${url}" "$out" "$t" || dl "$url" "$out" "$t" ;;
  esac
}

# 下载并执行 GitHub 上的脚本：run_remote URL [参数...]
run_remote() {
  local url=$1 tmp rc
  shift
  tmp=$(mktemp /tmp/nx-remote.XXXXXX)
  info "获取脚本: $url"
  if ! gh_dl "$url" "$tmp" 120; then rm -f "$tmp"; err "下载失败"; return 1; fi
  bash "$tmp" "$@"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# 执行第三方一行命令前先展示
run_cmd() {
  printf '  %s$ %s%s\n' "$C_GRY" "$1" "$C_RST"
  bash -c "$1"
}

IPV4_CACHE=""; IPV6_CACHE=""
public_ipv4() {
  [[ -n $IPV4_CACHE ]] && { echo "$IPV4_CACHE"; return 0; }
  local u ip
  for u in https://4.ipw.cn https://api.ipify.org https://ipv4.ip.sb; do
    ip=$(curl -4 -fsS --max-time 4 "$u" 2>/dev/null | tr -d '[:space:]')
    if is_ipv4 "$ip"; then IPV4_CACHE=$ip; echo "$ip"; return 0; fi
  done
  return 1
}
public_ipv6() {
  [[ -n $IPV6_CACHE ]] && { echo "$IPV6_CACHE"; return 0; }
  local u ip
  for u in https://6.ipw.cn https://api64.ipify.org https://ipv6.ip.sb; do
    ip=$(curl -6 -fsS --max-time 4 "$u" 2>/dev/null | tr -d '[:space:]')
    if is_ipv6 "$ip"; then IPV6_CACHE=$ip; echo "$ip"; return 0; fi
  done
  return 1
}

in_china() {
  local loc
  loc=$(curl -fsS --max-time 4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^loc=/{print $2}')
  [[ $loc == CN ]]
}

main_iface() { ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
main_ipv4_local() { ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'; }

port_in_use() { [[ -n $(ssq -lntu "( sport = :$1 )") ]]; }

# ------------------------------------------------------------------ 防火墙
fw_backend() {
  if has ufw && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then echo ufw; return; fi
  if has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then echo firewalld; return; fi
  if has iptables && iptables -S INPUT 2>/dev/null | grep -qE '^-P INPUT (DROP|REJECT)|-j (DROP|REJECT)'; then echo iptables; return; fi
  echo none
}

fw_persist() {
  if has netfilter-persistent; then
    netfilter-persistent save >/dev/null 2>&1
  elif [[ -f /etc/sysconfig/iptables ]] && has iptables-save; then
    iptables-save > /etc/sysconfig/iptables 2>/dev/null
    if [[ -f /etc/sysconfig/ip6tables ]] && has ip6tables-save; then ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null; fi
  fi
  return 0
}

fw_protos() { case $1 in tcp) echo tcp ;; udp) echo udp ;; *) echo "tcp udp" ;; esac; }

# fw_open 端口(可为 a:b 区间) 协议(tcp|udp|both)
fw_open() {
  local p=$1 b x t
  b=$(fw_backend)
  # firewalld 同时改运行时和永久配置而不 reload：iptables 后端下 reload 会清掉 Docker/fail2ban 的动态规则
  case $b in
    ufw) for x in $(fw_protos "${2:-both}"); do ufw allow "$p/$x" >/dev/null 2>&1; done ;;
    firewalld)
      for x in $(fw_protos "${2:-both}"); do
        firewall-cmd --add-port="${p/:/-}/$x" >/dev/null 2>&1
        firewall-cmd --permanent --add-port="${p/:/-}/$x" >/dev/null 2>&1
      done ;;
    iptables)
      for t in iptables ip6tables; do
        has "$t" || continue
        for x in $(fw_protos "${2:-both}"); do
          "$t" -w -C INPUT -p "$x" --dport "$p" -j ACCEPT 2>/dev/null || "$t" -w -I INPUT -p "$x" --dport "$p" -j ACCEPT 2>/dev/null
        done
      done
      fw_persist ;;
    *) return 0 ;;
  esac
  info "防火墙($b) 已放行 $p/${2:-both}"
}

fw_close() {
  local p=$1 b x t changed=0
  b=$(fw_backend)
  case $b in
    ufw) for x in $(fw_protos "${2:-both}"); do ufw delete allow "$p/$x" >/dev/null 2>&1; done ;;
    firewalld)
      for x in $(fw_protos "${2:-both}"); do
        firewall-cmd --remove-port="${p/:/-}/$x" >/dev/null 2>&1
        firewall-cmd --permanent --remove-port="${p/:/-}/$x" >/dev/null 2>&1
      done ;;
    *)
      for t in iptables ip6tables; do
        has "$t" || continue
        for x in $(fw_protos "${2:-both}"); do
          while "$t" -w -D INPUT -p "$x" --dport "$p" -j ACCEPT 2>/dev/null; do changed=1; done
        done
      done
      if [[ $changed == 1 ]]; then fw_persist; fi ;;
  esac
  if [[ $b == ufw || $b == firewalld ]]; then info "防火墙($b) 已关闭 $p/${2:-both}"
  elif [[ $changed == 1 ]]; then info "防火墙(iptables) 已关闭 $p/${2:-both}"; fi
}

# ------------------------------------------------------------------ 配置
nx_conf_get() { [[ -f $NX_DIR/nx.conf ]] && awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$NX_DIR/nx.conf"; }
nx_conf_set() {
  mkdir -p "$NX_DIR"
  touch "$NX_DIR/nx.conf"
  if grep -q "^$1=" "$NX_DIR/nx.conf"; then
    sed -i "s|^$1=.*|$1=$2|" "$NX_DIR/nx.conf"
  else
    echo "$1=$2" >> "$NX_DIR/nx.conf"
  fi
}

# ------------------------------------------------------------------ 显示宽度对齐（中文按 2 列）
dwidth() {
  local b c
  b=$(printf '%s' "$1" | LC_ALL=C wc -c)
  c=$(printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c)
  echo $(( c + (b - c) / 2 ))
}
pad() {
  local d
  d=$(dwidth "$1")
  printf '%s%*s' "$1" $(( $2 > d ? $2 - d : 0 )) ''
}
row() { printf '  %s%s%s %s\n' "$C_CYN" "$(pad "$1" 12)" "$C_RST" "$2"; }
item2() { printf '  %s%-4s%s %s %s%-4s%s %s\n' "$C_CYN" "$1" "$C_RST" "$(pad "$2" 30)" "$C_CYN" "$3" "$C_RST" "$4"; }

# ================================================================== 系统信息
sys_info() {
  local cpu cores freq usage load mem swap disk tcpn udpn iface rx tx cc qd v4 v6 geo dns tz up virt js
  info "正在采集系统信息，请稍候..."
  cpu=$(awk -F': +' '/^model name|^Model name/ {print $2; exit}' /proc/cpuinfo)
  [[ -z $cpu ]] && cpu=$(lscpu 2>/dev/null | awk -F': +' '/Model name/ {print $2; exit}')
  cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
  freq=$(awk -F': +' '/^cpu MHz/ {printf "%.2f GHz", $2 / 1000; exit}' /proc/cpuinfo)
  usage=$(awk '{u = $2 + $4; t = $2 + $4 + $5; if (NR == 1) { u1 = u; t1 = t } else if (t - t1 > 0) printf "%.0f%%", (u - u1) * 100 / (t - t1); else print "0%"}' \
    <(grep '^cpu ' /proc/stat) <(sleep 1; grep '^cpu ' /proc/stat))
  load=$(awk '{print $1 " / " $2 " / " $3}' /proc/loadavg)
  mem=$(free -m | awk 'NR == 2 {printf "%d / %d MB (%.1f%%)", $3, $2, $3 * 100 / $2}')
  swap=$(free -m | awk 'NR == 3 {if ($2 == 0) print "未启用"; else printf "%d / %d MB (%.1f%%)", $3, $2, $3 * 100 / $2}')
  disk=$(df -h / | awk 'NR == 2 {printf "%s / %s (%s)", $3, $2, $5}')
  tcpn=$(ssq -tan state established | grep -c .)
  udpn=$(ssq -uan | grep -c .)
  iface=$(main_iface)
  if [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
    rx=$(fmt_bytes "$(cat "/sys/class/net/$iface/statistics/rx_bytes")")
    tx=$(fmt_bytes "$(cat "/sys/class/net/$iface/statistics/tx_bytes")")
  fi
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
  v4=$(public_ipv4)
  v6=$(public_ipv6)
  js=$(curl -fsS --max-time 5 https://ipinfo.io/json 2>/dev/null)
  if [[ -n $js ]]; then
    geo="$(sed -n 's/.*"country": *"\([^"]*\)".*/\1/p' <<<"$js" | head -1) $(sed -n 's/.*"city": *"\([^"]*\)".*/\1/p' <<<"$js" | head -1)  $(sed -n 's/.*"org": *"\([^"]*\)".*/\1/p' <<<"$js" | head -1)"
  fi
  dns=$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)
  tz=$(timedatectl show -p Timezone --value 2>/dev/null)
  [[ -z $tz ]] && tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
  up=$(awk '{d = int($1 / 86400); h = int($1 % 86400 / 3600); m = int($1 % 3600 / 60); if (d) printf "%d天 ", d; if (h) printf "%d时 ", h; printf "%d分", m}' /proc/uptime)
  virt=$(virt_type)
  title "系统信息"
  row "主机名" "$(hostname)"
  row "系统" "$OS_NAME"
  row "内核" "$(uname -r)"
  row "虚拟化" "$virt"
  hr
  row "CPU 架构" "$(uname -m)"
  row "CPU 型号" "${cpu:-未知}"
  row "CPU 核心" "$cores 核  ${freq}"
  row "CPU 占用" "$usage"
  row "系统负载" "$load"
  row "TCP/UDP" "已建立 TCP $tcpn · UDP $udpn"
  hr
  row "物理内存" "$mem"
  row "虚拟内存" "$swap"
  row "系统盘" "$disk"
  hr
  row "主网卡" "${iface:--}  累计接收 ${rx:--} · 发送 ${tx:--}"
  row "拥塞控制" "${cc:--} / ${qd:--}"
  row "IPv4" "${v4:-无}"
  row "IPv6" "${v6:-无}"
  row "位置/运营商" "${geo:-未知}"
  row "DNS" "${dns:--}"
  hr
  row "时区" "${tz:-未知}  $(date '+%F %T')"
  row "运行时长" "$up"
}

# ================================================================== 更新 / 清理
fix_dpkg() {
  local i=0
  if has fuser; then
    while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
      [[ $i -ge 40 ]] && break
      [[ $i -eq 0 ]] && info "等待其他 apt/dpkg 进程结束..."
      i=$((i + 1))
      sleep 3
    done
  fi
  DEBIAN_FRONTEND=noninteractive dpkg --configure -a >/dev/null 2>&1
  return 0
}

sys_update() {
  local rc
  info "开始更新系统软件包"
  case $(pkg_mgr) in
    apt-get)
      fix_dpkg
      apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade ;;
    dnf) dnf -y upgrade --refresh ;;
    yum) yum -y update ;;
    apk) apk update && apk upgrade ;;
    pacman) pacman -Syu --noconfirm ;;
    zypper) zypper -n refresh && zypper -n update ;;
    *) err "未识别的包管理器"; return 1 ;;
  esac
  rc=$?
  if [[ $rc -eq 0 ]]; then ok "系统更新完成"; else err "更新过程中出现错误（退出码 $rc）"; fi
  if [[ -f /var/run/reboot-required ]]; then warn "系统提示需要重启以完成更新（如内核升级）"; fi
  return "$rc"
}

sys_clean() {
  local before after freed
  info "开始清理"
  before=$(df -k / | awk 'NR == 2 {print $3}')
  case $(pkg_mgr) in
    apt-get)
      fix_dpkg
      apt-get autoremove --purge -y
      apt-get clean
      dpkg -l 2>/dev/null | awk '/^rc/ {print $2}' | xargs -r apt-get purge -y ;;
    dnf) dnf autoremove -y; dnf clean all ;;
    yum) yum autoremove -y; yum clean all ;;
    apk) rm -rf /var/cache/apk/* ;;
    pacman) pacman -Qdtq 2>/dev/null | xargs -r pacman -Rns --noconfirm; pacman -Scc --noconfirm ;;
    zypper) zypper clean --all ;;
  esac >/dev/null 2>&1
  if has journalctl; then journalctl --vacuum-time=7d --vacuum-size=200M >/dev/null 2>&1; fi
  find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' -o -name '*.xz' \) -delete 2>/dev/null
  find /tmp /var/tmp -mindepth 1 -type f -mtime +7 -delete 2>/dev/null
  after=$(df -k / | awk 'NR == 2 {print $3}')
  freed=$(( (before - after) * 1024 ))
  (( freed < 0 )) && freed=0
  ok "清理完成，释放约 $(fmt_bytes "$freed")"
}

# ================================================================== 常用工具
pkg_name() {
  local m
  m=$(pkg_mgr)
  case "$1:$m" in
    dnsutils:dnf|dnsutils:yum) echo bind-utils ;;
    dnsutils:apk) echo bind-tools ;;
    dnsutils:pacman) echo bind ;;
    netcat:apt-get|netcat:apk) echo netcat-openbsd ;;
    netcat:dnf|netcat:yum) echo nmap-ncat ;;
    netcat:pacman) echo openbsd-netcat ;;
    *) echo "$1" ;;
  esac
}

ensure_epel() {
  case $(pkg_mgr) in
    dnf|yum)
      rpm -q epel-release >/dev/null 2>&1 || pkg_install epel-release >/dev/null 2>&1 || true ;;
  esac
}

install_list() {
  local p name okn=0 failn=0 failed=""
  local -a names=()
  ensure_epel
  for p in "$@"; do names+=("$(pkg_name "$p")"); done
  if pkg_install "${names[@]}" >/dev/null 2>&1; then ok "安装完成：成功 ${#names[@]} 个"; return 0; fi
  # 整批失败多半是个别包在当前仓库不存在，逐个重装以找出是哪几个
  for name in "${names[@]}"; do
    if pkg_install "$name" >/dev/null 2>&1; then
      okn=$((okn + 1))
    else
      failn=$((failn + 1)); failed+="$name "
    fi
  done
  if (( okn == 0 )); then err "安装失败（${failed% }），请检查软件源与内存"; return 1; fi
  ok "安装完成：成功 $okn 个${failed:+，失败 $failn 个（${failed% }）}"
}

menu_tools() {
  local c v
  local -a _pk
  while :; do
    title "常用工具安装"
    item 1 "常用工具：curl wget sudo socat unzip tar nano vim htop jq lsof tmux git"
    item 2 "网络排障：mtr traceroute dnsutils tcpdump iperf3 iftop nload vnstat netcat"
    item 3 "btop 资源监控"
    item 4 "自定义安装（输入包名，空格分隔）"
    item 5 "卸载软件（输入包名）"
    item 0 "返回"
    read_choice c
    case $c in
      1) install_list curl wget sudo socat unzip tar nano vim htop jq lsof tmux git; pause ;;
      2) install_list mtr traceroute dnsutils tcpdump iperf3 iftop nload vnstat netcat; pause ;;
      3) install_list btop; pause ;;
      4) ask v "包名" "" && [[ -n $v ]] && { read -ra _pk <<<"$v"; install_list "${_pk[@]}"; }; pause ;;
      5) ask v "要卸载的包名" "" && [[ -n $v ]] && confirm "确认卸载 $v?" N && { read -ra _pk <<<"$v"; pkg_remove "${_pk[@]}"; }; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== BBR / 网络优化
NET_SYSCTL="/etc/sysctl.d/99-nx-net.conf"
BBR_SYSCTL="/etc/sysctl.d/99-nx-bbr.conf"

bbr_supported() {
  modprobe tcp_bbr >/dev/null 2>&1
  grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
}

# sysctl --system 最后加载 /etc/sysctl.conf，其中同名键会覆盖 sysctl.d 的配置：注释掉冲突行（可还原）
sysctl_conf_yield() {
  local k
  [[ -f /etc/sysctl.conf ]] || return 0
  for k in $(awk -F'[ =]+' '/^[a-z]/ {print $1}' "$1"); do
    sed -i -E "s/^([[:space:]]*${k//./\\.}[[:space:]]*=)/# nx: \1/" /etc/sysctl.conf
  done
}
sysctl_conf_restore() { [[ -f /etc/sysctl.conf ]] && sed -i -E 's/^# nx: //' /etc/sysctl.conf; return 0; }

bbr_enable() {
  if ! bbr_supported; then
    case $(virt_type) in
      lxc) err "宿主机未加载 BBR 模块：在宿主机执行 nx bbr（或 modprobe tcp_bbr）后，小鸡里再运行即可" ;;
      openvz) err "OpenVZ 容器无法修改拥塞控制" ;;
      *) err "当前内核不支持 BBR（可在本菜单安装新内核）" ;;
    esac
    return 1
  fi
  printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > "$BBR_SYSCTL"
  sysctl_conf_yield "$BBR_SYSCTL"
  sysctl -p "$BBR_SYSCTL" >/dev/null 2>&1
  if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr ]]; then ok "BBR + fq 已开启"; else err "开启失败"; return 1; fi
}

net_optimize() {
  local mem_mb buf fmax
  mem_mb=$(free -m | awk 'NR == 2 {print $2}')
  if (( mem_mb < 1024 )); then buf=16777216; else buf=67108864; fi
  fmax=$(sysctl -n fs.file-max 2>/dev/null)
  {
    echo "# 由 NX 工具箱生成：代理/转发节点网络优化（菜单「还原网络优化」可撤销）"
    echo "net.core.default_qdisc = fq"
    if bbr_supported; then echo "net.ipv4.tcp_congestion_control = bbr"; fi
    # 新版 systemd 已把 fs.file-max 设为极大值，只在更小时才调高
    if [[ $fmax =~ ^[0-9]{1,7}$ ]] && (( fmax < 1048576 )); then echo "fs.file-max = 1048576"; fi
    cat <<EOF
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = $buf
net.core.wmem_max = $buf
net.ipv4.tcp_rmem = 4096 131072 $buf
net.ipv4.tcp_wmem = 4096 65536 $buf
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
fs.inotify.max_user_instances = 8192
vm.swappiness = 10
EOF
  } > "$NET_SYSCTL"
  sysctl_conf_yield "$NET_SYSCTL"
  mkdir -p /etc/security/limits.d
  printf '* soft nofile 1048576\n* hard nofile 1048576\nroot soft nofile 1048576\nroot hard nofile 1048576\n' > /etc/security/limits.d/99-nx.conf
  if [[ -d /etc/systemd ]]; then
    mkdir -p /etc/systemd/system.conf.d
    printf '[Manager]\nDefaultLimitNOFILE=1048576\n' > /etc/systemd/system.conf.d/99-nx.conf
    systemctl daemon-reexec >/dev/null 2>&1
  fi
  if sysctl -p "$NET_SYSCTL" >/dev/null 2>&1; then
    ok "网络优化已应用（缓冲区上限 $(fmt_bytes "$buf")，文件句柄 1048576）"
  else
    warn "部分参数在当前环境不可用（容器/OpenVZ 常见），其余已生效"
  fi
}

net_restore() {
  rm -f "$NET_SYSCTL" "$BBR_SYSCTL" /etc/security/limits.d/99-nx.conf /etc/systemd/system.conf.d/99-nx.conf
  sysctl_conf_restore
  sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1
  ok "已删除 NX 网络优化配置（未写在任何配置文件里的参数重启后还原）"
}

menu_bbr() {
  local c
  while :; do
    title "BBR / 网络优化"
    row "拥塞控制" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) / $(sysctl -n net.core.default_qdisc 2>/dev/null)"
    row "可用算法" "$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
    row "内核" "$(uname -r)  ($(virt_type))"
    row "优化配置" "$([[ -f $NET_SYSCTL ]] && echo 已应用 || echo 未应用)"
    hr
    item 1 "开启 BBR + fq（原版内核 4.9+）"
    item 2 "网络参数优化（代理/转发节点：缓冲区、连接队列、端口范围、文件句柄）"
    item 3 "安装 BBRv3 / XanMod 等内核（ylx2016 Linux-NetSpeed，KVM 适用）"
    item 4 "还原网络优化"
    item 0 "返回"
    read_choice c
    case $c in
      1) bbr_enable; pause ;;
      2) net_optimize; pause ;;
      3)
        warn "更换内核有无法启动的风险，请确认服务商支持 VNC/救援模式"
        confirm "继续?" N && run_remote "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh"
        pause ;;
      4) net_restore; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== Docker
# get.docker.com 给 Rocky / Alma 配的 linux/rocky、linux/almalinux 仓库里没有 docker-ce（2026-11 实测），RHEL 衍生版直接用 CentOS 仓库
docker_el_clone() {
  case $OS_ID in centos|rhel|fedora) return 1 ;; esac
  grep -Eqs '^ID_LIKE=.*(rhel|centos)' /etc/os-release
}

docker_install_el() {
  local base=https://download.docker.com repo=/etc/yum.repos.d/docker-ce.repo
  if in_china; then base=https://mirrors.aliyun.com/docker-ce; fi
  dl "$base/linux/centos/docker-ce.repo" "$repo" 30 || { err "下载 Docker 仓库配置失败"; return 1; }
  if [[ $base != https://download.docker.com ]]; then sed -i "s#https://download.docker.com#$base#g" "$repo"; fi
  pkg_install docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
}

docker_install() {
  if has docker; then info "已安装 $(docker --version)"; fi
  if [[ $(pkg_mgr) == apk ]]; then
    apk add --no-cache docker docker-cli-compose && rc-update add docker default && rc-service docker start
  elif docker_el_clone; then
    docker_install_el && systemctl enable --now docker >/dev/null 2>&1
  else
    local tmp
    tmp=$(mktemp)
    dl https://get.docker.com "$tmp" 60 || { rm -f "$tmp"; err "下载 get.docker.com 失败"; return 1; }
    if in_china; then sh "$tmp" --mirror Aliyun; else sh "$tmp"; fi
    rm -f "$tmp"
    systemctl enable --now docker >/dev/null 2>&1
  fi
  if has docker; then ok "$(docker --version)"; docker compose version 2>/dev/null; else err "Docker 安装失败"; return 1; fi
  # 先开了小鸡再装 Docker：Docker 会把 FORWARD 链设为 DROP，小鸡会断网
  if lxc_detect && $IC network show "$LXC_BRIDGE" >/dev/null 2>&1; then lxc_docker_fix; fi
  return 0
}

docker_restart_check() {
  local i
  # systemd 默认 1 分钟内只让 docker 启动 3 次：连续改几项设置、或新配置失败后的自动重启，会让之后的启动被直接拒绝
  if has systemctl; then systemctl reset-failed docker >/dev/null 2>&1; fi
  { systemctl restart docker || rc-service docker restart; } >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9 10; do docker info >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}

# docker_daemon_set jq表达式：Docker 用新配置起不来时自动恢复原配置
docker_daemon_set() {
  local f=/etc/docker/daemon.json tmp bak
  ensure_cmd jq jq || { err "需要 jq"; return 1; }
  mkdir -p /etc/docker
  [[ -s $f ]] || echo '{}' > "$f"
  tmp=$(mktemp)
  if ! jq "$1" "$f" > "$tmp"; then rm -f "$tmp"; err "daemon.json 解析失败"; return 1; fi
  bak=$(mktemp)
  cp -p "$f" "$bak"
  cat "$tmp" > "$f"
  rm -f "$tmp"
  if docker_restart_check; then rm -f "$bak"; return 0; fi
  err "Docker 使用新配置无法启动，已恢复原配置"
  cat "$bak" > "$f"
  rm -f "$bak"
  docker_restart_check || err "恢复原配置后 Docker 仍未启动，请查看 journalctl -u docker"
  return 1
}

menu_docker() {
  local c v n
  while :; do
    title "Docker 管理"
    if has docker; then
      row "版本" "$(docker --version 2>/dev/null | cut -d, -f1)"
      row "运行状态" "$(systemctl is-active docker 2>/dev/null || echo -)"
      row "容器" "$(docker ps -q 2>/dev/null | wc -l) 运行 / $(docker ps -aq 2>/dev/null | wc -l) 总计 · 镜像 $(docker images -q 2>/dev/null | wc -l)"
    else
      row "状态" "未安装"
    fi
    hr
    item2 1 "安装 / 更新 Docker" 2 "容器列表"
    item2 3 "启动/停止/重启/删除容器" 4 "查看容器日志"
    item2 5 "清理无用镜像/容器/网络" 6 "设置镜像加速"
    item2 7 "开启 Docker IPv6" 8 "卸载 Docker"
    item 0 "返回"
    read_choice c
    case $c in
      1) docker_install; pause ;;
      2) docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}'; pause ;;
      3)
        docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
        ask n "容器名" "" || continue
        [[ -z $n ]] && continue
        ask v "操作 start/stop/restart/rm" "restart" || continue
        case $v in
          start|stop|restart) docker "$v" "$n" ;;
          rm) confirm "删除容器 $n?" N && docker rm -f "$n" ;;
          *) err "无效操作" ;;
        esac
        pause ;;
      4) ask n "容器名" "" && [[ -n $n ]] && docker logs --tail 100 "$n"; pause ;;
      5) confirm "删除所有已停止容器、未使用镜像和网络?" N && docker system prune -af; pause ;;
      6)
        echo "  Docker Hub 国内镜像经常变动，请填写当前可用的地址（例如 https://docker.1ms.run）"
        ask v "镜像加速地址" "" || continue
        if [[ $v =~ ^https?://[A-Za-z0-9.:/_-]+$ ]]; then docker_daemon_set ".\"registry-mirrors\" = [\"$v\"]" && ok "已设置"; else err "地址无效"; fi
        pause ;;
      7)
        v='.ipv6 = true | ."fixed-cidr-v6" = "fd00:dead:beef::/48" | ."ip6tables" = true'
        # Docker 27 之前 ip6tables 属于实验特性，不开 experimental 会导致 dockerd 无法启动
        n=$(docker version -f '{{.Server.Version}}' 2>/dev/null | cut -d. -f1)
        if [[ $n =~ ^[0-9]+$ ]] && (( n < 27 )); then v+=' | .experimental = true'; fi
        docker_daemon_set "$v" && ok "已开启 IPv6"; pause ;;
      8)
        confirm "卸载 Docker 并删除全部容器和镜像数据?" N || continue
        systemctl disable --now docker docker.socket >/dev/null 2>&1
        pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras \
          docker.io docker-compose docker docker-cli-compose >/dev/null 2>&1
        rm -rf /var/lib/docker /var/lib/containerd /etc/docker
        ok "已卸载"; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== 测试脚本合集
menu_tests() {
  local c h p
  while :; do
    title "测试脚本合集（第三方脚本，执行前会显示命令）"
    printf '  %s── IP / 解锁 ──%s\n' "$C_GRY" "$C_RST"
    item2 1 "IP 质量体检（xykt）" 2 "网络质量体检（xykt）"
    item2 3 "流媒体/AI 解锁检测" "" ""
    printf '  %s── 线路 ──%s\n' "$C_GRY" "$C_RST"
    item2 11 "三网回程路由（NextTrace）" 12 "回程线路类型（backtrace）"
    item2 13 "指定 IP 路由追踪" 14 "三网测速（i-abc）"
    item2 15 "TCP 端口延迟测试" "" ""
    printf '  %s── 性能 ──%s\n' "$C_GRY" "$C_RST"
    item2 21 "bench.sh" 22 "YABS"
    item2 23 "融合怪 ECS（spiritLHLS）" 24 "NodeQuality"
    item 0 "返回"
    read_choice c
    case $c in
      1) run_cmd 'bash <(curl -Ls IP.Check.Place)'; pause ;;
      2) run_cmd 'bash <(curl -Ls Net.Check.Place)'; pause ;;
      3) run_cmd 'bash <(curl -L -s check.unlock.media)'; pause ;;
      11) run_cmd 'curl -sL nxtrace.org/nt | bash && nexttrace --fast-trace --tcp'; pause ;;
      12) run_cmd 'curl -sSf https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh | sh && backtrace'; pause ;;
      13)
        ask h "目标 IP 或域名" "" || continue
        if [[ $h =~ ^[A-Za-z0-9.:-]+$ ]]; then
          has nexttrace || run_cmd 'curl -sL nxtrace.org/nt | bash'
          nexttrace "$h"
        else
          err "地址无效"
        fi
        pause ;;
      14) run_cmd 'bash <(curl -sL https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh)'; pause ;;
      15)
        ask h "主机" "" || continue; ask p "端口" "443" || continue
        if [[ $h =~ ^[A-Za-z0-9.:-]+$ ]] && is_port "$p"; then tcping_host "$h" "$p" 5; else err "输入无效"; fi
        pause ;;
      21) run_cmd 'wget -qO- bench.sh | bash'; pause ;;
      22) run_cmd 'curl -sL yabs.sh | bash'; pause ;;
      23) run_cmd 'bash <(wget -qO- bash.spiritlhl.net/ecs)'; pause ;;
      24) run_cmd 'bash <(curl -sL https://run.NodeQuality.com)'; pause ;;
      0|"") return ;;
    esac
  done
}

tcping_host() {
  local h=$1 p=$2 n=${3:-4} i d vals=""
  for (( i = 1; i <= n; i++ )); do
    d=$(timeout 3 bash -c '
      if [[ -n ${EPOCHREALTIME:-} ]]; then s=${EPOCHREALTIME/[.,]/}; exec 3<>"/dev/tcp/$1/$2" || exit 1; e=${EPOCHREALTIME/[.,]/}
      else s=$(date +%s%N); exec 3<>"/dev/tcp/$1/$2" || exit 1; e=$(date +%s%N); s=$((s / 1000)); e=$((e / 1000)); fi
      echo $((e - s))' _ "$h" "$p" 2>/dev/null)
    if [[ $d =~ ^[0-9]+$ ]]; then
      d=$(awk -v d="$d" 'BEGIN { printf "%.1f", d / 1000 }')
      printf '    #%d  %s:%s  %s ms\n' "$i" "$h" "$p" "$d"
      vals+="$d "
    else
      printf '    #%d  %s:%s  %s超时/拒绝%s\n' "$i" "$h" "$p" "$C_RED" "$C_RST"
    fi
    sleep 0.5
  done
  if [[ -n $vals ]]; then
    awk -v n="$n" -v v="$vals" 'BEGIN { c = split(v, a, " "); min = a[1]; max = a[1]; s = 0
      for (i = 1; i <= c; i++) { s += a[i]; if (a[i] < min) min = a[i]; if (a[i] > max) max = a[i] }
      printf "  成功 %d/%d  最小 %.1f  平均 %.1f  最大 %.1f ms\n", c, n, min, s / c, max }'
  fi
}

# ================================================================== SSH
SSHD_CONF="/etc/ssh/sshd_config"
SSH_BEGIN="# >>> nx-toolbox managed >>>"
SSH_END="# <<< nx-toolbox managed <<<"
SSH_BAK=""

ssh_backup() {
  SSH_BAK=$(mktemp -d /tmp/nx-ssh.XXXXXX)
  cp -a "$SSHD_CONF" "$SSH_BAK/"
  if [[ -d /etc/ssh/sshd_config.d ]]; then cp -a /etc/ssh/sshd_config.d "$SSH_BAK/"; fi
  [[ -f $SSHD_CONF.nx-orig ]] || cp -a "$SSHD_CONF" "$SSHD_CONF.nx-orig"
}

ssh_rollback() {
  [[ -n $SSH_BAK && -f $SSH_BAK/sshd_config ]] || return 1
  cat "$SSH_BAK/sshd_config" > "$SSHD_CONF"
  if [[ -d $SSH_BAK/sshd_config.d ]]; then
    rm -rf /etc/ssh/sshd_config.d
    cp -a "$SSH_BAK/sshd_config.d" /etc/ssh/
  fi
  warn "已回滚 SSH 配置"
}

# 在 sshd_config 顶部维护受管配置块：sshd 对同一选项取第一次出现的值，可覆盖云镜像 drop-in 的设置
sshd_set() {
  local k=$1 v=${2-} tmp
  [[ -f $SSHD_CONF ]] || { err "未找到 $SSHD_CONF（未安装 openssh-server?）"; return 1; }
  if ! grep -qF "$SSH_BEGIN" "$SSHD_CONF"; then
    tmp=$(mktemp)
    { echo "$SSH_BEGIN"; echo "$SSH_END"; cat "$SSHD_CONF"; } > "$tmp"
    cat "$tmp" > "$SSHD_CONF"
    rm -f "$tmp"
  fi
  sed -i "/^$SSH_BEGIN\$/,/^$SSH_END\$/{/^[[:space:]]*${k}[[:space:]]/d}" "$SSHD_CONF"
  if [[ -n $v ]]; then sed -i "/^$SSH_END\$/i $k $v" "$SSHD_CONF"; fi
}

# sshd 校验/读取配置需要特权分离目录；套接字激活且服务未运行时它可能不存在
ssh_privsep_dir() { mkdir -p /run/sshd 2>/dev/null && chmod 0755 /run/sshd 2>/dev/null; return 0; }

sshd_effective() { ssh_privsep_dir; sshd -T 2>/dev/null | awk -v k="${1,,}" '$1 == k {print $2; exit}'; }

ssh_socket_mode() {
  has systemctl && [[ -d /run/systemd/system ]] || return 1
  systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-enabled --quiet ssh.socket 2>/dev/null
}

ssh_restart() {
  ssh_privsep_dir
  if has systemctl && [[ -d /run/systemd/system ]]; then
    systemctl reset-failed ssh.socket ssh.service sshd.service >/dev/null 2>&1
    if ssh_socket_mode; then
      # Ubuntu 22.10+ 套接字激活：端口由 ssh.socket 监听，重载生成器后只重启 socket，已建立的会话不受影响
      systemctl daemon-reload
      systemctl restart ssh.socket
      return
    fi
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
  else
    rc-service sshd restart >/dev/null 2>&1 || service sshd restart >/dev/null 2>&1 || service ssh restart >/dev/null 2>&1
  fi
}

# 校验后生效，失败自动回滚
ssh_commit() {
  local out
  ssh_privsep_dir
  if ! out=$(sshd -t 2>&1); then
    err "SSH 配置校验失败：$(head -n 2 <<<"$out")"
    ssh_rollback
    return 1
  fi
  if ! ssh_restart; then
    err "SSH 服务重启失败"
    ssh_rollback
    ssh_restart
    return 1
  fi
  return 0
}

ssh_change_port() {
  local p=$1 f i listening=0 ports
  is_port "$p" || { err "端口无效: $p"; return 1; }
  ensure_ss >/dev/null 2>&1
  if port_in_use "$p" && ! ssq -lntp "( sport = :$p )" | grep -qE '"(sshd|systemd)"'; then
    err "端口 $p 已被其他程序占用"; return 1
  fi
  # 小鸡的 NAT 端口映射不会出现在 ss 里
  if lxc_detect && ! port_block_free "$p" "$p" ""; then err "端口 $p 已被小鸡端口映射占用"; return 1; fi
  ssh_backup
  sed -i -E 's/^([[:space:]]*Port[[:space:]]+[0-9]+)/# nx: \1/' "$SSHD_CONF"
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [[ -f $f ]] && sed -i -E 's/^([[:space:]]*Port[[:space:]]+[0-9]+)/# nx: \1/' "$f"
  done
  sshd_set Port "$p"
  if has getenforce && [[ $(getenforce 2>/dev/null) == Enforcing ]]; then
    has semanage || ensure_cmd semanage policycoreutils-python-utils || ensure_cmd semanage policycoreutils-python
    semanage port -a -t ssh_port_t -p tcp "$p" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$p" 2>/dev/null
  fi
  fw_open "$p" tcp
  ssh_commit || return 1
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if ssq -lnt "( sport = :$p )" | grep -q .; then listening=1; break; fi
    sleep 0.5
  done
  if [[ $listening != 1 ]]; then
    err "新端口 $p 未进入监听，已回滚"
    ssh_rollback; ssh_restart
    return 1
  fi
  ok "SSH 端口已改为 $p"
  if [[ -f /etc/fail2ban/jail.d/zz-nx-sshd.local ]]; then
    ports=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | paste -sd, -)
    if [[ -n $ports ]]; then
      sed -i -E "s/^port[[:space:]]*=.*/port      = $ports/" /etc/fail2ban/jail.d/zz-nx-sshd.local
      fail2ban-client reload >/dev/null 2>&1 || svc_restart_any fail2ban >/dev/null 2>&1
      info "fail2ban 监控端口已同步为 $ports"
    fi
  fi
  warn "请先新开一个终端用 ssh -p $p 测试能否登录，确认后再关闭当前会话；云服务器还需在安全组放行 $p/tcp"
}

ssh_password_login() { # on|off
  ssh_backup
  if [[ $1 == on ]]; then
    sshd_set PasswordAuthentication yes
    sshd_set KbdInteractiveAuthentication yes
  else
    if [[ ! -s /root/.ssh/authorized_keys ]]; then
      warn "root 没有配置任何公钥，关闭密码登录后 root 将无法登录"
      confirm "确认其他用户已能用密钥登录，仍然关闭?" N || { ssh_rollback; return 1; }
    fi
    sshd_set PasswordAuthentication no
    sshd_set KbdInteractiveAuthentication no
  fi
  ssh_commit && ok "密码登录已$([[ $1 == on ]] && echo 开启 || echo 关闭)（生效值: $(sshd_effective PasswordAuthentication)）"
}

authorized_add() { # authorized_add 用户家目录 公钥文本
  local home=$1 key=$2 f
  f="$home/.ssh/authorized_keys"
  mkdir -p "$home/.ssh"
  chmod 700 "$home/.ssh"
  touch "$f"
  chmod 600 "$f"
  grep -qxF "$key" "$f" || append_line "$f" "$key"
}

valid_pubkey() { [[ $1 =~ ^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp[0-9]+|sk-[a-z0-9@.-]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; }

menu_sshkey() {
  local c k u n tmpk
  while :; do
    title "SSH 密钥登录"
    row "root 公钥数" "$(grep -cE '^(ssh-|ecdsa-|sk-)' /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
    row "密码登录" "$(sshd_effective PasswordAuthentication)"
    row "root 登录" "$(sshd_effective PermitRootLogin)"
    hr
    item 1 "粘贴公钥添加"
    item 2 "从 GitHub 用户导入公钥（github.com/用户名.keys）"
    item 3 "生成新密钥对（显示私钥，请立即保存）"
    item 4 "仅允许密钥登录（关闭密码登录）"
    item 5 "查看已授权公钥"
    item 0 "返回"
    read_choice c
    case $c in
      1)
        ask k "粘贴公钥（ssh-ed25519 AAAA... 一整行）" "" || continue
        if valid_pubkey "$k"; then authorized_add /root "$k"; ok "已添加"; else err "公钥格式无效"; fi
        pause ;;
      2)
        ask u "GitHub 用户名" "" || continue
        [[ $u =~ ^[A-Za-z0-9-]{1,39}$ ]] || { err "用户名无效"; pause; continue; }
        tmpk=$(mktemp)
        if dl "https://github.com/$u.keys" "$tmpk" 20 && [[ -s $tmpk ]]; then
          n=0
          while IFS= read -r k; do valid_pubkey "$k" && { authorized_add /root "$k"; n=$((n + 1)); }; done < "$tmpk"
          ok "已导入 $n 个公钥"
        else
          err "获取失败"
        fi
        rm -f "$tmpk"; pause ;;
      3)
        tmpk=$(mktemp -d)
        ssh-keygen -q -t ed25519 -N '' -C "nx@$(hostname)" -f "$tmpk/key" || { rm -rf "$tmpk"; pause; continue; }
        authorized_add /root "$(cat "$tmpk/key.pub")"
        echo; warn "以下为私钥，复制保存到本地（如 ~/.ssh/id_ed25519，权限 600），不会再次显示："
        echo; cat "$tmpk/key"; echo
        rm -rf "$tmpk"
        ok "公钥已加入 root 授权列表"; pause ;;
      4) confirm "确认已用密钥成功登录过，再关闭密码登录?" N && ssh_password_login off; pause ;;
      5) cat /root/.ssh/authorized_keys 2>/dev/null | awk '{print "  " NR ") " $1 " " substr($2, 1, 24) "... " $3}'; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== Root 登录（融合 NX2406/ovhroot）
# 公钥来源：优先发起 sudo 的用户；否则只取 sudo/wheel/admin 组里有公钥的用户（不碰 git、备份等服务账号）
root_source_users() {
  local u h g
  if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then echo "$SUDO_USER"; return; fi
  while IFS=: read -r u _ _ _ _ h _; do
    [[ $u == root || -z $h || $h == / ]] && continue
    [[ -s $h/.ssh/authorized_keys ]] || continue
    for g in $(id -nG "$u" 2>/dev/null); do
      case $g in sudo|wheel|admin) echo "$u"; break ;; esac
    done
  done < /etc/passwd
}

# 去掉云厂商写入 root authorized_keys 的 "Please login as the user ..." 限制，只保留公钥本体
root_unrestrict_keys() {
  local f=/root/.ssh/authorized_keys tmp
  [[ -f $f ]] || return 0
  grep -q 'Please login as' "$f" || return 0
  tmp=$(mktemp)
  awk '{
    if (index($0, "Please login as")) {
      if (match($0, /(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp[0-9]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+\/=]+/)) print substr($0, RSTART)
    } else print
  }' "$f" > "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
  info "已移除云厂商对 root 公钥的登录限制"
}

# root_login key|password [密码]
root_login() {
  local mode=${1:-key} pw=${2:-} u h k n=0 tmp
  local -a users
  mapfile -t users < <(root_source_users)
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  root_unrestrict_keys
  # 只同步不带选项的普通公钥行：带 command= 等限制的密钥属于特定用途，不应获得 root 权限
  for u in "${users[@]}"; do
    h=$(awk -F: -v u="$u" '$1 == u {print $6; exit}' /etc/passwd)
    if [[ -s $h/.ssh/authorized_keys ]]; then
      while IFS= read -r k; do
        valid_pubkey "$k" && append_line /root/.ssh/authorized_keys "$k"
      done < "$h/.ssh/authorized_keys"
      n=$((n + 1))
      ok "已同步用户 $u 的公钥给 root"
    fi
  done
  tmp=$(mktemp)
  awk 'NF && !seen[$0]++' /root/.ssh/authorized_keys > "$tmp" && cat "$tmp" > /root/.ssh/authorized_keys
  rm -f "$tmp"
  if [[ $n -eq 0 && $mode == key ]]; then
    warn "没有找到可同步的用户公钥（可在「SSH 密钥登录」中手动添加），root 将无法用密钥登录"
  fi
  ssh_backup
  if [[ $mode == password ]]; then sshd_set PermitRootLogin yes; else sshd_set PermitRootLogin prohibit-password; fi
  sshd_set PubkeyAuthentication yes
  if [[ $mode == password ]]; then
    if [[ -z $pw ]]; then
      if [[ -t 0 ]]; then
        ask_secret pw "设置 root 密码（回车随机生成）"
      fi
      [[ -z $pw ]] && pw=$(rand_pass 16)
    fi
    if ! echo "root:$pw" | chpasswd; then err "设置 root 密码失败"; ssh_rollback; return 1; fi
    sshd_set PasswordAuthentication yes
    sshd_set KbdInteractiveAuthentication yes
  fi
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    {
      echo "# 由 NX 工具箱生成：防止 cloud-init 重新禁用 root 登录"
      echo "disable_root: false"
      if [[ $mode == password ]]; then echo "ssh_pwauth: true"; fi
    } > /etc/cloud/cloud.cfg.d/99-nx-root.cfg
  fi
  ssh_commit || return 1
  ok "root 登录已开启（PermitRootLogin=$(sshd_effective PermitRootLogin)，密码登录=$(sshd_effective PasswordAuthentication)）"
  if [[ $mode == password ]]; then
    printf '\n  %sroot 密码：%s%s\n' "$C_GRN$C_BLD" "$pw" "$C_RST"
    warn "请妥善保存，并建议安装 fail2ban 防爆破"
  fi
}

menu_root() {
  local c
  while :; do
    title "Root 登录开启（融合 NX2406/ovhroot）"
    echo "  适用 OVH、AWS、甲骨文、Azure 等默认禁止 root、只能用 ubuntu/debian 等用户登录的 VPS"
    row "当前 root 登录" "$(sshd_effective PermitRootLogin)"
    row "密码登录" "$(sshd_effective PasswordAuthentication)"
    hr
    item 1 "开启 root 密钥登录（把当前 sudo 用户的公钥同步给 root，原 ovhroot 功能）"
    item 2 "开启 root 密码登录（同步公钥 + 设置 root 密码 + 允许密码登录）"
    item 3 "运行原版 ovhroot 脚本"
    item 0 "返回"
    read_choice c
    case $c in
      1) root_login key; pause ;;
      2) root_login password; pause ;;
      3) run_remote "$OVHROOT_RAW_URL"; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== fail2ban
f2b_install() {
  local ports backend banaction maxretry bantime findtime ignore cip i logpath=""
  ensure_epel
  if ! has fail2ban-client; then
    info "安装 fail2ban"
    pkg_install fail2ban >/dev/null 2>&1 || { err "fail2ban 安装失败"; return 1; }
  fi
  ssh_privsep_dir
  ports=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | paste -sd, -)
  [[ -z $ports ]] && ports=ssh
  if [[ -f /var/log/auth.log || -f /var/log/secure ]]; then
    backend=auto
  elif has journalctl; then
    backend=systemd
    if [[ $(pkg_mgr) == apt-get ]]; then pkg_install python3-systemd >/dev/null 2>&1; fi
  else
    backend=auto; logpath=/var/log/messages
  fi
  if has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then banaction=firewallcmd-rich-rules
  elif has ufw && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then banaction=ufw
  elif has iptables; then banaction=iptables-multiport
  else banaction=nftables-multiport
  fi
  # sudo -i / su - 会清掉 SSH_CLIENT，再从 SSH_CONNECTION 和 who 里找当前登录 IP
  cip=$(awk '{print $1}' <<<"${SSH_CLIENT:-${SSH_CONNECTION:-}}")
  if [[ -z $cip ]]; then cip=$(who -m 2>/dev/null | sed -n 's/.*(\([0-9A-Fa-f.:]*\)).*/\1/p' | head -n 1); fi
  is_ip "$cip" || cip=""
  if [[ -z $cip ]]; then warn "未能识别你当前的登录 IP，请把它手动加入白名单，避免输错密码时把自己封禁"; fi
  ask maxretry "失败多少次封禁" "5" || return 1
  ask findtime "统计时间窗口（如 10m）" "10m" || return 1
  ask bantime "封禁时长（如 1h / 1d / 365d，-1 永久）" "1d" || return 1
  ask ignore "白名单 IP/网段（空格分隔，默认含当前登录 IP）" "127.0.0.1/8 ::1${cip:+ $cip}" || return 1
  is_uint "$maxretry" || maxretry=5
  [[ $findtime =~ ^[0-9]+[smhdw]?$ ]] || findtime=10m
  [[ $bantime =~ ^(-1|[0-9]+[smhdw]?)$ ]] || bantime=1d
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/zz-nx-sshd.local <<EOF
# 由 NX 工具箱生成
[sshd]
enabled   = true
port      = $ports
backend   = $backend${logpath:+
logpath   = $logpath}
banaction = $banaction
maxretry  = $maxretry
findtime  = $findtime
bantime   = $bantime
ignoreip  = $ignore
EOF
  if has systemctl; then systemctl enable fail2ban >/dev/null 2>&1; systemctl restart fail2ban; else rc-update add fail2ban default >/dev/null 2>&1; rc-service fail2ban restart; fi
  for i in 1 2 3 4 5 6 7 8 9 10; do fail2ban-client status sshd >/dev/null 2>&1 && break; sleep 1; done
  if fail2ban-client status sshd >/dev/null 2>&1; then
    ok "fail2ban 已启用：端口 $ports，$findtime 内失败 $maxretry 次封禁 $bantime（$banaction / $backend）"
  else
    err "fail2ban 启动异常："
    fail2ban-client -t 2>&1 | tail -n 5
    return 1
  fi
}

menu_f2b() {
  local c ip
  while :; do
    title "fail2ban SSH 防爆破"
    if has fail2ban-client && fail2ban-client status sshd >/dev/null 2>&1; then
      fail2ban-client status sshd | sed 's/^/  /'
    else
      row "状态" "未安装或未运行"
    fi
    hr
    item2 1 "安装 / 重新配置" 2 "解封 IP"
    item2 3 "手动封禁 IP" 4 "查看日志"
    item2 5 "卸载 fail2ban" "" ""
    item 0 "返回"
    read_choice c
    case $c in
      1) f2b_install; pause ;;
      2) ask ip "要解封的 IP（all 为全部）" "" && { if [[ $ip == all ]]; then fail2ban-client unban --all; elif is_ip "$ip"; then fail2ban-client set sshd unbanip "$ip"; fi; }; pause ;;
      3) ask ip "要封禁的 IP" "" && is_ip "$ip" && fail2ban-client set sshd banip "$ip"; pause ;;
      4) tail -n 40 /var/log/fail2ban.log 2>/dev/null || journalctl -u fail2ban -n 40 --no-pager; pause ;;
      5)
        confirm "卸载 fail2ban?" N || continue
        systemctl disable --now fail2ban >/dev/null 2>&1
        pkg_remove fail2ban >/dev/null 2>&1
        rm -f /etc/fail2ban/jail.d/zz-nx-sshd.local
        ok "已卸载"; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== Swap / 时区 / 主机名 / DNS / 优先级
swap_set() {
  local mb=$1 v fstype avail
  is_uint "$mb" || { err "大小无效"; return 1; }
  v=$(virt_type)
  if [[ $v == openvz || $v == lxc ]]; then err "$v 虚拟化不支持自建 swap"; return 1; fi
  if grep -q '^/swapfile ' /proc/swaps; then swapoff /swapfile || { err "关闭旧 swap 失败（内存不足?）"; return 1; }; fi
  rm -f /swapfile
  sed -i '\#^/swapfile[[:space:]]#d' /etc/fstab
  if [[ $mb -eq 0 ]]; then ok "已删除 /swapfile"; return 0; fi
  avail=$(df -m / | awk 'NR == 2 {print $4}')
  if (( avail < mb + 200 )); then err "磁盘剩余 ${avail}MB，不足以创建 ${mb}MB swap"; return 1; fi
  fstype=$(df -T / | awk 'NR == 2 {print $2}')
  if [[ $fstype == btrfs ]]; then
    if ! btrfs filesystem mkswapfile --size "${mb}m" /swapfile >/dev/null 2>&1; then
      truncate -s 0 /swapfile; chattr +C /swapfile 2>/dev/null
      dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
    fi
  else
    fallocate -l "${mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
  fi
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null 2>&1
  if ! swapon /swapfile 2>/dev/null; then
    rm -f /swapfile
    dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile || { rm -f /swapfile; err "启用 swap 失败"; return 1; }
  fi
  grep -qE '^/swapfile[[:space:]]' /etc/fstab || append_line /etc/fstab "/swapfile none swap sw 0 0"
  if [[ -f /etc/alpine-release ]]; then rc-update add swap boot >/dev/null 2>&1; fi
  ok "Swap 已设置为 ${mb}MB"
}

menu_swap() {
  local v
  title "虚拟内存 Swap"
  free -m | sed 's/^/  /'
  hr
  echo "  常用: 512 / 1024 / 2048；输入 0 删除 /swapfile"
  ask v "Swap 大小（MB）" "1024" || return
  swap_set "$v"
  pause
}

tz_set() {
  local z=$1
  [[ $z =~ ^[A-Za-z0-9_+/-]+$ ]] || { err "时区格式不对: $z"; return 1; }
  [[ -f /usr/share/zoneinfo/UTC ]] || { info "安装时区数据 tzdata..."; pkg_install tzdata >/dev/null 2>&1; }
  [[ -f /usr/share/zoneinfo/$z ]] || { err "时区不存在: $z"; return 1; }
  if has timedatectl && timedatectl set-timezone "$z" 2>/dev/null; then :; else
    ln -sf "/usr/share/zoneinfo/$z" /etc/localtime
    echo "$z" > /etc/timezone
  fi
  ok "时区已设置为 $z，当前时间 $(date '+%F %T')"
}

menu_tz() {
  local c z
  title "系统时区"
  row "当前" "$(timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime)  $(date '+%F %T')"
  hr
  item2 1 "Asia/Shanghai 上海" 2 "Asia/Hong_Kong 香港"
  item2 3 "Asia/Tokyo 东京" 4 "Asia/Singapore 新加坡"
  item2 5 "America/Los_Angeles 洛杉矶" 6 "Europe/London 伦敦"
  item2 7 "UTC" 8 "自定义"
  item 0 "返回"
  read_choice c
  case $c in
    1) z=Asia/Shanghai ;; 2) z=Asia/Hong_Kong ;; 3) z=Asia/Tokyo ;; 4) z=Asia/Singapore ;;
    5) z=America/Los_Angeles ;; 6) z=Europe/London ;; 7) z=UTC ;;
    8) ask z "时区名（如 Europe/Berlin）" "" || return ;;
    *) return ;;
  esac
  if [[ $z =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$ ]]; then tz_set "$z"; else err "时区名无效: $z"; fi
  pause
}

hostname_set() {
  local n=$1 old
  [[ $n =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || { err "主机名无效（字母数字和-，最长 63）"; return 1; }
  old=$(hostname)
  # 容器里 systemd-hostnamed 可能起不来，hostnamectl 会卡满 D-Bus 超时（25 秒）才失败
  if has hostnamectl && timeout 10 hostnamectl set-hostname "$n" 2>/dev/null; then :; else echo "$n" > /etc/hostname; hostname "$n"; fi
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $n/" /etc/hosts
  else
    append_line /etc/hosts "127.0.1.1 $n"
  fi
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-nx-hostname.cfg; fi
  ok "主机名已从 $old 改为 $n（重新登录后提示符更新）"
}

dns_set() { # dns_set "v4 v4" "v6 v6"
  local v4=$1 v6=$2 all ip
  all="$v4"
  if [[ -n $v6 ]] && [[ -n $(ip -6 route show default 2>/dev/null) ]]; then all+=" $v6"; fi
  if has systemctl && systemctl is-active --quiet systemd-resolved 2>/dev/null && [[ -L /etc/resolv.conf ]]; then
    mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=%s\nDomains=~.\n' "$all" > /etc/systemd/resolved.conf.d/99-nx-dns.conf
    systemctl restart systemd-resolved
  else
    chattr -i /etc/resolv.conf 2>/dev/null
    [[ -f /etc/resolv.conf.nx-orig || ! -f /etc/resolv.conf ]] || cp -aL /etc/resolv.conf /etc/resolv.conf.nx-orig
    rm -f /etc/resolv.conf
    { for ip in $all; do echo "nameserver $ip"; done; echo "options timeout:2 attempts:2 rotate"; } > /etc/resolv.conf
  fi
  ok "DNS 已设置为: $all"
  if has NetworkManager && systemctl is-active --quiet NetworkManager 2>/dev/null; then warn "NetworkManager 可能会覆盖 resolv.conf，如被还原请在 NM 连接中设置 DNS"; fi
}

menu_dns() {
  local c a b
  title "优化 DNS"
  row "当前" "$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  hr
  item 1 "海外：1.1.1.1 8.8.8.8（+ IPv6 2606:4700:4700::1111 2001:4860:4860::8888）"
  item 2 "国内：223.5.5.5 119.29.29.29（+ IPv6 2400:3200::1 2402:4e00::）"
  item 3 "自定义"
  item 4 "还原（使用备份的原 resolv.conf）"
  item 0 "返回"
  read_choice c
  case $c in
    1) dns_set "1.1.1.1 8.8.8.8" "2606:4700:4700::1111 2001:4860:4860::8888" ;;
    2) dns_set "223.5.5.5 119.29.29.29" "2400:3200::1 2402:4e00::" ;;
    3)
      ask a "DNS 地址（空格分隔）" "" || return
      for b in $a; do is_ip "$b" || { err "无效地址: $b"; pause; return; }; done
      [[ -n $a ]] && dns_set "$a" "" ;;
    4)
      rm -f /etc/systemd/resolved.conf.d/99-nx-dns.conf
      if [[ -f /etc/resolv.conf.nx-orig ]]; then cat /etc/resolv.conf.nx-orig > /etc/resolv.conf; fi
      systemctl restart systemd-resolved >/dev/null 2>&1
      ok "已还原" ;;
    *) return ;;
  esac
  pause
}

is_musl() { compgen -G '/lib/ld-musl-*.so.1' >/dev/null; }

ip_priority() { # v4|v6
  if is_musl; then
    warn "musl 系统（如 Alpine）不读 /etc/gai.conf，无法全局设置 IPv4/IPv6 优先；可在程序里用 -4 / -6 指定"
    return 1
  fi
  touch /etc/gai.conf
  sed -i '/^precedence ::ffff:0:0\/96/d' /etc/gai.conf
  if [[ $1 == v4 ]]; then echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf; fi
  ok "已设置为 $([[ $1 == v4 ]] && echo IPv4 || echo IPv6) 优先"
  info "检测出口: $(curl -fsS --max-time 5 https://ip.sb 2>/dev/null || echo 获取失败)"
}

menu_priority() {
  local c cur=IPv6
  grep -q '^precedence ::ffff:0:0/96' /etc/gai.conf 2>/dev/null && cur=IPv4
  title "IPv4 / IPv6 优先级"
  row "当前" "$cur 优先"
  hr
  item 1 "IPv4 优先"
  item 2 "IPv6 优先（系统默认）"
  item 0 "返回"
  read_choice c
  case $c in 1) ip_priority v4; pause ;; 2) ip_priority v6; pause ;; esac
}

# ================================================================== 端口 / 防火墙
show_ports() {
  printf '  %s%s %s %s%s\n' "$C_BLD" "$(pad 协议 6)" "$(pad 监听地址 28)" "进程" "$C_RST"
  ssq -tulnp | awk '{
    proc = "-"
    if (match($0, /users:\(\("[^"]+"/)) proc = substr($0, RSTART + 9, RLENGTH - 10)
    n = split($5, a, ":")
    printf "%s\t%s\t%s\t%s\n", a[n], $1, $5, proc
  }' | sort -t "$(printf '\t')" -k1,1n -k2,2 | uniq | awk -F '\t' '{printf "  %-6s %-28s %s\n", $2, $3, $4}'
}

firewall_open_all() {
  local t num
  has ufw && ufw disable >/dev/null 2>&1
  if has firewall-cmd; then systemctl disable --now firewalld >/dev/null 2>&1; fi
  for t in iptables ip6tables; do
    has "$t" || continue
    "$t" -P INPUT ACCEPT 2>/dev/null
    "$t" -P FORWARD ACCEPT 2>/dev/null
    "$t" -P OUTPUT ACCEPT 2>/dev/null
    for num in $("$t" -L INPUT --line-numbers -n 2>/dev/null | awk '$2 == "DROP" || $2 == "REJECT" {print $1}' | sort -rn); do
      "$t" -D INPUT "$num" 2>/dev/null
    done
  done
  fw_persist
  ok "已关闭防火墙拦截（ufw/firewalld 停用，iptables INPUT 拦截规则已删除；Docker 等转发规则保留）"
  warn "云服务器仍需在控制台安全组放行端口"
}

menu_firewall() {
  local c p proto
  while :; do
    title "防火墙管理"
    row "当前防火墙" "$(fw_backend)"
    hr
    item2 1 "放行端口" 2 "关闭端口"
    item2 3 "查看规则" 4 "查看端口占用"
    item2 5 "开放所有端口（停用防火墙）" "" ""
    item 0 "返回"
    read_choice c
    case $c in
      1|2)
        ask p "端口（如 443 或 10000:10100）" "" || continue
        [[ $p =~ ^[0-9]{1,5}(:[0-9]{1,5})?$ ]] || { err "端口无效"; pause; continue; }
        ask proto "协议 tcp/udp/both" "both" || continue
        [[ $proto =~ ^(tcp|udp|both)$ ]] || proto=both
        if [[ $(fw_backend) == none ]]; then info "本机未启用防火墙，无需操作（云安全组需另外放行）"
        elif [[ $c == 1 ]]; then fw_open "$p" "$proto"
        else fw_close "$p" "$proto"; fi
        pause ;;
      3)
        case $(fw_backend) in
          ufw) ufw status numbered ;;
          firewalld) firewall-cmd --list-all ;;
          *) iptables -S 2>/dev/null | head -n 60; nft list ruleset 2>/dev/null | head -n 40 ;;
        esac
        pause ;;
      4) show_ports; pause ;;
      5) confirm "确认放行全部端口?" N && firewall_open_all; pause ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== 定时任务
menu_cron() {
  local c s cmd n tmp
  while :; do
    title "定时任务（root crontab）"
    crontab -l 2>/dev/null | grep -v '^#' | grep -v '^\s*$' | awk '{print "  " NR ") " $0}'
    hr
    item2 1 "添加任务" 2 "删除任务"
    item2 3 "编辑（crontab -e）" "" ""
    item 0 "返回"
    read_choice c
    case $c in
      1)
        echo "  时间格式：分 时 日 月 周，例如 0 4 * * *（每天 4 点）、*/5 * * * *（每 5 分钟）、@reboot"
        ask s "执行时间" "0 4 * * *" || continue
        ask cmd "命令" "" || continue
        [[ -n $cmd ]] || continue
        (crontab -l 2>/dev/null; echo "$s $cmd") | crontab - && ok "已添加"
        pause ;;
      2)
        ask n "删除第几条" "" || continue
        is_uint "$n" || continue
        tmp=$(mktemp)
        crontab -l 2>/dev/null | grep -v '^#' | grep -v '^\s*$' | awk -v n="$n" 'NR != n' > "$tmp"
        crontab "$tmp" && ok "已删除"
        rm -f "$tmp"; pause ;;
      3) crontab -e ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== 换源 / 重装 / 用户
menu_mirror() {
  local c
  title "切换系统软件源（LinuxMirrors）"
  item 1 "国内镜像源（阿里/腾讯/清华等，交互选择）"
  item 2 "海外官方/镜像源"
  item 3 "教育网镜像源"
  item 0 "返回"
  read_choice c
  case $c in
    1) run_cmd 'bash <(curl -sSL https://linuxmirrors.cn/main.sh)' ;;
    2) run_cmd 'bash <(curl -sSL https://linuxmirrors.cn/main.sh) --abroad' ;;
    3) run_cmd 'bash <(curl -sSL https://linuxmirrors.cn/main.sh) --edu' ;;
    *) return ;;
  esac
  pause
}

menu_dd() {
  local c os ver tmp url
  local -a dd_args=()
  title "一键 DD 重装系统（bin456789/reinstall）"
  warn "重装会清空整块硬盘的全部数据！请先备份。部分虚拟化（OpenVZ/LXC）不支持"
  hr
  item2 1 "Debian 12" 2 "Debian 13"
  item2 3 "Ubuntu 22.04" 4 "Ubuntu 24.04"
  item2 5 "Rocky Linux 9" 6 "AlmaLinux 9"
  item2 7 "Alpine Linux" 8 "自定义参数"
  item 0 "返回"
  read_choice c
  case $c in
    1) os=debian; ver=12 ;; 2) os=debian; ver=13 ;; 3) os=ubuntu; ver=22.04 ;; 4) os=ubuntu; ver=24.04 ;;
    5) os=rocky; ver=9 ;; 6) os=almalinux; ver=9 ;; 7) os=alpine; ver="" ;;
    8) ask os "reinstall.sh 参数（如 debian 12 或 windows --image-name '...' ）" "" || return; ver="" ;;
    *) return ;;
  esac
  [[ -n $os ]] || return
  if [[ -n $ver ]]; then
    dd_args=("$os" "$ver")
  else
    # 自定义参数允许用引号，但不接受命令替换、管道、重定向等 shell 语法
    if [[ $os == *[\$\`\;\|\&\<\>]* ]]; then err "参数不能包含 \$ \` ; | & < >"; pause; return; fi
    eval "dd_args=($os)" 2>/dev/null || { err "参数格式无效（引号未配对?）"; pause; return; }
  fi
  [[ $(virt_type) =~ ^(openvz|lxc)$ ]] && { err "容器虚拟化无法 DD"; pause; return; }
  confirm "确认重装为 $os $ver?" N || return
  confirm "再次确认：硬盘数据将全部丢失?" N || return
  tmp=/root/reinstall.sh
  url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  if in_china; then url="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"; fi
  if ! dl "$url" "$tmp" 60 && ! gh_dl "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh" "$tmp" 60; then
    err "下载 reinstall.sh 失败"; pause; return
  fi
  if bash "$tmp" "${dd_args[@]}"; then
    ok "准备完成，重启后开始重装（按脚本提示的账号密码登录）"
    confirm "立即重启?" Y && reboot
  else
    err "reinstall.sh 执行失败"
  fi
  pause
}

user_add() {
  local n pw sudo_grp
  ask n "新用户名" "" || return 1
  [[ $n =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { err "用户名无效"; return 1; }
  id "$n" >/dev/null 2>&1 && { err "用户已存在"; return 1; }
  useradd -m -s /bin/bash "$n" 2>/dev/null || adduser -D -s /bin/sh "$n" || { err "创建失败"; return 1; }
  ask_secret pw "设置密码（回车随机生成）"
  [[ -z $pw ]] && pw=$(rand_pass 16)
  echo "$n:$pw" | chpasswd
  if getent group sudo >/dev/null; then sudo_grp=sudo; else sudo_grp=wheel; fi
  has sudo || pkg_install sudo >/dev/null 2>&1
  usermod -aG "$sudo_grp" "$n" 2>/dev/null || addgroup "$n" "$sudo_grp" 2>/dev/null
  # Arch/Alpine 默认注释掉了 %wheel，单独写一条授权才保证能 sudo
  mkdir -p /etc/sudoers.d
  if confirm_opt "允许 $n 免密码 sudo?" N; then
    echo "$n ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/90-nx-$n"
  else
    echo "$n ALL=(ALL) ALL" > "/etc/sudoers.d/90-nx-$n"
  fi
  chmod 440 "/etc/sudoers.d/90-nx-$n"
  if has visudo && ! visudo -cf "/etc/sudoers.d/90-nx-$n" >/dev/null 2>&1; then
    rm -f "/etc/sudoers.d/90-nx-$n"; warn "sudo 授权文件校验失败，已撤销，请手动配置"
  fi
  if [[ -s /root/.ssh/authorized_keys ]] && confirm "复制 root 的公钥给 $n?" Y; then
    mkdir -p "/home/$n/.ssh"
    cp /root/.ssh/authorized_keys "/home/$n/.ssh/"
    chown -R "$n:$n" "/home/$n/.ssh"
    chmod 700 "/home/$n/.ssh"; chmod 600 "/home/$n/.ssh/authorized_keys"
  fi
  ok "用户 $n 已创建（$sudo_grp 组），密码：$pw"
}

menu_system() {
  local c v
  while :; do
    title "系统工具"
    item2 1 "修改 root 密码" 2 "修改 SSH 端口"
    item2 3 "SSH 密钥登录管理" 4 "SSH 密码登录 开/关"
    item2 5 "虚拟内存 Swap" 6 "系统时区"
    item2 7 "修改主机名" 8 "优化 DNS"
    item2 9 "IPv4/IPv6 优先级" 10 "端口占用查看"
    item2 11 "防火墙管理" 12 "fail2ban 防爆破"
    item2 13 "定时任务" 14 "切换软件源"
    item2 15 "一键 DD 重装系统" 16 "新建 sudo 用户"
    item2 17 "设置工具箱快捷命令" 18 "重启服务器"
    item 0 "返回"
    read_choice c
    case $c in
      1) passwd root; pause ;;
      2)
        ssh_privsep_dir
        printf '  当前 SSH 端口: %s\n' "$(sshd -T 2>/dev/null | awk '$1 == "port" {printf "%s ", $2}')"
        ask v "新端口（建议 10000-60000）" "" && [[ -n $v ]] && ssh_change_port "$v"
        pause ;;
      3) menu_sshkey ;;
      4)
        printf '  当前密码登录: %s\n' "$(sshd_effective PasswordAuthentication)"
        ask v "on 开启 / off 关闭" "" || continue
        case $v in on|off) ssh_password_login "$v" ;; esac
        pause ;;
      5) menu_swap ;;
      6) menu_tz ;;
      7) ask v "新主机名" "" && [[ -n $v ]] && hostname_set "$v"; pause ;;
      8) menu_dns ;;
      9) menu_priority ;;
      10) show_ports; pause ;;
      11) menu_firewall ;;
      12) menu_f2b ;;
      13) menu_cron ;;
      14) menu_mirror ;;
      15) menu_dd ;;
      16) user_add; pause ;;
      17)
        ask v "快捷命令名（字母数字）" "nx" || continue
        if [[ $v =~ ^[A-Za-z][A-Za-z0-9_-]{0,15}$ ]] && [[ $v == nx || ! -e /usr/local/bin/$v ]]; then
          [[ $v == nx ]] || ln -sf "$NX_BIN" "/usr/local/bin/$v"
          ok "之后输入 $v 即可打开工具箱"
        else
          err "名称无效或与已有命令冲突"
        fi
        pause ;;
      18) confirm "确认立即重启服务器?" N && reboot ;;
      0|"") return ;;
    esac
  done
}

# ================================================================== LXC 切小鸡（Incus，兼容 LXD）
LXC_CONF="$NX_DIR/lxc.conf"
LXC_INFO_DIR="/root/nx-lxc"
LXC_BRIDGE="incusbr0"
IC=""
LXC_KEYS=(IMAGE_REMOTE IMAGE CPU CPU_CAP MEM SWAP DISK NET IO PROCS SSH_START PORTS NESTING AUTOSTART)

lxc_defaults() {
  L_IMAGE_REMOTE="images"; L_IMAGE="debian/12"; L_CPU="1"; L_CPU_CAP="100"; L_MEM="512"; L_SWAP="256"
  L_DISK="10"; L_NET="100"; L_IO="0"; L_PROCS="512"; L_SSH_START="20000"; L_PORTS="20"; L_NESTING="1"; L_AUTOSTART="1"
}

lxc_load_conf() {
  local k v
  lxc_defaults
  [[ -f $LXC_CONF ]] || return 0
  while IFS='=' read -r k v || [[ -n $k ]]; do
    case " ${LXC_KEYS[*]} " in *" $k "*) printf -v "L_$k" '%s' "$v" ;; esac
  done < "$LXC_CONF"
}

lxc_save_conf() {
  local k var
  mkdir -p "$NX_DIR"
  { for k in "${LXC_KEYS[@]}"; do var="L_$k"; printf '%s=%s\n' "$k" "${!var}"; done; } > "$LXC_CONF"
}

# 只用 socket 判断 LXD：Ubuntu 云镜像的 lxd-installer 会在首次调用 lxc 时自动安装 LXD snap
lxc_detect() {
  if has incus; then IC=incus; LXC_BRIDGE="incusbr0"; return 0; fi
  if has lxc && [[ -S /var/snap/lxd/common/lxd/unix.socket || -S /var/lib/lxd/unix.socket ]]; then
    IC=lxc; LXC_BRIDGE="lxdbr0"; return 0
  fi
  IC=""
  return 1
}

lxc_need() {
  lxc_detect || { err "未安装 Incus，请先执行「环境安装」（nx lxc install）"; return 1; }
  has jq || ensure_cmd jq jq || { err "需要 jq"; return 1; }
  if ! $IC storage list --format csv 2>/dev/null | grep -q .; then err "Incus 尚未初始化，请执行 nx lxc init"; return 1; fi
  lxc_load_conf
}

lxc_exists() { $IC info "$1" >/dev/null 2>&1; }
lxc_name_ok() { [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9-]{0,62}$ && $1 != *- ]]; }

lxc_remote() {
  if [[ $L_IMAGE_REMOTE == tuna ]]; then
    if ! $IC remote list --format csv 2>/dev/null | grep -q '^tuna'; then
      $IC remote add tuna https://mirrors.tuna.tsinghua.edu.cn/lxc-images/ --protocol=simplestreams --public >/dev/null 2>&1
    fi
    echo tuna
  else
    echo images
  fi
}

# 统一的数值解析：to_mb 512 / 512M / 1G / 1.5G → MB；to_gb 10 / 10G / 512M → GB
to_mb() {
  local v=${1^^}
  if [[ $v =~ ^([0-9]+(\.[0-9]+)?)(M|MB|MIB)?$ ]]; then awk -v x="${BASH_REMATCH[1]}" 'BEGIN { printf "%d", x + 0.5 }'
  elif [[ $v =~ ^([0-9]+(\.[0-9]+)?)(G|GB|GIB)$ ]]; then awk -v x="${BASH_REMATCH[1]}" 'BEGIN { printf "%d", x * 1024 + 0.5 }'
  else return 1; fi
}
to_gb() {
  local v=${1^^}
  if [[ $v =~ ^([0-9]+(\.[0-9]+)?)(G|GB|GIB)?$ ]]; then awk -v x="${BASH_REMATCH[1]}" 'BEGIN { printf "%d", x + 0.5 }'
  elif [[ $v =~ ^([0-9]+)(M|MB|MIB)$ ]]; then awk -v x="${BASH_REMATCH[1]}" 'BEGIN { y = int(x / 1024 + 0.5); if (y < 1) y = 1; printf "%d", y }'
  else return 1; fi
}

cgroup_v2() { [[ $(stat -fc %T /sys/fs/cgroup 2>/dev/null) == cgroup2fs ]]; }

# ------------------------------------------------------------------ 安装 / 初始化
LXC_OPT_STORAGE=""; LXC_OPT_SIZE=""; LXC_OPT_SUBNET=""; LXC_OPT_MIRROR=""; LXC_OPT_REPO=""

lxc_parse_install_opts() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --storage) LXC_OPT_STORAGE=${2:-} ;;
      --size) LXC_OPT_SIZE=${2:-} ;;
      --subnet) LXC_OPT_SUBNET=${2:-} ;;
      --mirror) LXC_OPT_MIRROR=${2:-} ;;
      --repo) LXC_OPT_REPO=${2:-} ;;
      -y|--yes) ASSUME_YES=1; shift; continue ;;
      *) err "未知参数: $1"; return 2 ;;
    esac
    shift
    [[ $# -gt 0 ]] && shift
  done
  case $LXC_OPT_STORAGE in ""|btrfs|lvm|zfs|dir) ;; *) err "--storage 只能是 btrfs/lvm/zfs/dir"; return 2 ;; esac
  case $LXC_OPT_MIRROR in ""|images|tuna) ;; *) err "--mirror 只能是 images/tuna"; return 2 ;; esac
  case $LXC_OPT_REPO in ""|zabbly|distro) ;; *) err "--repo 只能是 zabbly/distro"; return 2 ;; esac
  if [[ -n $LXC_OPT_SIZE ]] && ! is_uint "$LXC_OPT_SIZE"; then err "--size 应为 GB 数字"; return 2; fi
  return 0
}

# 只开容器用 incus-base 就够：incus 包会拖入虚拟机组件（约 300 个包）。老仓库没有 incus-base 时装 incus
incus_apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" incus-base \
    || DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" incus
}

lxc_install() {
  local v zabbly=0 repo_ok=0 arch
  v=$(virt_type)
  case $v in
    openvz) err "OpenVZ 不支持运行容器，无法开小鸡"; return 1 ;;
    lxc) warn "当前机器本身是 LXC 容器，需要宿主机开启 nesting 才能运行 Incus" ;;
  esac
  if lxc_detect; then
    ok "已安装 $IC（$($IC version 2>/dev/null | awk -F': ' '/Server/ {print $2}')）"
  else
    case $(pkg_mgr) in
      apt-get)
        apt-get update -y >/dev/null 2>&1; APT_UPDATED=1
        pkg_install curl ca-certificates gnupg jq btrfs-progs lvm2 thin-provisioning-tools >/dev/null 2>&1
        arch=$(dpkg --print-architecture)
        case "$OS_ID:$OS_CODENAME:$arch" in
          debian:bookworm:amd64|debian:bookworm:arm64|debian:trixie:amd64|debian:trixie:arm64|\
          ubuntu:jammy:amd64|ubuntu:jammy:arm64|ubuntu:noble:amd64|ubuntu:noble:arm64|ubuntu:resolute:amd64|ubuntu:resolute:arm64)
            zabbly=1 ;;
        esac
        if [[ $LXC_OPT_REPO == distro ]]; then zabbly=0; fi
        if [[ $zabbly == 1 ]] && { [[ $LXC_OPT_REPO == zabbly ]] || confirm "使用 Incus 官方 Zabbly 源安装最新稳定版?（否则用系统仓库版本）" Y; }; then
          mkdir -p /etc/apt/keyrings
          if dl https://pkgs.zabbly.com/key.asc /etc/apt/keyrings/zabbly.asc 30; then
            ensure_cmd gpg gnupg >/dev/null 2>&1
            if ! gpg --show-keys --fingerprint /etc/apt/keyrings/zabbly.asc 2>/dev/null | tr -d ' ' | grep -q 4EFC590696CB15B87C73A3AD82CC8797C838DCFD; then
              err "Zabbly 密钥指纹校验失败，改用系统仓库"
              rm -f /etc/apt/keyrings/zabbly.asc
            else
              cat > /etc/apt/sources.list.d/zabbly-incus-stable.sources <<EOF
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: $OS_CODENAME
Components: main
Architectures: $arch
Signed-By: /etc/apt/keyrings/zabbly.asc
EOF
              info "从 Zabbly 源安装 Incus"
              if apt-get update >/dev/null 2>&1 && incus_apt_install; then repo_ok=1; else rm -f /etc/apt/sources.list.d/zabbly-incus-stable.sources; fi
            fi
          fi
        fi
        if [[ $repo_ok != 1 ]]; then
          info "从系统仓库安装 Incus"
          if [[ $OS_ID == debian && $OS_CODENAME == bookworm ]]; then
            echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/nx-bookworm-backports.list
            apt-get update >/dev/null 2>&1
            incus_apt_install -t bookworm-backports && repo_ok=1
          else
            incus_apt_install && repo_ok=1
          fi
        fi ;;
      dnf|yum) ensure_epel; pkg_install incus incus-tools jq && repo_ok=1 ;;
      apk) apk add --no-cache incus incus-client lxcfs jq && rc-update add incusd default && rc-service incusd start && repo_ok=1 ;;
      pacman) pacman -Sy --noconfirm --needed incus jq && systemctl enable --now incus.socket && repo_ok=1 ;;
      *) err "暂不支持该系统自动安装 Incus（推荐 Debian 12/13、Ubuntu 22.04/24.04）"; return 1 ;;
    esac
    lxc_detect || { err "Incus 安装失败"; return 1; }
    ok "Incus 安装完成：$($IC version 2>/dev/null | awk -F': ' '/Server/ {print $2}')"
  fi
  has jq || ensure_cmd jq jq
  lxc_init
}

lxc_init() {
  local c driver size subnet free_gb def_size preseed
  lxc_detect || { err "未安装 Incus"; return 1; }
  lxc_load_conf
  if $IC storage list --format csv 2>/dev/null | grep -q .; then
    ok "Incus 已初始化（存储池: $($IC storage list --format csv | cut -d, -f1,2 | tr '\n' ' ')）"
    lxc_docker_fix
    return 0
  fi
  title "初始化 Incus"
  case $LXC_OPT_STORAGE in
    lvm) c=1 ;; btrfs) c=2 ;; zfs) c=3 ;; dir) c=4 ;;
    *)
      echo "  存储驱动决定能否限制每台小鸡的硬盘大小（均使用回环文件，无需单独分区）："
      echo "    1) lvm  （推荐：每台小鸡独立卷，小鸡内 df 显示的就是分配的大小，配额最严格）"
      echo "    2) btrfs（配额同样生效，但小鸡内 df 显示的是整个存储池大小）"
      echo "    3) zfs  （需已安装 zfsutils）"
      echo "    4) dir  （最简单，但无法限制硬盘大小）"
      ask c "选择存储驱动" "1" || return 1 ;;
  esac
  case $c in
    2) driver=btrfs; ensure_cmd mkfs.btrfs btrfs-progs || { err "需要 btrfs-progs"; return 1; } ;;
    3) driver=zfs; has zfs || { err "未安装 zfs"; return 1; } ;;
    4) driver=dir ;;
    *)
      driver=lvm
      ensure_cmd lvcreate lvm2 || { err "需要 lvm2"; return 1; }
      case $(pkg_mgr) in
        apt-get) ensure_cmd thin_check thin-provisioning-tools ;;
        dnf|yum) ensure_cmd thin_check device-mapper-persistent-data ;;
        apk) ensure_cmd thin_check thin-provisioning-tools ;;
      esac || warn "未找到 thin_check，LVM thin 池可能无法创建"
      ;;
  esac
  free_gb=$(df -BG / | awk 'NR == 2 {gsub("G", "", $4); print $4}')
  def_size=$(( free_gb * 80 / 100 ))
  (( def_size < 5 )) && def_size=5
  if [[ $driver != dir ]]; then
    size=$LXC_OPT_SIZE
    if [[ -z $size ]]; then ask size "存储池大小 GB（系统盘剩余 ${free_gb}GB）" "$def_size" || return 1; fi
    is_uint "$size" && (( size >= 2 )) || { err "大小无效"; return 1; }
  fi
  subnet=$LXC_OPT_SUBNET
  if [[ -z $subnet ]]; then ask subnet "小鸡内网网段（auto 自动选择，或如 10.66.0.1/24）" "auto" || return 1; fi
  [[ $subnet == auto || $subnet =~ ^[0-9]+\.[0-9]+\.[0-9]+\.1/24$ ]] || { err "网段格式应为 x.x.x.1/24"; return 1; }
  if [[ -n $LXC_OPT_MIRROR ]]; then
    L_IMAGE_REMOTE=$LXC_OPT_MIRROR
  else
    echo "  镜像源：1) 官方 images.linuxcontainers.org   2) 清华 TUNA 镜像（国内机器推荐）"
    ask c "选择镜像源" "$([[ $L_IMAGE_REMOTE == tuna ]] && echo 2 || echo 1)" || return 1
    if [[ $c == 2 ]]; then L_IMAGE_REMOTE=tuna; else L_IMAGE_REMOTE=images; fi
  fi
  lxc_save_conf
  preseed=$(mktemp)
  {
    echo "config: {}"
    echo "networks:"
    echo "- name: $LXC_BRIDGE"
    echo "  type: bridge"
    echo "  config:"
    echo "    ipv4.address: $subnet"
    echo "    ipv4.nat: \"true\""
    echo "    ipv6.address: none"
    echo "storage_pools:"
    echo "- name: default"
    echo "  driver: $driver"
    if [[ $driver != dir ]]; then echo "  config:"; echo "    size: ${size}GiB"; fi
    echo "profiles:"
    echo "- name: default"
    echo "  devices:"
    echo "    eth0: {name: eth0, network: $LXC_BRIDGE, type: nic}"
    echo "    root: {path: /, pool: default, type: disk}"
  } > "$preseed"
  info "初始化中（$driver ${size:+${size}GB}）..."
  if [[ $IC == incus ]]; then incus admin init --preseed < "$preseed"; else lxd init --preseed < "$preseed"; fi || {
    rm -f "$preseed"; err "初始化失败"; return 1
  }
  rm -f "$preseed"
  lxc_remote >/dev/null
  lxc_docker_fix
  ok "初始化完成：存储 $driver，内网 $($IC network get "$LXC_BRIDGE" ipv4.address)，镜像源 $L_IMAGE_REMOTE"
}

# 宿主防火墙会挡住网桥上的 DHCP/DNS 和小鸡出网（ufw/firewalld 默认拒绝，Docker 把 FORWARD 设为 DROP）
lxc_docker_fix() {
  if has ufw && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow in on "$LXC_BRIDGE" >/dev/null 2>&1
    ufw route allow in on "$LXC_BRIDGE" >/dev/null 2>&1
    ufw route allow out on "$LXC_BRIDGE" >/dev/null 2>&1
  fi
  if has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --zone=trusted --change-interface="$LXC_BRIDGE" >/dev/null 2>&1
    firewall-cmd --permanent --zone=trusted --add-interface="$LXC_BRIDGE" >/dev/null 2>&1
  fi
  has iptables || return 0
  iptables -S DOCKER-USER >/dev/null 2>&1 || return 0
  iptables -C DOCKER-USER -i "$LXC_BRIDGE" -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -i "$LXC_BRIDGE" -j ACCEPT
  iptables -C DOCKER-USER -o "$LXC_BRIDGE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || iptables -I DOCKER-USER -o "$LXC_BRIDGE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  lxc_docker_persist
  return 0
}

# iptables 规则重启就没了，Docker 开机时 DOCKER-USER 是空链：让 docker.service 每次启动后补上放行规则
LXC_DOCKER_DROPIN=/etc/systemd/system/docker.service.d/nx-lxc.conf
lxc_docker_persist() {
  local b=$LXC_BRIDGE new
  has systemctl && [[ -d /run/systemd/system ]] || return 0
  new="[Service]
ExecStartPost=-/bin/sh -c 'iptables -C DOCKER-USER -i $b -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -i $b -j ACCEPT; iptables -C DOCKER-USER -o $b -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -o $b -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT'"
  [[ -f $LXC_DOCKER_DROPIN && $(cat "$LXC_DOCKER_DROPIN") == "$new" ]] && return 0
  mkdir -p "${LXC_DOCKER_DROPIN%/*}"
  printf '%s\n' "$new" > "$LXC_DOCKER_DROPIN"
  systemctl daemon-reload
}

# ------------------------------------------------------------------ 资源分配
lxc_alloc_ip() {
  local cidr base gw i ip used
  cidr=$($IC network get "$LXC_BRIDGE" ipv4.address 2>/dev/null)
  [[ $cidr =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)/([0-9]+)$ ]] || return 1
  base=${BASH_REMATCH[1]}; gw=${BASH_REMATCH[2]}
  used=$(
    $IC list --format json 2>/dev/null | jq -r '.[] | (.devices.eth0["ipv4.address"] // empty),
      ((.state.network.eth0.addresses // [])[] | select(.family == "inet") | .address)'
    $IC network list-leases "$LXC_BRIDGE" --format csv 2>/dev/null | cut -d, -f3
  )
  for (( i = 10; i <= 250; i++ )); do
    [[ $i == "$gw" ]] && continue
    ip="$base.$i"
    grep -qxF "$ip" <<<"$used" || { echo "$ip"; return 0; }
  done
  return 1
}

# 所有小鸡 proxy 设备占用的宿主端口（NAT 模式不会出现在 ss 里）
lxc_used_ports() {
  $IC list --format json 2>/dev/null | jq -r '.[] | .devices // {} | to_entries[] | select(.value.type == "proxy") | .value.listen // empty' \
    | sed -E 's/^[a-z]+:(\[[^]]*\]|[^:]*):(.*)$/\2/' | tr ',' '\n'
}

host_listen_ports() { ssq -lntu | awk '{n = split($5, a, ":"); print a[n]}' | sort -un; }

# port_block_free 起始 结束 [宿主监听端口表] [小鸡已映射端口表]：宿主未监听且未被其他小鸡映射
port_block_free() {
  local a=$1 b=$2 listen=${3-none} used=${4-none} p x lo hi
  (( a >= 1 && b <= 65535 && a <= b )) || return 1
  [[ $listen == none ]] && listen=$(host_listen_ports)
  [[ $used == none ]] && used=$(lxc_used_ports)
  for p in $listen; do
    is_uint "$p" || continue
    (( p >= a && p <= b )) && return 1
  done
  for x in $used; do
    lo=${x%-*}; hi=${x#*-}
    is_uint "$lo" && is_uint "$hi" || continue
    (( a <= hi && b >= lo )) && return 1
  done
  return 0
}

# 从 start 起找连续 n 个可用端口，输出起始端口
find_port_block() {
  local s=$1 n=$2 tries=0 listen used
  listen=$(host_listen_ports)
  used=$(lxc_used_ports)
  while (( tries < 2000 && s + n - 1 <= 65535 )); do
    if port_block_free "$s" $((s + n - 1)) "$listen" "$used"; then echo "$s"; return 0; fi
    s=$((s + n)); tries=$((tries + 1))
  done
  return 1
}

ipv6_expand() {
  local ip=${1%%/*} left right i miss
  local -a L=() R=() out=()
  if [[ $ip == *::* ]]; then left=${ip%%::*}; right=${ip#*::}; else left=$ip; right=""; fi
  if [[ -n $left ]]; then IFS=: read -ra L <<<"$left"; fi
  if [[ -n $right ]]; then IFS=: read -ra R <<<"$right"; fi
  miss=$(( 8 - ${#L[@]} - ${#R[@]} ))
  for i in "${L[@]}"; do out+=("$(printf '%04x' "0x$i")"); done
  for (( i = 0; i < miss; i++ )); do out+=("0000"); done
  for i in "${R[@]}"; do out+=("$(printf '%04x' "0x$i")"); done
  (IFS=:; echo "${out[*]}")
}

# 输出 "网卡 IPv6地址"：从宿主 /64（或更大）前缀中随机分配一个地址
lxc_ipv6_alloc() {
  local dev addr plen prefix
  dev=$(ip -6 route get 2001:4860:4860::8888 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
  [[ -n $dev ]] || return 1
  addr=$(ip -6 -o addr show dev "$dev" scope global 2>/dev/null | awk '!/temporary|deprecated/ {print $4; exit}')
  [[ -n $addr ]] || return 1
  plen=${addr#*/}; addr=${addr%/*}
  (( plen <= 64 )) || return 2
  prefix=$(ipv6_expand "$addr" | cut -d: -f1-4)
  printf '%s %s:%x:%x:%x:%x\n' "$dev" "$prefix" $((RANDOM | 0x100)) $RANDOM $RANDOM $((RANDOM | 1))
}

lxc_ipv6_sysctl() {
  local dev=$1
  cat > /etc/sysctl.d/99-nx-lxc-ipv6.conf <<EOF
# 由 NX 工具箱生成：小鸡独立 IPv6（routed 网卡）所需
# accept_ra=2 必须先于 forwarding 生效，否则开启转发时宿主会丢掉 RA 学到的默认路由
net.ipv6.conf.$dev.accept_ra = 2
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.$dev.forwarding = 1
net.ipv6.conf.all.proxy_ndp = 1
net.ipv6.conf.$dev.proxy_ndp = 1
EOF
  sysctl -p /etc/sysctl.d/99-nx-lxc-ipv6.conf >/dev/null 2>&1
}

# ------------------------------------------------------------------ 创建
# 容器内安装并配置 sshd（允许 root 密码登录）
LXC_SSH_SETUP='
set +e
. /etc/os-release 2>/dev/null
case "$ID $ID_LIKE" in
  *debian*|*ubuntu*) export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; apt-get install -y -qq openssh-server ;;
  *alpine*) apk add --no-cache openssh; rc-update add sshd default ;;
  *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) dnf -y install openssh-server || yum -y install openssh-server ;;
  *arch*) pacman -Sy --noconfirm openssh ;;
  *suse*) zypper -n install openssh ;;
esac
command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ] || { echo "NO_SSHD"; exit 1; }
ssh-keygen -A >/dev/null 2>&1
if grep -qE "^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d" /etc/ssh/sshd_config 2>/dev/null; then
  mkdir -p /etc/ssh/sshd_config.d
  printf "PermitRootLogin yes\nPasswordAuthentication yes\n" > /etc/ssh/sshd_config.d/00-nx.conf
fi
sed -i -E "s/^#?[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/; s/^#?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config
grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
if [ -d /run/systemd/system ]; then
  systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1
  systemctl restart ssh.socket >/dev/null 2>&1
  systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
else
  rc-service sshd restart >/dev/null 2>&1 || /etc/init.d/sshd restart >/dev/null 2>&1
fi
echo SSH_READY
'

lxc_wait_net() {
  local n=$1 i
  for (( i = 0; i < 40; i++ )); do
    if $IC exec "$n" -- sh -c 'ip -4 addr show eth0 2>/dev/null | grep -q "inet " && (getent hosts deb.debian.org >/dev/null 2>&1 || nslookup deb.debian.org >/dev/null 2>&1 || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1)' </dev/null >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

lxc_set_password() {
  printf 'root:%s\n' "$2" | $IC exec "$1" -- chpasswd 2>/dev/null
}

lxc_reset_c() {
  C_NAME=""; C_IMAGE=$L_IMAGE; C_CPU=$L_CPU; C_CPU_CAP=$L_CPU_CAP; C_MEM=$L_MEM; C_SWAP=$L_SWAP; C_DISK=$L_DISK
  C_NET=$L_NET; C_IO=$L_IO; C_PROCS=$L_PROCS; C_SSH_PORT="auto"; C_PORTS=$L_PORTS; C_PW=""; C_NESTING=$L_NESTING
  C_PRIV=0; C_AUTOSTART=$L_AUTOSTART; C_IPV6=0; C_NOSSH=0; C_RANGE=""
  C_NET_IN=""; C_NET_OUT=""; C_READ=""; C_WRITE=""; C_PIN=""
  C_TRAFFIC=0; C_TACT=limit; C_TCOUNT=both; C_TRATE=1; C_RESET_DAY=1; C_EXPIRE=""
}

traffic_gb() {
  local v=${1^^}
  if [[ $v =~ ^([0-9]+(\.[0-9]+)?)(T|TB|TIB)$ ]]; then awk -v x="${BASH_REMATCH[1]}" 'BEGIN { printf "%d", x * 1024 + 0.5 }'
  else to_gb "$1"; fi
}

# 到期日：YYYY-MM-DD，或 30d / 3m（从今天起算）；- 或 0 表示不限
lxc_expire_date() {
  local v=$1
  case $v in
    -|0|"") echo "" ;;
    *d) is_uint "${v%d}" && date -d "+${v%d} days" +%F ;;
    *m) is_uint "${v%m}" && date -d "+${v%m} months" +%F ;;
    *) [[ $v =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$v" +%F ;;
  esac
}

# 绑核列表（如 0-1,3）包含的核数；编号必须小于宿主核数
cpu_set_count() {
  local part a b max
  local -A seen=()
  max=$(nproc)
  [[ $1 =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || return 1
  for part in ${1//,/ }; do
    a=$((10#${part%-*})); b=$((10#${part#*-}))
    (( a <= b && b < max )) || return 1
    for (( ; a <= b; a++ )); do seen[$a]=1; done
  done
  echo "${#seen[@]}"
}

# Incus 硬盘限速取值：数字为 MB/s，带 iops 后缀为 IOPS，0 或空为不限
io_lim() { case $1 in ""|0|0iops) ;; *iops) echo "$1" ;; *) echo "${1}MB" ;; esac; }
io_desc() { case $1 in ""|0|0iops) echo 不限 ;; *iops) echo "${1%iops} IOPS" ;; *) echo "$1 MB/s" ;; esac; }
mbps_desc() { if [[ ${1:-0} == 0 ]]; then echo 不限; else echo "$1 Mbps"; fi; }

# 解析创建参数到 C_*
lxc_parse_opts() {
  local o v
  while [[ $# -gt 0 ]]; do
    o=$1; shift; v=""
    case $o in
      --image|--cpu|--cpu-cap|--mem|--swap|--disk|--net|--io|--procs|--ssh-port|--ports|--password|--ipv6|--nesting|--autostart|\
      --net-in|--net-out|--read|--write|--iops|--cpu-pin|--traffic|--traffic-action|--traffic-count|--traffic-rate|--reset-day|--expire)
        [[ $# -gt 0 ]] || { err "参数 $o 缺少值"; return 2; }
        v=$1; shift ;;&
      --net-in) C_NET_IN=$v ;;
      --net-out) C_NET_OUT=$v ;;
      --read) C_READ=${v,,} ;;
      --write) C_WRITE=${v,,} ;;
      --iops) C_READ="${v}iops"; C_WRITE="${v}iops" ;;
      --cpu-pin) C_PIN=$v ;;
      --traffic) C_TRAFFIC=$(traffic_gb "$v") || { err "月流量格式无效: $v（如 500、500G、2T，0 不限）"; return 2; } ;;
      --traffic-action) C_TACT=$v ;;
      --traffic-count) C_TCOUNT=$v ;;
      --traffic-rate) C_TRATE=$v ;;
      --reset-day) C_RESET_DAY=$v ;;
      --expire) C_EXPIRE=$(lxc_expire_date "$v") || { err "到期时间无效: $v（YYYY-MM-DD 或 30d，- 表示不限）"; return 2; } ;;
      --image) C_IMAGE=$v ;;
      --cpu) C_CPU=$v ;;
      --cpu-cap) C_CPU_CAP=$v ;;
      --mem) C_MEM=$(to_mb "$v") || { err "内存格式无效: $v"; return 2; } ;;
      --swap) C_SWAP=$(to_mb "$v") || { err "swap 格式无效: $v"; return 2; } ;;
      --disk) C_DISK=$(to_gb "$v") || { err "硬盘格式无效: $v"; return 2; } ;;
      --net) C_NET=$v ;;
      --io) C_IO=$v ;;
      --procs) C_PROCS=$v ;;
      --ssh-port) C_SSH_PORT=$v ;;
      --ports) C_PORTS=$v ;;
      --password) C_PW=$v ;;
      --ipv6) case $v in 1|yes|on|auto) C_IPV6=1 ;; 0|no|off) C_IPV6=0 ;; *) C_IPV6=$v ;; esac ;;
      --nesting) [[ $v =~ ^(1|yes|on|true)$ ]] && C_NESTING=1 || C_NESTING=0 ;;
      --autostart) [[ $v =~ ^(1|yes|on|true)$ ]] && C_AUTOSTART=1 || C_AUTOSTART=0 ;;
      --privileged) C_PRIV=1 ;;
      --no-ssh) C_NOSSH=1 ;;
      -y|--yes) ASSUME_YES=1 ;;
      -*) err "未知参数: $o"; return 2 ;;
      *) C_NAME=$o ;;
    esac
  done
  return 0
}

lxc_validate_c() {
  lxc_name_ok "$C_NAME" || { err "名称无效（字母开头，字母数字和 -，最长 63）"; return 1; }
  lxc_exists "$C_NAME" && { err "小鸡 $C_NAME 已存在"; return 1; }
  [[ $C_IMAGE =~ ^[A-Za-z0-9._/-]+$ ]] || { err "镜像名无效: $C_IMAGE"; return 1; }
  if [[ -n $C_PIN ]]; then
    C_CPU=$(cpu_set_count "$C_PIN") || { err "绑核列表无效: $C_PIN（如 0-1,3，编号 0-$(( $(nproc) - 1 ))）"; return 1; }
  fi
  is_uint "$C_CPU" && (( C_CPU >= 1 && C_CPU <= $(nproc) )) || { err "CPU 核数应为 1-$(nproc)"; return 1; }
  is_uint "$C_CPU_CAP" && (( C_CPU_CAP >= 5 && C_CPU_CAP <= 100 )) || { err "CPU 上限应为 5-100(%)"; return 1; }
  is_uint "$C_MEM" && (( C_MEM >= 64 )) || { err "内存至少 64MB"; return 1; }
  is_uint "$C_SWAP" || { err "swap 无效"; return 1; }
  is_uint "$C_DISK" && (( C_DISK >= 1 )) || { err "硬盘至少 1GB"; return 1; }
  is_uint "$C_NET" || { err "带宽无效（Mbps，0 不限）"; return 1; }
  is_uint "$C_IO" || { err "IO 无效（MB/s，0 不限）"; return 1; }
  local x
  for x in "$C_NET_IN" "$C_NET_OUT"; do
    [[ -z $x ]] || is_uint "$x" || { err "带宽无效: $x（Mbps，0 不限）"; return 1; }
  done
  for x in "$C_READ" "$C_WRITE"; do
    [[ -z $x || $x =~ ^[0-9]+(iops)?$ ]] || { err "读写限速无效: $x（MB/s 写数字，IOPS 写如 1000iops）"; return 1; }
  done
  is_uint "$C_TRAFFIC" || { err "月流量无效（GB，0 不限）"; return 1; }
  [[ $C_TACT == limit || $C_TACT == stop ]] || { err "超流量处理只能是 limit（限速）或 stop（关机）"; return 1; }
  [[ $C_TCOUNT =~ ^(both|out|in|max)$ ]] || { err "流量计算方式只能是 both / out / in / max"; return 1; }
  is_uint "$C_TRATE" && (( C_TRATE >= 1 )) || { err "超流量后的限速至少 1 Mbps"; return 1; }
  is_uint "$C_RESET_DAY" && (( C_RESET_DAY >= 1 && C_RESET_DAY <= 28 )) || { err "流量重置日应为 1-28"; return 1; }
  is_uint "$C_PROCS" && (( C_PROCS >= 32 )) || { err "进程数至少 32"; return 1; }
  if [[ -n $C_PW ]] && [[ ${#C_PW} -lt 6 || $C_PW == *[[:space:]:]* ]]; then err "密码至少 6 位且不能含空格和冒号"; return 1; fi
  # 端口：SSH 端口 + 端口段
  local cnt=0 a b
  if [[ $C_PORTS =~ ^([0-9]+)-([0-9]+)$ ]]; then
    a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
    port_block_free "$a" "$b" || { err "端口段 $a-$b 已被占用"; return 1; }
    C_RANGE="$a-$b"
  elif is_uint "$C_PORTS"; then
    cnt=$C_PORTS
  else
    err "端口段格式无效（数量，或 起-止）"; return 1
  fi
  if [[ $C_SSH_PORT == auto ]]; then
    a=$(find_port_block "$L_SSH_START" $((cnt + 1))) || { err "找不到可用端口"; return 1; }
    C_SSH_PORT=$a
    if (( cnt > 0 )); then C_RANGE="$((a + 1))-$((a + cnt))"; fi
  else
    is_port "$C_SSH_PORT" || { err "SSH 端口无效"; return 1; }
    port_block_free "$C_SSH_PORT" "$C_SSH_PORT" || { err "SSH 端口 $C_SSH_PORT 已被占用"; return 1; }
    if (( cnt > 0 )) && [[ -z $C_RANGE ]]; then
      a=$(find_port_block $((C_SSH_PORT + 1)) "$cnt") || { err "找不到 $cnt 个连续可用端口"; return 1; }
      C_RANGE="$a-$((a + cnt - 1))"
    fi
  fi
  [[ -z $C_PW ]] && C_PW=$(rand_pass 12)
  return 0
}

# 用 C_* 创建一台小鸡
lxc_create_do() {
  local ip ref listen v6dev v6addr out quota rd wr ni no
  local -a cfg
  ref="$(lxc_remote):$C_IMAGE"
  ip=$(lxc_alloc_ip) || { err "内网 IP 已分配完"; return 1; }
  cfg=(-c "limits.cpu=${C_PIN:-$C_CPU}" -c "limits.memory=${C_MEM}MiB" -c "limits.memory.enforce=hard"
       -c "limits.processes=$C_PROCS" -c "user.nx.managed=1" -c "user.nx.image=$C_IMAGE"
       -c "user.nx.ssh_port=$C_SSH_PORT" -c "user.nx.ports=${C_RANGE:-}")
  if (( C_CPU_CAP < 100 )); then quota=$(( C_CPU * C_CPU_CAP )); cfg+=(-c "limits.cpu.allowance=${quota}ms/100ms"); fi
  if [[ $C_AUTOSTART == 1 ]]; then cfg+=(-c boot.autostart=true); else cfg+=(-c boot.autostart=false); fi
  if [[ $C_NESTING == 1 ]]; then cfg+=(-c security.nesting=true); fi
  if [[ $C_PRIV == 1 ]]; then cfg+=(-c security.privileged=true); fi
  if [[ $C_SWAP == 0 ]]; then
    cfg+=(-c limits.memory.swap=false)
  else
    cfg+=(-c limits.memory.swap=true)
    if cgroup_v2; then cfg+=(-c "raw.lxc=lxc.cgroup2.memory.swap.max = $(( C_SWAP * 1024 * 1024 ))"); fi
    if [[ -z ${LXC_SWAP_WARNED:-} ]] && (( $(awk '/^SwapTotal/ {print $2}' /proc/meminfo) == 0 )); then
      warn "宿主机没有 swap，小鸡的 Swap 配额不会生效（512MB 的 Rocky/Alma 小鸡跑 dnf 会被 OOM），可在宿主执行 nx swap 2048"
      LXC_SWAP_WARNED=1
    fi
  fi
  info "创建 $C_NAME：$ref · ${C_CPU}核${C_PIN:+（绑定 $C_PIN）} · ${C_MEM}MB · ${C_DISK}GB · 内网 $ip"
  if ! $IC init "$ref" "$C_NAME" "${cfg[@]}"; then
    err "创建失败。镜像名是否正确？可用 nx lxc images 查看常用镜像"
    return 1
  fi
  local -a rootopt=("size=${C_DISK}GiB") nicopt=("ipv4.address=$ip")
  rd=$(io_lim "${C_READ:-$C_IO}"); wr=$(io_lim "${C_WRITE:-$C_IO}")
  if [[ -n $rd ]]; then rootopt+=("limits.read=$rd"); fi
  if [[ -n $wr ]]; then rootopt+=("limits.write=$wr"); fi
  # 从小鸡角度看：ingress 是下行（下载），egress 是上行（上传）
  ni=${C_NET_IN:-$C_NET}; no=${C_NET_OUT:-$C_NET}
  if (( ni > 0 )); then nicopt+=("limits.ingress=${ni}Mbit"); fi
  if (( no > 0 )); then nicopt+=("limits.egress=${no}Mbit"); fi
  if ! out=$($IC config device override "$C_NAME" root "${rootopt[@]}" 2>&1); then
    if [[ -n $rd$wr ]] && $IC config device override "$C_NAME" root "size=${C_DISK}GiB" >/dev/null 2>&1; then
      warn "当前存储不支持硬盘 IO 限速，已忽略"
    else
      err "设置硬盘失败: $out"
      $IC delete -f "$C_NAME" >/dev/null 2>&1
      return 1
    fi
  fi
  if ! out=$($IC config device override "$C_NAME" eth0 "${nicopt[@]}" 2>&1); then
    err "设置网卡失败: $out"; $IC delete -f "$C_NAME" >/dev/null 2>&1; return 1
  fi
  for listen in 0.0.0.0 "$(main_ipv4_local)"; do
    [[ -n $listen ]] || continue
    if $IC config device add "$C_NAME" nx-ssh proxy "listen=tcp:$listen:$C_SSH_PORT" "connect=tcp:$ip:22" nat=true >/dev/null 2>&1; then break; fi
  done
  if ! $IC config device get "$C_NAME" nx-ssh listen >/dev/null 2>&1; then
    err "SSH 端口映射失败"; $IC delete -f "$C_NAME" >/dev/null 2>&1; return 1
  fi
  if [[ -n $C_RANGE ]]; then
    # Incus 不接受起止相同的端口段（如 20001-20001）
    local pr=$C_RANGE
    if [[ ${pr%-*} == "${pr#*-}" ]]; then pr=${pr%-*}; fi
    $IC config device add "$C_NAME" nx-tcp proxy "listen=tcp:$listen:$pr" "connect=tcp:$ip:$pr" nat=true >/dev/null 2>&1 || warn "TCP 端口段映射失败"
    $IC config device add "$C_NAME" nx-udp proxy "listen=udp:$listen:$pr" "connect=udp:$ip:$pr" nat=true >/dev/null 2>&1 || warn "UDP 端口段映射失败"
  fi
  if [[ $C_IPV6 != 0 ]]; then
    read -r v6dev v6addr <<<"$(lxc_ipv6_alloc)"
    if [[ $C_IPV6 != 1 ]] && is_ipv6 "$C_IPV6"; then v6addr=$C_IPV6; fi
    if [[ -n $v6dev && -n $v6addr ]]; then
      lxc_ipv6_sysctl "$v6dev"
      local -a v6opt=(nictype=routed "parent=$v6dev" "ipv6.address=$v6addr")
      if (( ni > 0 )); then v6opt+=("limits.ingress=${ni}Mbit"); fi
      if (( no > 0 )); then v6opt+=("limits.egress=${no}Mbit"); fi
      if $IC config device add "$C_NAME" eth1 nic "${v6opt[@]}" >/dev/null 2>&1; then
        $IC config set "$C_NAME" user.nx.ipv6 "$v6addr" >/dev/null 2>&1
      else
        warn "IPv6 网卡添加失败，已跳过"; v6addr=""
      fi
    else
      warn "宿主机没有可分配的 IPv6 前缀（需要 /64 或更大的网段），已跳过 IPv6"; v6addr=""
    fi
  fi
  if ! $IC start "$C_NAME"; then
    err "启动失败"; $IC info "$C_NAME" --show-log 2>/dev/null | tail -n 15
    $IC delete -f "$C_NAME" >/dev/null 2>&1
    warn "已删除未建成的小鸡 $C_NAME"
    return 1
  fi
  info "等待网络就绪..."
  if ! lxc_wait_net "$C_NAME"; then warn "小鸡网络未就绪（检查宿主 NAT/防火墙），跳过 SSH 安装"; C_NOSSH=1; fi
  if [[ $C_NOSSH != 1 ]]; then
    info "安装并配置 SSH..."
    mkdir -p "$LXC_INFO_DIR"
    chmod 700 "$LXC_INFO_DIR"
    if ! $IC exec "$C_NAME" -- sh -c "$LXC_SSH_SETUP" </dev/null >"$LXC_INFO_DIR/$C_NAME.log" 2>&1 || ! grep -q SSH_READY "$LXC_INFO_DIR/$C_NAME.log"; then
      warn "容器内 SSH 配置可能未完成，日志: $LXC_INFO_DIR/$C_NAME.log"
    fi
  fi
  lxc_set_password "$C_NAME" "$C_PW" || warn "设置 root 密码失败"
  lxc_save_info "$ip" "${v6addr:-}"
  if [[ $C_TRAFFIC != 0 || -n $C_EXPIRE ]]; then lxc_guard_enable; fi
  lxc_print_info "$C_NAME"
}

lxc_save_info() {
  local ip=$1 v6=$2 host
  host=$(public_ipv4 2>/dev/null || main_ipv4_local)
  mkdir -p "$LXC_INFO_DIR"
  chmod 700 "$LXC_INFO_DIR"
  cat > "$LXC_INFO_DIR/$C_NAME.txt" <<EOF
NAME=$C_NAME
IMAGE=$C_IMAGE
CPU=$C_CPU
CPU_CAP=$C_CPU_CAP
MEM=$C_MEM
SWAP=$C_SWAP
DISK=$C_DISK
NET=$C_NET
IO=$C_IO
NET_IN=${C_NET_IN:-$C_NET}
NET_OUT=${C_NET_OUT:-$C_NET}
READ=${C_READ:-$C_IO}
WRITE=${C_WRITE:-$C_IO}
CPU_PIN=$C_PIN
TRAFFIC=$C_TRAFFIC
TRAFFIC_ACTION=$C_TACT
TRAFFIC_COUNT=$C_TCOUNT
TRAFFIC_RATE=$C_TRATE
RESET_DAY=$C_RESET_DAY
EXPIRE=$C_EXPIRE
IP=$ip
IPV6=$v6
HOST=$host
SSH_PORT=$C_SSH_PORT
PORTS=$C_RANGE
PASSWORD=$C_PW
CREATED=$(date '+%F %T')
EOF
  chmod 600 "$LXC_INFO_DIR/$C_NAME.txt"
}

lxc_info_get() { [[ -f $LXC_INFO_DIR/$1.txt ]] && awk -F= -v k="$2" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$LXC_INFO_DIR/$1.txt"; }

lxc_print_info() {
  local n=$1 f="$LXC_INFO_DIR/$1.txt"
  [[ -f $f ]] || { warn "没有 $n 的信息记录"; return 1; }
  hr
  printf '  %s小鸡 %s%s\n' "$C_GRN$C_BLD" "$n" "$C_RST"
  row "系统" "$(lxc_info_get "$n" IMAGE)"
  local pin rd wr ni no quota exp
  pin=$(lxc_info_get "$n" CPU_PIN)
  rd=$(lxc_info_get "$n" READ); rd=${rd:-$(lxc_info_get "$n" IO)}
  wr=$(lxc_info_get "$n" WRITE); wr=${wr:-$(lxc_info_get "$n" IO)}
  ni=$(lxc_info_get "$n" NET_IN); ni=${ni:-$(lxc_info_get "$n" NET)}
  no=$(lxc_info_get "$n" NET_OUT); no=${no:-$(lxc_info_get "$n" NET)}
  quota=$(lxc_info_get "$n" TRAFFIC); exp=$(lxc_info_get "$n" EXPIRE)
  row "CPU" "$(lxc_info_get "$n" CPU) 核（性能上限 $(lxc_info_get "$n" CPU_CAP)%）${pin:+ · 绑定核 $pin}"
  row "内存/Swap" "$(lxc_info_get "$n" MEM) MB / $(lxc_info_get "$n" SWAP) MB"
  row "硬盘" "$(lxc_info_get "$n" DISK) GB · 读 $(io_desc "$rd") · 写 $(io_desc "$wr")"
  if [[ ${ni:-0} == "${no:-0}" ]]; then row "带宽" "$(mbps_desc "$ni")（上下行）"
  else row "带宽" "下行 $(mbps_desc "$ni") · 上行 $(mbps_desc "$no")"; fi
  if [[ ${quota:-0} != 0 ]]; then
    local tc rday act rate
    tc=$(lxc_info_get "$n" TRAFFIC_COUNT); rday=$(lxc_info_get "$n" RESET_DAY)
    act=$(lxc_info_get "$n" TRAFFIC_ACTION); rate=$(lxc_info_get "$n" TRAFFIC_RATE)
    if [[ $act == stop ]]; then act=停机; else act="限速 ${rate:-1} Mbps"; fi
    lxc_state_load "$n"
    row "月流量" "已用 $(fmt_bytes "$(lxc_used_bytes "$tc" "$S_RX" "$S_TX")") / $quota GB（$(lxc_count_label "$tc")，每月 ${rday:-1} 号重置，超额后$act）"
  fi
  if [[ -n $exp ]]; then row "到期" "$exp（$(lxc_days_left "$exp")，到期后自动停机）"; fi
  row "内网 IP" "$(lxc_info_get "$n" IP)"
  row "SSH" "ssh root@$(lxc_info_get "$n" HOST) -p $(lxc_info_get "$n" SSH_PORT)"
  row "root 密码" "$(lxc_info_get "$n" PASSWORD)"
  row "端口段" "$(lxc_info_get "$n" PORTS | sed 's/^$/无/')（TCP+UDP，宿主同号映射）"
  row "IPv6" "$(lxc_info_get "$n" IPV6 | sed 's/^$/无/')"
  row "信息文件" "$f"
  hr
}

lxc_create_wizard() {
  local c v v6 cnt
  lxc_need || return 1
  lxc_reset_c
  title "开小鸡"
  local i=1
  while lxc_exists "lxc$i"; do i=$((i + 1)); done
  ask C_NAME "名称" "lxc$i" || return 1
  echo "  系统：1) debian/12  2) debian/13  3) ubuntu/24.04  4) ubuntu/22.04  5) alpine/3.22"
  echo "        6) rockylinux/9  7) almalinux/9  8) archlinux  9) 自定义"
  ask c "选择系统" "1" || return 1
  case $c in
    1) C_IMAGE=debian/12 ;; 2) C_IMAGE=debian/13 ;; 3) C_IMAGE=ubuntu/24.04 ;; 4) C_IMAGE=ubuntu/22.04 ;;
    5) C_IMAGE=alpine/3.22 ;; 6) C_IMAGE=rockylinux/9 ;; 7) C_IMAGE=almalinux/9 ;; 8) C_IMAGE=archlinux ;;
    9) ask C_IMAGE "镜像名（如 fedora/43、centos/10-Stream，nx lxc images 查看更多）" "$L_IMAGE" || return 1 ;;
  esac
  ask C_CPU "CPU 核数（宿主共 $(nproc) 核）" "$C_CPU" || return 1
  ask C_CPU_CAP "CPU 性能上限 %（100 不限制）" "$C_CPU_CAP" || return 1
  ask C_MEM "内存 MB" "$C_MEM" || return 1
  C_MEM=$(to_mb "$C_MEM") || { err "内存格式无效"; return 1; }
  ask C_SWAP "Swap MB（0 关闭）" "$C_SWAP" || return 1
  C_SWAP=$(to_mb "$C_SWAP") || { err "Swap 格式无效"; return 1; }
  ask C_DISK "硬盘 GB" "$C_DISK" || return 1
  C_DISK=$(to_gb "$C_DISK") || { err "硬盘格式无效"; return 1; }
  ask C_NET "带宽 Mbps（上下行，0 不限）" "$C_NET" || return 1
  ask C_IO "硬盘读写限速 MB/s（0 不限）" "$C_IO" || return 1
  if confirm_opt "设置更多限制（上下行分开、读写/IOPS 分开、绑核、月流量、到期）?" N; then
    ask C_NET_IN "下行带宽 Mbps（0 不限）" "$C_NET" || return 1
    ask C_NET_OUT "上行带宽 Mbps（0 不限）" "$C_NET" || return 1
    ask C_READ "硬盘读限速（MB/s，或如 2000iops；0 不限）" "$C_IO" || return 1
    ask C_WRITE "硬盘写限速（MB/s，或如 1000iops；0 不限）" "$C_IO" || return 1
    C_READ=${C_READ,,}; C_WRITE=${C_WRITE,,}
    ask C_PIN "绑定 CPU 核（如 0-1,3；回车不绑定）" "" || return 1
    ask v "每月流量 GB（0 不限，可写 2T）" "0" || return 1
    C_TRAFFIC=$(traffic_gb "$v") || { err "月流量格式无效: $v"; return 1; }
    if [[ $C_TRAFFIC != 0 ]]; then
      echo "  流量计算：1) 上下行合计  2) 只计上行  3) 只计下行  4) 上下行取大"
      ask v "请选择" "1" || return 1
      case $v in 2) C_TCOUNT=out ;; 3) C_TCOUNT=in ;; 4) C_TCOUNT=max ;; *) C_TCOUNT=both ;; esac
      ask C_RESET_DAY "每月几号重置（1-28）" "1" || return 1
      echo "  超额后：1) 限速  2) 关机"
      ask v "请选择" "1" || return 1
      if [[ $v == 2 ]]; then C_TACT=stop; else C_TACT=limit; ask C_TRATE "超额后限速 Mbps" "1" || return 1; fi
    fi
    ask v "到期时间（YYYY-MM-DD 或 30d；回车不限）" "" || return 1
    C_EXPIRE=$(lxc_expire_date "$v") || { err "到期时间无效: $v"; return 1; }
  fi
  ask C_PROCS "进程数上限" "$C_PROCS" || return 1
  ask C_SSH_PORT "SSH 映射端口（auto 自动分配）" "auto" || return 1
  ask cnt "额外 NAT 端口数量（0 不开；也可填区间如 30000-30019）" "$C_PORTS" || return 1
  C_PORTS=$cnt
  read -r v6 _ <<<"$(lxc_ipv6_alloc 2>/dev/null)"
  if [[ -n $v6 ]] && confirm_opt "分配独立公网 IPv6（宿主网卡 $v6 的 /64 段）?" N; then C_IPV6=1; fi
  ask C_PW "root 密码（回车随机生成）" "" || return 1
  if confirm "开启嵌套（可在小鸡里跑 Docker）?" "$([[ $C_NESTING == 1 ]] && echo Y || echo N)"; then C_NESTING=1; else C_NESTING=0; fi
  lxc_validate_c || return 1
  hr
  printf '  %s · %s · %s核(%s%%) · 内存 %sMB · Swap %sMB · 硬盘 %sGB · 带宽 %s · SSH %s · 端口段 %s%s\n' \
    "$C_NAME" "$C_IMAGE" "$C_CPU" "$C_CPU_CAP" "$C_MEM" "$C_SWAP" "$C_DISK" \
    "$([[ $C_NET == 0 ]] && echo 不限 || echo "${C_NET}Mbps")" "$C_SSH_PORT" "${C_RANGE:-无}" "$([[ $C_IPV6 != 0 ]] && echo ' · IPv6')"
  printf '  下行 %s · 上行 %s · 硬盘读 %s · 写 %s%s%s%s\n' "$(mbps_desc "${C_NET_IN:-$C_NET}")" "$(mbps_desc "${C_NET_OUT:-$C_NET}")" \
    "$(io_desc "${C_READ:-$C_IO}")" "$(io_desc "${C_WRITE:-$C_IO}")" "${C_PIN:+ · 绑核 $C_PIN}" \
    "$([[ $C_TRAFFIC != 0 ]] && echo " · 月流量 ${C_TRAFFIC}GB")" "${C_EXPIRE:+ · 到期 $C_EXPIRE}"
  confirm "确认创建?" Y || return 1
  lxc_create_do
}

lxc_create_cli() {
  lxc_need || return 1
  lxc_reset_c
  lxc_parse_opts "$@" || return 2
  if [[ -z $C_NAME ]]; then
    local i=1
    while lxc_exists "lxc$i"; do i=$((i + 1)); done
    C_NAME="lxc$i"
  fi
  lxc_validate_c || return 1
  lxc_create_do
}

# nx lxc batch --count N [--prefix nat] [资源参数...]
lxc_batch() {
  local count="" prefix="nat" i idx=1 made=0 summary
  local -a rest=()
  lxc_need || return 1
  while [[ $# -gt 0 ]]; do
    case $1 in
      --count) count=${2:-} ;;
      --prefix) prefix=${2:-} ;;
      *) rest+=("$1"); shift; continue ;;
    esac
    shift
    [[ $# -gt 0 ]] && shift
  done
  if [[ -z $count && -t 0 ]]; then
    title "批量开小鸡"
    ask count "数量" "5" || return 1
    ask prefix "名称前缀" "$prefix" || return 1
    lxc_reset_c
    ask C_IMAGE "系统镜像" "$C_IMAGE" || return 1
    ask C_CPU "每台 CPU 核数" "$C_CPU" || return 1
    ask C_CPU_CAP "CPU 性能上限 %" "$C_CPU_CAP" || return 1
    ask C_MEM "每台内存 MB" "$C_MEM" || return 1
    ask C_SWAP "每台 Swap MB" "$C_SWAP" || return 1
    ask C_DISK "每台硬盘 GB" "$C_DISK" || return 1
    ask C_NET "每台带宽 Mbps（0 不限）" "$C_NET" || return 1
    ask C_PORTS "每台额外端口数" "$C_PORTS" || return 1
    ask C_TRAFFIC "每台月流量 GB（0 不限，可写 2T）" "0" || return 1
    ask C_EXPIRE "到期时间（YYYY-MM-DD 或 30d；回车不限）" "" || return 1
    rest=(--image "$C_IMAGE" --cpu "$C_CPU" --cpu-cap "$C_CPU_CAP" --mem "$C_MEM" --swap "$C_SWAP" --disk "$C_DISK" --net "$C_NET" --ports "$C_PORTS"
          --traffic "$C_TRAFFIC")
    if [[ -n $C_EXPIRE ]]; then rest+=(--expire "$C_EXPIRE"); fi
    confirm "确认批量创建 $count 台?" Y || return 1
  fi
  is_uint "$count" && (( count >= 1 && count <= 200 )) || { err "数量应为 1-200"; return 1; }
  lxc_name_ok "${prefix}1" || { err "前缀无效"; return 1; }
  summary="$LXC_INFO_DIR/batch-$(date +%Y%m%d-%H%M%S).txt"
  mkdir -p "$LXC_INFO_DIR"
  printf '%-12s %-8s %-14s %-18s %s\n' "名称" "SSH端口" "端口段" "内网IP" "root密码" > "$summary"
  for (( i = 1; i <= count; i++ )); do
    while lxc_exists "$prefix$idx"; do idx=$((idx + 1)); done
    lxc_reset_c
    lxc_parse_opts "${rest[@]}" || return 2
    C_NAME="$prefix$idx"
    if lxc_validate_c && lxc_create_do >/dev/null; then
      made=$((made + 1))
      printf '%-12s %-8s %-14s %-18s %s\n' "$C_NAME" "$C_SSH_PORT" "${C_RANGE:--}" "$(lxc_info_get "$C_NAME" IP)" "$C_PW" >> "$summary"
      ok "[$i/$count] $C_NAME  SSH $C_SSH_PORT  端口 ${C_RANGE:--}"
    else
      err "[$i/$count] $C_NAME 创建失败"
    fi
    idx=$((idx + 1))
  done
  chmod 600 "$summary"
  hr
  cat "$summary"
  hr
  ok "批量完成：成功 $made / $count，汇总已保存 $summary（宿主 IP: $(public_ipv4 2>/dev/null || main_ipv4_local)）"
}

# ------------------------------------------------------------------ 管理
lxc_list() {
  local name st os ip cpu mem disk ssh ports v6 color
  lxc_need || return 1
  printf '  %s%s %s %s %s %s %s %s %s%s\n' "$C_BLD" "$(pad 名称 14)" "$(pad 状态 6)" "$(pad 系统 14)" "$(pad 内网IP 15)" \
    "$(pad CPU 4)" "$(pad 内存 9)" "$(pad 硬盘 7)" "SSH / 端口段" "$C_RST"
  $IC list --format json | jq -r '.[] | [
      .name, .status,
      (.config["user.nx.image"] // (((.config["image.os"] // "") + " " + (.config["image.release"] // "")) | if . == " " then "-" else . end)),
      (((.state.network.eth0.addresses // []) | map(select(.family == "inet")) | .[0].address) // "-"),
      (.config["limits.cpu"] // "-"), (.config["limits.memory"] // "-"),
      (.expanded_devices.root.size // "-"),
      (.config["user.nx.ssh_port"] // "-"),
      ((.config["user.nx.ports"] // "") | if . == "" then "-" else . end),
      ((.config["user.nx.ipv6"] // "") | if . == "" then "-" else . end)
    ] | @tsv' | while IFS=$'\t' read -r name st os ip cpu mem disk ssh ports v6; do
      if [[ $st == Running ]]; then color=$C_GRN; st=运行; else color=$C_RED; st=停止; fi
      printf '  %-14s %s%s%s   %-14s %-15s %-4s %-9s %-7s %s / %s%s\n' "$name" "$color" "$st" "$C_RST" "${os:0:14}" "$ip" "$cpu" "$mem" "$disk" \
        "$ssh" "$ports" "$([[ $v6 != - ]] && echo "  v6 $v6")"
    done
}

lxc_pick() { # lxc_pick 变量名（局部变量不能与调用方传入的变量名相同）
  local __v=$1 __name
  ask __name "小鸡名称" "" || return 1
  [[ -n $__name ]] || return 1
  lxc_exists "$__name" || { err "小鸡不存在: $__name"; return 1; }
  printf -v "$__v" '%s' "$__name"
}

lxc_delete() {
  local n=$1
  lxc_exists "$n" || { err "小鸡不存在: $n"; return 1; }
  confirm "删除小鸡 $n（数据不可恢复）?" N || return 1
  $IC delete -f "$n" && rm -f "$LXC_INFO_DIR/$n.txt" "$LXC_INFO_DIR/$n.log" "$LXC_STATE_DIR/$n.state" && ok "已删除 $n"
}

lxc_ports_show() {
  local n=$1
  $IC query "/1.0/instances/$n" 2>/dev/null | jq -r '.devices // {} | to_entries[] | select(.value.type == "proxy") |
    "  \(.key)\t\(.value.listen) → \(.value.connect)"'
}

lxc_port_add() { # 小鸡 宿主端口[-结束] [小鸡端口[-结束]] [tcp|udp|both]
  local n=$1 hp=$2 cp=${3:-$2} proto=${4:-both} ip a b x listen
  lxc_exists "$n" || { err "小鸡不存在"; return 1; }
  [[ $hp =~ ^[0-9]+(-[0-9]+)?$ && $cp =~ ^[0-9]+(-[0-9]+)?$ ]] || { err "端口格式无效"; return 1; }
  a=${hp%-*}; b=${hp#*-}
  port_block_free "$a" "$b" || { err "宿主端口 $hp 已被占用"; return 1; }
  ip=$($IC config device get "$n" eth0 ipv4.address 2>/dev/null)
  [[ -n $ip ]] || { err "小鸡没有固定内网 IP（非 nx 创建?）"; return 1; }
  listen=$($IC config device get "$n" nx-ssh listen 2>/dev/null | sed -E 's/^tcp:([^:]*):.*/\1/')
  [[ -z $listen ]] && listen=0.0.0.0
  for x in $(fw_protos "$proto"); do
    $IC config device add "$n" "nx-p$a-$x" proxy "listen=$x:$listen:$hp" "connect=$x:$ip:$cp" nat=true >/dev/null \
      && ok "已映射 $x 宿主 $hp → $n:$cp" || err "$x 映射失败"
  done
}

# 按当前核数（含绑核列表）重算 CPU 性能上限
lxc_cpu_cap_apply() { # 名称 [上限%]
  local n=$1 cap=${2:-} cores
  [[ -n $cap ]] || cap=$(lxc_info_get "$n" CPU_CAP)
  cores=$($IC config get "$n" limits.cpu)
  is_uint "$cores" || cores=$(cpu_set_count "$cores" 2>/dev/null) || cores=1
  if [[ -z $cap || $cap == 100 ]]; then $IC config unset "$n" limits.cpu.allowance >/dev/null 2>&1
  else $IC config set "$n" limits.cpu.allowance="$(( cores * cap ))ms/100ms"; fi
}

lxc_set_cli() { # nx lxc set 名称 [选项]：资源、限速、流量配额、到期，均即时生效
  local n=${1:-} o v cores ni no rd wr guard=0 changed=0 restart=0
  [[ $# -gt 0 ]] && shift
  lxc_exists "$n" || { err "小鸡不存在: $n"; return 1; }
  while [[ $# -gt 0 ]]; do
    o=$1; v=${2:-}; shift; [[ $# -gt 0 ]] && shift
    case $o in
      --cpu)
        is_uint "$v" && (( v >= 1 && v <= $(nproc) )) || { err "CPU 核数应为 1-$(nproc)"; return 1; }
        $IC config set "$n" limits.cpu="$v" || return 1
        lxc_info_set "$n" CPU "$v"; lxc_info_set "$n" CPU_PIN ""
        lxc_cpu_cap_apply "$n" ;;
      --cpu-pin)
        if [[ $v == - ]]; then
          cores=$(lxc_info_get "$n" CPU); is_uint "$cores" || cores=1
          $IC config set "$n" limits.cpu="$cores" || return 1
          lxc_info_set "$n" CPU_PIN ""
        else
          cores=$(cpu_set_count "$v") || { err "绑核列表无效: $v（如 0-1,3，编号 0-$(( $(nproc) - 1 ))）"; return 1; }
          $IC config set "$n" limits.cpu="$v" || return 1
          lxc_info_set "$n" CPU "$cores"; lxc_info_set "$n" CPU_PIN "$v"
        fi
        lxc_cpu_cap_apply "$n" ;;
      --cpu-cap)
        is_uint "$v" && (( v >= 5 && v <= 100 )) || { err "CPU 上限应为 5-100(%)"; return 1; }
        lxc_cpu_cap_apply "$n" "$v" || return 1
        lxc_info_set "$n" CPU_CAP "$v" ;;
      --mem)
        v=$(to_mb "$v") && (( v >= 64 )) || { err "内存格式无效或小于 64MB"; return 1; }
        $IC config set "$n" limits.memory="${v}MiB" || return 1
        lxc_info_set "$n" MEM "$v" ;;
      --swap)
        v=$(to_mb "$v") || { err "Swap 格式无效"; return 1; }
        if [[ $v == 0 ]]; then $IC config set "$n" limits.memory.swap=false; $IC config unset "$n" raw.lxc
        else $IC config set "$n" limits.memory.swap=true; cgroup_v2 && $IC config set "$n" raw.lxc="lxc.cgroup2.memory.swap.max = $(( v * 1024 * 1024 ))"; fi
        lxc_info_set "$n" SWAP "$v"; restart=1 ;;
      --disk)
        v=$(to_gb "$v") || { err "硬盘格式无效"; return 1; }
        $IC config device set "$n" root size="${v}GiB" || return 1
        lxc_info_set "$n" DISK "$v" ;;
      --net|--net-in|--net-out)
        is_uint "$v" || { err "带宽无效: $v（Mbps，0 不限）"; return 1; }
        ni=$(lxc_info_get "$n" NET_IN); ni=${ni:-$(lxc_info_get "$n" NET)}
        no=$(lxc_info_get "$n" NET_OUT); no=${no:-$(lxc_info_get "$n" NET)}
        case $o in --net) ni=$v; no=$v; lxc_info_set "$n" NET "$v" ;; --net-in) ni=$v ;; *) no=$v ;; esac
        lxc_info_set "$n" NET_IN "${ni:-0}"; lxc_info_set "$n" NET_OUT "${no:-0}"
        lxc_state_load "$n"
        if [[ $S_STATE == limited ]]; then warn "$n 正处于超额限速中，新带宽在流量恢复后生效"
        else lxc_nic_limit "$n" "${ni:-0}" "${no:-0}"; fi ;;
      --io|--read|--write|--iops)
        v=${v,,}
        if [[ $o == --iops ]]; then is_uint "$v" || { err "IOPS 无效: $v"; return 1; }; v="${v}iops"; fi
        [[ $v =~ ^[0-9]+(iops)?$ ]] || { err "读写限速无效: $v（MB/s 写数字，IOPS 写如 1000iops）"; return 1; }
        rd=$(lxc_info_get "$n" READ); rd=${rd:-$(lxc_info_get "$n" IO)}
        wr=$(lxc_info_get "$n" WRITE); wr=${wr:-$(lxc_info_get "$n" IO)}
        case $o in --read) rd=$v ;; --write) wr=$v ;; *) rd=$v; wr=$v ;; esac
        lxc_disk_limit "$n" "$rd" "$wr" || { err "设置硬盘限速失败（当前存储可能不支持）"; return 1; }
        lxc_info_set "$n" READ "${rd:-0}"; lxc_info_set "$n" WRITE "${wr:-0}"
        if [[ $o == --io ]]; then lxc_info_set "$n" IO "$v"; fi ;;
      --procs)
        is_uint "$v" && (( v >= 32 )) || { err "进程数至少 32"; return 1; }
        $IC config set "$n" limits.processes="$v" || return 1 ;;
      --traffic)
        v=$(traffic_gb "$v") || { err "月流量格式无效: $v（如 500、500G、2T，0 不限）"; return 1; }
        lxc_info_set "$n" TRAFFIC "$v"; guard=1 ;;
      --traffic-action)
        [[ $v == limit || $v == stop ]] || { err "超流量处理只能是 limit（限速）或 stop（关机）"; return 1; }
        lxc_info_set "$n" TRAFFIC_ACTION "$v"; guard=1 ;;
      --traffic-count)
        [[ $v =~ ^(both|out|in|max)$ ]] || { err "流量计算方式只能是 both / out / in / max"; return 1; }
        lxc_info_set "$n" TRAFFIC_COUNT "$v"; guard=1 ;;
      --traffic-rate)
        is_uint "$v" && (( v >= 1 )) || { err "超流量后的限速至少 1 Mbps"; return 1; }
        lxc_info_set "$n" TRAFFIC_RATE "$v"
        lxc_state_load "$n"
        if [[ $S_STATE == limited ]]; then lxc_nic_limit "$n" "$v" "$v"; fi ;;
      --reset-day)
        is_uint "$v" && (( v >= 1 && v <= 28 )) || { err "流量重置日应为 1-28"; return 1; }
        lxc_info_set "$n" RESET_DAY "$v"; guard=1 ;;
      --expire)
        v=$(lxc_expire_date "$v") || { err "到期时间无效: $v（YYYY-MM-DD 或 30d，- 表示不限）"; return 1; }
        lxc_info_set "$n" EXPIRE "$v"; guard=1 ;;
      *) err "未知参数: $o"; return 2 ;;
    esac
    changed=1
  done
  if [[ $guard == 1 ]]; then
    if [[ ! -f $LXC_INFO_DIR/$n.txt ]]; then
      warn "$n 不是 nx 创建的小鸡（没有 $LXC_INFO_DIR/$n.txt），流量配额与到期不会生效"
    elif grep -qsE '^(TRAFFIC=[1-9]|EXPIRE=[0-9])' "$LXC_INFO_DIR/$n.txt"; then
      lxc_guard_enable
    fi
    lxc_guard
  fi
  [[ $changed == 1 ]] && ok "已更新 $n 的配置（立即生效）"
  if [[ $restart == 1 ]]; then warn "Swap 上限需要重启小鸡后生效：nx lxc restart $n"; fi
  return 0
}

lxc_info_set() {
  local f="$LXC_INFO_DIR/$1.txt" tmp
  [[ -f $f ]] || return 0
  tmp=$(mktemp)
  # 值经环境变量传入：awk -v 会解释反斜杠转义，密码里的 \ 会被改掉
  NX_V="$3" awk -v k="$2" 'index($0, k "=") == 1 { print k "=" ENVIRON["NX_V"]; done = 1; next } { print }
    END { if (!done) print k "=" ENVIRON["NX_V"] }' "$f" > "$tmp" && cat "$tmp" > "$f"
  rm -f "$tmp"
}

lxc_modify_wizard() {
  local n v
  lxc_pick n || return 1
  title "修改小鸡配置 · $n"
  row "CPU" "$($IC config get "$n" limits.cpu) 核  上限 $($IC config get "$n" limits.cpu.allowance | sed 's/^$/不限/')"
  row "内存" "$($IC config get "$n" limits.memory)"
  row "硬盘" "$($IC config device get "$n" root size 2>/dev/null)"
  row "带宽" "$($IC config device get "$n" eth0 limits.ingress 2>/dev/null | sed 's/^$/不限/')"
  hr
  echo "  直接回车表示不修改"
  local -a args=()
  ask v "CPU 核数" "" && [[ -n $v ]] && args+=(--cpu "$v")
  ask v "CPU 性能上限 %（100 不限）" "" && [[ -n $v ]] && args+=(--cpu-cap "$v")
  ask v "内存 MB" "" && [[ -n $v ]] && args+=(--mem "$v")
  ask v "Swap MB（0 关闭）" "" && [[ -n $v ]] && args+=(--swap "$v")
  ask v "硬盘 GB（只能扩大）" "" && [[ -n $v ]] && args+=(--disk "$v")
  ask v "带宽 Mbps（0 不限）" "" && [[ -n $v ]] && args+=(--net "$v")
  ask v "硬盘 IO MB/s（0 不限）" "" && [[ -n $v ]] && args+=(--io "$v")
  if confirm_opt "修改更多（上下行分开、读写/IOPS、绑核、月流量、到期）?" N; then
    ask v "下行带宽 Mbps" "" && [[ -n $v ]] && args+=(--net-in "$v")
    ask v "上行带宽 Mbps" "" && [[ -n $v ]] && args+=(--net-out "$v")
    ask v "硬盘读限速（MB/s 或如 2000iops）" "" && [[ -n $v ]] && args+=(--read "$v")
    ask v "硬盘写限速（MB/s 或如 1000iops）" "" && [[ -n $v ]] && args+=(--write "$v")
    ask v "绑定 CPU 核（如 0-1,3；- 取消绑定）" "" && [[ -n $v ]] && args+=(--cpu-pin "$v")
    ask v "每月流量 GB（0 不限，可写 2T）" "" && [[ -n $v ]] && args+=(--traffic "$v")
    ask v "超额后 limit（限速）/ stop（关机）" "" && [[ -n $v ]] && args+=(--traffic-action "$v")
    ask v "到期时间（YYYY-MM-DD 或 30d；- 不限）" "" && [[ -n $v ]] && args+=(--expire "$v")
  fi
  [[ ${#args[@]} -gt 0 ]] && lxc_set_cli "$n" "${args[@]}"
}

lxc_snap() { # create|restore|delete|list 名称 [快照名]
  local act=$1 n=$2 s=${3:-}
  lxc_exists "$n" || { err "小鸡不存在"; return 1; }
  case $act in
    create)
      [[ -z $s ]] && s="snap-$(date +%Y%m%d-%H%M%S)"
      if [[ $IC == incus ]]; then incus snapshot create "$n" "$s"; else lxc snapshot "$n" "$s"; fi && ok "已创建快照 $s" ;;
    restore)
      [[ -n $s ]] || { err "需要快照名"; return 1; }
      if [[ $IC == incus ]]; then incus snapshot restore "$n" "$s"; else lxc restore "$n" "$s"; fi && ok "已恢复到 $s" ;;
    delete)
      [[ -n $s ]] || { err "需要快照名"; return 1; }
      if [[ $IC == incus ]]; then incus snapshot delete "$n" "$s"; else lxc delete "$n/$s"; fi && ok "已删除快照 $s" ;;
    list|*)
      if [[ $IC == incus ]]; then incus snapshot list "$n"; else lxc info "$n" | sed -n '/^Snapshots:/,$p'; fi ;;
  esac
}

lxc_rebuild() {
  local n=$1 img=${2:-} pw
  lxc_exists "$n" || { err "小鸡不存在"; return 1; }
  [[ -z $img ]] && img=$($IC config get "$n" user.nx.image)
  [[ -z $img ]] && img=$L_IMAGE
  confirm "重装 $n 为 $img（数据全部清空，配置与端口映射保留）?" N || return 1
  $IC stop -f "$n" >/dev/null 2>&1
  if ! $IC rebuild "$(lxc_remote):$img" "$n" --force 2>/dev/null && ! $IC rebuild "$(lxc_remote):$img" "$n"; then
    err "重装失败（需要 Incus 0.5+ / LXD 5.19+）"; return 1
  fi
  $IC config set "$n" user.nx.image "$img"
  $IC start "$n" || return 1
  mkdir -p "$LXC_INFO_DIR"
  lxc_wait_net "$n" && $IC exec "$n" -- sh -c "$LXC_SSH_SETUP" </dev/null >"$LXC_INFO_DIR/$n.log" 2>&1
  pw=$(lxc_info_get "$n" PASSWORD)
  [[ -z $pw ]] && pw=$(rand_pass 12)
  lxc_set_password "$n" "$pw"
  lxc_info_set "$n" IMAGE "$img"
  lxc_info_set "$n" PASSWORD "$pw"
  ok "已重装 $n 为 $img，root 密码: $pw"
}

lxc_overview() {
  local total run cpu_sum mem_sum disk_sum
  lxc_need || return 1
  title "宿主机资源总览"
  read -r total run cpu_sum mem_sum disk_sum <<<"$($IC list --format json | jq -r '
    def mib: if . == null then 0 elif test("GiB$|GB$") then (sub("GiB$|GB$"; "") | tonumber * 1024)
             elif test("MiB$|MB$") then (sub("MiB$|MB$"; "") | tonumber) else 0 end;
    def gib: if . == null then 0 elif test("GiB$|GB$") then (sub("GiB$|GB$"; "") | tonumber)
             elif test("MiB$|MB$") then (sub("MiB$|MB$"; "") | tonumber / 1024) else 0 end;
    [length, (map(select(.status == "Running")) | length),
     (map(.config["limits.cpu"] // "0" | tonumber? // 0) | add // 0),
     (map(.config["limits.memory"] | mib) | add // 0),
     (map(.expanded_devices.root.size | gib) | add // 0)] | @tsv')"
  row "小鸡数量" "${total:-0} 台（运行 ${run:-0}）"
  row "CPU" "宿主 $(nproc) 核 · 已分配 ${cpu_sum:-0} 核"
  row "内存" "宿主 $(free -m | awk 'NR == 2 {print $2}') MB · 已分配 $(printf '%.0f' "${mem_sum:-0}") MB"
  row "硬盘" "已分配 $(printf '%.0f' "${disk_sum:-0}") GB"
  hr
  $IC storage info default 2>/dev/null | grep -Ei 'space used|total space' | sed 's/^/  /'
  row "网桥" "$LXC_BRIDGE $($IC network get "$LXC_BRIDGE" ipv4.address 2>/dev/null)"
  row "镜像源" "$L_IMAGE_REMOTE"
}

lxc_defaults_menu() {
  lxc_load_conf
  title "开小鸡默认参数"
  ask L_IMAGE "默认镜像" "$L_IMAGE"
  ask L_CPU "CPU 核数" "$L_CPU"
  ask L_CPU_CAP "CPU 性能上限 %" "$L_CPU_CAP"
  ask L_MEM "内存 MB" "$L_MEM"
  ask L_SWAP "Swap MB" "$L_SWAP"
  ask L_DISK "硬盘 GB" "$L_DISK"
  ask L_NET "带宽 Mbps" "$L_NET"
  ask L_IO "硬盘 IO MB/s（0 不限）" "$L_IO"
  ask L_PROCS "进程数上限" "$L_PROCS"
  ask L_SSH_START "SSH 端口起始值" "$L_SSH_START"
  ask L_PORTS "每台额外端口数" "$L_PORTS"
  ask L_IMAGE_REMOTE "镜像源 images / tuna" "$L_IMAGE_REMOTE"
  [[ $L_IMAGE_REMOTE == tuna ]] || L_IMAGE_REMOTE=images
  lxc_save_conf
  ok "已保存到 $LXC_CONF"
}

lxc_images() {
  echo "  常用镜像（images: 远程，可直接用于 --image）："
  echo "    debian/12  debian/13  ubuntu/22.04  ubuntu/24.04  ubuntu/26.04  alpine/3.22  alpine/3.24  alpine/edge"
  echo "    rockylinux/9  rockylinux/10  almalinux/9  almalinux/10  centos/10-Stream  fedora/43  archlinux"
  echo "    opensuse/16.0  openeuler/24.03"
  echo "  完整列表：incus image list images: | less   （镜像源当前为 $L_IMAGE_REMOTE）"
}

lxc_uninstall() {
  local n p others dir=/var/lib/incus
  lxc_detect || { info "未安装 Incus"; return 0; }
  [[ $IC == lxc ]] && dir=/var/snap/lxd/common/lxd
  warn "将删除全部小鸡、镜像、存储池、网桥和 $IC 软件"
  others=$($IC list --format json 2>/dev/null | jq -r '.[] | select(.config["user.nx.image"] == null) | .name' 2>/dev/null | tr '\n' ' ')
  if [[ -n ${others// /} ]]; then warn "其中这些实例不是 NX 创建的，也会一起删除: $others"; fi
  confirm "确认卸载 $IC 环境?" N || return 1
  confirm "再次确认：所有小鸡数据都会丢失?" N || return 1
  info "删除小鸡与镜像..."
  for n in $($IC list --format csv -c n 2>/dev/null); do $IC delete -f "$n" >/dev/null 2>&1; done
  for n in $($IC image list --format csv -c f 2>/dev/null); do $IC image delete "$n" >/dev/null 2>&1; done
  $IC profile device remove default root >/dev/null 2>&1
  $IC profile device remove default eth0 >/dev/null 2>&1
  for p in $($IC network list --format csv 2>/dev/null | awk -F, '$3 == "YES" {print $1}'); do $IC network delete "$p" >/dev/null 2>&1; done
  info "删除存储池..."
  for p in $($IC storage list --format csv 2>/dev/null | cut -d, -f1); do $IC storage delete "$p" >/dev/null 2>&1; done
  if [[ $IC == incus ]]; then
    if has systemctl; then systemctl stop incus.service incus.socket incus-user.socket >/dev/null 2>&1; fi
    if has rc-service; then rc-service incusd stop >/dev/null 2>&1; fi
  fi
  # 兜底：结束残留 dnsmasq、卸载挂载并释放回环设备，否则存储池目录删不掉、重装也会失败
  pkill -f "dnsmasq.*${dir}/networks" 2>/dev/null
  grep -oE "${dir}[^ ]*" /proc/mounts 2>/dev/null | sort -r | while read -r p; do umount -l "$p" 2>/dev/null; done
  losetup -a 2>/dev/null | grep -F "$dir/disks" | cut -d: -f1 | while read -r p; do losetup -d "$p" 2>/dev/null; done
  if [[ $IC == lxc ]]; then
    snap remove --purge lxd >/dev/null 2>&1
  else
    pkg_remove incus incus-client incus-base incus-ui-canonical >/dev/null 2>&1
    rm -rf /var/lib/incus /etc/apt/sources.list.d/zabbly-incus-stable.sources
    # Zabbly 的内核源也用这把密钥
    grep -rqs zabbly.asc /etc/apt/sources.list /etc/apt/sources.list.d/ || rm -f /etc/apt/keyrings/zabbly.asc
  fi
  lxc_guard_disable
  if [[ -f $LXC_DOCKER_DROPIN ]]; then
    rm -f "$LXC_DOCKER_DROPIN"
    rmdir "${LXC_DOCKER_DROPIN%/*}" 2>/dev/null
    systemctl daemon-reload >/dev/null 2>&1
  fi
  if has iptables; then
    iptables -D DOCKER-USER -i "$LXC_BRIDGE" -j ACCEPT 2>/dev/null
    iptables -D DOCKER-USER -o "$LXC_BRIDGE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
  fi
  rm -rf /etc/sysctl.d/99-nx-lxc-ipv6.conf "$LXC_INFO_DIR"
  ip link delete "$LXC_BRIDGE" >/dev/null 2>&1
  if has nft; then nft delete table inet incus >/dev/null 2>&1; nft delete table inet lxd >/dev/null 2>&1; fi
  ok "$IC 环境已卸载"
}

# ------------------------------------------------------------------ 月流量配额 / 到期
LXC_STATE_DIR="$NX_DIR/lxc-guard"
LXC_GUARD_UNIT="nx-lxc-guard"

lxc_nic_limit() { # 名称 下行Mbps 上行Mbps（0 不限），IPv6 网卡一并设置
  local n=$1 d k v
  for d in eth0 eth1; do
    $IC config device get "$n" "$d" type >/dev/null 2>&1 || continue
    for k in ingress egress; do
      if [[ $k == ingress ]]; then v=${2:-0}; else v=${3:-0}; fi
      if [[ $v == 0 ]]; then $IC config device unset "$n" "$d" "limits.$k" >/dev/null 2>&1
      else $IC config device set "$n" "$d" "limits.$k=${v}Mbit" >/dev/null 2>&1; fi
    done
  done
}

lxc_disk_limit() { # 名称 读 写（数字为 MB/s，带 iops 为 IOPS）
  local n=$1 k v
  for k in read write; do
    if [[ $k == read ]]; then v=$(io_lim "$2"); else v=$(io_lim "$3"); fi
    if [[ -z $v ]]; then $IC config device unset "$n" root "limits.$k" >/dev/null 2>&1
    else $IC config device set "$n" root "limits.$k=$v" || return 1; fi
  done
}

lxc_state_load() {
  local f="$LXC_STATE_DIR/$1.state" k v
  S_PERIOD=""; S_PID=0; S_LRX=0; S_LTX=0; S_RX=0; S_TX=0; S_STATE=ok
  [[ -f $f ]] || return 0
  while IFS='=' read -r k v; do
    case $k in PERIOD|PID|LRX|LTX|RX|TX|STATE) printf -v "S_$k" '%s' "$v" ;; esac
  done < "$f"
}

lxc_state_save() {
  mkdir -p "$LXC_STATE_DIR"
  printf 'PERIOD=%s\nPID=%s\nLRX=%s\nLTX=%s\nRX=%s\nTX=%s\nSTATE=%s\n' \
    "$S_PERIOD" "$S_PID" "$S_LRX" "$S_LTX" "$S_RX" "$S_TX" "$S_STATE" > "$LXC_STATE_DIR/$1.state"
}

# 当前计费周期：每月 R 号重置
lxc_period() {
  local r=${1:-1} y m d
  y=$(date +%Y); m=$((10#$(date +%m))); d=$((10#$(date +%d)))
  if (( d < r )); then m=$((m - 1)); if (( m == 0 )); then m=12; y=$((y - 1)); fi; fi
  printf '%d-%02d\n' "$y" "$m"
}

lxc_used_bytes() { # 计算方式 下行字节 上行字节
  case $1 in
    out) echo "$3" ;;
    in) echo "$2" ;;
    max) echo $(( $2 > $3 ? $2 : $3 )) ;;
    *) echo $(( $2 + $3 )) ;;
  esac
}

lxc_guard_log() {
  mkdir -p "$LXC_STATE_DIR"
  echo "$(date '+%F %T') $*" >> "$LXC_STATE_DIR/guard.log"
}

lxc_guard_stop() { $IC stop "$1" --timeout 20 >/dev/null 2>&1 || $IC stop "$1" --force >/dev/null 2>&1; }

# 解除限制：恢复原带宽；被守护任务关掉的小鸡重新开机
lxc_guard_lift() {
  local n=$1 ni no
  ni=$(lxc_info_get "$n" NET_IN); ni=${ni:-$(lxc_info_get "$n" NET)}
  no=$(lxc_info_get "$n" NET_OUT); no=${no:-$(lxc_info_get "$n" NET)}
  if [[ $2 == limited ]]; then lxc_nic_limit "$n" "${ni:-0}" "${no:-0}"; fi
  if [[ $2 == stopped || $2 == expired ]]; then $IC start "$n" >/dev/null 2>&1; fi
}

lxc_guard() {
  local name st pid rx tx per quota used act rate exp today
  lxc_detect || return 0
  if ! grep -qsE '^(TRAFFIC=[1-9]|EXPIRE=[0-9])' "$LXC_INFO_DIR"/*.txt && ! compgen -G "$LXC_STATE_DIR/*.state" >/dev/null; then
    return 0
  fi
  has jq || return 0
  mkdir -p "$LXC_STATE_DIR"
  if has flock; then exec 8>"$LXC_STATE_DIR/.lock"; flock -n 8 || return 0; fi
  today=$(date +%F)
  while IFS=$'\t' read -r name st pid rx tx; do
    [[ -f $LXC_INFO_DIR/$name.txt ]] || continue
    quota=$(lxc_info_get "$name" TRAFFIC); quota=${quota:-0}
    exp=$(lxc_info_get "$name" EXPIRE)
    if [[ $quota == 0 && -z $exp ]]; then
      # 配额和到期都取消了：解除之前的限制
      if [[ -f $LXC_STATE_DIR/$name.state ]]; then
        lxc_state_load "$name"
        if [[ $S_STATE != ok ]]; then lxc_guard_lift "$name" "$S_STATE"; lxc_guard_log "$name 已取消流量配额与到期，已恢复"; fi
        rm -f "$LXC_STATE_DIR/$name.state"
      fi
      continue
    fi
    lxc_state_load "$name"
    # 第一次纳入统计时以当前计数为起点，之前的流量不算
    if [[ ! -f $LXC_STATE_DIR/$name.state ]]; then S_PID=$pid; S_LRX=$rx; S_LTX=$tx; fi
    if [[ $st == Running ]]; then
      # 小鸡重启后网卡计数从 0 开始，用 init 进程号识别
      if [[ $pid != "$S_PID" ]]; then S_LRX=0; S_LTX=0; fi
      if (( rx >= S_LRX )); then S_RX=$(( S_RX + rx - S_LRX )); else S_RX=$(( S_RX + rx )); fi
      if (( tx >= S_LTX )); then S_TX=$(( S_TX + tx - S_LTX )); else S_TX=$(( S_TX + tx )); fi
      S_LRX=$rx; S_LTX=$tx; S_PID=$pid
    fi
    per=$(lxc_period "$(lxc_info_get "$name" RESET_DAY)")
    if [[ $S_PERIOD != "$per" ]]; then
      if [[ $S_STATE == limited || $S_STATE == stopped ]]; then
        lxc_guard_lift "$name" "$S_STATE"; S_STATE=ok
        lxc_guard_log "$name 进入新的流量周期，已恢复"
      fi
      S_PERIOD=$per; S_RX=0; S_TX=0
    fi
    if [[ -n $exp && $today > $exp ]]; then
      if [[ $S_STATE != expired ]]; then lxc_guard_log "$name 已于 $exp 到期，已停机"; fi
      if [[ $S_STATE != expired || $st == Running ]]; then lxc_guard_stop "$name"; fi
      S_STATE=expired
    elif [[ $S_STATE == expired ]]; then
      lxc_guard_lift "$name" expired; S_STATE=ok
      lxc_guard_log "$name 已续期（到期 ${exp:-不限}），已开机"
    fi
    if [[ $S_STATE != expired ]]; then
      used=$(lxc_used_bytes "$(lxc_info_get "$name" TRAFFIC_COUNT)" "$S_RX" "$S_TX")
      if [[ $quota != 0 ]] && (( used >= quota * 1073741824 )); then
        act=$(lxc_info_get "$name" TRAFFIC_ACTION)
        rate=$(lxc_info_get "$name" TRAFFIC_RATE); rate=${rate:-1}
        if [[ $S_STATE == ok && $act == stop ]]; then
          lxc_guard_stop "$name"; S_STATE=stopped
          lxc_guard_log "$name 本周期流量已用完（${quota}GB），已停机"
        elif [[ $S_STATE == ok ]]; then
          lxc_nic_limit "$name" "$rate" "$rate"; S_STATE=limited
          lxc_guard_log "$name 本周期流量已用完（${quota}GB），已限速 ${rate} Mbps"
        elif [[ $S_STATE == stopped && $st == Running ]]; then
          lxc_guard_stop "$name"
        fi
      elif [[ $S_STATE == limited || $S_STATE == stopped ]]; then
        lxc_guard_lift "$name" "$S_STATE"; S_STATE=ok
        lxc_guard_log "$name 流量额度已调整，已恢复"
      fi
    fi
    lxc_state_save "$name"
  done < <($IC query '/1.0/instances?recursion=2' 2>/dev/null | jq -r '.[] | [.name, .status, (.state.pid // 0),
      ([(.state.network // {}) | to_entries[] | select(.key != "lo") | .value.counters.bytes_received // 0] | add // 0),
      ([(.state.network // {}) | to_entries[] | select(.key != "lo") | .value.counters.bytes_sent // 0] | add // 0)] | @tsv')
  # 交互菜单里调用后要释放，否则菜单开着期间定时任务都拿不到锁
  if has flock; then exec 8>&-; fi
}

lxc_guard_enable() {
  [[ -x $NX_BIN ]] || self_install >/dev/null 2>&1
  if has systemctl && [[ -d /run/systemd/system ]]; then
    [[ -f /etc/systemd/system/$LXC_GUARD_UNIT.timer ]] && return 0
    cat > "/etc/systemd/system/$LXC_GUARD_UNIT.service" <<EOF
[Unit]
Description=NX LXC traffic quota and expiry guard

[Service]
Type=oneshot
ExecStart=$NX_BIN lxc guard
EOF
    cat > "/etc/systemd/system/$LXC_GUARD_UNIT.timer" <<EOF
[Unit]
Description=Run NX LXC guard every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$LXC_GUARD_UNIT.timer" >/dev/null 2>&1 && info "已启用流量/到期守护（每分钟检查一次）"
  elif [[ -d /etc/cron.d ]]; then
    echo "* * * * * root $NX_BIN lxc guard >/dev/null 2>&1" > /etc/cron.d/$LXC_GUARD_UNIT
  else
    grep -qs "$NX_BIN lxc guard" /etc/crontabs/root || echo "* * * * * $NX_BIN lxc guard >/dev/null 2>&1" >> /etc/crontabs/root
  fi
}

lxc_guard_disable() {
  if has systemctl; then systemctl disable --now "$LXC_GUARD_UNIT.timer" >/dev/null 2>&1; fi
  rm -f "/etc/systemd/system/$LXC_GUARD_UNIT.service" "/etc/systemd/system/$LXC_GUARD_UNIT.timer" "/etc/cron.d/$LXC_GUARD_UNIT"
  if [[ -f /etc/crontabs/root ]]; then sed -i "\|$NX_BIN lxc guard|d" /etc/crontabs/root; fi
  if has systemctl; then systemctl daemon-reload >/dev/null 2>&1; fi
  rm -rf "$LXC_STATE_DIR"
}

lxc_days_left() {
  local d
  d=$(( ( $(date -d "$1" +%s) - $(date -d "$(date +%F)" +%s) ) / 86400 ))
  if (( d > 0 )); then echo "剩 $d 天"; elif (( d == 0 )); then echo "今天是最后一天"; else echo "已过期 $(( -d )) 天"; fi
}

lxc_count_label() { case $1 in out) echo 只计上行 ;; in) echo 只计下行 ;; max) echo 上下行取大 ;; *) echo 上下行合计 ;; esac; }

lxc_state_cell() { # 状态 宽度：先补齐再上色，颜色码不能算进宽度
  local t c
  case $1 in
    limited) t=超额限速; c=$C_YLW ;;
    stopped) t=超额停机; c=$C_RED ;;
    expired) t=已到期; c=$C_RED ;;
    *) t=正常; c=$C_GRN ;;
  esac
  printf '%s%s%s' "$c" "$(pad "$t" "$2")" "$C_RST"
}

lxc_traffic_show() {
  local n quota exp used
  lxc_need || return 1
  lxc_guard
  printf '  %s%s %s %s %s %s %s %s%s\n' "$C_BLD" "$(pad 名称 14)" "$(pad 周期 8)" "$(pad 下行 10)" "$(pad 上行 10)" \
    "$(pad 已用/额度 22)" "$(pad 状态 8)" "到期" "$C_RST"
  for n in $($IC list --format csv -c n 2>/dev/null); do
    [[ -f $LXC_INFO_DIR/$n.txt ]] || continue
    quota=$(lxc_info_get "$n" TRAFFIC); quota=${quota:-0}
    exp=$(lxc_info_get "$n" EXPIRE)
    lxc_state_load "$n"
    used=$(lxc_used_bytes "$(lxc_info_get "$n" TRAFFIC_COUNT)" "$S_RX" "$S_TX")
    printf '  %-14s %-8s %-10s %-10s %s %s %s\n' "$n" "${S_PERIOD:--}" "$(fmt_bytes "$S_RX")" "$(fmt_bytes "$S_TX")" \
      "$(pad "$([[ $quota == 0 ]] && echo 不限 || echo "$(fmt_bytes "$used") / ${quota}GB")" 22)" \
      "$(lxc_state_cell "$S_STATE" 8)" "${exp:-不限}$([[ -n $exp ]] && echo "（$(lxc_days_left "$exp")）")"
  done
  if [[ -s $LXC_STATE_DIR/guard.log ]]; then
    hr
    echo "  最近记录："
    tail -n 5 "$LXC_STATE_DIR/guard.log" | sed 's/^/    /'
  fi
}

lxc_renew() { # 名称 30d|3m|YYYY-MM-DD|-
  local n=$1 v=${2:-30d} cur base new
  lxc_exists "$n" || { err "小鸡不存在: $n"; return 1; }
  [[ -f $LXC_INFO_DIR/$n.txt ]] || { err "$n 不是 nx 创建的小鸡，没有信息记录"; return 1; }
  cur=$(lxc_info_get "$n" EXPIRE)
  base=$(date +%F)
  if [[ -n $cur && $cur > $base ]]; then base=$cur; fi
  case $v in
    *d) is_uint "${v%d}" && new=$(date -d "$base +${v%d} days" +%F) ;;
    *m) is_uint "${v%m}" && new=$(date -d "$base +${v%m} months" +%F) ;;
    *) new=$(lxc_expire_date "$v") || new="!" ;;
  esac
  [[ $new != "!" && ( -n $new || $v == - || $v == 0 ) ]] || { err "续期时长无效: $v（30d / 3m / YYYY-MM-DD，- 取消到期）"; return 1; }
  lxc_info_set "$n" EXPIRE "$new"
  if [[ -n $new ]]; then lxc_guard_enable; fi
  lxc_guard
  ok "$n 到期时间: ${new:-不限}"
}

lxc_usage() {
  cat <<'EOF'
NX LXC 切小鸡（基于 Incus）

  nx lxc                          交互菜单
  nx lxc install                  安装并初始化 Incus（存储池/网桥/镜像源）
      可免交互: --storage lvm|btrfs|zfs|dir --size 50(GB) --subnet auto|10.66.0.1/24 --mirror images|tuna --repo zabbly|distro
  nx lxc create [名称] [选项]     开小鸡
      --image debian/12   --cpu 1   --cpu-cap 50(%)   --mem 512(M/G)   --swap 256   --disk 10(G)
      --net 100(Mbps)     --io 50(MB/s)   --procs 512   --ssh-port auto|端口   --ports 20|起-止
      --password 密码     --ipv6 on|地址  --nesting on|off  --autostart on|off  --privileged  --no-ssh
    更细的限制：
      --net-in 200 --net-out 50      下行 / 上行分开限速（Mbps）
      --read 100 --write 50          硬盘读 / 写分开限速（MB/s；写成 2000iops 则限 IOPS）  --iops 1000
      --cpu-pin 0-1,3                绑定到指定 CPU 核（核数按列表计算）
      --traffic 500|2T               每月流量（GB），超额后 --traffic-action limit（限速，默认）|stop（关机）
      --traffic-rate 1               超额后的限速 Mbps    --traffic-count both|out|in|max    --reset-day 1（每月几号重置）
      --expire 2026-12-31|30d        到期日，过期后自动停机，续费后自动开机
  nx lxc batch --count 10 [--prefix nat] [同上资源选项]   批量开小鸡
  nx lxc list | info 名称 | start|stop|restart 名称 | delete 名称 [-y] | shell 名称
  nx lxc set 名称 [同 create 的资源 / 限速 / 流量 / 到期选项]   在线修改配置
  nx lxc traffic                  各小鸡本月流量、配额状态与到期时间
  nx lxc renew 名称 [30d|3m|日期|-]  续费：从原到期日顺延（- 取消到期）
  nx lxc port list|add|del 名称 [宿主端口[-止] 小鸡端口[-止] tcp|udp|both | 设备名]
  nx lxc passwd 名称 [新密码]      nx lxc rebuild 名称 [镜像]
  nx lxc snap create|restore|delete|list 名称 [快照名]
  nx lxc overview | images | defaults | uninstall

示例
  nx lxc create web1 --cpu 2 --cpu-cap 50 --mem 1G --swap 512 --disk 20 --net 200 --ports 30
  nx lxc batch --count 10 --prefix nat --mem 256 --disk 5 --net 50 --ports 20
  nx lxc create vip1 --cpu-pin 2-3 --net-in 500 --net-out 100 --read 200 --write 100 --traffic 1T --expire 30d
  nx lxc renew vip1 30d
EOF
}

menu_lxc() {
  local c n v s
  lxc_detect
  lxc_load_conf
  while :; do
    title "LXC 切小鸡（Incus）"
    if [[ -n $IC ]]; then
      row "环境" "$IC $($IC version 2>/dev/null | awk -F': ' '/Server/ {print $2}') · 小鸡 $($IC list --format csv -c n 2>/dev/null | grep -c .) 台 · 镜像源 $L_IMAGE_REMOTE"
    else
      row "环境" "未安装（先执行 1）"
    fi
    hr
    item2 1 "环境安装 / 初始化" 2 "开小鸡（自定义配置）"
    item2 3 "批量开小鸡" 4 "小鸡列表"
    item2 5 "查看小鸡信息（含密码）" 6 "启动 / 停止 / 重启"
    item2 7 "修改配置（资源/限速/配额）" 8 "端口映射管理"
    item2 9 "重置 root 密码" 10 "进入小鸡终端"
    item2 11 "快照管理" 12 "重装系统"
    item2 13 "删除小鸡" 14 "宿主资源总览"
    item2 15 "默认参数设置" 16 "卸载 Incus 环境"
    item 17 "流量统计 / 月流量配额 / 到期续费"
    item 0 "返回"
    read_choice c
    case $c in
      1) lxc_install; pause ;;
      2) lxc_create_wizard; pause ;;
      3) lxc_batch; pause ;;
      4) lxc_list; pause ;;
      5) lxc_need && lxc_pick n && lxc_print_info "$n"; pause ;;
      6)
        lxc_need && lxc_pick n || { pause; continue; }
        ask v "操作 start/stop/restart" "restart" || continue
        case $v in start|stop|restart) $IC "$v" "$n" --force 2>/dev/null || $IC "$v" "$n"; ok "$n: $v";; esac
        pause ;;
      7) lxc_need && lxc_modify_wizard; pause ;;
      8)
        lxc_need && lxc_pick n || { pause; continue; }
        lxc_ports_show "$n"
        ask v "操作 add/del" "add" || continue
        if [[ $v == add ]]; then
          local hp cp proto
          ask hp "宿主端口（如 8080 或 30000-30010）" "" || continue
          ask cp "小鸡内端口" "$hp" || continue
          ask proto "协议 tcp/udp/both" "both" || continue
          lxc_port_add "$n" "$hp" "$cp" "$proto"
        elif [[ $v == del ]]; then
          ask s "设备名（上方列表第一列）" "" && [[ -n $s ]] && $IC config device remove "$n" "$s" && ok "已删除 $s"
        fi
        pause ;;
      9)
        lxc_need && lxc_pick n || { pause; continue; }
        ask v "新密码（回车随机）" "" || continue
        [[ -z $v ]] && v=$(rand_pass 12)
        lxc_set_password "$n" "$v" && lxc_info_set "$n" PASSWORD "$v" && ok "$n 的 root 密码: $v"
        pause ;;
      10) lxc_need && lxc_pick n && { $IC exec "$n" -- bash -l 2>/dev/null || $IC exec "$n" -- sh -l; } ;;
      11)
        lxc_need && lxc_pick n || { pause; continue; }
        lxc_snap list "$n"
        ask v "操作 create/restore/delete" "create" || continue
        ask s "快照名（create 可留空）" "" || continue
        lxc_snap "$v" "$n" "$s"
        pause ;;
      12) lxc_need && lxc_pick n && { ask v "镜像（回车保持原系统）" "" ; lxc_rebuild "$n" "$v"; }; pause ;;
      13) lxc_need && lxc_pick n && lxc_delete "$n"; pause ;;
      14) lxc_overview; pause ;;
      15) lxc_defaults_menu; pause ;;
      16) lxc_uninstall; pause ;;
      17)
        lxc_traffic_show || { pause; continue; }
        hr
        echo "  1) 设置月流量配额   2) 续费 / 设置到期   0) 返回"
        ask v "请选择" "0" || continue
        case $v in
          1) lxc_pick n && ask s "每月流量 GB（0 不限，可写 2T）" "" && [[ -n $s ]] && lxc_set_cli "$n" --traffic "$s" ;;
          2) lxc_pick n && ask s "续费时长（30d / 3m / YYYY-MM-DD，- 取消到期）" "30d" && lxc_renew "$n" "$s" ;;
        esac
        pause ;;
      0|"") return ;;
    esac
  done
}

lxc_cli() {
  local sub a
  local -a args=()
  for a in "$@"; do
    case $a in -y|--yes) ASSUME_YES=1 ;; *) args+=("$a") ;; esac
  done
  set -- "${args[@]}"
  sub=${1:-}
  [[ $# -gt 0 ]] && shift
  case $sub in
    "") menu_lxc ;;
    install) lxc_parse_install_opts "$@" && lxc_install ;;
    init) lxc_parse_install_opts "$@" && lxc_init ;;
    create|new) lxc_create_cli "$@" ;;
    batch) lxc_batch "$@" ;;
    list|ls) lxc_list ;;
    info) lxc_need && lxc_print_info "${1:-}" ;;
    start|stop|restart)
      lxc_need || return 1
      lxc_exists "${1:-}" || { err "小鸡不存在: ${1:-}"; return 1; }
      $IC "$sub" "$1" ;;
    delete|del|rm) lxc_need && lxc_delete "${1:-}" ;;
    set) lxc_need && lxc_set_cli "$@" ;;
    port)
      lxc_need || return 1
      case ${1:-list} in
        list) lxc_ports_show "${2:-}" ;;
        add) lxc_port_add "${2:-}" "${3:-}" "${4:-${3:-}}" "${5:-both}" ;;
        del) $IC config device remove "${2:-}" "${3:-}" ;;
        *) lxc_usage ;;
      esac ;;
    passwd)
      lxc_need || return 1
      local pw=${2:-$(rand_pass 12)}
      lxc_exists "${1:-}" || { err "小鸡不存在"; return 1; }
      lxc_set_password "$1" "$pw" && lxc_info_set "$1" PASSWORD "$pw" && ok "$1 的 root 密码: $pw" ;;
    shell|exec) lxc_need && { $IC exec "${1:-}" -- bash -l 2>/dev/null || $IC exec "${1:-}" -- sh -l; } ;;
    snap) lxc_need && lxc_snap "${1:-list}" "${2:-}" "${3:-}" ;;
    rebuild) lxc_need && lxc_rebuild "${1:-}" "${2:-}" ;;
    overview) lxc_overview ;;
    images) lxc_load_conf; lxc_images ;;
    defaults) lxc_defaults_menu ;;
    uninstall) lxc_uninstall ;;
    guard) lxc_guard ;;
    traffic) lxc_traffic_show ;;
    renew) lxc_need && lxc_renew "${1:-}" "${2:-30d}" ;;
    help|-h|--help) lxc_usage ;;
    *) err "未知子命令: $sub"; lxc_usage; return 2 ;;
  esac
}

# ================================================================== 应用市场
# 均调用各项目官方脚本或官方镜像；GitHub 上的脚本在国内自动走加速代理
APP_DIR="$NX_DIR/apps"
APP_HINT=""

app_official() { # app_official 名称 来源：安装前确认
  title "安装 $1"
  row "来源" "$2"
  hr
  confirm "运行 $1 官方一键脚本?" Y
}

# 已安装就打开它自带的管理命令，否则运行官方脚本
app_gh() { # app_gh 名称 管理命令 脚本URL
  if [[ -n $2 ]] && has "$2"; then info "$1 已安装，打开它的管理菜单（以后可直接输入 $2）"; "$2"; return; fi
  app_official "$1" "$3" || return 1
  run_remote "$3"
}

app_1panel() {
  local c
  if has 1pctl; then
    title "1Panel（已安装）"
    item 1 "查看面板地址与账号"
    item 2 "修改面板密码"
    item 3 "卸载 1Panel"
    item 0 "返回"
    read_choice c
    case $c in 1) 1pctl user-info ;; 2) 1pctl update password ;; 3) 1pctl uninstall ;; esac
    return 0
  fi
  app_official 1Panel "https://1panel.cn（resource.fit2cloud.com 官方脚本）" || return 1
  run_cmd 'bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"'
}

app_bt() { # cn | en
  local c
  if has bt; then
    title "宝塔 / aaPanel（已安装）"
    item 1 "打开 bt 管理菜单"
    item 2 "卸载面板"
    item 0 "返回"
    read_choice c
    case $c in
      1) bt ;;
      2) confirm "卸载面板（网站与数据库请先备份）?" N && run_cmd 'cd /tmp && curl -fsSLO https://download.bt.cn/install/bt-uninstall.sh && bash bt-uninstall.sh' ;;
    esac
    return 0
  fi
  if [[ $1 == en ]]; then
    app_official aaPanel "https://www.aapanel.com（宝塔国际版）" || return 1
    run_cmd 'cd /tmp && curl -ksSO https://www.aapanel.com/script/install_7.0_en.sh && bash install_7.0_en.sh aapanel'
  else
    app_official 宝塔面板 "https://www.bt.cn" || return 1
    run_cmd 'cd /tmp && curl -sSO https://download.bt.cn/install/install_panel.sh && bash install_panel.sh ed8484bec'
  fi
}

# v2ray-agent 只有从 /root/install.sh 运行时才会建立 vasma 快捷命令
app_v2ray_agent() {
  if has vasma; then info "v2ray-agent 已安装，打开管理菜单（以后可直接输入 vasma）"; vasma; return; fi
  app_official "v2ray-agent 八合一" "https://github.com/mack-a/v2ray-agent" || return 1
  gh_dl https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh /root/install.sh 120 || { err "下载失败"; return 1; }
  chmod 700 /root/install.sh && /root/install.sh
}

# docker_app 容器名 镜像 默认端口 容器端口 [docker run 额外参数...]
docker_app() {
  local name=$1 img=$2 dport=$3 cport=$4 port c host
  shift 4
  host=$(public_ipv4 2>/dev/null || main_ipv4_local)
  if has docker && docker inspect "$name" >/dev/null 2>&1; then
    port=$(cat "$APP_DIR/$name.port" 2>/dev/null)
    [[ -n $port ]] || port=$(docker port "$name" "$cport/tcp" 2>/dev/null | head -n1 | awk -F: '{print $NF}')
    title "$name（已安装）"
    row "状态" "$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)"
    row "访问" "http://$host:${port:-?}"
    row "数据" "/home/docker/$name"
    if [[ -n $APP_HINT ]]; then row "提示" "$APP_HINT"; fi
    hr
    item 1 "更新（拉取最新镜像并重建，数据保留）"
    item 2 "重启"
    item 3 "卸载"
    item 0 "返回"
    read_choice c
    case $c in
      1)
        docker pull "$img" || return 1
        docker rm -f "$name" >/dev/null
        docker run -d --name "$name" --restart=always -p "${port:-$dport}:$cport" "$@" "$img" >/dev/null && ok "$name 已更新" ;;
      2) docker restart "$name" >/dev/null && ok "$name 已重启" ;;
      3)
        confirm "卸载 $name?" N || return 0
        docker rm -f "$name" >/dev/null
        if confirm_opt "同时删除数据目录 /home/docker/$name?" N; then rm -rf "/home/docker/$name"; fi
        if [[ -n $port ]]; then fw_close "$port" tcp; fi
        rm -f "$APP_DIR/$name.port"
        ok "$name 已卸载" ;;
    esac
    return 0
  fi
  title "安装 $name"
  row "镜像" "$img"
  hr
  if ! has docker; then
    confirm "需要先安装 Docker，现在安装?" Y || return 1
    docker_install || return 1
  fi
  ask port "访问端口" "$dport" || return 1
  is_port "$port" || { err "端口无效: $port"; return 1; }
  if port_in_use "$port"; then err "端口 $port 已被占用"; return 1; fi
  mkdir -p "/home/docker/$name" "$APP_DIR"
  info "拉取镜像并启动..."
  docker run -d --name "$name" --restart=always -p "$port:$cport" "$@" "$img" >/dev/null || { err "启动失败"; return 1; }
  echo "$port" > "$APP_DIR/$name.port"
  fw_open "$port" tcp
  ok "$name 已启动：http://$host:$port"
  if [[ -n $APP_HINT ]]; then info "$APP_HINT"; fi
  warn "云服务器还需在安全组放行 $port/tcp"
}

app_run() { # 菜单编号或应用名
  APP_HINT=""
  case $1 in
    1|1panel) app_1panel ;;
    2|bt|baota) app_bt cn ;;
    3|aapanel) app_bt en ;;
    4|portainer)
      APP_HINT="首次打开需在 5 分钟内创建管理员，超时执行 docker restart portainer"
      docker_app portainer portainer/portainer-ce:lts 9000 9000 -v /var/run/docker.sock:/var/run/docker.sock -v /home/docker/portainer:/data ;;
    5|3x-ui|3xui|x-ui) app_gh 3x-ui x-ui https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh ;;
    6|sing-box|sb) app_gh "sing-box 四合一" sb https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh ;;
    7|v2ray-agent|vasma) app_v2ray_agent ;;
    8|warp) app_gh WARP warp https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh ;;
    9|nezha) app_gh 哪吒监控 "" https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh ;;
    10|kuma|uptime-kuma) docker_app uptime-kuma louislam/uptime-kuma:latest 3001 3001 -v /home/docker/uptime-kuma:/app/data ;;
    11|openlist|alist)
      APP_HINT="生成管理员密码: docker exec openlist ./openlist admin random"
      # 4.1 起镜像以 UID 1001 运行，数据目录必须归它所有
      mkdir -p /home/docker/openlist && chown -R 1001:1001 /home/docker/openlist
      docker_app openlist openlistteam/openlist:latest-aria2 5244 5244 -v /home/docker/openlist:/opt/openlist/data ;;
    *) err "未知应用: $1（可用: 1panel bt aapanel portainer 3x-ui sing-box v2ray-agent warp nezha kuma openlist）"; return 2 ;;
  esac
}

menu_apps() {
  local c
  while :; do
    title "应用市场"
    printf '  %s面板%s\n' "$C_GRY" "$C_RST"
    item2 1 "1Panel 运维面板" 2 "宝塔面板（国内版）"
    item2 3 "aaPanel（宝塔国际版）" 4 "Portainer（Docker 图形管理）"
    printf '  %s代理 / 网络%s\n' "$C_GRY" "$C_RST"
    item2 5 "3x-ui（Xray 多协议面板）" 6 "sing-box 四合一（fscarmen）"
    item2 7 "v2ray-agent 八合一（mack-a）" 8 "WARP（解锁流媒体 / 补 IPv4、IPv6）"
    printf '  %s监控 / 工具%s\n' "$C_GRY" "$C_RST"
    item2 9 "哪吒监控（面板 / Agent）" 10 "Uptime Kuma（网站可用性监控）"
    item 11 "OpenList（网盘挂载与文件列表，Alist 社区版）"
    hr
    printf '  %s已安装的应用再次进入即为管理 / 更新 / 卸载%s\n' "$C_GRY" "$C_RST"
    item 0 "返回"
    read_choice c
    case $c in
      0|"") return ;;
      *) app_run "$c"; pause ;;
    esac
  done
}

# ================================================================== 一条龙调优
TUNE_ALL=(update clean swap ssh f2b openall bbr tz dns v4 tools kernel)
TUNE_SSH_PORT=5522

# 改 SSH 端口和开放所有端口默认不勾选：前者要先放行安全组，后者会停用防火墙
tune_defaults() {
  declare -gA TUNE_ON=([update]=1 [clean]=1 [swap]=1 [ssh]=0 [f2b]=1 [openall]=0 [bbr]=1 [tz]=1 [dns]=1 [v4]=1 [tools]=1 [kernel]=1)
}

tune_label() {
  case $1 in
    update) echo "更新系统软件包" ;;
    clean) echo "清理系统垃圾" ;;
    swap) echo "Swap 设为 1G（已有 swap 或容器虚拟化时跳过）" ;;
    ssh) echo "SSH 端口改为 $TUNE_SSH_PORT（需先在安全组放行）" ;;
    f2b) echo "fail2ban 防 SSH 暴力破解" ;;
    openall) echo "开放所有端口（停用 ufw / firewalld）" ;;
    bbr) echo "开启 BBR + fq" ;;
    tz) echo "时区设为 Asia/Shanghai" ;;
    dns) echo "DNS 自动优选（国内 223.5.5.5 / 海外 1.1.1.1 8.8.8.8）" ;;
    v4) echo "IPv4 优先" ;;
    tools) echo "常用工具 curl wget sudo tar unzip socat htop nano vim" ;;
    kernel) echo "内核网络参数优化（缓冲区 / 队列 / 连接数）" ;;
  esac
}

tune_step() {
  case $1 in
    update) sys_update ;;
    clean) sys_clean ;;
    swap)
      if (( $(awk '/^SwapTotal/ {print $2}' /proc/meminfo) > 0 )); then info "已有 swap，跳过"; return 0; fi
      case $(virt_type) in openvz|lxc) info "容器虚拟化无法自建 swap，跳过"; return 0 ;; esac
      swap_set 1024 ;;
    ssh) ssh_change_port "$TUNE_SSH_PORT" ;;
    f2b) f2b_install ;;
    openall) firewall_open_all ;;
    bbr)
      case $(virt_type) in
        openvz|lxc) bbr_supported || { info "宿主机没有开启 BBR，容器内无法开启，跳过"; return 0; } ;;
      esac
      bbr_enable ;;
    tz) tz_set Asia/Shanghai ;;
    dns)
      if in_china; then dns_set "223.5.5.5 119.29.29.29" "2400:3200::1 2402:4e00::"
      else dns_set "1.1.1.1 8.8.8.8" "2606:4700:4700::1111 2001:4860:4860::8888"; fi ;;
    v4)
      if is_musl; then info "musl 系统不支持 gai.conf，跳过"; return 0; fi
      ip_priority v4 ;;
    tools) install_list curl wget sudo tar unzip socat htop nano vim ;;
    kernel) net_optimize ;;
  esac
}

# 依次执行，单项失败不影响后续
tune_run() {
  local s i=0 okn=0
  local -a res=()
  for s in "$@"; do
    i=$((i + 1))
    printf '\n  %s[%d/%d] %s%s\n' "$C_BLD" "$i" "$#" "$(tune_label "$s")" "$C_RST"
    if tune_step "$s"; then
      okn=$((okn + 1)); res+=("${C_GRN}✓${C_RST} $(tune_label "$s")")
    else
      res+=("${C_RED}✗${C_RST} $(tune_label "$s")")
    fi
  done
  title "一条龙调优结果"
  printf '  %s\n' "${res[@]}"
  ok "完成 $okn / $# 项"
}

tune_selected() { local s; for s in "${TUNE_ALL[@]}"; do if [[ ${TUNE_ON[$s]} == 1 ]]; then echo "$s"; fi; done; }

menu_tune() {
  local c x s i
  local -a sel
  tune_defaults
  while :; do
    title "一条龙系统调优"
    i=0
    for s in "${TUNE_ALL[@]}"; do
      i=$((i + 1))
      printf '  %s%2d%s  [%s]  %s\n' "$C_CYN" "$i" "$C_RST" "$([[ ${TUNE_ON[$s]} == 1 ]] && echo "${C_GRN}✓${C_RST}" || echo ' ')" "$(tune_label "$s")"
    done
    hr
    echo "  输入编号切换勾选（可多个，空格分隔）；直接回车开始执行；0 返回"
    read -r -p "  > " c || return
    [[ $c == 0 ]] && return
    if [[ -z $c ]]; then
      mapfile -t sel < <(tune_selected)
      if [[ ${#sel[@]} -eq 0 ]]; then warn "没有勾选任何项目"; continue; fi
      confirm "开始执行 ${#sel[@]} 项调优?" Y || continue
      tune_run "${sel[@]}"
      pause
      return
    fi
    for x in $c; do
      is_uint "$x" && (( x >= 1 && x <= ${#TUNE_ALL[@]} )) || continue
      s=${TUNE_ALL[x - 1]}
      if [[ ${TUNE_ON[$s]} == 1 ]]; then TUNE_ON[$s]=0; else TUNE_ON[$s]=1; fi
      if [[ $s == ssh && ${TUNE_ON[ssh]} == 1 ]]; then
        ask TUNE_SSH_PORT "SSH 新端口" "$TUNE_SSH_PORT"
        is_port "$TUNE_SSH_PORT" || { warn "端口无效，恢复为 5522"; TUNE_SSH_PORT=5522; }
      fi
    done
  done
}

tune_cli() { # nx tune [--all] [--with a,b] [--skip a,b] [--ssh-port N] [-y]
  local s x
  local -a sel
  tune_defaults
  while [[ $# -gt 0 ]]; do
    case $1 in
      --all) for s in "${TUNE_ALL[@]}"; do TUNE_ON[$s]=1; done ;;
      --with|--skip)
        [[ $# -ge 2 ]] || { err "参数 $1 缺少值"; return 2; }
        for x in ${2//,/ }; do
          [[ -n ${TUNE_ON[$x]+x} ]] || { err "未知项目: $x（可选: ${TUNE_ALL[*]}）"; return 2; }
          if [[ $1 == --with ]]; then TUNE_ON[$x]=1; else TUNE_ON[$x]=0; fi
        done
        shift ;;
      --ssh-port)
        is_port "${2:-}" || { err "SSH 端口无效: ${2:-}"; return 2; }
        TUNE_SSH_PORT=$2; TUNE_ON[ssh]=1; shift ;;
      -y|--yes) ASSUME_YES=1 ;;
      *) err "未知参数: $1"; return 2 ;;
    esac
    shift
  done
  mapfile -t sel < <(tune_selected)
  [[ ${#sel[@]} -gt 0 ]] || { warn "没有选择任何项目"; return 1; }
  title "一条龙系统调优"
  for s in "${sel[@]}"; do echo "  · $(tune_label "$s")"; done
  confirm "执行以上 ${#sel[@]} 项?" Y || return 1
  tune_run "${sel[@]}"
}

# ================================================================== 集成项目
psl_run() {
  if [[ -x $PSL_BIN ]]; then "$PSL_BIN"; return; fi
  info "首次使用：下载 vps-PSL 端口限速（NX2406/vps-PSL），运行后会安装 PSL / psl 命令"
  run_remote "$PSL_RAW_URL"
}

nxr_install() {
  local tmp
  tmp=$(mktemp)
  info "安装 Realm 转发面板 nxr（NX2406/nx-realm）"
  if gh_dl "$NXR_RAW_URL" "$tmp" 60 && grep -q '^NXR_VERSION=' "$tmp" && bash -n "$tmp" 2>/dev/null; then
    install -m 755 "$tmp" "$NXR_BIN"
    rm -f "$tmp"
    ok "nxr 已安装，之后可直接输入 nxr 打开"
    return 0
  fi
  rm -f "$tmp"
  err "下载 nxr 失败：$NXR_RAW_URL"
  return 1
}

nxr_run() {
  if [[ ! -x $NXR_BIN ]]; then nxr_install || return 1; fi
  "$NXR_BIN" "$@"
}

# ================================================================== 安装 / 更新 / 卸载
# 下载的脚本是否完整可用（最后一行必须是入口调用）
script_ok() {
  grep -q '^NX_VERSION=' "$1" && bash -n "$1" 2>/dev/null && [[ $(tail -n 1 "$1") == 'main "$@"' ]]
}

# self_install [--force]：不会用旧版本覆盖已安装的新版本（--force 除外）
self_install() {
  local src=${BASH_SOURCE[0]} tmp cur force=0
  [[ ${1:-} == --force ]] && force=1
  cur=$(grep -m1 '^NX_VERSION=' "$NX_BIN" 2>/dev/null | cut -d'"' -f2)
  if [[ -f $src && -r $src ]]; then
    [[ $src -ef $NX_BIN ]] && return 0
    cmp -s "$src" "$NX_BIN" 2>/dev/null && return 0
    if [[ $force != 1 && -n $cur ]] && ver_gt "$cur" "$NX_VERSION"; then
      warn "已安装的 nx $cur 比当前脚本 $NX_VERSION 新，未覆盖（确需降级: bash $src install --force）"
      return 0
    fi
    install -m 755 "$src" "$NX_BIN" && info "已安装快捷命令 nx $NX_VERSION（$NX_BIN）"
    return 0
  fi
  if [[ -n $cur ]] && ! ver_gt "$NX_VERSION" "$cur"; then return 0; fi
  tmp=$(mktemp)
  if gh_dl "$NX_RAW_URL" "$tmp" 60 && script_ok "$tmp"; then
    install -m 755 "$tmp" "$NX_BIN" && info "已安装快捷命令 nx（$NX_BIN）"
  else
    warn "快捷命令安装失败：无法下载 $NX_RAW_URL"
  fi
  rm -f "$tmp"
}

nx_update() {
  local tmp newv
  tmp=$(mktemp)
  info "下载最新版 NX 工具箱"
  if ! gh_dl "$NX_RAW_URL" "$tmp" 60; then rm -f "$tmp"; err "下载失败"; return 1; fi
  if ! script_ok "$tmp"; then rm -f "$tmp"; err "下载内容不完整或校验失败，未更新"; return 1; fi
  newv=$(grep -m1 '^NX_VERSION=' "$tmp" | cut -d'"' -f2)
  if ! install -m 755 "$tmp" "$NX_BIN"; then rm -f "$tmp"; err "写入 $NX_BIN 失败"; return 1; fi
  rm -f "$tmp"
  ok "NX 工具箱已更新：$NX_VERSION → $newv"
  if [[ -x $NXR_BIN ]] && confirm "同时更新 Realm 转发面板 nxr?" Y; then "$NXR_BIN" update; fi
  if [[ -t 0 ]]; then exec "$NX_BIN"; fi
}

nx_uninstall() {
  local f
  title "卸载 NX 工具箱"
  echo "  将删除 nx 命令及其快捷方式。以下独立组件不会被删除，可各自卸载："
  echo "    · Realm 转发面板：nxr → 99"
  echo "    · 端口限速：PSL → 10"
  echo "    · LXC 小鸡：nx lxc uninstall"
  confirm "确认卸载 NX 工具箱?" N || return 1
  for f in /usr/local/bin/* /usr/bin/*; do
    if [[ -L $f && $(readlink -f "$f") == "$NX_BIN" ]]; then rm -f "$f"; fi
  done
  if confirm_opt "同时删除 NX 生成的系统优化配置（BBR/网络优化/limits）?" N; then net_restore; fi
  if [[ -f /etc/systemd/system/$LXC_GUARD_UNIT.timer || -f /etc/cron.d/$LXC_GUARD_UNIT ]] || grep -qs "$NX_BIN lxc guard" /etc/crontabs/root; then
    lxc_guard_disable
    warn "小鸡的月流量配额与到期守护依赖 nx 命令，已一并停用"
  fi
  rm -rf "$NX_DIR"
  rm -f "$NX_BIN"
  ok "NX 工具箱已卸载"
  exit 0
}

# ================================================================== 主菜单
banner() {
  printf '%s' "$C_CYN"
  cat <<'EOF'
   _   ___  __
  | \ | \ \/ /
  |  \| |\  /    Linux VPS 常用脚本合集
  | |\  |/  \    vps-PSL · ovhroot · LXC 切小鸡 · Realm 转发面板
  |_| \_/_/\_\
EOF
  printf '%s' "$C_RST"
  printf '  %sNX 工具箱%s v%s    %s命令行输入 nx 可快速启动%s\n' "$C_BLD" "$C_RST" "$NX_VERSION" "$C_YLW" "$C_RST"
  printf '  %s%s · %s · %s · 负载 %s%s\n' "$C_GRY" "$OS_NAME" "$(uname -m)" "$(virt_type)" "$(awk '{print $1}' /proc/loadavg)" "$C_RST"
}

menu_main() {
  local c nxr_state
  while :; do
    clear_screen
    banner
    hr
    item2 1 "系统信息查询" 2 "系统更新"
    item2 3 "系统清理" 4 "常用工具安装"
    item2 5 "BBR / 网络优化" 6 "Docker 管理"
    item2 7 "测试脚本合集" 8 "系统工具"
    item2 12 "应用市场（面板/代理/监控）" 13 "一条龙系统调优"
    hr
    item2 9 "Root 登录开启（ovhroot）" 10 "端口限速（vps-PSL）"
    item 11 "LXC 切小鸡（Incus · CPU/内存/硬盘/带宽/IO/端口/IPv6/月流量/到期）"
    hr
    if [[ -x $NXR_BIN ]]; then nxr_state="${C_GRN}已安装${C_RST}"; else nxr_state="${C_YLW}★ 独立项目${C_RST}"; fi
    printf '  %s%-4s%s %s%s%s  %s\n' "$C_YLW" "20" "$C_RST" "$C_BLD" "Realm 转发面板 nxr" "$C_RST" "$nxr_state"
    printf '       %s一个前置 · 多个 IX · 多个出口，多节点链路一键创建，独立命令 nxr%s\n' "$C_GRY" "$C_RST"
    hr
    item2 00 "更新脚本" 99 "卸载工具箱"
    item 0 "退出"
    hr
    read_choice c
    case $c in
      1) sys_info; pause ;;
      2) title "系统更新"; sys_update; pause ;;
      3) title "系统清理"; sys_clean; pause ;;
      4) menu_tools ;;
      5) menu_bbr ;;
      6) menu_docker ;;
      7) menu_tests ;;
      8) menu_system ;;
      9) menu_root ;;
      10) psl_run; pause ;;
      11) menu_lxc ;;
      12) menu_apps ;;
      13) menu_tune ;;
      20) nxr_run ;;
      00) nx_update; pause ;;
      99) nx_uninstall; pause ;;
      0) exit 0 ;;
    esac
  done
}

usage() {
  cat <<EOF
NX 工具箱 v$NX_VERSION · Linux VPS 常用脚本合集

用法: nx [命令]          不带参数进入交互菜单

  info                  系统信息
  update | clean        系统更新 / 系统清理
  bbr                   开启 BBR + fq
  optimize              网络参数优化（代理/转发节点）
  swap <MB>             设置 swap 大小（0 删除）
  ssh-port <端口>       修改 SSH 端口（自动放行防火墙/SELinux，失败回滚）
  root [--password [密码]]   开启 root 登录（ovhroot 增强版，默认同步 sudo 用户公钥）
  f2b                   安装/配置 fail2ban SSH 防爆破
  docker                安装 Docker
  tz <时区>             设置时区，如 nx tz Asia/Shanghai
  hostname <名称>       修改主机名
  tune [--all] [--with ssh,openall] [--skip swap] [--ssh-port 5522] [-y]
                        一条龙调优：更新/清理/swap/fail2ban/BBR/时区/DNS/IPv4 优先/常用工具/内核参数
  app [名称]            应用市场：1panel bt aapanel portainer 3x-ui sing-box v2ray-agent warp nezha kuma openlist
  psl                   端口限速 vps-PSL
  lxc [子命令]          LXC 切小鸡，详见 nx lxc help
  realm | r [参数]      Realm 转发面板 nxr（独立项目，参数透传给 nxr）
  dd                    一键 DD 重装系统
  upgrade               更新工具箱      uninstall   卸载工具箱
  version | help

  任意命令加 -y / --yes 跳过确认（realm 的参数原样交给 nxr）

一键运行:
  bash <(curl -sL $NX_RAW_URL)
EOF
}

main() {
  local cmd a
  local -a args=()
  case ${1:-} in
    realm|r|nxr) ;;
    *)
      for a in "$@"; do
        case $a in -y|--yes) ASSUME_YES=1 ;; *) args+=("$a") ;; esac
      done
      set -- "${args[@]}" ;;
  esac
  cmd=${1:-}
  [[ $# -gt 0 ]] && shift
  case $cmd in
    version|-v|--version) echo "nx $NX_VERSION"; return 0 ;;
    help|-h|--help) usage; return 0 ;;
  esac
  need_root
  detect_os
  mkdir -p "$NX_DIR"
  GH_PROXY=$(nx_conf_get GH_PROXY)
  GH_PROXY=${GH_PROXY:-auto}
  ensure_ss >/dev/null 2>&1
  case $cmd in
    "")
      if [[ ! -t 0 ]]; then exec </dev/tty || die "请在交互终端中运行：bash <(curl -sL $NX_RAW_URL)"; fi
      self_install >/dev/null 2>&1
      menu_main ;;
    info) sys_info ;;
    update) sys_update ;;
    clean) sys_clean ;;
    bbr) bbr_enable ;;
    optimize|net-opt) net_optimize ;;
    swap) swap_set "${1:-1024}" ;;
    ssh-port) ssh_change_port "${1:-}" ;;
    root)
      if [[ ${1:-} == --password ]]; then root_login password "${2:-}"; else root_login key; fi ;;
    f2b|fail2ban) f2b_install ;;
    docker) docker_install ;;
    tz) tz_set "${1:-Asia/Shanghai}" ;;
    hostname) hostname_set "${1:-}" ;;
    psl|PSL) psl_run ;;
    tune) tune_cli "$@" ;;
    app|apps) if [[ -n ${1:-} ]]; then app_run "$1"; else menu_apps; fi ;;
    lxc) lxc_cli "$@" ;;
    realm|r|nxr) nxr_run "$@" ;;
    dd) menu_dd ;;
    install) self_install --force ;;
    upgrade|self-update) nx_update ;;
    uninstall) nx_uninstall ;;
    *) err "未知命令: $cmd"; usage; return 2 ;;
  esac
}

if [[ -n ${BASH_SOURCE[0]:-} && ${BASH_SOURCE[0]} != "$0" ]]; then return 0 2>/dev/null; fi
main "$@"
