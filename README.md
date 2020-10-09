# lnmp
Centos7自动化安装、配置最新版Nginx、PHP、Mariadb、Redis和phpMyadmin

使用方法

1.下载所有文件

2.根据自己实际情况修改init.sh中的自定义变量

3.linux下给init.sh添加执行权限（chmod +x init.sh），然后执行

4.自动下载、安装、配置软件，配置完毕后自动重启，所用时间仅与网速有关（需下载300MB左右的软件）

可选项
5.配置https，参见
https://certbot.eff.org/lets-encrypt/centosrhel7-nginx

6.Mysql备份，参见
https://github.com/teddysun/across/blob/master/backup.sh
