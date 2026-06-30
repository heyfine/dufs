#!/bin/bash

# ============================================
# Dufs 交互式部署脚本（修复版）
# ============================================

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 去除首尾空格
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误：Docker 未安装。${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker 环境检查通过。${NC}"
}

# 清理旧容器
clean_old() {
    if docker ps -a --format '{{.Names}}' | grep -q "^dufs$"; then
        echo -e "${YELLOW}正在停止并删除旧容器...${NC}"
        docker stop dufs 2>/dev/null || true
        docker rm dufs 2>/dev/null || true
    fi
}

# 获取输入
get_input() {
    echo -e "${BLUE}请输入共享目录的绝对路径（例如 /vol1/1000）：${NC}"
    read -p "> " SHARE_DIR
    SHARE_DIR=$(trim "$SHARE_DIR")
    while [ -z "$SHARE_DIR" ]; do
        echo -e "${RED}目录不能为空。${NC}"
        read -p "> " SHARE_DIR
        SHARE_DIR=$(trim "$SHARE_DIR")
    done
    if [ ! -d "$SHARE_DIR" ]; then
        echo -e "${YELLOW}目录不存在，正在创建...${NC}"
        mkdir -p "$SHARE_DIR"
    fi

    echo -e "${BLUE}请输入服务端口（默认 5000）：${NC}"
    read -p "> " PORT
    PORT=$(trim "$PORT")
    PORT=${PORT:-5000}

    echo -e "${BLUE}是否允许上传/删除？（y/n，默认 n 只读）${NC}"
    read -p "> " ALLOW_ALL
    ALLOW_ALL=$(trim "$ALLOW_ALL")
    ALLOW_ALL=${ALLOW_ALL:-n}
    ALLOW_FLAG=""
    [[ "$ALLOW_ALL" =~ ^[Yy]$ ]] && ALLOW_FLAG="-A"

    echo -e "${BLUE}请输入要隐藏的目录名（多个用逗号分隔），留空则不隐藏：${NC}"
    echo -e "${YELLOW}提示：如果想隐藏根目录，请直接输入根目录的文件夹名（如 1000）。${NC}"
    read -p "> " HIDDEN_DIRS
    HIDDEN_DIRS=$(trim "$HIDDEN_DIRS")

    HIDDEN_FLAG=""
    HIDDEN_DIRS_SPACE=""
    if [ -n "$HIDDEN_DIRS" ]; then
        HIDDEN_FLAG="--hidden \"$HIDDEN_DIRS\""
        HIDDEN_DIRS_SPACE=$(echo "$HIDDEN_DIRS" | tr ',' ' ' | sed 's/  */ /g')
    fi

    echo -e "${BLUE}是否启用 --render-try-index？（y/n，默认 n）${NC}"
    read -p "> " RENDER_TRY
    RENDER_TRY=$(trim "$RENDER_TRY")
    RENDER_TRY=${RENDER_TRY:-n}
    RENDER_FLAG=""
    [[ "$RENDER_TRY" =~ ^[Yy]$ ]] && RENDER_FLAG="--render-try-index"

    echo -e "${BLUE}是否自动创建 index.html？（y/n，默认 n）${NC}"
    read -p "> " CREATE_INDEX
    CREATE_INDEX=$(trim "$CREATE_INDEX")
    CREATE_INDEX=${CREATE_INDEX:-n}

    # ---- 核心修复：正确创建 index.html ----
    if [[ "$CREATE_INDEX" =~ ^[Yy]$ ]] && [ -n "$HIDDEN_DIRS_SPACE" ]; then
        echo -e "${GREEN}正在创建 index.html...${NC}"
        
        # 获取共享目录的文件夹名（basename）
        SHARE_BASENAME=$(basename "$SHARE_DIR")
        
        for dir in $HIDDEN_DIRS_SPACE; do
            # 判断：如果 dir 等于共享目录的 basename，说明用户想隐藏根目录
            if [ "$dir" = "$SHARE_BASENAME" ]; then
                # 直接在共享目录根目录下创建 index.html
                TARGET_DIR="$SHARE_DIR"
                echo -e "${YELLOW}检测到要隐藏根目录（$SHARE_BASENAME），将在根目录创建 index.html${NC}"
            else
                # 否则在子目录下创建
                TARGET_DIR="$SHARE_DIR/$dir"
                if [ ! -d "$TARGET_DIR" ]; then
                    mkdir -p "$TARGET_DIR"
                fi
            fi
            
            # 创建 index.html
            if [ ! -f "$TARGET_DIR/index.html" ]; then
                echo "" > "$TARGET_DIR/index.html" 2>/dev/null
                if [ -f "$TARGET_DIR/index.html" ]; then
                    echo -e "${GREEN}✓ 已创建：$TARGET_DIR/index.html${NC}"
                else
                    echo -e "${RED}✗ 创建失败：$TARGET_DIR/index.html（权限不足？）${NC}"
                fi
            else
                echo -e "${YELLOW}已存在，跳过：$TARGET_DIR/index.html${NC}"
            fi
        done
    else
        echo -e "${YELLOW}未选择创建 index.html。${NC}"
    fi

    echo -e "${BLUE}是否需要额外参数？（如 --enable-cors，留空跳过）${NC}"
    read -p "> " EXTRA_ARGS
    EXTRA_ARGS=$(trim "$EXTRA_ARGS")

    # 汇总
    echo -e "\n${GREEN}========== 配置汇总 ==========${NC}"
    echo -e "共享目录：$SHARE_DIR"
    echo -e "端口：$PORT"
    echo -e "权限：$([ -n "$ALLOW_FLAG" ] && echo "读写" || echo "只读")"
    echo -e "隐藏目录：${HIDDEN_DIRS:-无}"
    echo -e "render-try-index：$([ -n "$RENDER_FLAG" ] && echo "启用" || echo "禁用")"
    echo -e "额外参数：${EXTRA_ARGS:-无}"
    echo -e "${GREEN}================================${NC}"
    read -p "按 Enter 继续，或 Ctrl+C 取消。"
}

# 生成 docker-compose.yml
generate_compose() {
    CMD="/data $ALLOW_FLAG"
    [ -n "$HIDDEN_FLAG" ] && CMD="$CMD $HIDDEN_FLAG"
    [ -n "$RENDER_FLAG" ] && CMD="$CMD $RENDER_FLAG"
    [ -n "$EXTRA_ARGS" ] && CMD="$CMD $EXTRA_ARGS"

    cat > docker-compose.yml << EOF
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
    echo -e "${GREEN}✓ 已生成 docker-compose.yml${NC}"
}

# 启动
start_service() {
    echo -e "${BLUE}启动服务...${NC}"
    docker compose up -d
    if [ $? -eq 0 ]; then
        IP=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}✓ 启动成功！${NC}"
        echo -e "访问：${GREEN}http://$IP:$PORT${NC}"
        echo -e "\n${YELLOW}管理命令：${NC}"
        echo "  查看日志：docker compose logs -f"
        echo "  停止服务：docker compose down"
    else
        echo -e "${RED}启动失败。${NC}"
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
