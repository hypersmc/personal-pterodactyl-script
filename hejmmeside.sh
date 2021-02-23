#!/bin/bash

output(){
  echo -e '\e[36m'$1'\e[0m';
}
warning(){
  echo -e '\e[36m'$1'\e[0m';
}


start(){
	output "Installere Nginx (Ikke Apache fordi F Apache det er skrald!"
	apt -y install software-properties-common curl
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    add-apt-repository -y ppa:chris-lea/redis-server
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    apt update
    apt-add-repository universe
    apt -y install php7.2 php7.2-cli php7.2-gd php7.2-mysql php7.2-pdo php7.2-mbstring php7.2-tokenizer php7.2-bcmath php7.2-xml php7.2-fpm php7.2-curl php7.2-zip mariadb-server nginx tar unzip git redis-server
    clear
    warning "Der skete en fejl.... åh nejj"
    output "Jokes on you lol!"
}
start