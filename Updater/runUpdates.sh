#!/bin/bash 
export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin

#CONFIGURE FOR YOUR NEEDS
FULLPATH=/usr/local/bin/Updater
FILEPATH=$FULLPATH/updateScripts/*.sh

#DO NOT MODIFY BELOW
function PerformUpdate {
    #echo Parameter1: $1 
    
    currenttime=`date +%Y-%m-%d/%H:%M:%S`
	logger -s  "($currenttime) Performing update of :  $1"
	#try to run the scipt file to do the necessary updates
	if [[ -s "$1.sh" ]] ; then
	    #Corresponding script file is empty, try to restart the service
	    logger -s  "Script $1.sh is empty, cannot run it"
	else
	    #Corresponding serv file has data, try to run it
	    $FULLPATH/updateScripts/$1.sh
	fi ;
}  

cd $FULLPATH
for filename in $FILEPATH
do
    echo "Parsing $filename"
    ext=${filename##*.}
    temp=`basename $filename $ext`
    #get rid of leading .
    SERVICENAME=${temp%.}
    #echo running: $SERVICENAME    
    PerformUpdate $SERVICENAME
done;
logger -s "Cleanup Unused Docker images"
docker image prune -a



