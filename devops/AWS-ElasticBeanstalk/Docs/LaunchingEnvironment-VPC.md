SETTING UP A VPC
===============

Be aware that this technique is somewhat arduous (if you find one simpler, *please* let me know!). It is something you could do just once though, and not each time you startup your server. I am not sure, but I *think* the ony expense of keeping this VPC around is the cost of the Elastic IP (see below; but see https://aws.amazon.com/vpc/pricing/).  Also, I am not sure, but I suspect you need one of these VPC's and associated subnets etc. for each of your servers.

1. I started with the directions at http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/vpc-rds.html to create a "VPC with a Public and Private Subnet".

* In the part where it talks about "Elastic IP Allocation ID" I had to first use the AWS console GUI to allocate an Elastic IP. You can find this under the EC2 Dashboard.

* In order to create the DBSubnet, I had to create another private subnet for the VPC. In a different availability zone because of an error I got when creating the DBSubnet.

2. Creating your database. While it does seem possible to apply these VPC changes to an existing database (see https://aws.amazon.com/premiumsupport/knowledge-center/change-vpc-rds-db-instance/), I haven't yet had success with that. What has worked for me is to create a new database.

* When creating the database, use your new VPC and DB subnet group.

* Create a new security group, for the database, for the new VPC.

* Change this new database security group by adding a custom rule that allows ingress from your databases security group. Seems odd, but you're going to also use that security group in your configure.yml. Note down the name of that security group. E.g., sg-d8e99ea3

3. Changes to `configure.yml`. You'll need to make specific changes to this file for your VPC. These changes are given in http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/vpc-rds.html in the section "Deploying with the AWS Toolkits, Eb, CLI, or API" see EBSEnvironments/sharedimages-staging/configure-vpc.yml, which is a full example of yml parameters for setting up a VPC. You'll need to make these changes before zipping up your application bundle.

4. After thoughts. This has worked for me. The only issue I can see is that the EC2 instance doesn't have public DNS access. Perhaps this is because of the way I set up the VPC? The drawback of this for now is that I can't access the server logs, which are just stored locally on the EC2 instance. Which will make debugging more difficult. Either I'll need to make the EC2 instance have a public DNS access, or I'll have to make the logs publicly accessible some other way.