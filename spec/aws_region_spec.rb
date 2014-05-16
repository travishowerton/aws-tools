require 'aws_region'

describe AwsRegion do
  before(:each) do
    if !File.exists? "/etc/auth.yaml"
      puts "Error, auth config is not setup for tests.  Please create /etc/auth.yaml and rerun"
      exit
    end
  end
  it "Should Create Instance In Oregon" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])

    instance_template = 'app_server_image_template.json'
    template =<<EOF
{
"name": "Testapp32",
"user": "ubuntu",
"elastic_lb": "TestAppELB",
"subnet_id":                   "subnet-0a5dcc63",
"security_group_ids":          ["sg-9d0c06ff"],
"template": {
            "image_id":                    "ami-743e5444",
            "min_count":                   1,
            "max_count":                   1,
            "instance_type":               "m1.small",
            "placement":                   {"availability_zone": "us-west-2a",
                                            "tenancy": "default"},
            "monitoring":                  {"enabled": false},
            "network_interfaces": [
                {
                    "device_index": 0,
                    "subnet_id": "subnet-0a5dcc63",
                    "description": "Primary",
                    "delete_on_termination": true,
                    "associate_public_ip_address": true
                }
            ]
            }
}
EOF
    File.open(instance_template, 'w') {|file| file.write(template)}
    image_options = JSON.parse(File.read(instance_template), {:symbolize_names => true})
    instance = region.create_instance(image_options[:template])
    tags = {:environment => "test",
            :purpose     => "app32",
            "Name"       => image_options[:name],
            :user        => image_options[:user]
    }
    tags[:elastic_lb] = image_options[:elastic_lb] if image_options.has_key?(:elastic_lb)
    instance.add_tags(tags)
    if image_options.has_key?(:security_group_ids)
      instance.set_security_groups(image_options[:security_group_ids])
    end
    if image_options.has_key?(:elb)
      instance.add_to_lb(image_options[:elb])
    end
  end
  it "Should Find an App32 Instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    i = region.find_instances({:instance_id => "i-0522030c"  })
    i.length.should == 1
    i[0].id.should == "i-0522030c"
  end
  it "Should Find one or more App32 Instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    i = region.find_instances({:environment => "test", :purpose => "app32"  })
    i.length.should > 0
  end
  it "Should Terminate Instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    i = region.find_instances({:instance_id => "i-4fcaed46"  })
    i[0].terminate

  end
  it "Should Add Instance to LB" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    i = region.find_instances({:instance_id => "i-260b2c2f"  })
    i[0].add_to_lb("TestAppELB")
  end
  it "Should Start an Instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    i = region.find_instances({:instance_id => "i-4fcaed46"  })
    i[0].start
  end
  it "Should Stop an Instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    i = region.find_instances({:instance_id => "i-4fcaed46"  })
    i[0].stop
  end
  it "Should Remove instance from LB using region object" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    ["i-3b6e3532", "i-467a214f", "i-8c510a85", "i-b3411aba","i-ec7b20e5"].each do |i|
      region.remove_instance_from_lb(i, "TestAppELB")
    end
  end
  it "Should Remove instance from LB using instance object" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    region.remove_instance_from_lb(i, "TestAppELB")
    i = region.find_instances({:instance_id => "i-4fcaed46"  })
  end

  it "Should create and delete a bucket in Oregon" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    if new_bucket.length > 0
      new_bucket[0].delete
    end
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket.should be_kind_of(Array)
    new_bucket.length.should be(0)
    bucket = region.create_bucket({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket.should be_kind_of(Array)
    new_bucket.length.should be(1)
    new_bucket[0].delete
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket.should be_kind_of(Array)
    new_bucket.length.should be(0)
  end
  it "Should create a bucket and an object and delete both" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    if new_bucket.length > 0
      new_bucket[0].delete_all_objects
      new_bucket[0].delete
    end
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket.should be_kind_of(Array)
    new_bucket.length.should be(0)
    bucket = region.create_bucket({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket.should be_kind_of(Array)
    new_bucket.length.should be(1)
    # Create an item
    bucket = new_bucket[0]
    `ls > /tmp/bucket.test.file.a`
    `rm -f /tmp/bucket.test.file.a+` if File.exists?("/tmp/bucket.test.file.a+")
    bucket.put({:aws_path => "test/directory",
                :local_file_path => "/tmp/bucket.test.file.a"})
    bucket.get({:s3_path_to_object => "test/directory/bucket.test.file.a",
                :dest_file_path => "/tmp/bucket.test.file.a+"})
    File.exists?("/tmp/bucket.test.file.a+").should be(true)
    bucket.find({:aws_path => "test/directory",
                 :prefix => "bucket.test"}).length.should == 1

    bucket.delete_object({:s3_path_to_object => "test/directory/bucket.test.file.a"})
    expect { bucket.get({:s3_path_to_object => "test/directory/file.a",
                :dest_file_path => "/tmp/bucket.test.file.a+"})}.to raise_error
    bucket.delete
    new_bucket = region.find_buckets({bucket: "test-bucket-to-be-deleted-soon"})
    new_bucket.should be_kind_of(Array)
    new_bucket.length.should be(0)
  end
  it "Should put CW metrics" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    cw_inst = region.create_cw_instance()
    cw_inst.put_metric("AwsUtil,Test,1,a:1")
  end
  it "Should find a db instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    instances = region.find_db_instances({:instance_id => "testapp"})
    instances.length.should == 1
    instance = instances[0]
    instance.status.should == "available"
    snapshot1 = instance.get_latest_db_snapshot({:snapshot_name => "testapp"})
    snapshot2 = instance.get_latest_db_snapshot()
    snapshot1[:db_snapshot_identifier].should == snapshot2[:db_snapshot_identifier]
  end
  it "Should verify wait method of db instance" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    instances = region.find_db_instances({:instance_id => "testapp"})
    instances.length.should == 1
    instance = instances[0]
    instance.status.should == "available"
    instance.wait({:desired_status => "available",
                   :timeout => 2})

  end
  it "Should purge old db snapshots" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    instances = region.find_db_instances({:instance_id => "testapp"})
    instances.length.should == 1
    instance = instances[0]
    instance.purge_db_snapshots
  end
  it "Should create db" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    instances = region.find_db_instances({:instance_id => "mazama"})
    instances.length.should == 0
    region.create_db_instance(YAML::load File.read("./mazama.db.yaml"))
  end
  it "Should delete db" do
    cfg = YAML::load File.read("/etc/auth.yaml")
    region = AwsRegion.new("or", cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])
    db = "mazama"
    instances = region.find_db_instances({:instance_id => db})
    instances.length.should == 1
    instance = instances[0]
    instance.delete
  end
end
