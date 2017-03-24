#!/bin/bash
if [ $# -ne 2 ]
then
  echo "*****Input the necessary parameters: local_ip cookie"
  echo "*****Call the script like: sh auto_config.sh 192.168.199.111 def_cookie"
  exit 1
fi

local_ip=$1
cookie=$2
cp -f /opt/etcloud/im_server/etc/vm.args.in /opt/etcloud/im_server/etc/vm.args
cp -f /opt/etcloud/im_server/etc/sys.config.in /opt/etcloud/im_server/etc/sys.config

sed -i "/setcookie/s/def_cookie/$cookie/g" /opt/etcloud/im_server/etc/vm.args
sed -i "/name/s/[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}/$local_ip/g" /opt/etcloud/im_server/etc/vm.args
sed -i "/eredis/s/[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}/$local_ip/g" /opt/etcloud/im_server/etc/sys.config
exit 0
