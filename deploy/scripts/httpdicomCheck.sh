#!/bin/bash
#$1 path to conf.plist
#$2 port
#$3 log level
#$4 log path

ECHO=`/usr/bin/curl --silent http://localhost:$2/echo`
if [ ! "$ECHO" == "echo" ]
then
    DATE=`date +%Y-%m-%d:%H:%M:%S`
    printf "\r\n[ERROR] no echo from $2 at $DATE\r\n"
    killall -9 -c httpdicom
    /Users/Shared/httpdicom/bin/httpdicom $3 $2 $1 >> $4 2>&1 &
    sleep 3
    ECHO=`/usr/bin/curl --silent http://localhost:$2/echo`
    if [ ! "$ECHO" == "echo" ]
    then
        printf "[ERROR] could not restart httpdicom\r\n"
    fi
fi
