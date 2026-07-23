#!/bin/bash
# ==============================================================================
# ARX5-SDK-V2 一键环境配置 (封装发行版)
#
#   ./setup.sh              配置环境 (缺什么装什么, 已装的跳过)
#   ./setup.sh --check      只体检不安装 (看哪步有问题)
#   ./setup.sh --force      强制重装 Python 依赖
#   ./setup.sh --mirror     用国内镜像源 (清华) —— 国内网络强烈建议
#   ./setup.sh --mirror=URL 用指定源
#
# 设计: 不用 set -e —— 一步失败继续跑完剩下的, 最后一次性列出所有问题。
# 详细日志: setup.log
#
# 注: pin (Pinocchio) 全家桶约 200MB+。国内直连 PyPI 约 150KB/s -> 半小时;
#     换清华源通常几分钟。
# ==============================================================================

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG="$HERE/setup.log"
: > "$LOG"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[0;33m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'

CHECK_ONLY=0; FORCE=0; MIRROR=""
TSINGHUA="https://pypi.tuna.tsinghua.edu.cn/simple"
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    --mirror) MIRROR="$TSINGHUA" ;;
    --mirror=*) MIRROR="${a#--mirror=}" ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "未知参数: $a (用 --help 看用法)"; exit 1 ;;
  esac
done

STEP=0; TOTAL=5
FAILED=(); FIXES=()

step() { STEP=$((STEP+1)); printf "\n${BOLD}[%d/%d] %s${NC}\n" "$STEP" "$TOTAL" "$1"; }
ok()   { printf "      ${GRN}✓${NC} %s\n" "$1"; }
warn() { printf "      ${YEL}!${NC} %s\n" "$1"; }
bad()  { printf "      ${RED}✗${NC} %s\n" "$1"; }
info() { printf "      ${DIM}%s${NC}\n" "$1"; }
fail() { bad "$1"; FAILED+=("[$STEP] $2"); FIXES+=("$3"); }
log()  { echo "$@" >> "$LOG" 2>&1; }

py_has() { python3 -c "import $1" >/dev/null 2>&1; }
py_ver() { python3 -c "import $1,sys; print(getattr($1,'__version__','?'))" 2>/dev/null; }

# PEP 668 (Ubuntu 24.04+): 系统 Python 受管控, 必须 --break-system-packages
PIP_FLAGS="--user"
if [ -f "/usr/lib/python3/dist-packages/EXTERNALLY-MANAGED" ] || \
   python3 -c "import sysconfig,os,sys; sys.exit(0 if os.path.exists(os.path.join(sysconfig.get_path('stdlib'), 'EXTERNALLY-MANAGED')) else 1)" 2>/dev/null; then
  PIP_FLAGS="--user --break-system-packages"
fi

pip_install() {
  local pkg="$1"
  local mflag=""
  [ -n "$MIRROR" ] && mflag="-i $MIRROR"
  log "=== pip install $mflag $pkg ==="
  if [ -t 1 ]; then
    # 终端下让 pip 直写 stdout —— 它自带下载进度条 (装 pin 那 200MB 全程可见)。
    # 经过管道 pip 会检测到非 TTY 而自动关掉进度条, 所以不能 tee。
    # stderr 走进程替换: 屏幕和日志两边都有, 失败时不至于黑屏干等。
    # shellcheck disable=SC2086
    python3 -m pip install $PIP_FLAGS $mflag $pkg 2> >(tee -a "$LOG" >&2)
    return $?
  fi
  # 非终端 (输出被重定向/自动化): 走日志 + 关键行过滤
  # stdbuf -oL: 关掉块缓冲, 否则进度要等装完才一次性吐出来 (看着像卡死)
  # shellcheck disable=SC2086
  stdbuf -oL -eL python3 -m pip install $PIP_FLAGS $mflag $pkg 2>&1 \
    | tee -a "$LOG" \
    | grep -E --line-buffered "Downloading|Installing collected|Successfully|error|ERROR" \
    | sed 's/^/      /'
  return "${PIPESTATUS[0]}"
}

# pip 缺失时自动安装, 三级回退:
#   ① apt (Ubuntu/Debian 正道, 要输一次 sudo 密码)
#   ② ensurepip (Debian 系默认禁用, 但其他发行版/自编译 Python 可用)
#   ③ get-pip.py (官方引导脚本, 只装到 ~/.local, 不碰系统目录)
install_pip() {
  if command -v apt-get >/dev/null; then
    info "尝试 sudo apt-get install -y python3-pip (可能要输密码)"
    sudo apt-get install -y python3-pip >>"$LOG" 2>&1
    python3 -m pip --version >/dev/null 2>&1 && return 0
    warn "apt 安装未成功 (无 sudo 权限或无网?), 换下一种方式"
  fi
  python3 -m ensurepip --upgrade >>"$LOG" 2>&1
  python3 -m pip --version >/dev/null 2>&1 && return 0
  local gflags="$PIP_FLAGS"
  # venv 里 --user 不可用 (装进 venv 自身即可)
  python3 -c "import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)" 2>/dev/null \
    && gflags=""
  local gp="/tmp/get-pip-$$.py"
  local url="https://bootstrap.pypa.io/pip/get-pip.py"
  info "尝试官方 get-pip.py"
  if curl -fsSL "$url" -o "$gp" 2>>"$LOG" || wget -q "$url" -O "$gp" 2>>"$LOG"; then
    # shellcheck disable=SC2086
    python3 "$gp" $gflags >>"$LOG" 2>&1
    rm -f "$gp"
    python3 -m pip --version >/dev/null 2>&1 && return 0
  fi
  return 1
}

printf "\n${BOLD}╔════════════════════════════════════════════╗${NC}\n"
printf   "${BOLD}║   ARX5-SDK-V2 环境配置 (封装发行版)        ║${NC}\n"
printf   "${BOLD}╚════════════════════════════════════════════╝${NC}\n"
[ "$CHECK_ONLY" = 1 ] && info "(--check 模式: 只体检, 不安装)"

# ─── 1. 系统 + Python 版本 (必须匹配 .so 绑定的版本) ─────────────────────────
step "系统 / Python 版本"

# 从 .so 文件名解析本发行版绑定的 CPython 版本与架构, 如
#   __init__.cpython-312-x86_64-linux-gnu.so -> 需要 Python 3.12 + x86_64
SO_FILE=$(ls "$HERE"/bimanual/__init__.cpython-*.so 2>/dev/null | head -1)
if [ -z "$SO_FILE" ]; then
  fail "找不到 bimanual/__init__.cpython-*.so" "SDK 二进制缺失" \
       "本目录不完整, 重新解压/拷贝 ARX5-SDK-V2, 或在源码机上重跑 sdk.sh 重新生成"
  NEED_PY=""; NEED_ARCH=""
else
  TAG=$(basename "$SO_FILE" | sed 's/^__init__\.cpython-//; s/\.so$//')   # 312-x86_64-linux-gnu
  NEED_PY="${TAG%%-*}"                                   # 312
  NEED_PY="${NEED_PY:0:1}.${NEED_PY:1}"                  # 3.12
  NEED_ARCH=$(echo "$TAG" | cut -d- -f2)                 # x86_64
  info "SDK 二进制绑定: CPython $NEED_PY / $NEED_ARCH"
fi

case "$(uname -s)" in Linux) ok "Linux ($(uname -r))" ;;
  *) fail "非 Linux: $(uname -s)" "系统不支持" "SDK 需要 Linux + SocketCAN" ;; esac

if [ -n "$NEED_ARCH" ] && [ "$(uname -m)" != "$NEED_ARCH" ]; then
  fail "架构不匹配: 本机 $(uname -m), SDK 是 $NEED_ARCH" "架构不匹配" \
       "在 $(uname -m) 机器上用源码包的 sdk.sh 重新构建发行版"
else
  ok "架构 $(uname -m)"
fi

if ! command -v python3 >/dev/null; then
  fail "python3 不存在" "缺 python3" "sudo apt install python3 python3-pip"
else
  PYV=$(python3 -c "import sys; print('%d.%d' % sys.version_info[:2])")
  if [ -n "$NEED_PY" ] && [ "$PYV" != "$NEED_PY" ]; then
    fail "Python $PYV != $NEED_PY (.so 与 Python 小版本绑定, 版本不对无法 import)" \
         "Python 版本不匹配" \
         "装 Python $NEED_PY 并用它运行; 或在 Python $PYV 的机器上用源码包的 sdk.sh 重新构建"
  else
    ok "Python $PYV"
  fi
fi

# ─── 2. pip (缺失则自动安装) ─────────────────────────────────────────────────
step "pip"
if ! python3 -m pip --version >/dev/null 2>&1 && [ "$CHECK_ONLY" = 0 ]; then
  warn "pip 缺失 —— 自动安装"
  install_pip
fi
if python3 -m pip --version >/dev/null 2>&1; then
  ok "$(python3 -m pip --version 2>/dev/null | cut -d' ' -f1-2)"
  info "安装参数: $PIP_FLAGS"
elif [ "$CHECK_ONLY" = 1 ]; then
  fail "python3 -m pip 不可用" "缺 pip" "不带 --check 重跑会自动安装; 或 sudo apt install python3-pip"
else
  fail "python3 -m pip 不可用 (自动安装也失败, 见 setup.log)" "缺 pip" \
       "sudo apt install python3-pip"
fi

# ─── 3. Python 依赖 ──────────────────────────────────────────────────────────
step "Python 依赖 (numpy / python-can / pin / ruckig)"
#   import名:pip包名
DEPS=("numpy:numpy" "can:python-can>=4.0" "pinocchio:pin" "ruckig:ruckig")
if [ -z "$MIRROR" ] && [ "$CHECK_ONLY" = 0 ]; then
  info "提示: 国内网络建议 --mirror (pin 全家桶 200MB+, 直连 PyPI 可能要半小时)"
fi
for d in "${DEPS[@]}"; do
  mod="${d%%:*}"; pkg="${d#*:}"
  if [ "$FORCE" = 0 ] && py_has "$mod"; then
    ok "$pkg (已装, $(py_ver "$mod"))"
  elif [ "$CHECK_ONLY" = 1 ]; then
    fail "$pkg 未安装" "缺 $pkg" "./setup.sh --mirror  (或手动 pip install $PIP_FLAGS '$pkg')"
  else
    printf "      安装 %s ...\n" "$pkg"
    if pip_install "$pkg" && py_has "$mod"; then
      ok "$pkg 装好 ($(py_ver "$mod"))"
    else
      fail "$pkg 安装失败" "装不上 $pkg" "看 setup.log; 网络问题加 --mirror 重试"
    fi
  fi
done

# ─── 4. SDK 自检 (import 编译包 + FK/IK 往返) ────────────────────────────────
step "SDK 自检"
SELFCHECK=$(cd "$HERE" && python3 - 2>&1 <<'PYEOF'
import numpy as np
import bimanual
xyzrpy = bimanual.forward_kinematics([0, 0.2, 0.3, 0, 0, 0])
q = bimanual.inverse_kinematics(xyzrpy)
back = bimanual.forward_kinematics(q)
assert np.allclose(xyzrpy, back, atol=1e-3), f"FK/IK 往返不一致: {xyzrpy} vs {back}"
print(f"OK {bimanual.__version__}")
PYEOF
)
if [[ "$SELFCHECK" == OK* ]]; then
  ok "import bimanual + FK/IK 往返 (SDK ${SELFCHECK#OK })"
else
  log "=== SDK 自检输出 ==="; log "$SELFCHECK"
  fail "SDK 自检失败: $(echo "$SELFCHECK" | tail -1)" "SDK 跑不起来" \
       "通常是上面某步没过 (版本/依赖); 全过还失败就看 setup.log"
fi

# ─── 5. can-utils + CAN 接口 (接口只检查提示, 不配置) ────────────────────────
step "can-utils / CAN 接口"
if ! command -v candump >/dev/null && [ "$CHECK_ONLY" = 0 ] && command -v apt-get >/dev/null; then
  info "缺 can-utils —— 尝试 sudo apt-get install -y can-utils (可能要输密码)"
  sudo apt-get install -y can-utils >>"$LOG" 2>&1
fi
if command -v candump >/dev/null; then
  ok "can-utils"
else
  warn "can-utils 缺失 (CAN 配置/抓包要用) —— sudo apt install can-utils"
fi
CANS=$(ip -br link 2>/dev/null | awk '$1 ~ /^can/ {print $1"("$2")"}' | tr '\n' ' ')
if [ -n "$CANS" ]; then
  ok "检测到: $CANS"
else
  warn "没有 can* 接口 —— 跑真机前需先配置 USB-CAN (联系厂家获取 ARX_CAN 配置工具)"
  info "demo 里的 can_port 要与实际接口名一致 (ip link show 查看)"
fi

# ─── 汇总 ────────────────────────────────────────────────────────────────────
printf "\n${BOLD}════════════════ 汇总 ════════════════${NC}\n"
if [ ${#FAILED[@]} -eq 0 ]; then
  printf "${GRN}${BOLD}✓ 全部通过${NC}  接下来:\n"
  printf "    python3 single_arm_demo.py    # 单臂 (默认 can1)\n"
  printf "    python3 dual_arm_demo.py      # 双臂 (can1 + can3)\n"
  exit 0
else
  printf "${RED}${BOLD}✗ %d 个问题:${NC}\n" "${#FAILED[@]}"
  for i in "${!FAILED[@]}"; do
    printf "  ${RED}✗${NC} %s\n      ${DIM}修复: %s${NC}\n" "${FAILED[$i]}" "${FIXES[$i]}"
  done
  printf "\n详细日志: %s\n" "$LOG"
  exit 1
fi
