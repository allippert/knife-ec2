#
# Author:: Alan Lippert (<alan.lippert@blackbaud.com>)
#

require 'chef/knife/ec2_base'
require 'chef/knife/winrm_base'

class Chef
  class Knife
    class Ec2AsLaunchconfigCreate < Knife

      include Knife::Ec2Base
      include Knife::WinrmBase
      deps do
        require 'fog'
        require 'readline'
        require 'chef/json_compat'
        require 'chef/knife/bootstrap'
        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife ec2 as launchconfig create (options)"

      attr_accessor :initial_sleep_delay
      attr_reader :launch_config

      option :launch_config_id,
             :short => "-n name",
             :long =>  "--launch-config-id id",
             :description => "The unique id/name for the launch configuration"

      option :flavor,
             :short => "-f FLAVOR",
             :long => "--flavor FLAVOR",
             :description => "The flavor of server(s) (m1.small, m1.medium, etc)",
             :proc => Proc.new { |f| Chef::Config[:knife][:flavor] = f }

      option :image,
             :short => "-I IMAGE",
             :long => "--image IMAGE",
             :description => "The AMI for the server(s)",
             :proc => Proc.new { |i| Chef::Config[:knife][:image] = i }

      option :iam_instance_profile,
             :long => "--iam-profile NAME",
             :description => "The IAM instance profile to apply to this instance."

      option :security_groups,
             :short => "-G X,Y,Z",
             :long => "--groups X,Y,Z",
             :description => "The security groups for the server(s) in the auto scaling group; not allowed when using VPC",
             :proc => Proc.new { |groups| groups.split(',') }

      option :security_group_ids,
             :short => "-g X,Y,Z",
             :long => "--security-group-ids X,Y,Z",
             :description => "The security group ids for this server(s) in the auto scaling group; required when using VPC",
             :proc => Proc.new { |security_group_ids| security_group_ids.split(',') }

      option :associate_public_ip_address,
             :long => "--associate-public-ip-address",
             :description => "Indicate whether to associate a public IP address with the instance. If specified, it can be true or false."

      option :ssh_key_name,
             :short => "-S KEY",
             :long => "--ssh-key KEY",
             :description => "The AWS SSH key id",
             :proc => Proc.new { |key| Chef::Config[:knife][:aws_ssh_key_id] = key }

      option :identity_file,
             :short => "-i IDENTITY_FILE",
             :long => "--identity-file IDENTITY_FILE",
             :description => "The SSH identity file used for authentication"

      option :prerelease,
             :long => "--prerelease",
             :description => "Install the pre-release chef gems"

      option :bootstrap_version,
             :long => "--bootstrap-version VERSION",
             :description => "The version of Chef to install",
             :proc => Proc.new { |v| Chef::Config[:knife][:bootstrap_version] = v }

      option :distro,
             :short => "-d DISTRO",
             :long => "--distro DISTRO",
             :description => "Bootstrap a distro using a template; default is 'chef-full'",
             :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d },
             :default => "cloud-init-omnibus-shell-linux"

      option :template_file,
             :long => "--template-file TEMPLATE",
             :description => "Full path to location of template to use",
             :proc => Proc.new { |t| Chef::Config[:knife][:template_file] = t },
             :default => false

      option :ebs_size,
             :long => "--ebs-size SIZE",
             :description => "The size of the EBS volume in GB, for EBS-backed instances"

      option :ebs_optimized,
             :long => "--ebs-optimized",
             :description => "Enabled optimized EBS I/O"

      option :run_list,
             :short => "-r RUN_LIST",
             :long => "--run-list RUN_LIST",
             :description => "Comma separated list of roles/recipes to apply",
             :proc => lambda { |o| o.split(/[\s,]+/) }

      option :secret,
             :short => "-s SECRET",
             :long => "--secret ",
             :description => "The secret key to use to encrypt data bag item values",
             :proc => lambda { |s| Chef::Config[:knife][:secret] = s }

      option :secret_file,
             :long => "--secret-file SECRET_FILE",
             :description => "A file containing the secret key to use to encrypt data bag item values",
             :proc => lambda { |sf| Chef::Config[:knife][:secret_file] = sf }

      option :json_attributes,
             :short => "-j JSON",
             :long => "--json-attributes JSON",
             :description => "A JSON string to be added to the first run of chef-client",
             :proc => lambda { |o| JSON.parse(o) }

      option :bootstrap_protocol,
             :long => "--bootstrap-protocol protocol",
             :description => "protocol to bootstrap windows servers. options: winrm/ssh",
             :proc => Proc.new { |key| Chef::Config[:knife][:bootstrap_protocol] = key },
             :default => "winrm"

      option :fqdn,
             :long => "--fqdn FQDN",
             :description => "Pre-defined FQDN",
             :proc => Proc.new { |key| Chef::Config[:knife][:fqdn] = key },
             :default => nil

      option :aws_user_data,
             :long => "--user-data USER_DATA_FILE",
             :short => "-u USER_DATA_FILE",
             :description => "The EC2 User Data file to provision the instance with",
             :proc => Proc.new { |m| Chef::Config[:knife][:aws_user_data] = m },
             :default => nil

      def run
        $stdout.sync = true

        validate!

        #requested_elastic_ip = config[:associate_eip] if config[:associate_eip]

        # For VPC EIP assignment we need the allocation ID so fetch full EIP details
        #elastic_ip = connection.addresses.detect{|addr| addr if addr.public_ip == requested_elastic_ip}

        @launch_config = autoscaling.configurations.create(create_launch_config_def)

        # If we don't specify a security group or security group id, Fog will
        # pick the appropriate default one. In case of a VPC we don't know the
        # default security group id at this point unless we look it up, hence
        # 'default' is printed if no id was specified.
        printed_security_groups = "default"
        printed_security_groups = @launch_config.security_groups.join(", ") if @launch_config.security_groups

#        printed_security_group_ids = "default"
#        printed_security_group_ids = @launch_config.security_group_ids.join(", ") if @launch_config.security_group_ids

        puts "\n"
        msg_pair("Launch Config ID", @launch_config.id)
        msg_pair("Flavor", @launch_config.instance_type)
        msg_pair("Image", @launch_config.image_id)
        msg_pair("Region", connection.instance_variable_get(:@region))
        msg_pair("Security Groups", printed_security_groups) unless vpc_mode? or (@launch_config.security_groups.nil? and @launch_config.security_group_ids)
#        msg_pair("Security Group Ids", printed_security_group_ids) if vpc_mode? or @launch_config.security_group_ids
        msg_pair("IAM Profile", locate_config_value(:iam_instance_profile)) if locate_config_value(:iam_instance_profile)
        msg_pair("SSH Key", @launch_config.key_name)

        device_map = @launch_config.block_device_mappings.first
        msg_pair("Root Volume ID", device_map['volumeId'])
        msg_pair("Root Device Name", device_map['deviceName'])
        msg_pair("Root Device Delete on Terminate", device_map['deleteOnTermination'])

        if config[:ebs_size]
          if ami.block_device_mappings.first['volumeSize'].to_i < config[:ebs_size].to_i
            volume_too_large_warning = "#{config[:ebs_size]}GB " +
                "EBS volume size is larger than size set in AMI of " +
                "#{ami.block_device_mappings.first['volumeSize']}GB.\n" +
                "Use file system tools to make use of the increased volume size."
            msg_pair("Warning", volume_too_large_warning, :yellow)
          end
        end

        if config[:ebs_optimized]
          msg_pair("EBS is Optimized", @launch_config.ebs_optimized.to_s)
        end
        msg_pair("Environment", config[:environment] || '_default')
        msg_pair("Run List", (config[:run_list] || []).join(', '))
        msg_pair("JSON Attributes",config[:json_attributes]) unless !config[:json_attributes] || config[:json_attributes].empty?
      end

      def bootstrap_common_params(bootstrap)
        bootstrap.config[:run_list] = config[:run_list]
        bootstrap.config[:bootstrap_version] = locate_config_value(:bootstrap_version)
        bootstrap.config[:distro] = locate_config_value(:distro)
        bootstrap.config[:template_file] = locate_config_value(:template_file)
        bootstrap.config[:environment] = locate_config_value(:environment)
        bootstrap.config[:prerelease] = config[:prerelease]
        bootstrap.config[:first_boot_attributes] = locate_config_value(:json_attributes) || {}
        bootstrap.config[:encrypted_data_bag_secret] = locate_config_value(:encrypted_data_bag_secret)
        bootstrap.config[:encrypted_data_bag_secret_file] = locate_config_value(:encrypted_data_bag_secret_file)
        bootstrap.config[:secret] = locate_config_value(:secret)
        bootstrap.config[:secret_file] = locate_config_value(:secret_file)
        # Modify global configuration state to ensure hint gets set by
        # knife-bootstrap
        Chef::Config[:knife][:hints] ||= {}
        Chef::Config[:knife][:hints]["ec2"] ||= {}
        bootstrap
      end

      def bootstrap_for_cloud_init()
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.config[:identity_file] = config[:identity_file]
        # may be needed for vpc_mode
        bootstrap.config[:host_key_verify] = config[:host_key_verify]
        bootstrap_common_params(bootstrap)
      end

      def vpc_mode?
        # Amazon Virtual Private Cloud requires a subnet_id. If
        # present, do a few things differently
        !!locate_config_value(:subnet_id)
      end

      def ami
        @ami ||= connection.images.get(locate_config_value(:image))
      end

      def validate!

        super([:image, :aws_ssh_key_id, :aws_access_key_id, :aws_secret_access_key])

        if locate_config_value(:launch_config_id).nil?
          ui.error("You have not provided the unique id/name of the autoscale launch configuration")
          exit 1
        end

        if ami.nil?
          ui.error("You have not provided a valid image (AMI) value.  Please note the short option for this value recently changed from '-i' to '-I'.")
          exit 1
        end

        if vpc_mode? and !!config[:security_groups]
          ui.error("You are using a VPC, security groups specified with '-G' are not allowed, specify one or more security group ids with '-g' instead.")
          exit 1
        end
        if !vpc_mode? and !!config[:private_ip_address]
          ui.error("You can only specify a private IP address if you are using VPC.")
          exit 1
        end

        if config[:associate_eip]
          eips = connection.addresses.collect{|addr| addr if addr.domain == eip_scope}.compact

          unless eips.detect{|addr| addr.public_ip == config[:associate_eip] && addr.server_id == nil}
            ui.error("Elastic IP requested is not available.")
            exit 1
          end
        end
      end

      def create_launch_config_def
        launch_config_def = {
            :id                     => locate_config_value(:launch_config_id),
            :image_id               => locate_config_value(:image),
            :security_groups        => config[:security_groups],
            :instance_type          => locate_config_value(:flavor),
            :key_name               => Chef::Config[:knife][:aws_ssh_key_id],
            :iam_instance_profile   => locate_config_value(:iam_instance_profile)
        }

        if config[:ebs_optimized]
          launch_config_def[:ebs_optimized] = "true"
        else
          launch_config_def[:ebs_optimized] = "false"
        end

        ami_map = ami.block_device_mappings.first
        ebs_size = begin
          if config[:ebs_size]
            Integer(config[:ebs_size]).to_s
          else
            ami_map["volumeSize"].to_s
          end
        rescue ArgumentError
          puts "--ebs-size must be an integer"
          msg opt_parser
          exit 1
        end
        delete_term = if config[:ebs_no_delete_on_term]
                        "false"
                      else
                        ami_map["deleteOnTermination"]
                      end

        launch_config_def[:block_device_mappings] =
            [{
                 'DeviceName' => ami_map["deviceName"],
                 'Ebs.VolumeSize' => ebs_size,
                 'Ebs.DeleteOnTermination' => delete_term
             }]

        (config[:ephemeral] || []).each_with_index do |device_name, i|
          launch_config_def[:block_device_mappings] = (launch_config_def[:block_device_mappings] || []) << {'VirtualName' => "ephemeral#{i}", 'DeviceName' => device_name}
        end

        # Setup bootstrap user_data for cloud-init
        template_file = bootstrap_for_cloud_init.find_template
        launch_config_def[:user_data] = bootstrap_for_cloud_init.render_template(File.read(template_file))

        #msg_pair("User Data", launch_config_def[:user_data])

        launch_config_def
      end

    end
  end
end
