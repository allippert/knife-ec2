require File.expand_path('../../spec_helper', __FILE__)
require 'fog'

describe Chef::Knife::Ec2AsGroupCreate do
  before do
    @knife_as_create = Chef::Knife::Ec2AsGroupCreate.new
    @knife_as_create.initial_sleep_delay = 0

    {
        :name => 'autoscale-group-name',
        :launch_config => 'rspec-launch-config',
        :aws_ssh_key_id => 'aws_ssh_key_id',
        :aws_access_key_id => 'aws_access_key_id',
        :aws_secret_access_key => 'aws_secret_access_key',
        :max_size => 1,
        :min_size => 1
    }.each do |key, value|
      Chef::Config[:knife][key] = value
    end

    @as_autoscaling = double(Fog::AWS::AutoScaling)

    @as_configurations = double()
    @new_as_configurations = double()

    @as_configurations_attribs = { :id => 'rspec-launch-config',
                                   :instance_type => 'm1.small',
                                   :image_id => 'ami-47241231',
                                   :key_name => 'my_ssh_key',
                                   :security_groups => ['group1', 'group2']
                                  }

    @as_configurations_attribs.each_pair do |attrib, value|
      @new_as_configurations.stub(attrib).and_return(value)
    end

    @as_groups = double()
    @new_as_groups = double()

    @as_groups_attribs = { :id => 'rspec-autoscale-group',
                           :launch_configuration_name => 'rspec-launch-config',
                           :availability_zones => 'zones',
                           :default_cooldown => 100,
                           :desired_capacity => 1,
                           :health_check_grace_period => 0,
                           :health_check_type => 'EC2',
                           :max_size => 1,
                           :min_size => 1,
                           :enabled_metrics => nil,
                           :instances => [],
                           :load_balancer_names => '',
                           :placement_group => '',
                           :tags => {},
                           :termination_policies => ['Default'],
                           :vpc_zone_identifier => nil
                         }

    @as_groups_attribs.each_pair do |attrib, value|
      @new_as_groups.stub(attrib).and_return(value)
    end

  end

  describe "run" do
    before do
      @as_configurations.should_receive(:get).with(@as_configurations_attribs[:id]).and_return(@new_as_configurations)
      @as_autoscaling.should_receive(:configurations).and_return(@as_configurations)
      @as_autoscaling.should_receive(:groups).and_return(@as_groups)
      @as_groups.should_receive(:new).and_return(@new_as_groups)

      @new_as_groups.stub(:max_size=)
      @new_as_groups.stub(:min_size=)

      @new_as_groups.should_receive(:save).and_return(@new_as_groups)

      Fog::AWS::AutoScaling.should_receive(:new).and_return(@as_autoscaling)
    end

    it "sets the launch config id correctly" do
      @knife_as_create.run
      @knife_as_create.launch_config.id.should == 'rspec-launch-config'
    end
  end

  describe "create_as_group_def" do
    before do
      @as_configurations.should_receive(:get).with(@as_configurations_attribs[:id]).and_return(@new_as_configurations)
      @as_autoscaling.should_receive(:configurations).and_return(@as_configurations)

      Fog::AWS::AutoScaling.should_receive(:new).and_return(@as_autoscaling)
    end

    it "sets min-size option correctly" do
      gd = @knife_as_create.create_as_group_def
      gd[:min_size].should == 1
    end

  end

end
