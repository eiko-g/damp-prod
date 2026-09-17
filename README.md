# Docker Apache + MariaDB + PHP Prod Env
自用配置，为 `php:8.5-apache` + `mariadb:lts`，加个 `phpmyadmin:latest`。

默认 Docker 是运行在 root 模式的，如果你弄了 [rootless mode](https://docs.docker.com/engine/security/rootless/) 的话，就要做点修改了，具体是啥得你自己研究。

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

建议安装 [acme.sh](https://github.com/acmesh-official/acme.sh/wiki/%E8%AF%B4%E6%98%8E)，然后使用 `sudo ./addvhost.sh` 来添加虚拟主机配置。

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