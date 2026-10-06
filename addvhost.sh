#!/usr/bin/env bash
# 本脚本由 AI 辅助生成，再由我修改，似乎没啥问题
set -euo pipefail

# 检查是否以 root 权限运行
# if [ "$(id -u)" -ne 0 ]; then
#   echo "⚠️ 请使用 root 权限运行此脚本"
#   exit 1
# fi
sudo -v &>/dev/null
if [ $? != 0 ]; then
  echo "$(whoami) is not sudo user"
  exit -1
else
  echo "$(whoami) is sudo user"
fi


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VHOST_DIR="$ROOT_DIR/userdata/httpd_conf/vhosts"
LOG_DIR="$ROOT_DIR/logs/httpd_log"
SSL_DIR="$ROOT_DIR/userdata/httpd_conf/ssl"
WEBROOT_DIR="$ROOT_DIR/userdata/wwwroot"

mkdir -p "$VHOST_DIR" "$LOG_DIR" "$SSL_DIR" "$WEBROOT_DIR"

read -p "ℹ️ 请输入要配置的域名，不加 www（例如：example.com）：" DOMAIN
DOMAIN="${DOMAIN:-}"
if [ -z "$DOMAIN" ]; then
  echo "❌ 域名不能为空"
  exit 1
fi

SITE_ROOT="$WEBROOT_DIR/${DOMAIN}"
CONTAINER_SITE_ROOT="/var/www/html/${DOMAIN}"
VHOST_FILE="$VHOST_DIR/${DOMAIN}.conf"
ACCESS_LOG="/var/log/apache2/${DOMAIN}.access.%Y-%m-%d-%H_%M_%S.log"
ERROR_LOG="/var/log/apache2/${DOMAIN}.error.%Y-%m-%d-%H_%M_%S.log"
mkdir -p "$SITE_ROOT"

if [ -z "$(ls -A "$SITE_ROOT")" ]; then
  echo "ℹ️ 添加占位网页"
  cat > "$SITE_ROOT/index.php" <<EOF
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Where All Miracles Begin</title>
</head>
<body>
    <p>あまねく奇跡の始発点</p>
</body>
</html>
EOF
else
  echo "ℹ️ 目录非空，跳过占位网页：${SITE_ROOT}"
fi

echo "ℹ️ 添加 vhosts 配置"
cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot "${CONTAINER_SITE_ROOT}"
    php_admin_value open_basedir "${CONTAINER_SITE_ROOT}:/tmp/:/var/tmp/:/proc/"
    <Directory "${CONTAINER_SITE_ROOT}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

echo "ℹ️ 重启 Apache"
# 重新加载 Apache 配置（Docker 环境）
if command -v sudo >/dev/null 2>&1; then
  sudo docker compose exec www apachectl -k graceful
else
  docker compose exec www apachectl -k graceful
fi

# 检查 acme.sh 是否已安装
ACME_BIN=""
if command -v acme.sh >/dev/null 2>&1; then
  ACME_BIN="$(command -v acme.sh)"
elif [ -f "$HOME/.acme.sh/acme.sh" ]; then
  ACME_BIN="$HOME/.acme.sh/acme.sh"
else
  echo "⚠️ 未检测到 acme.sh，跳过证书申请步骤"
  echo "✅ 已生成 vhost 配置：${VHOST_FILE}"
fi

echo "ℹ️ 申请证书"
echo "若一直 pending 的话，可尝试修改默认签发方至 Let's Encrypt"
echo "acme.sh --set-default-ca --server letsencrypt"
# 生成证书
"$ACME_BIN" --issue -d "$DOMAIN" -d "www.$DOMAIN"  --webroot "$SITE_ROOT" --log
# 安装到指定目录
"$ACME_BIN" --install-cert -d "$DOMAIN" \
  --cert-file "$SSL_DIR/${DOMAIN}.crt" \
  --key-file "$SSL_DIR/${DOMAIN}.key" \
  --fullchain-file "$SSL_DIR/${DOMAIN}.fullchain.crt" \
  --ca-file "$SSL_DIR/${DOMAIN}.ca.crt"

echo "ℹ️ 给 vhosts 添加 SSL 内容"
cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot "${CONTAINER_SITE_ROOT}"
    php_admin_value open_basedir "${CONTAINER_SITE_ROOT}:/tmp/:/var/tmp/:/proc/"
    <Directory "${CONTAINER_SITE_ROOT}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot "${CONTAINER_SITE_ROOT}"
    php_admin_value open_basedir "${CONTAINER_SITE_ROOT}:/tmp/:/var/tmp/:/proc/"
    SSLEngine on
    SSLCertificateFile "/etc/apache2/ssl/${DOMAIN}.fullchain.crt"
    SSLCertificateKeyFile "/etc/apache2/ssl/${DOMAIN}.key"

    <Directory "${CONTAINER_SITE_ROOT}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

#    ErrorLog "${ERROR_LOG} 5M"
#    CustomLog "${ACCESS_LOG} 5M" combined
</VirtualHost>
EOF

echo "ℹ️ 重启 Apache"
# 重新加载 Apache 配置（Docker 环境）
if command -v sudo >/dev/null 2>&1; then
  sudo docker compose exec www apachectl -k graceful
else
  docker compose exec www apachectl -k graceful
fi

echo "✅ 已生成 vhost 配置：${VHOST_FILE}"
# echo "日志目录：${LOG_DIR}"
echo "✅ 证书目录：${SSL_DIR}"
echo "✅ SSL 证书已申请并安装完成。"
