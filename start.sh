erl -pa apps/im_server/ebin/  deps/*/ebin/   -mnesia dir '"data"'  -config rel/files/sys.config -args_file rel/files/vm.args -s main
