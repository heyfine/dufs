#!/bin/bash

# ============================================
# Dufs 交互式部署脚本（优化版）
# 功能：配置目录、端口、权限、隐藏目录等
#       自动为隐藏目录创建空 index.html
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误：Docker 未安装，请先安装 Docker。${NC}"
        exit 1
    fi
    if ! command -v docker compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}错误：Docker Compose 未安装，请先安装。${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker 环境检查通过。${NC}"
}

# 清理旧容器
clean_old() {
    if docker ps -a --format '{{.Names}}' | grep -q "^dufs$"; then
        echo -e "${YELLOW}检测到已存在的 dufs 容器，正在停止并删除...${NC}"
        docker stop dufs 2>/dev/null || true
        docker rm dufs 2>/dev/null || true
    fi
}

# 去除字符串首尾空格
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# 获取输入
get_input() {
    # 共享目录
    echo -e "${BLUE}请输入要共享的目录绝对路径（例如 /root/share）：${NC}"
    read -p "> " SHARE_DIR
    SHARE_DIR=$(trim "$SHARE_DIR")
    while [ -z "$SHARE_DIR" ]; do
        echo -e "${RED}目录不能为空，请重新输入。${NC}"
        read -p "> " SHARE_DIR
        SHARE_DIR=$(trim "$SHARE_DIR")
    done
    if [ ! -d "$SHARE_DIR" ]; then
        echo -e "${YELLOW}目录不存在，正在创建...${NC}"
        mkdir -p "$SHARE_DIR"
    fi

    # 端口
    echo -e "${BLUE}请输入服务端口（默认 5000）：${NC}"
    read -p "> " PORT
    PORT=$(trim "$PORT")
    PORT=${PORT:-5000}
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}无效端口，使用默认 5000。${NC}"
        PORT=5000
    fi

    # 权限
    echo -e "${BLUE}是否允许上传/删除等所有操作？（y/n，默认 n 只读）${NC}"
    read -p "> " ALLOW_ALL
    ALLOW_ALL=$(trim "$ALLOW_ALL")
    ALLOW_ALL=${ALLOW_ALL:-n}
    if [[ "$ALLOW_ALL" =~ ^[Yy]$ ]]; then
        ALLOW_FLAG="-A"
    else
        ALLOW_FLAG=""
    fi

    # 隐藏目录
    echo -e "${BLUE}请输入要隐藏的目录名（多个用逗号分隔，例如 A,B,private），留空则不隐藏：${NC}"
    read -p "> " HIDDEN_DIRS
    HIDDEN_DIRS=$(trim "$HIDDEN_DIRS")
    if [ -n "$HIDDEN_DIRS" ]; then
        HIDDEN_FLAG="--hidden \"$HIDDEN_DIRS\""
        # 将逗号分隔转为空格，用于后续循环
        HIDDEN_DIRS_SPACE=$(echo "$HIDDEN_DIRS" | tr ',' ' ' | sed 's/  */ /g')
    else
        HIDDEN_DIRS_SPACE=""
        HIDDEN_FLAG=""
    fi

    # render-try-index
    echo -e "${BLUE}是否启用 --render-try-index？（y/n，默认 n）${NC}"
    echo -e "${YELLOW}启用后，访问目录时会优先显示 index.html（若存在），否则显示文件列表。${NC}"
    read -p "> " RENDER_TRY
    RENDER_TRY=$(trim "$RENDER_TRY")
    RENDER_TRY=${RENDER_TRY:-n}
    if [[ "$RENDER_TRY" =~ ^[Yy]$ ]]; then
        RENDER_FLAG="--render-try-index"
    else
        RENDER_FLAG=""
    fi

    # 独立询问是否创建 index.html（即使不启用 render-try-index 也可创建）
    echo -e "${BLUE}是否自动为隐藏目录创建空的 index.html？（y/n，默认 n）${NC}"
    echo -e "${YELLOW}如果启用 --render-try-index，此文件将生效；否则仅作为占位。${NC}"
    read -p "> " CREATE_INDEX
    CREATE_INDEX=$(trim "$CREATE_INDEX")
    CREATE_INDEX=${CREATE_INDEX:-n}

    # 执行创建
    if [[ "$CREATE_INDEX" =~ ^[Yy]$ ]] && [ -n "$HIDDEN_DIRS_SPACE" ]; then
        echo -e "${GREEN}开始为隐藏目录创建空的 index.html...${NC}"
        for dir in $HIDDEN_DIRS_SPACE; do
            TARGET_DIR="$SHARE_DIR/$dir"
            if [ ! -d "$TARGET_DIR" ]; then
                echo -e "${YELLOW}目录 $TARGET_DIR 不存在，自动创建。${NC}"
                mkdir -p "$TARGET_DIR" || { echo -e "${RED}创建目录失败：$TARGET_DIR${NC}"; exit 1; }
            fi
            if [ ! -f "$TARGET_DIR/index.html" ]; then
                echo "" > "$TARGET_DIR/index.html" 2>/dev/null
                if [ -f "$TARGET_DIR/index.html" ]; then
                    echo -e "${GREEN}✓ 已创建：$TARGET_DIR/index.html${NC}"
                else
                    echo -e "${RED}✗ 创建文件失败：$TARGET_DIR/index.html（权限不足？）${NC}"
                fi
            else
                echo -e "${YELLOW}已存在，跳过：$TARGET_DIR/index.html${NC}"
            fi
        done
    elif [[ "$CREATE_INDEX" =~ ^[Yy]$ ]] && [ -z "$HIDDEN_DIRS_SPACE" ]; then
        echo -e "${YELLOW}未指定隐藏目录，跳过创建。${NC}"
    else
        echo -e "${YELLOW}未选择创建 index.html。${NC}"
    fi

    # 额外参数
    echo -e "${BLUE}是否需要添加额外参数？（例如 --enable-cors，留空跳过）${NC}"
    read -p "> " EXTRA_ARGS
    EXTRA_ARGS=$(trim "$EXTRA_ARGS")

    # 汇总
    echo -e "\n${GREEN}========== 配置汇总 ==========${NC}"
    echo -e "共享目录：$SHARE_DIR"
    echo -e "服务端口：$PORT"
    echo -e "权限：$([ -n "$ALLOW_FLAG" ] && echo "读写（-A）" || echo "只读")"
    echo -e "隐藏目录：${HIDDEN_DIRS:-无}"
    echo -e "render-try-index：$([ -n "$RENDER_FLAG" ] && echo "启用" || echo "禁用")"
    echo -e "创建 index.html：$([ "$CREATE_INDEX" == "y" ] && echo "是" || echo "否")"
    echo -e "额外参数：${EXTRA_ARGS:-无}"
    echo -e "${GREEN}================================${NC}"

    echo -e "${BLUE}确认以上配置？按 Enter 继续，或 Ctrl+C 取消。${NC}"
    read -p ""
}

# 生成 docker-compose.yml
generate_compose() {
    COMPOSE_FILE="docker-compose.yml"
    CMD="/data $ALLOW_FLAG"
    [ -n "$HIDDEN_FLAG" ] && CMD="$CMD $HIDDEN_FLAG"
    [ -n "$RENDER_FLAG" ] && CMD="$CMD $RENDER_FLAG"
    [ -n "$EXTRA_ARGS" ] && CMD="$CMD $EXTRA_ARGS"

    cat > "$COMPOSE_FILE" << EOF
services:
  dufs:
    image: sigoden/dufs
    container_name: dufs
    restart: unless-stopped
    ports:
      - "${PORT}:5000"
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - ${SHARE_DIR}:/data
    command: ${CMD}
EOF

    echo -e "${GREEN}✓ 已生成 $COMPOSE_FILE${NC}"
}

# 启动服务
start_service() {
    echo -e "${BLUE}正在启动服务...${NC}"
    docker compose up -d
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 服务启动成功！${NC}"
        echo -e "访问地址：${GREEN}http://$(hostname -I | awk '{print $1}'):$PORT${NC}"
        echo -e "或使用：${GREEN}http://$(curl -s ifconfig.me):$PORT${NC}"
        echo -e "\n${YELLOW}常用命令：${NC}"
        echo "  查看日志：docker compose logs -f"
        echo "  停止服务：docker compose down"
        echo "  重启服务：docker compose restart"
    else
        echo -e "${RED}启动失败，请检查日志。${NC}"
        exit 1
    fi
}

# 主流程
main() {
    echo -e "${GREEN}====== Dufs 交互式部署脚本（优化版） ======${NC}"
    check_docker
    clean_old
    get_input
    generate_compose
    start_service
}

main
