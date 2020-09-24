#!/bin/bash

output(){
  echo -e '\e[36m'$1'\e[0m';
}
warning(){
  echo -e '\e[36m'$1'\e[0m';
}

setup(){
  output "Installation script for Pterodactyl."
  output "YOU ARE NOT SUPPOSED TO RUN THIS YOURSELF."
  output "UNLESS YOU KNOW WHAT IT DOES."
  output "-JumpWatch/HypersMC"
  output ""

  checkos

  if [ "$EUID" -ne 0 ]; then
    output "Reminder run this script as root!"
    exit 3
  fi
  if [ "$lsb_dist" = "ubuntu" ]; then
    apt-get update --fix-missing
    apt-get -y install software-properties-common
    add-apt-repository -y universe
    apt-get -y install virt-what curl
  fi
  output "virt detection"

  virt_server=$(echo $(virt-what))
  output "$virt_server"
  if [ "$virt_server" != "" ] && [ "$virt_server" != "kvm" ] && [ "$virt_server" != *"vmware"* ] && [ "$virt_server" != *"hyperv"* ] && [ "$virt_server" != *"openvz lxc"* ] && [ "$virt_server" != *"xen xen-hvm"* ] && [ "$virt_server" != *"xen xen-hvm aws"* ]; then
    warning "Sorry but this install script won't continue on a unsupported Virtualization."
    output "Installation cancelled!"
    exit 5
  fi
  output "before we start you need to type following:"
  output "FQDN (just the http:// or https:// no ip. all lowercase):"
  read FQDNB
  output "FQDN (without https:// or http://):"
  read FQDN
  output "Email:"
  read Email
  repositories

}

checkos(){
  if [ -r /etc/os-release ]; then
    lsb_dist="$(. /etc/os-release && echo "$ID")"
    dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
    if [ $lsb_dist = "rhel" ]; then
      dist_version="$(echo $dist_version | awk -F. '{print $1}')"
    fi
  else
    exit 1
  fi
  if [ "$lsb_dist" =  "ubuntu" ]; then
    if [ "$dist_version" != "20.04" ] && [ "$dist_version" != "18.04" ] && [ "$dist_version" != "16.04" ]; then
      output "Unsupported Ubuntu detected. Only Ubuntu 20.04, 18.04 and 16.04 are supported."
      exit 2
    fi
  else
    output "operating system not supported!"
    output ""
    output "Please use following Operating systems."
    output "Supported OS:"
    output "Ubuntu: 20.04, 18.04"
    exit 2
  fi
}
repositories(){
  output "repositories setup"
  if [ "$lsb_dist" = "ubuntu" ]; then
    if [ "$dist_version" = "18.04" ] || [ "$dist_version" = "20.04" ]; then
      apt -y install software-properties-common curl
      LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
      add-apt-repository -y ppa:chris-lea/redis-server
      curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
      apt update
      apt-add-repository universe
      apt -y install php7.2 php7.2-cli php7.2-gd php7.2-mysql php7.2-pdo php7.2-mbstring php7.2-tokenizer php7.2-bcmath php7.2-xml php7.2-fpm php7.2-curl php7.2-zip mariadb-server nginx tar unzip git redis-server
    fi
  fi
  database
}
database(){
  output "please type login root password:"
  read rootpass
  output "please type an database name for the panel:"
  read dbname
  output "please type database ip: (127.0.0.1 example)"
  read dbip
  output "please type an database password for the panel:"
  read dbpass
  s1="USE mysql;"
  s2="CREATE USER '$dbname'@'$dbip' IDENTIFIED BY '$dbpass';"
  s3="CREATE DATABASE panel;"
  s4="GRANT ALL PRIVILEGES ON panel.* TO '$dbname'@'$dbip' WITH GRANT OPTION;"
  s5="FLUSH PRIVILEGES;"
  SQL="${s1}${s2}${s3}${s4}${s5}"
  mysql -u root -e "$SQL"
  composerandenv
}

composerandenv(){
  output "database done. Downloading panel."
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl
  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/v0.7.18/panel.tar.gz
  tar --strip-components=1 -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  cp .env.example .env
  curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
  /usr/local/bin/composer install --no-dev --optimize-autoloader
  php artisan key:generate --force
  php artisan p:environment:setup -n --author=$Email --url=$FQDNB$FQDN --timezone=America/New_York --cache=redis --session=database --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379
  php artisan p:environment:database --host=$dbip --port=3306 --database=panel --username=$dbname --password=$dbpass
  output "select your mail method"
  php artisan p:environment:mail
  output "if everything is correct everything should be working now!"
  php artisan migrate --seed --force


  output "please type Admin user username:"
  read AUsername
  output "please type Admin user first-name:"
  read FirstName
  output "please type Admin user last-name:"
  read LastName
  output "please type Admin user password:"
  read Apassword

  php artisan p:user:make --email=$Email --admin=1 --username=$AUsername --name-first=$FirstName --name-last=$LastName --password=$Apassword
  output "making permissions for webserver"
  chown -R www-data:www-data * /var/www/pterodactyl
  output "doing crontab"
  (crontab -l ; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1")| crontab -
  service cron restart
  output "making & setting up pteroq.service inside /etc/systemd/system/"
  cat > /etc/systemd/system/pteroq.service <<- 'EOF'
# Pterodactyl Queue Worker File
# ----------------------------------

[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
# On some systems the user and group might be different.
# Some systems use `apache` or `nginx` as the user and group.
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl enable --now redis-server
  sudo systemctl enable --now pteroq.service
  webserversetup
}

webserversetup(){
  output "Removing default nginx config"
  rm -rf /etc/nginx/sites-enabled/default
  if [ "$FQDNB" == "https://" ]; then
    output "Https ssl key is being ,made"
    sudo add-apt-repository ppa:certbot/certbot
    sudo apt update
    sudo apt install certbot
    systemctl stop apache
    service nginx stop
    certbot certonly --standalone --email "$Email" --agree-tos -d "$FQDN" --non-interactive
    service nginx restart
    output "Https webserver is being made"
    echo '
server {
    listen 80;
    server_name '"$FQDN"';
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name '"$FQDN"';

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/'"$FQDN"'/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/'"$FQDN"'/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php7.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
' | sudo -E tee /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    systemctl restart nginx
    output "Https webserver done."
  elif [ "$FQDNB" == "http://" ]; then
    systemctl stop apache
        echo '
server {
    listen 80;
    server_name '"$FQDN"';

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php7.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
' | sudo -E tee /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    systemctl restart nginx
    output "Http webserver done."
  fi
  installdaemonakanode
}

installdaemonakanode(){
  cd /root
  output "doing daemon installation"
  curl -sSL https://get.docker.com/ | CHANNEL=stable bash
  systemctl enable docker
  warning "If you want swap enabled then you have to follow the guide."
  curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
  apt -y install nodejs make gcc g++
  mkdir -p /srv/daemon /srv/daemon-data
  cd /srv/daemon
  curl -L https://github.com/pterodactyl/daemon/releases/download/v0.6.13/daemon.tar.gz | tar --strip-components=1 -xzv
  npm install --only=production --no-audit --unsafe-perm
  output "installation finished!"
  output "making wings"
  cat > /etc/systemd/system/wings.service <<- 'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service

[Service]
User=root
#Group=some_group
WorkingDirectory=/srv/daemon
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/bin/node /srv/daemon/src/index.js
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now wings
  coreinfo
}
coreinfo(){
  output ""
  output "your website link is: $FQDNB$FQDN"
  output ""
  output "your database credentials:"
  output "DBIP: $dbip"
  output "Database: panel"
  output "DBUser: $dbname"
  output "DBPass: $dbpass"
  output ""
  output "Login:"
  output "Email: $Email"
  output "Username: $AUsername"
  output "First name: $FirstName"
  output "Last name: $LastName"
  output "Password: $Apassword"
}
#yeet stuff
setup