#!/bin/bash

# =================定义颜色=================
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# =================定义路径=================
CONFIG_FILE="/etc/realm/config.toml"
BIN_FILE="/usr/local/bin/realm"
SERVICE_FILE="/etc/systemd/system/realm.service"

# =================权限检查=================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请使用 root 权限运行此脚本！${RESET}"
        exit 1
    fi
}

# =================功能：1. 安装=================
install_realm() {
    if [ -f "$BIN_FILE" ]; then
        echo -e "${YELLOW}提示：Realm 已经安装过了！${RESET}"
        sleep 2
        return
    fi
    echo -e "${CYAN}正在拉取官方最新版 Realm...${RESET}"
    wget -qO realm.tar.gz https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz
    
    if [ ! -f "realm.tar.gz" ]; then
        echo -e "${RED}下载失败，请检查 VPS 网络！${RESET}"
        sleep 2
        return
    fi

    tar -xzf realm.tar.gz
    mv realm $BIN_FILE
    chmod +x $BIN_FILE
    rm realm.tar.gz

    # 初始化配置目录和文件
    mkdir -p /etc/realm
    touch $CONFIG_FILE

    # 配置 Systemd 守护进程
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Realm Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_FILE -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable realm >/dev/null 2>&1
    echo -e "${GREEN}Realm 核心安装完成，并已设置开机自启！${RESET}"
    sleep 2
}

# =================功能：2. 添加规则 (支持 IPv6)=================
add_rule() {
    if [ ! -f "$BIN_FILE" ]; then
        echo -e "${RED}错误：请先在菜单中安装 Realm！${RESET}"
        sleep 2
        return
    fi
    echo -e "${CYAN}--- 添加新的端口转发 ---${RESET}"
    read -p "1. 请输入本机监听端口 (如 10000): " LOCAL_PORT
    read -p "2. 请输入目标 IP 或 域名: " REMOTE_IP
    read -p "3. 请输入目标端口: " REMOTE_PORT

    # 智能判断目标地址是否为纯 IPv6 (判断是否包含冒号)
    if [[ "$REMOTE_IP" == *":"* ]]; then
        # 如果是 IPv6，按照标准加上中括号
        FORMATTED_REMOTE="[${REMOTE_IP}]:${REMOTE_PORT}"
    else
        # 如果是 IPv4 或 域名，保持原样
        FORMATTED_REMOTE="${REMOTE_IP}:${REMOTE_PORT}"
    fi

    # 追加写入配置文件 (listen 改为 [::] 以同时支持 IPv4 和 IPv6 入口)
    cat >> $CONFIG_FILE <<EOF

[[endpoints]]
listen = "[::]:${LOCAL_PORT}"
remote = "${FORMATTED_REMOTE}"
EOF

    systemctl restart realm
    echo -e "${GREEN}规则添加成功！服务已自动重启生效。${RESET}"
    echo -e "当前映射：${YELLOW}本机双栈 ${LOCAL_PORT} 端口 -> 目标 ${FORMATTED_REMOTE}${RESET}"
    sleep 3
}

# =================功能：3. 查看规则=================
view_rules() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}找不到配置文件，你可能还没安装或添加规则。${RESET}"
    else
        echo -e "${CYAN}========== 当前转发配置 ==========${RESET}"
        cat $CONFIG_FILE
        echo -e "${CYAN}==================================${RESET}"
    fi
    echo -e "${YELLOW}按任意键返回主菜单...${RESET}"
    read -n 1
}

# =================功能：4. 修改/删除规则=================
edit_rules() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}找不到配置文件。${RESET}"
        sleep 2
        return
    fi
    echo -e "${CYAN}即将进入 nano 编辑器。${RESET}"
    echo -e "提示：删除不需要的 [[endpoints]] 块即可删除规则。"
    echo -e "编辑完成后，按 ${YELLOW}Ctrl+O${RESET} 保存，回车确认，按 ${YELLOW}Ctrl+X${RESET} 退出。"
    sleep 3
    nano $CONFIG_FILE
    
    systemctl restart realm
    echo -e "${GREEN}配置已保存，Realm 服务已重启生效！${RESET}"
    sleep 2
}

# =================功能：5. 卸载=================
uninstall_realm() {
    echo -e "${RED}警告：这将会停止服务并删除所有转发规则！${RESET}"
    read -p "确定要卸载吗？(y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        systemctl stop realm >/dev/null 2>&1
        systemctl disable realm >/dev/null 2>&1
        rm -f $BIN_FILE
        rm -f $SERVICE_FILE
        rm -rf /etc/realm
        systemctl daemon-reload
        echo -e "${GREEN}Realm 已彻底卸载！${RESET}"
    else
        echo -e "${YELLOW}已取消卸载。${RESET}"
    fi
    sleep 2
}

# =================主菜单循环=================
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${GREEN}        Realm 端口转发管理脚本 v1.0      ${RESET}"
        echo -e "${GREEN}=========================================${RESET}"
        
        # 精准检查运行状态
        if [ ! -f "$BIN_FILE" ]; then
            echo -e "当前状态: ${RED}未安装${RESET}"
        elif systemctl is-active --quiet realm; then
            echo -e "当前状态: ${GREEN}运行中 (Running)${RESET}"
        else
            echo -e "当前状态: ${YELLOW}已安装，但未运行 (通常是因为还没添加任何规则)${RESET}"
        fi

        
        echo -e "${GREEN}=========================================${RESET}"
        echo -e "${CYAN}1.${RESET} 安装 Realm 环境"
        echo -e "${CYAN}2.${RESET} 添加端口转发规则"
        echo -e "${CYAN}3.${RESET} 查看当前所有规则"
        echo -e "${CYAN}4.${RESET} 手动编辑 / 删除规则 (调用 nano)"
        echo -e "${CYAN}5.${RESET} 完全卸载 Realm"
        echo -e "${CYAN}0.${RESET} 退出脚本"
        echo -e "${GREEN}=========================================${RESET}"
        read -p "请输入数字选择操作: " CHOICE

        case $CHOICE in
            1) install_realm ;;
            2) add_rule ;;
            3) view_rules ;;
            4) edit_rules ;;
            5) uninstall_realm ;;
            0) clear; echo -e "${GREEN}退出脚本，服务依然会在后台运行！再见。${RESET}"; exit 0 ;;
            *) echo -e "${RED}无效输入，请重新输入 0-5 之间的数字！${RESET}"; sleep 1 ;;
        esac
    done
}

# =================执行入口=================
check_root
show_menu
