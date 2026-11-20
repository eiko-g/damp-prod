FROM php:8.5-apache

ARG PHP_MEMORY_LIMIT=256M
ARG PHP_MAX_EXECUTION_TIME=30
ARG PHP_UPLOAD_MAX_FILESIZE=20M
ARG PHP_POST_MAX_SIZE=20M
ARG PHP_TIMEZONE=Asia/Shanghai

# OPCache（2C2G 小机器上开着能省不少 CPU）
ARG PHP_OPCACHE_MEMORY=128M
ARG PHP_OPCACHE_MAX_FILES=10000
ARG PHP_OPCACHE_VALIDATE_TIMESTAMPS=1
ARG PHP_OPCACHE_REVALIDATE_FREQ=2
ARG PHP_OPCACHE_JIT=off
ARG PHP_OPCACHE_JIT_BUFFER_SIZE=0

# Apache prefork（每个 worker = 一个 PHP 进程，2G 内存下数量要压住）
ARG APACHE_START_SERVERS=5
ARG APACHE_MIN_SPARE_SERVERS=5
ARG APACHE_MAX_SPARE_SERVERS=8
ARG APACHE_MAX_REQUEST_WORKERS=20
ARG APACHE_KEEPALIVE_TIMEOUT=3
ARG APACHE_MAX_KEEPALIVE_REQUESTS=100

ENV DEBIAN_FRONTEND=noninteractive

# 安装 Composer，环境变量是 Docker 镜像内使用时用的，不然有 Warning
# COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
# ENV COMPOSER_CACHE_READ_ONLY=1

# 安装 PIE
COPY --from=ghcr.io/php/pie:bin /pie /usr/bin/pie

# 使用 Prod 配置
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# 使用 Dev 配置
# RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# 更新镜像内部依赖，然后装点东西
# PHP 8.5 已内置 OPCache
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libpng-dev \
    libzip-dev \
    zlib1g-dev \
    libonig-dev \
    # libicu 是给 intl 用的
    libicu-dev \
    # libmagicwand 是给 Imagick 用的
    libmagickwand-dev \
    curl \
    zip \
    unzip \
    # sendmail \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-install -j$(nproc) \
    mysqli \
    pdo \
    pdo_mysql \
    zip \
    mbstring \
    fileinfo \
    exif \
    intl

# 用 PIE 装扩展
RUN pie install imagick/imagick

# PHP 的配置
RUN echo "memory_limit = ${PHP_MEMORY_LIMIT}" >> /usr/local/etc/php/conf.d/docker-php-memory-limit.ini \
    && echo "max_execution_time = ${PHP_MAX_EXECUTION_TIME}" >> /usr/local/etc/php/conf.d/docker-php-max-execution-time.ini \
    && echo "upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}" >> /usr/local/etc/php/conf.d/docker-php-upload-max-filesize.ini \
    && echo "post_max_size = ${PHP_POST_MAX_SIZE}" >> /usr/local/etc/php/conf.d/docker-php-post-max-size.ini \
    && echo "expose_php = off" >>  /usr/local/etc/php/conf.d/docker-php-expose-php.ini \
    && echo "date.timezone = ${PHP_TIMEZONE}" >>  /usr/local/etc/php/conf.d/docker-php-date-timezone.ini

# OPCache 的配置。官方镜像里 opcache 是编译好了但默认没启用的，有 .so 才启用
RUN EXT_DIR="$(php -r 'echo ini_get("extension_dir");')" \
    && if [ -f "$EXT_DIR/opcache.so" ] && ! php -m | grep -qi '^Zend OPcache$'; then docker-php-ext-enable opcache; fi \
    && { \
        echo "opcache.enable = 1"; \
        echo "opcache.enable_cli = 0"; \
        echo "opcache.memory_consumption = ${PHP_OPCACHE_MEMORY}"; \
        echo "opcache.max_accelerated_files = ${PHP_OPCACHE_MAX_FILES}"; \
        echo "opcache.validate_timestamps = ${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"; \
        echo "opcache.revalidate_freq = ${PHP_OPCACHE_REVALIDATE_FREQ}"; \
        echo "opcache.jit = ${PHP_OPCACHE_JIT}"; \
        echo "opcache.jit_buffer_size = ${PHP_OPCACHE_JIT_BUFFER_SIZE}"; \
    } > /usr/local/etc/php/conf.d/docker-php-opcache.ini

# Apache 的配置
RUN a2enmod rewrite headers ssl expires

# Apache prefork 调优：ServerLimit 自动跟着 MaxRequestWorkers 走，省得还要多改一个值
RUN MAX_WORKERS="${APACHE_MAX_REQUEST_WORKERS}" \
    && SERVER_LIMIT=$(( MAX_WORKERS + 4 )) \
    && printf '%s\n' \
        "<IfModule mpm_prefork_module>" \
        "    StartServers           ${APACHE_START_SERVERS}" \
        "    MinSpareServers        ${APACHE_MIN_SPARE_SERVERS}" \
        "    MaxSpareServers        ${APACHE_MAX_SPARE_SERVERS}" \
        "    ServerLimit            ${SERVER_LIMIT}" \
        "    MaxRequestWorkers      ${MAX_WORKERS}" \
        "    MaxConnectionsPerChild 0" \
        "</IfModule>" \
        > /etc/apache2/mods-available/mpm_prefork.conf \
    && printf '%s\n' \
        "KeepAlive On" \
        "MaxKeepAliveRequests ${APACHE_MAX_KEEPALIVE_REQUESTS}" \
        "KeepAliveTimeout ${APACHE_KEEPALIVE_TIMEOUT}" \
        > /etc/apache2/conf-available/zz-damp-tuning.conf \
    && a2enconf zz-damp-tuning
RUN sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf \
    && sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf

# 弄个非 root 用户
RUN useradd -r -u 1000 -g www-data webuser

# 配置 PHP 的日志目录跟权限
RUN mkdir -p /var/log/php \
    && chown -R webuser:www-data /var/log/php \
    && chmod 755 /var/log/php

# 设置网站目录的权限
RUN chown -R webuser:www-data /var/www/html \
    && chmod -R 750 /var/www/html

# 切换到非 root 用户
USER webuser

# Health check
# HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
#     CMD curl -f http://localhost/ || exit 1