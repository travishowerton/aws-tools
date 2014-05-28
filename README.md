aws-tools
=========

[aws-tools](https://github.com/greenkarmet/aws-tools) provides a simple API to a limited
set of AWS facilities. It also has a nice little command line tool to do AWS things.
The set of functionality is selfishly limited to exactly the set of things I currently
need from AWS.  If you are interested in extending the functionality, fork a branch and
have at it.

Fair Warning
------------
The current version 0.0.2 is not really intended for general use.  You will find the
library incomplete and lightly tested.  In addition, we expect that the API will
change as development continues.

Installation
------------

The aws-tools gem can be installed by running:

    gem install aws-tools


API Example Usage
-----------------

Documentation
-------------

API documentation for aws-tools is available at: [RubyDoc.info](http://rubydoc.info/github/greenkarmet/aws-tools/master/frames)


License
-------

aws-tools is released under the MIT license, see LICENSE for details.


Source Code
-----------

Source code for aws-tools is available on [GitHub](https://github.com/greenkarmet/aws-tools).


Issue Tracker
-------------

Please post any bugs, issues, feature requests or questions to the
[GitHub issue tracker](https://github.com/greenkarmet/aws-tools/issues).

Command Line
============

Command Line Syntax
-------------------

Many of the commands require specifying the region, environment and purpose of the object being managed, the region
can be any one of **[or, ca, va]**.  The environment and purpose are tags on the object that allow objects to be organized
loosly within groups.  In practice, we normally use enviornments of **'test'**, **'demo'**, **'development'**, or **'production'** and
purpose is much more flexible and more aligned with the use of the object such as **'app'**, **'db'**, **'mongo'**, etc.

A subset of these commands allow specifying a method of selecting an instance based on age using the **--choose** flag.
With this flag, it is possible to select the **first** instance found, the **oldest** instance or the **newest** instance.

The commands start and terminate_instance allow the flag **--keep-one** which guarantees that the aws_manager.rb will not remove
the last instance matching the criteria.

###EC2 Instance commands:

        aws_manager.rb --region region run_instance <instance template file>
        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] connect [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] start [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] [--keep-one] stop [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] get_instance_status [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] get_instance_ip [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] [--keep_one] terminate_instance [id]

####run_instance

This command builds a new instance based on the criteria in the YAML template.  This template is of the format:

        ---
        :tags:
          :environment: test
          :purpose: app
          :elastic_lb: TestAppELB
          :Name: TestappServer
          :user: ubuntu
          :security_group_ids: sg-ffffffff
          :subnet_id: subnet-fffffffff
          :elastic_ip_allocation_id: eipalloc-fffffffff
        :template:
          :image_id: ami-fffffffff
          :instance_type: m1.small
          :max_count: 1
          :min_count: 1
          :monitoring:
            :enabled: false
          :network_interfaces:
          - :associate_public_ip_address: true
            :description: Primary
            :subnet_id: subnet-fffffffff
            :delete_on_termination: true
            :device_index: 0
          :placement:
            :availability_zone: us-west-2a
            :tenancy: default

#####template

These are parameters passed directly to the AWS instance run_instance facility.  See [AWA Run Instance Documentation](http://docs.aws.amazon.com/sdkforruby/api/frames.html)

#####tags

Anything in the list of tags will be applied to the instance after it is created.  The specific tags listed
above also help direct the aws_manager.rb when the instance is started in the future.  These are:

 * **elastic_ip** - The elastic IP to bind to the instance when it starts
 * **security_group_ids** - Comma separated list of security group ids to bind the instance to when it starts
 * **subnet_id** - Subnet id to put the instance in
 * **elastic_ip_allocation_id** - If instance is in a vpc, the id of the elastic ip to bind the instance to

####connect

Connects to a specific instance using ssh

####start

Starts an instance

####stop

Stops an instance

####get_instance_status

Reports on the current status of an instance

####get_instance_ip

Reports the current public IP of an instance

####terminate_instance

Terminates an instance

###CW commands:

        aws_manager.rb --region region put_cw_metric csv_metric

Sends a metric to cloud watch.  The metric must be formatted as a csv row of the format **"namespace,name,value,dims"**

 * Note that dims is formatted as an arbitrary semicolon separated list of name:value dimensions.  For example:

        activeservers,count,10,env:prod;purp:test

###S3 commands:

        aws_manager.rb --region region put_to_bucket filename s3_filename

Put a local file (filename) to an s3 bucket defined by s3_filename.  The S3 filename must be of the format: bucketname:/s3/file/path

###RDS commands:

        aws_manager.rb --region region create_db <db template file>
        aws_manager.rb --region region [--environment environment] [--purpose purpose] delete_db [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] wait_for_db [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] get_db_status [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] get_db_endpoint [id]
        aws_manager.rb --region region [--environment environment] [--purpose purpose] purge_db_snapshots [id]

####run_instance

This command builds a new instance based on the criteria in the YAML template.  This template is of the format:

        ---
        :tags:
          :environment: demo
          :purpose: db
          :name: mazamademo
          :snapshot_name: mazamademo
          :vpc_security_group_ids: sg-24010b46
        :opts:
          :db_instance_identifier: mazamademo
          :db_subnet_group_name: testdbsubnetgroup
          :publicly_accessible: false
          :db_instance_class: db.t1.micro
          :availability_zone: us-west-2a
          :multi_az: false
          :engine: mysql

####tags

Anything in the list of tags will be applied to the instance after it is created.  In addition, there
are some required tags.  These are:

 * **name** - Database name
 * **snapshot_name** - Basename of the snapshot to use when building the database
 * **vpc_security_group_ids** - Comma-separated list of vpc_security_group_ids to be bound to instance

####opts

Parameters passed directly to RDS restore_db_instance_from_db_snapshot method.  See [RDS Restore instance from db method](http://docs.aws.amazon.com/sdkforruby/api/Aws/RDS/V20130909.html#restore_db_instance_from_db_snapshot-instance_method)


###SNS commands:

        aws_manager.rb --region region sns \"<topic_arn>\" \"subject\"

example topic_arn:

        arn:aws:sns:us-east-1:795987318935:prod_app_start_failure

###Other commands:

        aws_manager.rb --help

###Misc

        Note that there are shortened versions of the options flags:
          --region      = -r
          --environment = -e
          --purpose     = -p
          --choose      = -c
          --keep_one    = -k
          --help        = -h


Command Line Example
--------------------


Creating an instance is a feature we use heavily to scale our app as needed.  To create
an EC2 instance, it is necessary to have a instance template in the form of yaml located
in /etc/.  For this example, let's put a template called 'app_server.yaml' into /etc that
looks like this:

        ---
        :tags:
          :environment: test
          :purpose: app
          :elastic_lb: TestAppELB
          :Name: TestappServer
          :user: ubuntu
          :security_group_ids: sg-ffffffff
          :subnet_id: subnet-fffffffff
          :elastic_ip_allocation_id: eipalloc-fffffffff
        :template:
          :image_id: ami-fffffffff
          :instance_type: m1.small
          :max_count: 1
          :min_count: 1
          :monitoring:
            :enabled: false
          :network_interfaces:
          - :associate_public_ip_address: true
            :description: Primary
            :subnet_id: subnet-fffffffff
            :delete_on_termination: true
            :device_index: 0
          :placement:
            :availability_zone: us-west-2a
            :tenancy: default

With this template, we are going to create an instance of the image_id: "ami-fffffffff", add it
to the elastic load balancer: "TestAppELB" in a vpc with the subnet: "subnet-fffffffff".  The server
will have an elastic ip for the VPC with the allocation id of: "eipalloc-fffffffff" and will be
assigned the security group of: "sg-ffffffff".

Before the command line tool can be run, credentials need to be stored in a yaml file in /etc/auth.yaml also.
An example of this is:

        ---
        account_id:        '777777777777'
        access_key_id:     'AAAAAAAAAAAAAAAAAAAAA'
        secret_access_key: 'LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL'

With these files installed, the following command would build this new instance:

    aws_manager.rb -r or -e test -p app run_instance /etc/app_server.yaml


