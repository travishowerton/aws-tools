#!/usr/bin/env ruby

require 'aws-sdk-core'
require 'yaml'
require 'optparse'
require 'erb'
require_relative 'lib/aws_region.rb'

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
                'sns',
                'terminate_instance']

def filter_instances(all_instances, statuses)
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
  instances
end
def locate_instance_choice(instances, instance_id, options={})
  selection_filter = options.has_key?(:selection_filter) ? options[:selection_filter] : nil
  if instances.length == 0
    puts "There are no instances matching criteria"
    return nil
  elsif instances.length == 1
    instances[0]
  else
    if !instance_id.nil?
      instance = nil
      if instance_id.length > 2 # This is an instance id
        instances.each do |i|
          if i.id == instance_id
            instance = i
          end
        end
        if instance.nil?
          "Error, can't locate instance with instance id: #{instance_id}"
          return nil
        end
      else
        if instances.length - 1 >= instance_id.to_i
          instance = instances[instance_id.to_i]
        end
      end
      return instance
    else
      if selection_filter == :first
        return instances[0]
      elsif selection_filter == :oldest
          oldest = instances[0]
          instances.each do |i|
            oldest = i if i._instance[:launch_time] < oldest._instance[:launch_time]
          end
          return oldest
      elsif selection_filter == :newest
        newest = instances[0]
        instances.each do |i|
          newest = i if i._instance[:launch_time] > newest._instance[:launch_time]
        end
        return newest
      else
        puts "Error, there are multiple instances that match these tags.  Please choose one:"
        puts "index: private_ip / public_ip / instance_id / launch_time"
        for i in 0..(instances.length - 1)
          puts "#{i}: #{instances[i]._instance[:private_ip_address]} / #{instances[i]._instance[:public_ip_address]} / #{instances[i]._instance[:instance_id]} / #{instances[i]._instance[:launch_time]}"
        end
        ans = STDIN.gets.chomp().to_i
        return instances[ans]
      end
    end
    nil
  end

end
def syntax
  puts "Syntax:"
  puts "   EC2 Instance commands:"
  puts "        aws_manager.rb --region region run_instance <instance template file> "
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] connect [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] start [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] [--keep-one] stop [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] get_instance_status [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] get_instance_ip [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] [--choose first|oldest|newest] [--keep_one] terminate_instance [id]"
  puts "   CW commands:"
  puts "        aws_manager.rb --region region put_cw_metric csv_metric"
  puts "   S3 commands:"
  puts "        aws_manager.rb --region region put_to_bucket filename s3_filename"
  puts "   RDS commands:"
  puts "        aws_manager.rb --region region create_db <db template file> "
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] delete_db [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] wait_for_db [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] get_db_status [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] get_db_endpoint [id]"
  puts "        aws_manager.rb --region region [--environment environment] [--purpose purpose] purge_db_snapshots [id]"
  puts "   SNS commands:"
  puts "        aws_manager.rb --region region sns \"<topic_arn>\" \"subject\""
  puts "        example topic_arn: 'arn:aws:sns:us-east-1:795987318935:prod_app_start_failure'"
  puts "   Other commands:"
  puts "        aws_manager.rb --help"
  puts "\nNote that there are shortened versions of the options flags:"
  puts "        --region      = -r"
  puts "        --environment = -e"
  puts "        --purpose     = -p"
  puts "        --choose      = -c"
  puts "        --keep_one    = -k"
  puts "        --help        = -h"
  exit
end
def main
  syntax if ARGV.length <= 0
  params = ARGV.getopts("hr:e:p:fkc:", "choose:", "keep-one", "help", "region:", "environment:", "purpose:")
  syntax if params['h'] or params['help']
  purpose = params['p'] || params['purpose']
  environment = params['e'] || params['environment']
  region = params['r'] || params['region']
  keep_one = params['k'] || params['keep-one']
  selection_criteria = params['c'] || params['choose']
  selection_criteria = selection_criteria.downcase.to_sym if selection_criteria
  syntax if selection_criteria and !([:first,:oldest, :newest].include?(selection_criteria))
  syntax if ARGV.length <= 0
  command = ARGV.shift
  save_cl = ARGV.dup
  name = ARGV.length == 1 ? ARGV.shift : nil

  syntax if !region or !(['or', 'ca', 'va'].include?(region))
  syntax if !(VALID_COMMANDS.include?(command))
  
  cfg = YAML::load File.read("/etc/auth.yaml")
  region = AwsRegion.new(region, cfg["account_id"], cfg["access_key_id"], cfg["secret_access_key"])

  if command == 'stop'
    if keep_one and filter_instances(region.find_instances({environment: environment, purpose: purpose  }), ['running']).length < 2
      puts "Error, there are less than 2 instances, and keep_one flag set.  Exiting."
      exit
    end
    instance = locate_instance_choice(filter_instances(region.find_instances({environment: environment, purpose: purpose  }), ['running']),name, {:selection_filter => selection_criteria})
    instance.stop(wait=true)
  elsif command == 'start'
    instance = locate_instance_choice(filter_instances(region.find_instances({environment: environment, purpose: purpose  }), ['stopped']),name, {:selection_filter => selection_criteria})
    instance.start(wait=true)
  elsif command == 'connect'
    instance = locate_instance_choice(filter_instances(region.find_instances({environment: environment, purpose: purpose  }), ['running']),name, {:selection_filter => selection_criteria})
    instance.connect
  elsif command == 'create_db'
    options = YAML::load File.read(name) if File.exists? name
    instance = region.create_db_instance(options)
  elsif command == 'delete_db'
    instances = region.find_db_instances({:environment => environment, :purpose => purpose, :instance_id => name})
    instances[0].delete
  elsif command == 'wait_for_db'
    instances = region.find_db_instances({:environment => environment, :purpose => purpose, :instance_id => name})
    instances[0].wait
  elsif command == 'get_db_endpoint'
    instances = region.find_db_instances({:environment => environment, :purpose => purpose, :instance_id => name})
    puts instances[0].endpoint
  elsif command == 'get_db_status'
    instances = region.find_db_instances({:environment => environment, :purpose => purpose, :instance_id => name})
    puts instances[0].status
  elsif command == 'get_instance_status'
    instance = locate_instance_choice(filter_instances(region.find_instances({environment: environment, purpose: purpose  }), []), name, {:selection_filter => selection_criteria})
    puts instance.state
  elsif command == 'get_instance_ip'
    instance = locate_instance_choice(filter_instances(region.find_instances({environment: environment, purpose: purpose  }), []), name, {:selection_filter => selection_criteria})
    puts instance.public_ip
  elsif command == 'purge_db_snapshots'
    instances = region.find_db_instances({:environment => environment, :purpose => purpose, :instance_id => name})
    instances[0].purge_db_snapshots
  elsif command == 'put_cw_metric'
    syntax if ARGV.length <= 1
    instance = region.create_cw_instance
    instance.put_metric(name)
  elsif command == 'put_to_bucket'
    syntax if ARGV.length <= 0
    (bucket,file_identity) = ARGV[0].split(/:/)
    syntax if bucket.strip.length <=0 or file_identity.strip.length <= 0
    instance = region.find_bucket({bucket: bucket})
    instance.put_file(name, file_identity)
  elsif command == 'run_instance'
    instance_template = name
    if !File.exists?(instance_template)
      puts "Cannot find instance template to build server from: #{instance_template}"
      exit
    end
    #image_options = YAML::load File.read(instance_template)
    image_options = YAML.load(ERB.new(File.read(instance_template)).result)
    instance = region.create_instance(image_options)
  elsif command == 'terminate_instance'
    if keep_one and filter_instances(region.find_instances({environment: environment, purpose: purpose  }), ['running']).length < 2
      puts "Error, there are less than 2 instances, and keep_one flag set.  Exiting."
      exit
    end
    instance = locate_instance_choice(filter_instances(region.find_instances({environment: environment, purpose: purpose  }), []), name, {:selection_filter => selection_criteria})
    instance.terminate
  elsif command == 'sns'
    instance = region.create_sns_instance
    instance.publish save_cl[0], save_cl[1]
    exit
  elsif
    syntax
  end
end

main()
