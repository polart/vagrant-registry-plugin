require 'spec_helper'

describe VagrantPlugins::Registry::Config do
  it 'has a version number' do
    expect(Vagrant::Registry::VERSION).not_to be nil
  end

  it 'does something useful' do
    expect(false).to eq(true)
  end
end
