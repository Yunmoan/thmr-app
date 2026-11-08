#!/usr/bin/env bash
#
# Copyright (c) 2026, ACDD. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# ----------------- 0. 安全防呆拦截 (严禁以 root 身份直接运行整个脚本) -----------------
# 原因：
# 1. 最小权限原则：多媒体拉流与播放是高风险操作，绝不能以超级用户执行；
# 2. VLC 官方二进制程序内置安全校验，硬编码拒绝以 root 身份启动 (报 "VLC is not supposed to be run as root. Sorry.")。
if [[ $EUID -eq 0 ]]; then
    echo -e "\n\033[1;31m[安全拦截] 严禁以 root 身份直接执行本脚本！\033[0m"
    echo -e "\033[1;33m说明：VLC 播放器原生拒绝 root 权限运行。安装依赖时脚本会自动按需提权，无需手动加 sudo。\033[0m"
    echo -e "\033[1;32m请切换为普通用户后重新执行: ./player.sh\033[0m\n"
    exit 1
fi

STREAM_DOMESTIC="https://radio.zyghit.cn/radio/touhou/320k"
STREAM_INTERNATIONAL="https://radio.yunmoan.cn/radio/touhou/320k"
STREAM_URL="$STREAM_DOMESTIC"
FIFO_PATH="/tmp/radio_stream_${UID}.fifo"
VLC_SOCK="/tmp/vlc_ctrl_${UID}.sock"
LOG_FILE=$(mktemp /tmp/curl_radio_log.XXXXXX)
MAIN_PID=$$

# ----------------- 1. 依赖检测与「按需局部提权」自动安装 -----------------
check_dependencies() {
    local missing_deps=()
    local missing_pkgs_deb=()
    local missing_pkgs_rhel=()

    # 1. 探测 curl (流媒体网络拉流)
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
        missing_pkgs_deb+=("curl")
        missing_pkgs_rhel+=("curl")
    fi

    # 2. 探测 vlc / cvlc (流媒体播放核心依赖)
    if ! command -v cvlc >/dev/null 2>&1 && ! command -v vlc >/dev/null 2>&1; then
        missing_deps+=("vlc (cvlc)")
        missing_pkgs_deb+=("vlc")
        missing_pkgs_rhel+=("vlc")
    fi

    # 3. 探测套接字控制工具 (socat 或 nc，用于音量调节)
    if ! command -v socat >/dev/null 2>&1 && ! command -v nc >/dev/null 2>&1; then
        missing_deps+=("socat")
        missing_pkgs_deb+=("socat")
        missing_pkgs_rhel+=("socat")
    fi

    # 如有全部依赖：完全不触碰 sudo/root 权限，直接进入后续播放流程
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        return 0
    fi

    # 如没有：探测系统发行版并准备按需提权安装
    echo -e "\033[1;33m[$(date '+%H:%M:%S')] 检测到系统缺少以下依赖: ${missing_deps[*]}\033[0m"
    echo -e "\033[1;34m[$(date '+%H:%M:%S')] 正在探测当前 Linux 发行版类型...\033[0m"

    local os_family=""
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID:-}" in
            debian|ubuntu|linuxmint|kali|deepin|pop|raspbian)
                os_family="debian"
                ;;
            rhel|centos|fedora|rocky|almalinux|ol|amzn)
                os_family="rhel"
                ;;
            *)
                if [[ "${ID_LIKE:-}" =~ debian|ubuntu ]]; then
                    os_family="debian"
                elif [[ "${ID_LIKE:-}" =~ rhel|fedora|centos ]]; then
                    os_family="rhel"
                fi
                ;;
        esac
    fi

    # 备选：根据包管理器命令兜底检测
    if [[ -z "$os_family" ]]; then
        if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
            os_family="debian"
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            os_family="rhel"
        fi
    fi

    local pkg_mgr=""
    local pkgs_to_install=()
    if [[ "$os_family" == "debian" ]]; then
        echo -e "\033[1;32m[$(date '+%H:%M:%S')] 识别为 Debian 系列发行版 (Debian / Ubuntu 等)\033[0m"
        pkg_mgr="apt-get"
        pkgs_to_install=("${missing_pkgs_deb[@]}")
    elif [[ "$os_family" == "rhel" ]]; then
        echo -e "\033[1;32m[$(date '+%H:%M:%S')] 识别为 RHEL 系列发行版 (RHEL / CentOS / Fedora / Rocky 等)\033[0m"
        pkg_mgr="dnf"
        command -v dnf >/dev/null 2>&1 || pkg_mgr="yum"
        pkgs_to_install=("${missing_pkgs_rhel[@]}")
    else
        echo -e "\033[1;31m[错误] 未能识别为 Debian 或 RHEL 系列发行版，无法自动安装依赖。\033[0m"
        echo -e "\033[1;33m请手动安装以下必要工具后重新运行: ${missing_deps[*]}\033[0m"
        exit 1
    fi

    # 核心设计：仅对包管理器单独使用 sudo 提权（按需提权）
    local sudo_cmd=""
    if command -v sudo >/dev/null 2>&1; then
        sudo_cmd="sudo"
        echo -e "\033[1;36m[$(date '+%H:%M:%S')] 正在通过 sudo 申请临时权限安装系统依赖（若有提示请输入当前用户的登录密码）...\033[0m"
        if ! $sudo_cmd -v; then
            echo -e "\n\033[1;31m[错误] sudo 认证失败或当前用户不在 sudoers 白名单中。\033[0m"
            echo -e "\033[1;33m请联系系统管理员代为执行以下安装命令后重新运行：\033[0m"
            if [[ "$os_family" == "debian" ]]; then
                echo -e "  \033[1mapt-get update && apt-get install -y ${pkgs_to_install[*]}\033[0m\n"
            else
                echo -e "  \033[1m$pkg_mgr install -y ${pkgs_to_install[*]}\033[0m\n"
            fi
            exit 1
        fi
    else
        echo -e "\n\033[1;31m[错误] 系统中未安装 sudo 工具，当前普通用户无法自动安装系统软件包。\033[0m"
        echo -e "\033[1;33m请联系系统管理员安装以下依赖后再行运行：\033[0m"
        if [[ "$os_family" == "debian" ]]; then
            echo -e "  \033[1mapt-get update && apt-get install -y ${pkgs_to_install[*]}\033[0m\n"
        else
            echo -e "  \033[1m$pkg_mgr install -y ${pkgs_to_install[*]}\033[0m\n"
        fi
        exit 1
    fi

    # 执行特权安装
    if [[ "$os_family" == "debian" ]]; then
        echo -e "\033[1;34m[$(date '+%H:%M:%S')] 正在通过 apt-get 自动安装: ${pkgs_to_install[*]} ...\033[0m"
        $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y "${pkgs_to_install[@]}"
    elif [[ "$os_family" == "rhel" ]]; then
        echo -e "\033[1;34m[$(date '+%H:%M:%S')] 正在通过 $pkg_mgr 自动安装: ${pkgs_to_install[*]} ...\033[0m"
        $sudo_cmd "$pkg_mgr" install -y "${pkgs_to_install[@]}"
    fi

    # 安装完成校验
    local still_missing=()
    ! command -v curl >/dev/null 2>&1 && still_missing+=("curl")
    ! command -v cvlc >/dev/null 2>&1 && ! command -v vlc >/dev/null 2>&1 && still_missing+=("vlc")

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo -e "\n\033[1;31m[错误] 自动安装未能成功就绪以下工具: ${still_missing[*]}\033[0m"
        echo -e "\033[1;33m请检查网络连接、软件源或手动安装后再次尝试。\033[0m\n"
        exit 1
    fi

    echo -e "\033[1;32m[$(date '+%H:%M:%S')] 依赖安装完成，临时特权已释放，即将以普通用户进入播放流程...\033[0m"
    sleep 1
}

# 执行依赖检测与安装
check_dependencies

# ----------------- 2. 全局清理钩子 (彻底防残留) -----------------
cleanup() {
    trap - INT TERM EXIT
    echo -e "\n\n\033[1;33m[$(date '+%H:%M:%S')] 正在停止播放并彻底回收资源...\033[0m"

    # 1. 杀死后台 curl 守护进程及子进程
    if [[ -n "$CURL_PID" ]] && kill -0 "$CURL_PID" 2>/dev/null; then
        pkill -P "$CURL_PID" 2>/dev/null
        kill -9 "$CURL_PID" 2>/dev/null
    fi

    # 2. 杀死后台 cvlc
    if [[ -n "$VLC_PID" ]] && kill -0 "$VLC_PID" 2>/dev/null; then
        kill -9 "$VLC_PID" 2>/dev/null
    fi

    # 3. 关闭文件描述符 3 (释放写端)
    exec 3>&- 2>/dev/null

    # 4. 清理管道文件、套接字与临时日志
    rm -f "$FIFO_PATH" "$VLC_SOCK" "$LOG_FILE" 2>/dev/null

    echo -e "\033[1;32m[$(date '+%H:%M:%S')] 进程、套接字与管道已全部清理完毕，安全退出。\033[0m"
    exit 0
}
trap cleanup INT TERM EXIT

# ----------------- 3. 启动前交互式配置 (音频源 & IP协议) -----------------
clear
echo "=================================================="
echo "           THMR东方网络电台流媒体播放端           "
echo "                Maintainer: ACDD                  "
echo "=================================================="
echo "步骤 1/2：请选择音频源线路："
echo "  1) 国内音频源 (radio.zyghit.cn) [低延迟，国内推荐]"
echo "  2) 国际音频源 (radio.yunmoan.cn) [海外优质节点]"
echo "--------------------------------------------------"

if [ -t 0 ]; then
    read -rp "请输入选项 [1/2，直接回车默认选 1]: " SOURCE_CHOICE
elif [ -r /dev/tty ]; then
    read -rp "请输入选项 [1/2，直接回车默认选 1]: " SOURCE_CHOICE < /dev/tty
else
    SOURCE_CHOICE=1
fi

case "$SOURCE_CHOICE" in
    2)
        STREAM_URL="$STREAM_INTERNATIONAL"
        SOURCE_NAME="国际音频源 (yunmoan.cn)"
        ;;
    *)
        STREAM_URL="$STREAM_DOMESTIC"
        SOURCE_NAME="国内音频源 (zyghit.cn)"
        ;;
esac

echo -e "\n已选定音频源: \033[1;32m$SOURCE_NAME\033[0m"
echo "--------------------------------------------------"
echo "步骤 2/2：请选择拉流的网络协议："
echo "  1) 强制 IPv4 (-4)"
echo "  2) 强制 IPv6 (-6)"
echo "  3) 自动双栈 (由系统调度)"
echo "--------------------------------------------------"

if [ -t 0 ]; then
    read -rp "请输入选项 [1/2/3，直接回车默认选 3]: " USER_CHOICE
elif [ -r /dev/tty ]; then
    read -rp "请输入选项 [1/2/3，直接回车默认选 3]: " USER_CHOICE < /dev/tty
else
    USER_CHOICE=3
fi

case "$USER_CHOICE" in
    1)
        IP_FLAG="-4"
        IP_NAME="IPv4 Only"
        ;;
    2)
        IP_FLAG="-6"
        IP_NAME="IPv6 Only"
        ;;
    *)
        IP_FLAG=""
        IP_NAME="Dual-Stack (Auto)"
        ;;
esac

echo -e "\n已选定配置: \033[1;32m$SOURCE_NAME\033[0m | 模式: \033[1;32m$IP_NAME\033[0m"
echo "=================================================="
echo "操作提示："
echo "  [+] / [=] 增加音量    [-] / [_] 降低音量"
echo "  [q] 退出播放          [Ctrl+C] 强制退出"
echo "=================================================="

# ----------------- 4. 初始化管道与描述符 -----------------
rm -f "$FIFO_PATH" "$VLC_SOCK"
mkfifo "$FIFO_PATH"
# 锁定描述符 3 读写端，屏蔽 EOF，防止断流或切歌导致 VLC 退出
exec 3<> "$FIFO_PATH"

# ----------------- 5. 启动 curl 流媒体拉流守护进程 (支持断流自动重连) -----------------
echo -e "\033[1;34m[$(date '+%H:%M:%S')] 正在通过 curl 连接音频流...\033[0m"

curl_fetcher() {
    local retry_delay=2
    local fail_count=0
    while true; do
        local start_time=$(date +%s)

        # 启动 curl 拉流
        curl -sS -L -N --connect-timeout 10 $IP_FLAG "$STREAM_URL" >&3 2>>"$LOG_FILE"
        local exit_code=$?

        # 若收到退出信号则退出守护循环
        [[ $exit_code -eq 130 || $exit_code -eq 143 || $exit_code -eq 137 ]] && break

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        # 正常播放超过 10 秒后断流，重置连续失败计数
        if [[ $duration -ge 10 ]]; then
            fail_count=0
        else
            ((fail_count++))
        fi

        # 连续快速失败达到 5 次，判定为网络不可达或地址失效，停止重试
        if [[ $fail_count -ge 5 ]]; then
            echo -e "\n[$(date '+%H:%M:%S')] 连续拉流失败达到上限，停止重连。" >> "$LOG_FILE"
            break
        fi

        echo -e "\r\033[K\033[1;33m[$(date '+%H:%M:%S')] 网络中断，${retry_delay}秒后尝试自动重连 (连续失败: ${fail_count}/5)...\033[0m" >&2
        sleep "$retry_delay"
        echo -e "\r\033[K\033[1;34m[$(date '+%H:%M:%S')] 正在重新连接音频流...\033[0m" >&2
    done
}

curl_fetcher &
CURL_PID=$!

# ----------------- 6. 启动 cvlc 并挂载 UNIX 控制套接字 -----------------
# 注意：VLC 3.x 下旧版 RC 接口名为 oldrc，且需要 --rc-fake-tty 避免无输入时退出
cvlc -q -I dummy \
     --extraintf oldrc \
     --rc-unix "$VLC_SOCK" \
     --rc-fake-tty \
     --no-video \
     "$FIFO_PATH" >/dev/null 2>&1 &
VLC_PID=$!

# 等待套接字文件生成
for ((i = 0; i < 30; i++)); do
    [[ -S "$VLC_SOCK" ]] && break
    sleep 0.1
done

if [[ ! -S "$VLC_SOCK" ]]; then
    echo -e "\033[1;31m[错误] VLC 控制套接字创建失败！\033[0m"
    cleanup
fi

# 套接字控制函数（兼容 openbsd-netcat 与 socat）
send_vlc() {
    local cmd="$1"
    if command -v socat >/dev/null 2>&1; then
        echo "$cmd" | socat - UNIX-CONNECT:"$VLC_SOCK" >/dev/null 2>&1
    elif command -v nc >/dev/null 2>&1; then
        echo "$cmd" | nc -U "$VLC_SOCK" >/dev/null 2>&1
    fi
}

# ----------------- 7. 前台热键监听守护循环 -----------------
echo -e "\033[1;32m[$(date '+%H:%M:%S')] 播放已就绪，正在实时播放中...\033[0m\n"

while true; do
    # 检查 curl 守护进程状态
    if ! kill -0 "$CURL_PID" 2>/dev/null; then
        echo -e "\n\033[1;31m[错误] curl 拉流守护进程意外退出！日志如下：\033[0m"
        cat "$LOG_FILE" 2>/dev/null
        break
    fi

    # 检查 cvlc 进程状态
    if ! kill -0 "$VLC_PID" 2>/dev/null; then
        echo -e "\n\033[1;31m[错误] VLC 播放进程意外退出！\033[0m"
        break
    fi

    # 监听用户按键（免回车，1秒超时以便轮询子进程存活）
    got_key=0
    key=""
    if [ -t 0 ]; then
        if read -r -s -n 1 -t 1 key; then
            got_key=1
        fi
    elif [ -r /dev/tty ]; then
        if read -r -s -n 1 -t 1 key < /dev/tty; then
            got_key=1
        fi
    else
        sleep 1
    fi

    if [[ $got_key -eq 1 ]]; then
        case "$key" in
            +|"=")
                send_vlc "volup 2"
                echo -ne "\r\033[K\033[1;36m[$(date '+%H:%M:%S')] 音量 +2\033[0m"
                ;;
            -|_)
                send_vlc "voldown 2"
                echo -ne "\r\033[K\033[1;36m[$(date '+%H:%M:%S')] 音量 -2\033[0m"
                ;;
            q|Q)
                echo -e "\n\033[1;33m用户请求退出...\033[0m"
                break
                ;;
        esac
    fi
done

cleanup
