#!/bin/bash

############ 自定义变量开始 #########

#开发环境还是正式上线环境，开发环境开启错误提示
env='production'
#env='development'


#Nginx监听域名（也是thinkphp项目目录名）、端口
domain='test.com'
port='80'

#生成github/码云用到的私钥公钥对，用于克隆项目
email='test@qq.com'

#设置root用户密码
rootPassword='123456'

#创建可远程登录Mysql用户
name='test'
password='123456'

############ 自定义变量结束 #########


#查看生成的公钥，复制到github/码云公钥中，才能使用git clone项目
ssh-keygen -t rsa -C "$email" -P '' -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub


#添加Nginx、MariaDB官方仓库
cat > /etc/yum.repos.d/nginx.repo <<'EOF'
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
EOF

curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

yum --exclude=kernel* -y update

#从remi源安装最新版php、redis等
yum -y install https://rpms.remirepo.net/enterprise/remi-release-7.rpm

yum -y install yum-utils

yum-config-manager --enable remi-php74


yum -y install nginx php74 php-fpm php-opcache mariadb mariadb-client mariadb-server mysql-proxy redis php-mysqlnd php-redis php-gd php-mbstring vim wget mlocate psmisc openssl openssl-devel curl curl-devel ntpdate git composer nodejs phpMyAdmin expect screen

#备份配置文件
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
cp /etc/php.ini /etc/php.ini.bak
cp /etc/my.cnf /etc/my.cnf.bak


#修改Nginx配置
sed -i "s/#gzip  on;/gzip  on;/g" /etc/nginx/nginx.conf
sed -i '$d' /etc/nginx/nginx.conf



if [ "$env" == 'development' ]
then
    sed -i "/gzip  on;/a\    server_tokens on;" /etc/nginx/nginx.conf
else
    sed -i "/gzip  on;/a\    server_tokens off;" /etc/nginx/nginx.conf
fi



cat >> /etc/nginx/nginx.conf <<EOF

    server {

        listen       ${port} default_server;
        listen       [::]:${port} default_server;
        server_name  ${domain};
        root         /usr/share/nginx/${domain}/public;

EOF

mkdir -p /usr/share/nginx/${domain}

cat >> /etc/nginx/nginx.conf <<'EOF'
        location / {
        index index.html index.htm index.php;
        if (!-e $request_filename) {
            rewrite ^/(.*)$ /index.php/$1 last;
            break;
        }
        }

        location ~ \.php(.*)$ {
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            fastcgi_split_path_info ^(.+\.php)(.*)$;
            fastcgi_param   PATH_INFO $fastcgi_path_info;
            fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
            fastcgi_param  PATH_TRANSLATED  $document_root$fastcgi_path_info;
            include        fastcgi_params;
        }

        location ~ .*\.(jpg|png|gif|jpeg|webm|rar|zip|7z)$ {
            expires 7d;
        }

        location ~ .*\.(js|css)$ {
            expires 1d;
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }

    }
}
EOF


#修改php配置
sed -i "s#;date.timezone =#date.timezone = Asia/Shanghai#g" /etc/php.ini
sed -i "s#;max_input_vars = 1000#max_input_vars = 10240#g" /etc/php.ini
sed -i "s#upload_max_filesize = 2M#upload_max_filesize = 128M#g" /etc/php.ini
sed -i "s#max_file_uploads = 20#max_file_uploads = 128#g" /etc/php.ini
sed -i "s#post_max_size = 8M#post_max_size = 128M#g" /etc/php.ini
sed -i "s#session.cookie_httponly =#session.cookie_httponly = 1#g" /etc/php.ini
sed -i "s#short_open_tag = Off#short_open_tag = On#g" /etc/php.ini


if [ "$env" == 'development' ]
then

    sed -i "s#display_errors = Off#display_errors = On#g" /etc/php.ini
    sed -i "s#error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT#error_reporting = E_ALL#g" /etc/php.ini
    sed -i "s#expose_php = Off#expose_php = On#g" /etc/php.ini

else

    sed -i "s#display_errors = On#display_errors = Off#g" /etc/php.ini
    sed -i "s#expose_php = On#expose_php = Off#g" /etc/php.ini

fi


#开启opcache会导致php代码修改后不能及时生效，rm -rf /tmp/*php-fpm*来删除opcache
cat >> /etc/php.ini <<'EOF'

[opcache]
zend_extension = opcache.so
opcache.enable = 1
opcache.enable_cli = 1
opcache.file_cache = /tmp
opcache.huge_code_pages = 1
EOF


#修改MariaDB配置
echo "[mysqld]" >> /etc/my.cnf
echo "lower_case_table_names = 1" >> /etc/my.cnf
echo "max_connections = 1024" >> /etc/my.cnf


#监听子域名phpMyAdmin，如果为本地虚拟机也需要为此子域名绑定hosts映射
cat >> /etc/nginx/conf.d/phpMyAdmin.conf <<EOF
server {
        listen   80; 
        server_name phpmyadmin.${domain};
        root /usr/share/phpMyAdmin;

EOF
cat >> /etc/nginx/conf.d/phpMyAdmin.conf <<'EOF'
    location / { 
        index  index.php;
    }   

    location ~* ^.+.(jpg|jpeg|gif|css|png|js|ico|xml)$ {
        access_log        off;
        expires           30d;
    }   

    location ~ /\.ht {
        deny  all;
    }   

    location ~ /(libraries|setup/frames|setup/libs) {
        deny all;
        return 404;
    }   

    location ~ \.php$ {
        include /etc/nginx/fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /usr/share/phpMyAdmin$fastcgi_script_name;
    }   
}
EOF


#cookie加密秘钥
sed -i '102d' /usr/share/phpMyAdmin/libraries/config.default.php
sed -i "102i "'$'"cfg['blowfish_secret'] = '"`date | md5sum | awk '{print $1}'`"';" /usr/share/phpMyAdmin/libraries/config.default.php


#设置开机项并立即启动服务
systemctl enable firewalld.service
systemctl enable nginx.service
systemctl enable php-fpm.service
systemctl enable mariadb.service
systemctl enable redis.service
systemctl enable crond.service


systemctl start firewalld.service
systemctl start nginx.service
systemctl start php-fpm.service
systemctl start mariadb.service
systemctl start redis.service
systemctl start crond.service


#开放80、443端口
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --reload


#vim和vi默认显示行号和不区分大小写，会提示错误不用管
echo "set nu" >> /etc/vimrc
echo "set ic" >> /etc/vimrc
echo "set nu" >> /etc/virc
echo "set ic" >> /etc/virc

source /etc/vimrc 2>/dev/null
source /etc/virc 2>/dev/null


#定义命令别名
echo "alias ls='ls -lhit --color'" >> /etc/bashrc
echo "alias vi='vim'" >> /etc/bashrc
echo "alias grep='egrep'" >> /etc/bashrc
echo "alias egrep='egrep -ni --color=auto'" >> /etc/bashrc

source /etc/bashrc


#更新系统时间
ntpdate -u time.windows.com
date


chmod 744 ./mysqlSecureInstallation.exp
chmod 744 ./createNewUser.exp


#弹出mysql安全配置向导
./mysqlSecureInstallation.exp $rootPassword


#导入phpMyadmin数据库，创建可以远程登录用户
./createNewUser.exp $rootPassword $name $password

updatedb
reboot
