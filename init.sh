#!/bin/bash

############ 自定义变量开始 #########

#开发环境还是正式上线环境，开发环境开启错误提示
env='production'
#env='development'

#生成github/码云用到的私钥公钥对，用于克隆项目
email='test@qq.com'

#Nginx监听域名（也是thinkphp项目目录名）、端口
domain='test.com'
port='80'

#php版本
phpVersion=80

#MariaDB端口和root用户密码
mariadbPort='3306'
rootPassword='123456'

#创建可远程登录MariaDB用户
name='test'
password='123456'

#redis端口和密码
redisPort='6379'
redisPassword='123456'


############ 自定义变量结束 #########

releasever=$(rpm -q centos-release | awk -F '[-.]' '{print $3}')

#关闭selinux
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

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

#升级软件不升级Linux内核
yum --exclude=kernel* -y update

#从remi源安装最新版php、redis等
yum -y install epel-release
yum -y install centos-release-scl
yum -y install remi-release
yum -y install https://repo.ius.io/ius-release-el${releasever}.rpm
yum -y install https://rpms.remirepo.net/enterprise/remi-release-${releasever}.rpm
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum -y install https://www.elrepo.org/elrepo-release-${releasever}.el${releasever}.elrepo.noarch.rpm
yum -y localinstall --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-${releasever}.noarch.rpm

sed -i "0,/enabled=0/s/enabled=0/enabled=1/" /etc/yum.repos.d/remi-php${phpVersion}.repo

yum repolist enabled
yum clean all
yum makecache

yum -y install nginx php${phpVersion} php-fpm php-opcache php-devel mariadb mariadb-server php-mysqlnd php-pdo php-json redis php-redis php-gd php-mbstring openssl openssl-devel curl curl-devel php-pear 
yum -y install screen expect vim wget mlocate psmisc git nodejs

curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

pecl channel-update pecl.php.net

#备份配置文件
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
cp /etc/php.ini /etc/php.ini.bak
cp /etc/my.cnf /etc/my.cnf.bak
cp /etc/redis.conf /etc/redis.conf.bak


#修改Nginx配置
if [ "$env" == 'development' ]
then
    sed -i "/gzip  on;/a\    server_tokens on;" /etc/nginx/nginx.conf
else
    sed -i "/gzip  on;/a\    server_tokens off;" /etc/nginx/nginx.conf
fi

publicPath=/usr/share/nginx/${domain}/public

#每个虚拟主机配置1个独立文件
cat >> /etc/nginx/conf.d/${domain}.conf <<EOF
server {

	listen       ${port};
	listen       [::]:${port};
	server_name  ${domain};
	root         ${publicPath};

EOF
cat >> /etc/nginx/conf.d/${domain}.conf <<'EOF'
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
EOF

mkdir -p ${publicPath}

cat > ${publicPath}/index.php <<EOF
<?php
phpinfo();

EOF

#修改php配置
sed -i "s#;date.timezone =#date.timezone = Asia/Shanghai#g" /etc/php.ini
sed -i "s#;max_input_vars = 1000#max_input_vars = 10240#g" /etc/php.ini
sed -i "s#upload_max_filesize = 2M#upload_max_filesize = 128M#g" /etc/php.ini
sed -i "s#max_file_uploads = 20#max_file_uploads = 128#g" /etc/php.ini
sed -i "s#post_max_size = 8M#post_max_size = 128M#g" /etc/php.ini
sed -i "s#session.cookie_httponly =#session.cookie_httponly = 1#g" /etc/php.ini


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
echo opcache.jit = 1205 >> /etc/php.d/*opcache.ini
echo opcache.jit_buffer_size = 64M >> /etc/php.d/*opcache.ini


#修改MariaDB配置
cat >> /etc/my.cnf <<EOF
[mysqld]
port=${mariadbPort}

lower_case_table_names = 1 
max_connections = 1024
local-infile=0
skip_symbolic_links=yes
symbolic-links=0

[mysqld_safe]
log-error=/var/log/mysqld.log
EOF


#修改redis配置
sed -i "s#port 6379#port ${redisPort}#g" /etc/redis.conf
sed -i "s/# requirepass foobared/requirepass ${redisPassword}/g" /etc/redis.conf


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


chmod 744 ./mysqlSecureInstallation.exp
chmod 744 ./createNewUser.exp


#Mysql安全配置向导
./mysqlSecureInstallation.exp ${rootPassword}


#创建Mysql远程登录用户
./createNewUser.exp ${rootPassword} ${name} ${password}

updatedb

date

free -mh

df -hl

echo '初始化完毕'
