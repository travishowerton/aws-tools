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


Command Line Example Usage
--------------------------

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
