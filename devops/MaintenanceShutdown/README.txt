The SyncServerII iOS client library has a mechanism to enable taking the server down for maintenance, and reporting that downtime to the iOS client app. See also https://github.com/crspybits/SyncServerII/issues/84

The following assumes the server is running on AWS/Elastic Beanstalk.

1) Edit the failover file message (e.g., production.motd.txt). The iOS client app already displays the title "The server is down for maintenance."

2) Copy the failover file to the relevant location on AWS/S3. The usage of S3 is incidental; these message files just need to be placed where the iOS app is expecting them. The URL paths for these files are specified in the Server.plist file in the iOS app. 

3) Make sure the message file on S3 has public-read permissions set. (AWS S3 will probably complain loudly at this permissions setting, but that's OK).

4) Take the server down using the "suspend.sh on" script of the relevant environment. This will take the server down to 0 EC2 instances and cause the load balancer to respond with a 503 HTTP status code, which the iOS client app uses to detect this maintenance condition. See the example message image file in this folder.

At this point, the server will not accept new requests. (I'm not sure what happens when you reduce to 0 instances, for requests that are currently running.) And you can perform database maintenance as needed. To bring the server back up, do the following:

A) If there is a server version update, deploy that update using the "deploy.sh" script for the relevant environment.
	Note that while there are 0 EC2 instances currently running, this *does* update the AWS application source bundle for the environment so that the next step will work. Though just now (4/2/19), I had to run deploy.sh a second time (with the same environment info) after the "suspend.sh off" because the environment was in a "Warning" state.

B) Use the "suspend.sh off" script to resume the server. (As noted above, if you deployed a new server version, this will run that version).

C) Remove the failover file on S3. The intent is that this file is only in place when we are doing server maintenance.