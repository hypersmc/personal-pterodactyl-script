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

  if [ "$EUID" -ne 0]; then
    output "Run this script as root!"
    exit 3
  fi
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
        if  [ "$dist_version" != "20.04" ] && [ "$dist_version" != "18.04" ] && [ "$dist_version" != "16.04" ]; then
            output "Unsupported Ubuntu detected. Only Ubuntu 20.04, 18.04 and 16.04 are supported."
            exit 2
        fi
    elif [ "$lsb_dist" = "debian" ]; then
        if [ "$dist_version" != "10" ] &&[ "$dist_version" != "9" ]; then
            output "Unsupported Debian detected. Only Debian 10 and 9 are supported."
            exit 2
        fi
    elif [ "$lsb_dist" = "fedora" ]; then
        if [ "$dist_version" != "32" ] && [ "$dist_version" != "31" ]; then
            output "Unsupported Fedora detected. Only Fedora 32 and 31 are supported."
            exit 2
        fi
    elif [ "$lsb_dist" = "centos" ]; then
        if [ "$dist_version" != "8" ] && [ "$dist_version" != "7" ]; then
            output "Unsupported CentOS detected. Only CentOS 8 and 7 are supported."
            exit 2
        fi
    elif [ "$lsb_dist" = "rhel" ]; then
        if  [ $dist_version != "8" ]; then
            output "Unsupported RHEL detected. Only RHEL 8 is supported."
            exit 2
        fi
    elif [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "debian" ] && [ "$lsb_dist" != "centos" ]; then
        output "operating system not supported!"
        output ""
        output "Please use following Operating systems."
        output "Supported OS:"
        output "Ubuntu: 20.04, 18.04"
        output "Debian: 10, 9"
        output "Fedora: 32, 31"
        output "CentOS: 8, 7"
        output "RHEL: 8"
        exit 2
    fi
}