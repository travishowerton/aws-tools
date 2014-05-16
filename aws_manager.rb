#!/usr/bin/env ruby

require 'aws-sdk-core'
require 'yaml'
require 'json'
require './lib/aws_region.rb'

VALID_COMMANDS=['start', 
                'stop', 
                'start_environment',
                'connect', 
                'create_db', 
                'delete_db', 
                'wait_for_db', 
                'get_db_endpoint', 
                'get_instance_status', 
                'get_instance_ip', 
                'get_db_status', 
                'purge_db_snapshots', 
                'put_cw_metric', 
                'put_to_bucket', 
                'run_instance', 
                'terminate_instance']

def locate_instance_choice(all_instances, instance_id, statuses)
  instances = []
  if statuses.length == 0
    instances = all_instances
  else
    all_instances.each do |i|
      if statuses.include?(i._instance[:state][:name])
        instances << i
      end
    end
  end
  if instances.length == 0
    puts "There are no running instances matching criteria"
    return nil
  elsif instances.length == 1
    instances[0]
  else
    if !instance_id.nil?
      instance = nil
      if instance_id.length > 2 # This is an instance id
        instances.each do |i|
          if i[:instance_id] == instance_id
            instance = i
          end
        end
        if instance.nil?
          "Error, can't locate instance with instance id: #{instance_id}"
          return nil
        end
      else
        if instances.length - 1 >= instance_id.to_i
          instance = running_instances[instance_id.to_i]
        end
      end
      return instance
    else
      puts "Error, there are multiple instances that match these tags.  Please choose one:"
      puts "index: private_ip / public_ip / instance_id / launch_time"
      for i in 0..(instances.length - 1)
        puts "#{i}: #{instances[i][:private_ip_address]} / #{instances[i][:public_ip_address]} / #{instances[i][:instance_id]} / #{instances[i][:launch_time]}"
      end
      ans = STDIN.gets.chomp().to_i
      return instances[ans]
    end
    nil
  end

end
def syntax
  puts "Invalid command.\n" +
        "Syntax: aws_manager [or|ca|va] " + 
          "[prod|test|..etc] " +
          "[app|hub|..etc] " +
          "[#{VALID_COMMANDS.join("|")} " +
          "{name}"
  exit
end
def main
  name = nil
  if ARGV.length == 3 and ARGV[1].downcase == "put_cw_metric"
      region  = ARGV[0].downcase
      command = ARGV[1].downcase
      metric  = ARGV[2].downcase
  elsif ARGV.length == 5 and ARGV[1].downcase == "put_to_bucket"
    region         = ARGV[0].downcase
    command        = ARGV[1].downcase
    bucket         = ARGV[2].downcase
    filename       = ARGV[3].downcase
    file_identity  = ARGV[4].downcase
  else
    if ARGV.length < 4
      syntax
    end
    region = ARGV[0].downcase
    instance_env = ARGV[1].downcase
    instance_purpose = ARGV[2].downcase
    command = ARGV[3].downcase
    name = ARGV[4].downcase if ARGV.length == 5
  end
  syntax if !(['or', 'ca', 'va'].include?(region))
  syntax if !(VALID_COMMANDS.include?(command))
  
  cfg = YAML::load File.read("/etc/auth.yaml")
  region = AwsRegion.new(region, cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])

  if command == 'stop'

    instance = locate_instance_choice(region.find_instances({environment: instance_env, purpose: instance_purpose  }),
                                      name,
                                      ['running'])
    instance.stop(wait=true)
  elsif command == 'start'
    instance = locate_instance_choice(region.find_instances({environment: instance_env, purpose: instance_purpose  }),
                                      name,
                                      ['stopped'])
    instance.start(wait=true)
  elsif command == 'connect'
    instance = locate_instance_choice(region.find_instances({environment: instance_env, purpose: instance_purpose  }),
                                      name,
                                      ['running'])
    instance.connect
  elsif command == 'create_db'
    options = YAML::Load name if File.exists? name
    instance = region.create_db_instance(options)
  elsif command == 'delete_db'
    instances = region.find_db_instances({:environment => instance_env, :purpose => instance_purpose, :instance_id => name})
    instances[0].delete
  elsif command == 'wait_for_db'
    instances = region.find_db_instances({:environment => instance_env, :purpose => instance_purpose, :instance_id => name})
    instances[0].wait
  elsif command == 'get_db_endpoint'
    instances = region.find_db_instances({:environment => instance_env, :purpose => instance_purpose, :instance_id => name})
    puts instances[0].endpoint
  elsif command == 'get_db_status'
    instances = region.find_db_instances({:environment => instance_env, :purpose => instance_purpose, :instance_id => name})
    puts instances[0].status
  elsif command == 'get_instance_status'
    instance = locate_instance_choice(region.find_instances({environment: instance_env, purpose: instance_purpose  }),
                                      name,
                                      [])
    puts instance.state
  elsif command == 'get_instance_ip'
    instance = locate_instance_choice(region.find_instances({environment: instance_env, purpose: instance_purpose  }),
                                      name,
                                      [])
    puts instance.public_ip
  elsif command == 'purge_db_snapshots'
    instances = region.find_db_instances({:environment => instance_env, :purpose => instance_purpose, :instance_id => name})
    instances[0].purge_db_snapshots
  elsif command == 'put_cw_metric'
    instance = region.create_cw_instance
    instance.put_metric(metric)
  elsif command == 'put_to_bucket'
    instance = region.find_bucket({bucket: bucket})
    instance.put_file(filename, file_identity)
  elsif command == 'run_instance'
    instance_template = name
    if !File.exists?(instance_template)
      puts "Cannot find instance template to build server from: #{instance_template}"
      exit
    end
    image_options = YAML:: File.read(instance_template)
    instance = region.create_instance(image_options[:template])
    tags = {:environment => instance_env,
            :purpose     => instance_purpose,
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

  elsif command == 'terminate_instance'
    instance = locate_instance_choice(region.find_instances({environment: instance_env, purpose: instance_purpose  }),
                                      name,
                                      [])
    instance.terminate
  elsif
    syntax
  end
end

main()
