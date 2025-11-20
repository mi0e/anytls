#!/bin/bash

# anytls 安装/卸载管理脚本
# 功能：安装 anytls (自动获取最新版) 或彻底卸载
# 支持架构：amd64 (x86_64)、arm64 (aarch64)、armv7 (armv7l)

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}必须使用 root 或 sudo 运行！${PLAIN}"
    exit 1
fi

# 全局变量
BINARY_DIR="/usr/local/bin"
BINARY_NAME="anytls-server"
SERVICE_NAME="anytls"

# 安装必要工具
function install_dependencies() {
    echo -e "${BLUE}[初始化] 正在检查并安装依赖...${PLAIN}"
    # 更新源，为了速度暂时屏蔽，如果报错请手动 apt update
    # apt update -y >/dev/null 2>&1

    for dep in wget curl unzip tar; do
        if ! command -v $dep &>/dev/null; then
            echo "正在安装 $dep..."
            apt install -y $dep >/dev/null 2>&1 || {
                echo -e "${RED}无法安装依赖: $dep，请手动运行 'apt update && apt install -y $dep' 后再试。${PLAIN}"
                exit 1
            }
        fi
    done
}

# 自动检测系统架构
function check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  BINARY_ARCH="amd64" ;;
        aarch64) BINARY_ARCH="arm64" ;;
        armv7l)  BINARY_ARCH="armv7" ;;
        *)       echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1 ;;
    esac
}

# 获取最新版本号
function get_latest_version() {
    echo -e "${BLUE}[信息] 正在获取 GitHub 最新版本...${PLAIN}"
    # 使用 GitHub API 获取最新 tag
    LATEST_TAG=$(curl -s "https://api.github.com/repos/anytls/anytls-go/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}获取版本失败，可能是 GitHub API 限制或网络问题。${PLAIN}"
        read -p "请手动输入版本号 (例如 v0.0.8): " LATEST_TAG
    fi
    
    # 去除 v 前缀用于文件名 (例如 v0.0.8 -> 0.0.8)
    VERSION_NO_V=$(echo "$LATEST_TAG" | sed 's/^v//')
    
    echo -e "${GREEN}检测到最新版本: ${LATEST_TAG}${PLAIN}"
}

# 改进的IP获取函数
get_ip() {
    local ip=""
    ip=$(curl -4 -s --connect-timeout 3 icanhazip.com 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null)
    [ -z "$ip" ] && ip=$(ip -o -4 addr show scope global | awk '{print $4}' | cut -d'/' -f1 | head -n1)
    
    if [ -z "$ip" ]; then
        read -p "无法获取公网IP，请手动输入: " ip
    fi
    echo "$ip"
}

# 生成随机端口
function get_random_port() {
    shuf -i 20000-65000 -n 1
}

# 生成随机密码
function get_random_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

# 显示菜单
function show_menu() {
    clear
    echo "-------------------------------------"
    echo -e " ${BLUE}anytls 服务管理脚本${PLAIN} "
    echo "-------------------------------------"
    echo "1. 安装 anytls (最新版)"
    echo "2. 卸载 anytls"
    echo "0. 退出"
    echo "-------------------------------------"
    read -p "请输入选项 [0-2]: " choice
    case $choice in
        1) install_anytls ;;
        2) uninstall_anytls ;;
        0) exit 0 ;;
        *) echo "无效选项！" && sleep 1 && show_menu ;;
    esac
}

# 安装功能
function install_anytls() {
    install_dependencies
    check_arch
    get_latest_version

    #构建下载链接
    # 文件名格式通常为 anytls_0.0.8_linux_amd64.zip
    FILENAME="anytls_${VERSION_NO_V}_linux_${BINARY_ARCH}.zip"
    DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/${LATEST_TAG}/${FILENAME}"
    ZIP_FILE="/tmp/${FILENAME}"

    # --- 配置端口 ---
    echo "-------------------------------------"
    read -p "请输入监听端口 [留空随机]: " INPUT_PORT
    if [ -z "$INPUT_PORT" ]; then
        PORT=$(get_random_port)
        echo -e "${YELLOW}已使用随机端口: $PORT${PLAIN}"
    else
        PORT=$INPUT_PORT
    fi

    # --- 配置密码 ---
    read -p "请设置密码 [留空随机]: " INPUT_PASS
    if [ -z "$INPUT_PASS" ]; then
        PASSWORD=$(get_random_password)
        echo -e "${YELLOW}已生成随机密码: $PASSWORD${PLAIN}"
    else
        PASSWORD=$INPUT_PASS
    fi
    echo "-------------------------------------"

    # 下载
    echo -e "${BLUE}[1/5] 下载文件...${PLAIN}"
    wget -N --no-check-certificate "$DOWNLOAD_URL" -O "$ZIP_FILE" || {
        echo -e "${RED}下载失败！请检查网络或 GitHub 连接。${PLAIN}"
        echo "尝试下载的 URL: $DOWNLOAD_URL"
        exit 1
    }

    # 解压
    echo -e "${BLUE}[2/5] 解压并安装...${PLAIN}"
    # 先尝试解压到临时目录，防止目录结构混乱
    TMP_EXTRACT="/tmp/anytls_extract"
    rm -rf "$TMP_EXTRACT" && mkdir -p "$TMP_EXTRACT"
    unzip -o "$ZIP_FILE" -d "$TMP_EXTRACT" >/dev/null 2>&1
    
    # 查找二进制文件（防止解压出文件夹）
    FOUND_BINARY=$(find "$TMP_EXTRACT" -type f -name "$BINARY_NAME" | head -n 1)
    
    if [ -f "$FOUND_BINARY" ]; then
        mv "$FOUND_BINARY" "$BINARY_DIR/$BINARY_NAME"
        chmod +x "$BINARY_DIR/$BINARY_NAME"
    else
        echo -e "${RED}错误：解压后未找到 $BINARY_NAME 文件！${PLAIN}"
        ls -R "$TMP_EXTRACT"
        exit 1
    fi

    # 清理
    rm -rf "$ZIP_FILE" "$TMP_EXTRACT"

    # 配置服务
    echo -e "${BLUE}[3/5] 配置 systemd 服务...${PLAIN}"
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=anytls Service
After=network.target

[Service]
ExecStart=$BINARY_DIR/$BINARY_NAME -l 0.0.0.0:$PORT -p $PASSWORD
Restart=always
User=root
Group=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    echo -e "${BLUE}[4/5] 启动服务...${PLAIN}"
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME

    # 检查状态
    sleep 2
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${RED}服务启动失败！请查看日志: journalctl -u $SERVICE_NAME -n 20${PLAIN}"
        exit 1
    fi

    # 获取服务器IP
    SERVER_IP=$(get_ip)

    # 输出信息
    echo -e "\n${GREEN}√ 安装完成！${PLAIN}"
    echo -e "-------------------------------------"
    echo -e "版本: ${LATEST_TAG}"
    echo -e "架构: ${BINARY_ARCH}"
    echo -e "端口: ${GREEN}${PORT}${PLAIN}"
    echo -e "密码: ${GREEN}${PASSWORD}${PLAIN}"
    echo -e "-------------------------------------"
    
    # 生成链接
    LINK="anytls://${PASSWORD}@${SERVER_IP}:${PORT}/?insecure=1"
    
    echo -e "\n${BLUE}〓 NekoBox / 客户端 连接信息 〓${PLAIN}"
    echo -e "${YELLOW}${LINK}${PLAIN}"
    echo -e "\n${YELLOW}请复制上方链接导入客户端。${PLAIN}"
}

# 卸载功能
function uninstall_anytls() {
    echo "正在卸载 anytls..."
    
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl disable $SERVICE_NAME 2>/dev/null
    
    rm -f "$BINARY_DIR/$BINARY_NAME"
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload

    echo -e "${GREEN}anytls 已完全卸载！${PLAIN}"
}

# 启动菜单
show_menu
