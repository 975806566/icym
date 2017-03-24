-module( emqttd_convert ).

-export([ get_real_uid/2,
          get_real_uid_list/1,
          get_uname_by_ruid/1
        ]).

get_real_uid( _Sdk, Username ) ->
    Username.

get_real_uid_list( Username ) ->
    [ Username ].

get_uname_by_ruid( RUid ) ->
    RUid.
