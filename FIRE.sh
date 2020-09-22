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

  output "virt detection"
  if [ "$lsb_dist" = "ubuntu" ]; then
    apt-get update --fix-missing
    apt-get -y install software-properties-common
    add-apt-repository -y universe
    apt-get -y install virt-what curl
  fi
  virt_server=$(echo $(virt-what))
  output "$virt_server"
  if [ "$virt_server" != "" ] && [ "$virt_server" != "kvm" ] && [ "$virt_server" != "vmware" ] && [ "$virt_server" != "hyperv" ] && [ "$virt_server" != "openvz lxc" ] && [ "$virt_server" != "xen xen-hvm" ] && [ "$virt_server" != "xen xen-hvm aws" ]; then
    warning "Sorry but this install script won't continue on a unsupported Virtualization."
    output "Installation cancelled!"
    exit 5
  fi
  output "before we start you need to type following:"
  output "FQDN (With or without https):"
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
  output "please type root password:"
  read rootpass
  output "please type the database name for the panel:"
  read dbname
  output "please type the database ip:"
  read dbip
  output "please type the database password for the panel:"
  read dbpass
  s1="USE mysql;"
  s2="CREATE USER '$dbname'@'$dbip' IDENTIFIED BY '$dbpass';"
  s3="CREATE DATABASE panel;"
  s4="GRANT ALL PRIVILEGES ON panel.* TO '$dbname'@'$dbip' WITH GRANT OPTION;"
  s5="FLUSH PRIVILEGES;"
  SQL="${s1}${s2}${s3}${s4}${s5}"
  mysql -u root -p "$rootpass" -e "$SQL"
  composerandenv
}

composerandenv(){
  output "database done. Downloading panel."
  curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl
  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/v0.7.18/panel.tar.gz
  tar --strip-components=1 -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  cp .env.example .env
  composer install --no-dev --optimize-autoloader
  php artisan key:generate --force
  php artisan p:environment:setup -n --author=$Email --url=$FQDN --timezone=America/New_York --cache=redis --session=database --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379
  php artisan p:environment:database --host=$dbip --port=3306 --database=$panel --username=$dbname --password=$dbpass
  output "select your mail method"
  php artisan p:environment:mail
  output "if everything is correct everything should be working now!"
  php artisan migrate --seed --force
  php artisan p:user:make --email=$Email --admin=1
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
  warning "You have to make webservice file yourself."
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
  output "your website link is: $FQDN"
  output ""
  output "your database credentials:"
  output "DBIP: $dbip"
  output "Database: panel"
  output "DBUser: $dbname"
  output "DBPass: $dbpass"
  output ""
  output "login:"
  output "email: $Email"
  output "username: notset"
  output "password: notset"
}
#yeet stuff
setup