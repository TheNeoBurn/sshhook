#! /bin/sh
while true
do
	# Connect to remote server forwarding the port
	ssh -i /root/.ssh/sshhook -g -R \*:222:localhost:22 sshhook@remote.server
	# Give some pause bewteen attempts
	sleep 5
done
