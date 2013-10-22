#
# Author:: Thomas Bishop (<bishop.thomas@gmail.com>)
# Copyright:: Copyright (c) 2010 Thomas Bishop
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path('../../spec_helper', __FILE__)
require 'fog'
require 'chef/knife/bootstrap'
require 'chef/knife/core/bootstrap_context'

describe Chef::Knife::Ec2AcLaunchconfigCreate do
  before do
    @knife_as_create = Chef::Knife::Ec2AsLaunchconfigCreate.new
    @knife_as_create.initial_sleep_delay = 0

    {
      :launch_config_id => 'launch-config-id',
      :image => 'image',
      :aws_ssh_key_id => 'aws_ssh_key_id',
      :aws_access_key_id => 'aws_access_key_id',
      :aws_secret_access_key => 'aws_secret_access_key'
    }.each do |key, value|
      Chef::Config[:knife][key] = value
    end

    @as_connection = double(Fog::Compute::AWS)
    @as_connection.stub_chain(:images, :get).and_return double('ami', :root_device_type => 'not_ebs', :platform => 'linux')

    @as_autoscaling = double()

    @as_configurations = double()
    @new_as_configurations = double()

    @as_configurations_attribs = { :id => 'rspec-launch-config',
                           :instance_type => 'm1.small',
                           :image_id => 'ami-47241231',
                           :key_name => 'my_ssh_key',
                           :security_groups => ['group1', 'group2'],
                           :root_device_type => 'not_ebs' }

    @as_configurations_attribs.each_pair do |attrib, value|
      @new_as_configurations.stub(attrib).and_return(value)
    end

  end

  describe "run" do
    before do
      @as_configurations.should_receive(:create).and_return(@new_as_configurations)
      @as_autoscaling.should_receive(:configurations).and_return(@as_configurations)

      Fog::Compute::AWS.should_receive(:new).and_return(@as_connection)
      Fog::AWS::AutoScaling.should_receive(:new).and_return(@as_autoscaling)
      
      @knife_as_create.stub(:puts)
      @knife_as_create.stub(:print)
      @knife_as_create.config[:image] = '12345'

      @bootstrap = Chef::Knife::Bootstrap.new
      Chef::Knife::Bootstrap.stub(:new).and_return(@bootstrap)

      @chef_config = Chef::Config

      Chef::Config.stub(:new).and_return(@chef_config)

      @bootstrap_context = Chef::Knife::Core::BootstrapContext.new(@bootstrap.config, @bootstrap.config[:run_list], Chef::Config)
      Chef::Knife::Core::BootstrapContext.stub(:new).and_return(@bootstrap_context)

      @bootstrap_context.should_receive(:validation_key).and_return('rspec-validation-key')
    end

    it "defaults to a distro of 'cloud-init'" do
      @knife_as_create.config[:distro] = @knife_as_create.options[:distro][:default]
      @knife_as_create.run
      @knife_as_create.config[:distro].should == 'cloud-init-omnibus-shell-linux'
    end

    it
  end

end

