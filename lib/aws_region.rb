#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'yaml'
require 'json'

class AwsRegion
  attr_accessor :ec2, :region, :rds, :account_id, :elb, :cw, :s3
  REGIONS = {'or' => "us-west-2", 'ca' => "us-west-1", 'va' => 'us-east-1'}
  def initialize(region, account_id, access_key_id, secret_access_key)
    @region = REGIONS[region]
    @account_id = account_id
    Aws.config = {:access_key_id => access_key_id,
                  :secret_access_key => secret_access_key}
    @ec2 = Aws::EC2.new({:region => @region})
    @rds = Aws::RDS.new({:region => @region})
    @elb = Aws::ElasticLoadBalancing.new({:region => @region})
    @cw = Aws::CloudWatch.new({:region => @region})
    @s3 = Aws::S3.new({:region => @region})

    def find_instances(options={})
      instances = []
      @ec2.describe_instances[:reservations].each do |i|
       i.instances.each do |y|
        instance = AwsInstance.new(self,{:instance => y})
        if instance.state != 'terminated'
          if options.has_key?(:environment) and options.has_key?(:purpose)
            instances << instance if  instance.tags[:environment] == options[:environment] and instance.tags[:purpose] == options[:purpose]
          elsif options.has_key?(:instance_id)
            instances << instance if instance.id == options[:instance_id]
          end
        end
       end
      end
      return instances
    end
    def find_db_instances(options={})
      instances = []
      @rds.describe_db_instances[:db_instances].each do |i|
        instance = AwsDbInstance.new(self, {:instance => i})
        if options.has_key?(:instance_id) and
           (!options.has_key?(:environment) or !options.has_key?(:purpose)) and
           instance.id == options[:instance_id]
           instances << instance
        elsif instance.id == options[:instance_id] and
              instance.tags[:environment] == options[:environment] and
              instance.tags[:purpose] == options[:purpose]
          instances << instance
        end
      end
      instances
    end

    def find_buckets(options={})
      buckets = []
      _buckets = @s3.list_buckets()
      _buckets[:buckets].each do |b|
          buckets << AwsBucket.new(self, {id: b[:name]})  if b[:name] == options[:bucket]
      end
      buckets
    end
    def create_instance(options={})
      AwsInstance.new(self, options)
    end
    def create_db_instance(options={})
      AwsDbInstance.new(self, options)
    end
    def create_cw_instance(options={})
      AwsCw.new(self, options)
    end
    def create_bucket(options={})
      AwsBucket.new(self, options)
    end
    def remove_instance_from_lb(instance, lb_name)
      lb = @elb.describe_load_balancers({:load_balancer_names => [lb_name]})
      if lb and lb[:load_balancer_descriptions].length > 0
        lb[:load_balancer_descriptions][0][:instances].each do |lbi|
          if lbi[:instance_id] == instance
            @elb.deregister_instances_from_load_balancer({:load_balancer_name => lb_name,
                                                          :instances => [{:instance_id => instance}]})
          end
        end
      end
    end
  end

  class AwsCw
    attr_accessor :region
    def initialize(region, options={})
      @region = region
    end
    def put_metric(arg_csv)
      (namespace, name, value, dims) = arg_csv.split(",")
      dimensions = []
      dims.split(";").each do |d|
        (n,v) = d.split(":")
        dimensions << {:name => n, :value => v}
      end
      args = {:namespace => namespace}
      metric ={:metric_name => name, :value => value.to_f, :timestamp => Time.now, :dimensions => dimensions}
      args[:metric_data] = [metric]
      @region.cw.put_metric_data(args)
    end    
  end

  class AwsBucket
    attr_accessor :region
    def initialize(region, options={})
      @region = region
      if options.has_key?(:id)
        @id = options[:id]
      elsif options.has_key?(:bucket)
        bucket = options[:bucket]
        if @region.find_buckets({bucket: bucket}).length <= 0
          @region.s3.create_bucket({:bucket => bucket,
                                    :create_bucket_configuration => {:location_constraint => @region.region}})
          if @region.find_buckets({bucket: bucket}).length <= 0
            raise "Error creating bucket: #{bucket} in region: #{@region.region}"
          end
        end
        @id = bucket
      end
    end
    def delete
      @region.s3.delete_bucket({bucket: @id})
    end
    def put_file(filename, file_identity)
      File.open(filename, 'r') do |reading_file|
        resp = @region.s3.put_object(
            acl: "bucket-owner-full-control",
            body: reading_file,
            bucket: @id,
            key: file_identity
        )
      end
    end

    def put(local_file_path, aws_path, options={})
      # puts a local file to an s3 object in bucket on path
      # example: put_local_file {:bucket=>"bucket", :local_file_path=>"/tmp/bar/foo.txt", :aws_path=>"b"}
      # would make an s3 object named foo.txt in bucket/b
      aws_path = aws_path[0..-2] if aws_path[-1..-1] == '/'
      s3_path = "#{aws_path}/#{File.basename(local_file_path)}"
      puts "s3 writing #{local_file_path} to bucket #{@id} path: #{aws_path} s3 path: #{s3_path}"
      f = File.open local_file_path, 'rb'
      options[:bucket] = @id
      options[:key] = s3_path
      options[:body] = f
      options[:storage_class] = 'REDUCED_REDUNDANCY'
      result = @region.s3.put_object(params=options)
      f.close
      result
    end

    def find(options={})
      # prefix is something like: hchd-A-A-Items
      # This will return in an array of strings the names of all objects in s3 in
      # the :aws_path under :bucket starting with passed-in prefix
      # example: :bucket=>'mazama-inventory', :aws_path=>'development', :prefix=>'broadhead'
      #           would return array of names of objects in said bucket
      #           matching (in regex terms) development/broadhead.*
      # return empty array if no matching objects exist
      aws_path = options[:aws_path]
      prefix   = options[:prefix]
      aws_path = '' if aws_path.nil?
      aws_path = aws_path[0..-2] if aws_path[-1..-1] == '/'
      puts "s3 searching bucket:#{@id} for #{aws_path}/#{prefix}"
      objects = @region.s3.list_objects(:bucket => @id,
                                 :prefix => "#{aws_path}/#{prefix}")
      f = objects.contents.collect(&:key)
      puts "s3 searched  got: #{f.inspect}"
      f
    end

    def get(options={})
      # writes to local file an s3 object in :bucket at :s3_path_to_object to :dest_file_path
      # example: get_object_as_local_file( {:bucket=>'mazama-inventory',
      #                                     :s3_path_to_object=>development/myfile.txt',
      #                                     :dest_file_path=>'/tmp/foo.txt'})
      #          would write to local /tmp/foo.txt a file retrieved from s3 in 'mazama-inventory' bucket
      #          at development/myfile.txt
      s3_path_to_object = options[:s3_path_to_object]
      dest_file_path    = options[:dest_file_path]
      File.delete dest_file_path if File.exists?(dest_file_path)
      puts "s3 get bucket:#{@id} path:#{s3_path_to_object} dest:#{dest_file_path}"
      response = @region.s3.get_object(:bucket => @id,
                                       :key    => s3_path_to_object)
      response.body.rewind
      # I DO NOT KNOW what happens if the body is "too big". I didn't see a method in the
      # API to chunk it out... but perhaps response.body does this already.
      File.open(dest_file_path, 'wb') do |file|
        response.body.each { |chunk| file.write chunk }
      end
      puts "s3 got " + `ls -l #{dest_file_path}`.strip
      nil
    end

    def delete_object(options={})
      # deletes from s3 an object in :bucket at :s3_path_to_object
      s3_path_to_object = options[:s3_path_to_object]
      puts "s3 delete  #{s3_path_to_object}"
      @region.s3.delete_object( :bucket => @id,
                                :key    => s3_path_to_object)
      puts "s3 deleted."
    end

    def delete_all_objects
      response = @region.s3.list_objects({:bucket => @id})
      response[:contents].each do |obj|
        @region.s3.delete_object( :bucket => @id,
                                  :key    => obj[:key])
      end
    end
  end
  class AwsDbInstance
    attr_accessor :id, :tags, :region, :endpoint
    def initialize(region, options = {})
      @region = region
      opts = options[:opts]
      if !options.has_key?(:instance)
        @id = opts[:db_instance_identifier]
        snapshot_name = options[:snapshot_name]
        if 0 < @region.find_db_instances({:instance_id => @id}).length
          puts "Error, instance: #{@id} already exists"
          return
        end
        last = self.get_latest_db_snapshot({:snapshot_name => snapshot_name})
        puts "Restoring: #{last.db_instance_identifier}, snapshot: #{last.db_instance_identifier} from : #{last.snapshot_create_time}"
        opts[:db_snapshot_identifier] = last.db_snapshot_identifier
        response = @region.rds.restore_db_instance_from_db_snapshot(opts)
        @_instance = response[:db_instance]
        @region.rds.add_tags_to_resource({:resource_name => "arn:aws:rds:#{@region.region}:#{@region.account_id}:db:#{@id}",
                                          :tags => [{:key => "environment", :value => options[:environment]},
                                                    {:key => "purpose", :value => options[:purpose]}]})

        self.wait

        opts = { :db_instance_identifier => @id,
                 :vpc_security_group_ids => options[:vpc_security_group_ids]}
        @region.rds.modify_db_instance(opts)
      else
        @_instance = options[:instance]
        @id = @_instance[:db_instance_identifier]
      end
      @tags = {}
      _tags = @region.rds.list_tags_for_resource({:resource_name => "arn:aws:rds:#{@region.region}:#{@region.account_id}:db:#{@id}"})
      _tags[:tag_list].each do |t|
        @tags[t[:key].to_sym] = t[:value]
      end
      @endpoint = @_instance.endpoint[:address]
    end

    def delete(options={})
      puts "Deleting database: #{@id}"
      opts = { :db_instance_identifier => @id,
               :skip_final_snapshot => false,
               :final_db_snapshot_identifier => "#{@id}-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}" }
      i = @region.rds.delete_db_instance(opts)
    end

    def purge_db_snapshots
      latest = 0
      @region.rds.describe_db_snapshots[:db_snapshots].each do |i|
         if i.snapshot_type == "manual" and i.db_instance_identifier == @id
           if i.snapshot_create_time.to_i > latest
             latest = i.snapshot_create_time.to_i
           end
         end
      end
      @region.rds.describe_db_snapshots[:db_snapshots].each do |i|
         if i.snapshot_type == "manual" and i.db_instance_identifier == @id
           if i.snapshot_create_time.to_i != latest
             puts "Removing snapshot: #{i.db_snapshot_identifier}/#{i.snapshot_create_time.to_s}"
             begin
               @region.rds.delete_db_snapshot({:db_snapshot_identifier => i.db_snapshot_identifier})
             rescue
               puts "Error removing snapshot: #{i.db_snapshot_identifier}/#{i.snapshot_create_time.to_s}"
             end
           else
             puts "Keeping snapshot: #{i.db_snapshot_identifier}/#{i.snapshot_create_time.to_s}"
           end
         end
       end
    end

    def wait(options = {:desired_status => "available",
                        :timeout => 600})
      inst = @region.find_db_instances({:instance_id => @id})[0]
      if !inst
        puts "Error, instance: #{@id} not found"
        return
      end
      t0 = Time.now.to_i
      while inst.status != options[:desired_status]
        inst = @region.find_db_instances({:instance_id => @id})[0]
        puts "Database: #{@id} at #{@endpoint}.  Current status: #{inst.status}"
        if Time.now.to_i - t0 > options[:timeout]
          puts "Timed out waiting for database: #{@id} at #{@endpoint} to move into status: #{options[:desired_status]}.  Current status: #{inst.status}"
          return
        end
        sleep 20
      end
    end

    def status
       @_instance.db_instance_status
    end

    def get_latest_db_snapshot(options={})
      snapshot_name = options.has_key?(:snapshot_name) ? options[:snapshot_name] : @id

      last = nil
      last_t = 0
      @region.rds.describe_db_snapshots[:db_snapshots].each do |i|
        if i.db_instance_identifier == snapshot_name and (last.nil? or i.snapshot_create_time > last_t)
          last = i
          last_t = i.snapshot_create_time
        end
      end
      last
    end

  end
  class AwsInstance
    attr_accessor :id, :tags, :region, :private_ip, :public_ip, :_instance
    def initialize(region, options = {})
      @region = region
      if !options.has_key?(:instance)
        resp = @region.ec2.run_instances(options)
        raise "Error creating instance using options" if resp.nil? or resp[:instances].length <= 0
        @_instance = resp[:instances][0]
      else
        @_instance = options[:instance]
      end
      @id = @_instance[:instance_id]
      @tags = {}
      @_instance.tags.each do |t|
        @tags[t[:key].to_sym] = t[:value]
      end
      @public_ip = @_instance[:public_ip_address]
      @private_ip = @_instance[:private_ip_address]
    end
    def state(use_cached_state=true)
      if !use_cached_state
        response = @region.ec2.describe_instances({instance_ids: [@id]})
        response[:reservations].each do |res|
          res[:instances].each do |inst|
            if inst[:instance_id] == @id
              return inst[:state][:name].strip()
            end
          end
        end
        return ""
      else
        @_instance.state[:name].strip()
      end
    end
    def start(wait=false)
      if self.state(use_cached_state = false) != "stopped"
        puts "Instance cannot be started - #{@region.region}://#{@id} is in the state: #{self.state}"
        return
      end
      puts "Starting instance: #{@region.region}://#{@id}"
      @region.ec2.start_instances({:instance_ids => [@id]})
      if wait
        begin
          sleep 10
          puts "Starting instance: #{@region.region}://#{@id} - state: #{self.state}"
        end while self.state(use_cached_state = false) != "running"
      end
      if @tags.has_key?("elastic_ip")
        @region.ec2.associate_address({:instance_id => @id, :public_ip => @tags['elastic_ip']})
        puts "Associated ip: #{@tags['elastic_ip']} with instance: #{@id}"
      elsif @tags.has_key?("elastic_ip_allocation_id")
        @region.ec2.associate_address({:instance_id => @id, :allocation_id => @tags['elastic_ip_allocation_id']})
        puts "Associated allocation id: #{@tags['elastic_ip_allocation_id']} with instance: #{@id}"
      end
      if @tags.has_key?("elastic_lb")
        self.add_to_lb(@tags["elastic_lb"])
        puts "Adding instance: #{@id} to '#{@tags['elastic_lb']}' load balancer"
      end
    end
    def set_security_groups(groups)
      resp = @region.ec2.modify_instance_attribute({:instance_id => @id,
                                                    :groups => groups})
    end
    def add_tags(h_tags)
      tags = []
      h_tags.each do |k,v|
        tags << {:key => k.to_s, :value => v}
      end
      resp = @region.ec2.create_tags({:resources => [@id],
                                      :tags => tags})
    end

    def add_to_lb(lb_name)
      @region.elb.register_instances_with_load_balancer({:load_balancer_name => lb_name,
                                                         :instances => [{:instance_id => @id}]})
    end

    def remove_from_lb(lb_name)
      lb = @region.elb.describe_load_balancers({:load_balancer_names => [lb_name]})
      if lb and lb[:load_balancer_descriptions].length > 0
        lb[:load_balancer_descriptions][0][:instances].each do |lb_i|
          if lb_i[:instance_id] == @id
            @elb.deregister_instances_from_load_balancer({:load_balancer_name => lb_name,
                                                          :instances => [{:instance_id => @id}]})
          end
        end
      end
    end

    def terminate()
      @region.ec2.terminate_instances({:instance_ids => [@id]})
    end

    def archive_logs()
    end

    def stop(wait=false)
      if self.state(use_cached_state = false) != "running"
        puts "Instance cannot be stopped - #{@region.region}://#{@id} is in the state: #{self.state}"
        return
      end
      if @tags.has_key?("elastic_lb")
        puts "Removing instance: #{@id} from '#{@tags['elastic_lb']}' load balancer"
        remove_from_lb(tags["elastic_lb"])
      end
      puts "Stopping instance: #{@region.region}://#{@id}"
      @region.ec2.stop_instances({:instance_ids => [@id]})
      while self.state(use_cached_state = false) != "stopped"
        sleep 10
        puts "Stopping instance: #{@region.region}://#{@id} - state: #{self.state}"
      end if wait
      if self.state(use_cached_state = false) == "stopped"
        puts "Instance stopped: #{@region.region}://#{@id}"
      end
    end
    def connect
      if self.state(use_cached_state = false) != "running"
        puts "Cannot connect, instance: #{@region.region}://#{@id} due to its state: #{self.state}"
        return
      end
      ip = self.public_ip != "" ? self.public_ip : self.private_ip
      #puts "Connecting: ssh -i ~/.ssh/ec2.#{@region.region}.pem #{@tags[:user]}@#{ip}"
      #exec "ssh -i ~/.ssh/ec2.#{@region.region}.pem #{@tags[:user]}@#{ip}"
      puts "Connecting: ssh #{@tags[:user]}@#{ip}"
      exec "ssh #{@tags[:user]}@#{ip}"
    end


  end
end
