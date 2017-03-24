#!/bin/bash

echo Start build im_server
echo ""

rm -rf deps
rm -rf rel/im_server
rm -rf rel/im_server.zip
git pull
chmod +x rebar
chmod +x rel/files/im_server 
chmod +x rel/files/auto_config.sh 
./rebar get-deps
./rebar compile
./rebar generate
cd rel
zip -r im_server.zip im_server/
echo "============= End =============="

exit 0;
