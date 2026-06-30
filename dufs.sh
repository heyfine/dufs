#!/bin/bash

# 双 Dufs 实例部署脚本
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

trim() { echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker 未安装。${NC}"
    exit 1
fi

# 获取共享目录
echo -e "${BLUE}请输入共享目录的绝对路径（如 /vol1/1000）：${NC}"
read -p "> " SHARE_DIR
SHARE_DIR=$(trim "$SHARE_DIR")
[ -z "$SHARE_DIR" ] && echo -e "${RED}目录不能为空。${NC}" && exit 1
[ ! -d "$SHARE_DIR" ] && mkdir -p "$SHARE_DIR"

# 公开实例端口
echo -e "${BLUE}请输入公开实例端口（默认 5000，无列表，只读直链）：${NC}"
read -p "> " PUBLIC_PORT
PUBLIC_PORT=${PUBLIC_PORT:-5000}

# 私有实例端口
echo -e "${BLUE}请输入私有实例端口（默认 5001，带列表，需认证）：${NC}"
read -p "> " PRIVATE_PORT
PRIVATE_PORT=${PRIVATE_PORT:-5001}

# 私有实例认证信息
echo -e "${BLUE}请设置私有实例的用户名：${NC}"
read -p "> " PRIVATE_USER
PRIVATE_USER=$(trim "$PRIVATE_USER")
[ -z "$PRIVATE_USER" ] && echo -e "${RED}用户名不能为空。${NC}" && exit 1

echo -e "${BLUE}请设置私有实例的密码：${NC}"
read -p "> " PRIVATE_PASS
PRIVATE_PASS=$(trim "$PRIVATE_PASS")
[ -z "$PRIVATE_PASS" ] && echo -e "${RED}密码不能为空。${NC}" && exit 1

# 停止旧容器（如果有）
docker stop dufs-public dufs-private 2>/dev/null || true
docker rm dufs-public dufs-private 2>/dev/null || true

# 生成 docker-compose.yml
cat > docker-compose.yml << EOF
services:
  dufs-public:
    image: sigoden/dufs
    container_name: dufs-public
    restart: unless-stopped
    ports:
      - "${PUBLIC_PORT}:5000"
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - ${SHARE_DIR}:/data
    command: /data --hidden "*"   # 隐藏所有文件/目录，但直链有效

  dufs-private:
    image: sigoden/dufs
    container_name: dufs-private
    restart: unless-stopped
    ports:
      - "${PRIVATE_PORT}:5000"
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - ${SHARE_DIR}:/data
    command: /data -A --auth "${PRIVATE_USER}:${PRIVATE_PASS}@/:rw"   # 显示列表，带认证，且可读写
EOF

echo -e "${GREEN}✓ 已生成 docker-compose.yml${NC}"

# 启动
docker compose up -d

IP=$(hostname -I | awk '{print $1}')
echo -e "\n${GREEN}部署完成！${NC}"
echo -e "公开实例（无列表，只读直链）：${GREEN}http://$IP:$PUBLIC_PORT${NC}"
echo -e "私有实例（有列表，需认证）：${GREEN}http://$IP:$PRIVATE_PORT${NC}"
echo -e "用户名：${PRIVATE_USER}，密码：${PRIVATE_PASS}"
echo -e "\n${YELLOW}管理命令：${NC}"
echo "  docker compose logs -f"
echo "  docker compose down"
