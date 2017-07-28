#!/bin/bash

FILE_PATH=/opt/etcloud/damon_log/

mkdir -p $FILE_PATH

LOG_FILE=$FILE_PATH/demon.log


while true
do

    if (( `ps -ef | grep 'im_server/erts-8.0/bin/beam.smp' | grep -v grep | wc -l` <= 0 )); then
        echo "im_server done $`date `" >>   $LOG_FILE
        /opt/etcloud/im_server/bin/im_server start
    fi

    if (( `ps -ef | grep 'log_server/erts-8.0/bin/beam' | grep -v grep | wc -l` <= 0 )); then
        echo "log_server done $`date `" >>  $LOG_FILE
        /opt/etcloud/log_server/bin/log_server start
    fi


    if (( `ps -ef | grep 'ham_server/erts-8.0/bin/beam' | grep -v grep | wc -l` <= 0 )); then
        echo "ham_server done $`date `" >>  $LOG_FILE
        /opt/etcloud/ham_server/bin/ham_server start
    fi

    sleep 5
done

