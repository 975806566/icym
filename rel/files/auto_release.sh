#!/bin/sh

cd ../..

cd ./rel

rm -rf im_server*

cd ..

./rebar get-d
./rebar compile
./rebar generate

cd rel

zip -r im_server.zip im_server


scp im_server.zip root@192.168.199.236:/opt/etcloud/im_server.zip

scp im_server.zip root@192.168.199.234:/opt/etcloud/im_server.zip
