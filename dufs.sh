#!/bin/bash

# ============================================
# Dufs 交互式部署脚本
# 功能：配置目录、端口、权限、隐藏目录等
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查 Docker 是否安装
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

# 停止并删除已有的 dufs 容器（如果有）
clean_old() {
    if docker ps -a --format '{{.Names}}' | grep -q "^dufs$"; then
        echo -e "${YELLOW}检测到已存在的 dufs 容器，正在停止并删除...${NC}"
        docker stop dufs 2>/dev/null || true
        docker rm dufs 2>/dev/null || true
    fi
    if docker ps -a --format '{{.Names}}' | grep -q "^dufs-nginx$"; then
        docker stop dufs-nginx 2>/dev/null || true
        docker rm dufs-nginx 2>/dev/null || true
    fi
}

# 获取用户输入
get_input() {
    # 共享目录
    echo -e "${BLUE}请输入要共享的目录绝对路径（例如 /root/share）：${NC}"
    read -p "> " SHARE_DIR
    while [ -z "$SHARE_DIR" ]; do
        echo -e "${RED}目录不能为空，请重新输入。${NC}"
        read -p "> " SHARE_DIR
    done
    # 如果目录不存在，创建
    if [ ! -d "$SHARE_DIR" ]; then
        echo -e "${YELLOW}目录不存在，正在创建...${NC}"
        mkdir -p "$SHARE_DIR"
    fi

    # 端口
    echo -e "${BLUE}请输入服务端口（默认 5000）：${NC}"
    read -p "> " PORT
    PORT=${PORT:-5000}
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}无效端口，使用默认 5000。${NC}"
        PORT=5000
    fi

    # 权限
    echo -e "${BLUE}是否允许上传/删除等所有操作？（y/n，默认 n 只读）${NC}"
    read -p "> " ALLOW_ALL
    ALLOW_ALL=${ALLOW_ALL:-n}
    if [[ "$ALLOW_ALL" =~ ^[Yy]$ ]]; then
        ALLOW_FLAG="-A"
    else
        ALLOW_FLAG=""
    fi

    # 隐藏目录
    echo -e "${BLUE}请输入要隐藏的目录名（多个用逗号分隔，例如 A,B,private），留空则不隐藏：${NC}"
    read -p "> " HIDDEN_DIRS
    if [ -n "$HIDDEN_DIRS" ]; then
        HIDDEN_FLAG="--hidden \"$HIDDEN_DIRS\""
    else
        HIDDEN_FLAG=""
    fi

    # render-try-index
    echo -e "${BLUE}是否启用 --render-try-index？（y/n，默认 n）${NC}"
    echo -e "${YELLOW}启用后，访问目录时会尝试显示 index.html，若不存在则显示列表。${NC}"
    read -p "> " RENDER_TRY
    RENDER_TRY=${RENDER_TRY:-n}
    if [[ "$RENDER_TRY" =~ ^[Yy]$ ]]; then
        RENDER_FLAG="--render-try-index"
        # 提示用户可以在隐藏目录下放 index.html
        if [ -n "$HIDDEN_DIRS" ]; then
            echo -e "${GREEN}提示：你可以在隐藏目录（如 ${HIDDEN_DIRS%%%,*}）下放置 index.html 来自定义访问该目录时的显示内容。${NC}"
        fi
    else
        RENDER_FLAG=""
    fi

    # 额外参数（可选）
    echo -e "${BLUE}是否需要添加额外参数？（例如 --enable-cors，留空跳过）${NC}"
    read -p "> " EXTRA_ARGS

    # 汇总显示
    echo -e "\n${GREEN}========== 配置汇总 ==========${NC}"
    echo -e "共享目录：$SHARE_DIR"
    echo -e "服务端口：$PORT"
    echo -e "权限：$([ -n "$ALLOW_FLAG" ] && echo "读写（-A）" || echo "只读")"
    echo -e "隐藏目录：${HIDDEN_DIRS:-无}"
    echo -e "render-try-index：$([ -n "$RENDER_FLAG" ] && echo "启用" || echo "禁用")"
    echo -e "额外参数：${EXTRA_ARGS:-无}"
    echo -e "${GREEN}================================${NC}"

    echo -e "${BLUE}确认以上配置？按 Enter 继续，或 Ctrl+C 取消。${NC}"
    read -p ""
}

# 生成 docker-compose.yml
generate_compose() {
    COMPOSE_FILE="docker-compose.yml"
    # 构建 command 行
    CMD="/data $ALLOW_FLAG"
    if [ -n "$HIDDEN_FLAG" ]; then
        CMD="$CMD $HIDDEN_FLAG"
    fi
    if [ -n "$RENDER_FLAG" ]; then
        CMD="$CMD $RENDER_FLAG"
    fi
    if [ -n "$EXTRA_ARGS" ]; then
        CMD="$CMD $EXTRA_ARGS"
    fi

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
    echo -e "${GREEN}====== Dufs 交互式部署脚本 ======${NC}"
    check_docker
    clean_old
    get_input
    generate_compose
    start_service
}

main
