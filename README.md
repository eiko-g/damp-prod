# Docker Apache + MariaDB + PHP Prod Env
自用配置，为 `php:8.5-apache` + `mariadb:lts`，加个 `phpmyadmin:latest`。

AI 辅助：Deepseek

默认 Docker 是运行在 root 模式的，如果你弄了 [rootless mode](https://docs.docker.com/engine/security/rootless/) 的话，~~就要做点修改了，具体是啥得你自己研究。~~ 已让大肥鱼改了改脚本，应该能直接用了。

快速使用：
```bash
# 复制一份配置
mv .env.example .env
# Docker，启动！
sudo docker compose up -d
# 更新镜像
sudo docker compose pull
# 重新构建 PHP 的镜像
sudo docker compose build
```

PHP 的默认时区为 `Asia/Shanghai`。

## 2C2G VPS 优化

> 此部分代码及说明为 Deepseek-4.1-Flash-1017 所写，已吃狗粮

整套参数是按「2 核 2G 内存」的小机器调的，数值都可改，集中在 `.env`（参考 `.env.example`）。`docker-compose.yml` 里所有变量都带默认值，不写 `.env` 也会按 2C2G 的默认值启动。改参数分两类：

| 参数                                                                                           | 生效方式                                                 |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| 运行时参数：端口、`TZ`、日志轮转、`DB_*`、`DB_MEM_LIMIT`/`WWW_MEM_LIMIT`、`DB_CPUS`/`WWW_CPUS` | `sudo docker compose up -d --force-recreate`             |
| 构建期参数：`PHP_*`、`PHP_OPCACHE_*`、`APACHE_*`                                               | `sudo docker compose build && sudo docker compose up -d` |

做了这些事：

- **容器内存/CPU 上限**：`DB_MEM_LIMIT`（默认 900m）、`WWW_MEM_LIMIT`（默认 768m）、`DB_CPUS`（1.0）、`WWW_CPUS`（1.5），避免某个容器把整机吃满被 OOM Killer 带走。
- **MariaDB**：`innodb_buffer_pool_size` 384M；`max_connections` 50；`table_open_cache` / `table_definition_cache` 各 400；`key_buffer_size` 16M（MyISAM 基本用不上）；`performance_schema` 关闭；慢查询日志默认开（`DB_LONG_QUERY_TIME=2` 秒）。
- **Apache prefork**：`MaxRequestWorkers` 默认 20（每个 worker 就是一个 PHP 进程），`ServerLimit` 自动跟随；`KeepAliveTimeout` 压到 3 秒，尽快释放 worker。
- **OPCache**：构建时自动启用（官方镜像编译好了但默认没开），`opcache.memory_consumption` 128M。
- **日志轮转**：容器日志 `max-size=10m`、`max-file=3`，小硬盘不会被 json-file 日志吃满。
- **启动顺序**：`www` 等 `db` 健康检查通过后再启动，避免小机器上反复重启空转 CPU。

内存换算：`APACHE_MAX_REQUEST_WORKERS × PHP_MEMORY_LIMIT` 是理论上限（默认 20 × 256M），实际按业务压测调。2G 机器建议再开 1~2G swap 兜底：

```bash
# 部分 VPS 不一定给设置 SWAP，需自行判断
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

看实时占用、改完参数后重启：

```bash
sudo docker stats --no-stream
sudo docker compose up -d --force-recreate
```

另外 MariaDB 的调参也可以写进 `./userdata/sql_conf/*.cnf`，但 **命令行参数优先级更高**，`.env` 里同名项会覆盖 `.cnf` 里的值。

---

建议安装 [acme.sh](https://github.com/acmesh-official/acme.sh/wiki/%E8%AF%B4%E6%98%8E)，然后使用 `sudo -u <当前用户名> ./addvhost.sh` 来 **以当前用户权限** 添加虚拟主机配置。

脚本会自动检查 Docker 运行模式：若 Docker 运行在 root 模式（需要 root 权限才能操作 Docker），而你又直接以 root 身份执行 `sudo ./addvhost.sh`，脚本会退出并提示改用上面的 `sudo -u <当前用户名> ./addvhost.sh`，避免生成的 vhost 配置与站点目录归属 root。

要使用 IPv6 的话，得去编辑 `/etc/docker/daemon.json`，加入下面的内容：

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/64",
  "ip6tables": true
}
```

然后 `sudo systemctl restart docker` 重启一下 Docker。

## PHP-Apache
具体配置基本在 `./dockerfile` 里了，使用 `8.5`，安装 `composer`，默认使用 `php.ini-production` 配置。

PHP 安装的扩展：

- mysqli
- pdo
- pdo_mysql
- zip
- mbstring
- gd
- fileinfo
- exif
- intl
- imagick

进 Docker 系统的 bash：

```bash
sudo docker compose exec www bash
```

## MariaDB
用的 LTS 线，简单配置了一些，应该可以直接用了。

## 参考文案
- [sprintcube/docker-compose-lamp](https://github.com/sprintcube/docker-compose-lamp)
- [jersonmartinez/docker-lamp](https://github.com/jersonmartinez/docker-lamp)
- [MariaDB 官方 Docker](https://hub.docker.com/_/mariadb)
- [PHP 官方 Docker](https://hub.docker.com/_/php)