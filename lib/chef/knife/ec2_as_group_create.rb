#
# Author:: Alan Lippert (<alan.lippert@blackbaud.com>)
#

require 'chef/knife/ec2_base'

class Chef
  class Knife
    class Ec2AsGroupCreate < Knife

      include Knife::Ec2Base
      deps do
        require 'fog'
        require 'readline'
        require 'chef/json_compat'
        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife ec2 as group create (options)"

      attr_accessor :initial_sleep_delay
      attr_reader :group

      option :name,
             :short => "-n name",
             :long =>  "--group-name name",
             :description => "The unique id/name for the auto scaling group"

      option :launch_config,
             :short => "-l",
             :long => "--launch-configuration name",
             :description => "Name of existing launch configuration to use to launch new instances.  Required."

      option :default_cooldown,
             :long => "--default-cooldown VALUE",
             :description => "Time (in seconds) between a successful scaling activity and succeeding scaling activity.",
             :proc => Proc.new { |key| Chef::Config[:knife][:default_cooldown] = key }

      option :desired_capacity,
             :long => "--desired-capacity VALUE",
             :description => "Capacity setting for the group (minimum-size <= desired-capacity <= maximum-size).",
             :proc => Proc.new { |key| Chef::Config[:knife][:desired_capacity] = key }

      option :grace_period,
             :long => "--grace-period VALUE",
             :description => "The period after an instance is launched. During this period, any health check failure of that instance is ignored.",
             :proc => Proc.new { |key| Chef::Config[:knife][:grace_period] = key }

      option :health_check_type,
             :long => "health-check-type VALUE",
             :description => "Type of health check for instances of this group.",
             :proc => Proc.new { |key| Chef::Config[:knife][:health_check_type] = key }

      option :load_balancers,
             :long => "--load-balancers VALUE1,VALUE2,VALUE3...",
             :description => "List of existing load balancers. Load balancers must exist in Elastic Load Balancing service within the scope of the caller's AWS account.",
             :proc => Proc.new { |load_balancers| load_balancers.split(',') }

      option :min_size,
             :short => "-m VALUE",
             :long => "--min-size VALUE",
             :description => "Minimum group size (0 <= minimum-size <= maximum-size). Required.",
             :proc => Proc.new { |key| Chef::Config[:knife][:min_size] = key }

      option :max_size,
             :short => "-M VALUE",
             :long => "--max-size VALUE",
             :description => "Maximum group size (minimum-size <= maximum-size < 10000). Required.",
             :proc => Proc.new { |key| Chef::Config[:knife][:max_size] = key }

      option :placement_group,
             :long => "--placement-group PLACEMENT_GROUP",
             :description => "The placement group to place a cluster compute instance",
             :proc => Proc.new { |pg| Chef::Config[:knife][:placement_group] = pg }

      option :tags,
             :short => "-T T=V[,T=V,...]",
             :long => "--tags Tag=Value[,Tag=Value...]",
             :description => "The tags for this server",
             :proc => Proc.new { |tags| tags.split(',') }

      option :termination_policies,
             :long => "--termination-policies VALUE1,VALUE2,VALUE3...",
             :description => "Ordered list of preferred termination policies used to select the instance(s) to terminate. The first policy in the list has the highest preference.",
             :proc => Proc.new { |termination_policies| termination_policies.split(',') }

      option :vpc_zone_identifier,
             :long => "--vpc-zone-identifier VALUE",
             :description => "A comma-separated list of subnet identifiers of Amazon Virtual Private Clouds (Amazon VPCs). If you specify subnets and Availability Zones, ensure that the subnets' Availability Zones  match the Availability Zones specified.",
             :proc => Proc.new { |key| Chef::Config[:knife][:vpc_zone_identifier] = key }

      option :availability_zone,
             :short => "-Z ZONE",
             :long => "--availability-zone ZONE",
             :description => "The Availability Zone",
             :proc => Proc.new { |key| Chef::Config[:knife][:availability_zone] = key.split(',') }

      def run
        $stdout.sync = true

        validate!

        @as_group = create_as_group
        @as_group = @as_group.save

        tags_array=[]
        hashed_tags={}
        tags.map{ |t| key,val=t.split('='); hashed_tags[key]=val ; tags_array.push(:Key => key, :PropagateAtLaunch => true, :Value => val, :ResourceId => @as_group.id, :ResourceType => 'auto-scaling-group')} unless tags.nil?

        # Always set the Name tag
        unless hashed_tags.keys.include? "Name"
          hashed_tags["Name"] = @as_group.id
          tags_array.push(:Key => "Name", :PropagateAtLaunch => true, :Value => @as_group.id, :ResourceId => @as_group.id, :ResourceType => 'auto-scaling-group')
        end

        printed_tags = hashed_tags.map{ |tag, val| "#{tag}: #{val}" }.join(", ")

        puts "\n"
        msg_pair("AutoScaling Group Name", @as_group.id)
        msg_pair("Launch Config ID", @as_group.launch_configuration_name)
        msg_pair("Availability Zones", @as_group.availability_zones) if @as_group.availability_zones
        msg_pair("Tags", printed_tags)
        msg_pair("DefaultCooldown", @as_group.default_cooldown)
        msg_pair("DesiredCapacity", @as_group.desired_capacity)
        msg_pair("EnabledMetrics", @as_group.enabled_metrics) if @as_group.enabled_metrics
        msg_pair("HealthCheckGracePeriod", @as_group.health_check_grace_period)
        msg_pair("HealthCheckType", @as_group.health_check_type)
        msg_pair("Instances", @as_group.instances)
        msg_pair("LoadBalancerNames", @as_group.load_balancer_names)
        msg_pair("MaxSize", @as_group.max_size)
        msg_pair("MinSize", @as_group.min_size)
        msg_pair("PlacementGroup", @as_group.placement_group)
        msg_pair("Tags", hashed_tags)
        msg_pair("TerminationPolicies", @as_group.termination_policies)
        msg_pair("VPCZoneIdentifier", @as_group.vpc_zone_identifier)

        print "\n#{ui.color("Waiting for autoscaling group", :magenta)}"

        # wait for instance to come up before acting against it
        @as_group.wait_for { print "."; ready? }

        puts("\n")

        # occasionally 'ready?' isn't, so retry a couple times if needed.
        tries = 6
        begin
          puts "\nCreating tags for autoscaling group\n"
          create_tags(tags_array) unless tags_array.empty?
        rescue Fog::Compute::AWS::NotFound => e
          raise if (tries -= 1) <= 0
          ui.warn("Autoscaling Group not ready, retrying tag application (retries left: #{tries})")
          sleep 5
          retry
        end


      end

      def launch_config
        @launch_config ||= autoscaling.configurations.get(locate_config_value(:launch_config))
      end

      def validate!

        super([:aws_access_key_id, :aws_secret_access_key])

        if locate_config_value(:name).nil?
          ui.error("You have not provided the unique id/name of the autoscale group")
          exit 1
        end

        if launch_config.nil?
          ui.error("You have not provided a valid launch configuration.")
          exit 1
        end

      end

      def create_as_group_def
        as_group_def = {
            :id                        => locate_config_value(:name),
            :launch_configuration_name => launch_config.id,
            :availability_zones => locate_config_value(:availability_zone)
        }

        as_group_def[:placement_group] = locate_config_value(:placement_group)
        as_group_def[:default_cooldown] = locate_config_value(:default_cooldown)
        as_group_def[:desired_capacity] = locate_config_value(:desired_capacity)
        as_group_def[:enabled_metrics] = locate_config_value(:enabled_metrics)
        as_group_def[:health_check_grace_period] = locate_config_value(:health_check_grace_period)
        as_group_def[:health_check_type] = locate_config_value(:health_check_type)
        as_group_def[:load_balancer_names] = locate_config_value(:load_balancer_names)
        as_group_def[:max_size] = locate_config_value(:max_size)
        as_group_def[:min_size] = locate_config_value(:min_size)
        as_group_def[:placement_group] = locate_config_value(:placement_group)
        as_group_def[:tags] = locate_config_value(:tags)
        as_group_def[:termination_policies] = locate_config_value(:termination_policies)
        as_group_def[:vpc_zone_identifier] = locate_config_value(:vpc_zone_identifier)

        as_group_def
      end

      def create_as_group
        @as_group = autoscaling.groups.new(create_as_group_def)
        # Bug in Fog overwrites the following attributes on initialization

        @as_group.default_cooldown = locate_config_value(:default_cooldown) if locate_config_value(:default_cooldown)
        @as_group.desired_capacity = locate_config_value(:desired_capacity) if locate_config_value(:desired_capacity)
        @as_group.enabled_metrics = locate_config_value(:enabled_metrics) if locate_config_value(:enabled_metrics)
        @as_group.health_check_grace_period = locate_config_value(:health_check_grace_period) if locate_config_value(:health_check_grace_period)
        @as_group.health_check_type = locate_config_value(:health_check_type) if locate_config_value(:health_check_type)
        @as_group.load_balancer_names = locate_config_value(:load_balancer_names) if locate_config_value(:load_balancer_names)
        @as_group.max_size = locate_config_value(:max_size) if locate_config_value(:max_size)
        @as_group.min_size = locate_config_value(:min_size) if locate_config_value(:min_size)
        @as_group.suspended_processes = locate_config_value(:suspended_processes) if locate_config_value(:suspended_processes)
        @as_group.termination_policies = locate_config_value(:termination_policies) if locate_config_value(:termination_policies)

        @as_group
      end

      def tags
        tags = locate_config_value(:tags)
        if !tags.nil? and tags.length != tags.to_s.count('=')
          ui.error("Tags should be entered in a key = value pair")
          exit 1
        end
        tags
      end

      def create_tags(tags_array)
        autoscaling.create_or_update_tags(tags_array)
      end

    end
  end
end
