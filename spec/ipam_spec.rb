require 'spec_helper'

describe DNS do
  before { @dns = DNS.new(:server => "foo.com", :rndc_key => "key", :rndc_secret => "secret", :ttl => 300) }

  describe :new do
    subject { @dns }
    it { should be_an_instance_of DNS }
    it { should_not be_nil }
  end

  describe :reverse_ipaddress do
    subject { @dns.reverse_ipaddress(:ipaddress => "10.1.1.1") }
    it { should eql "1.1.1.10.in-addr.arpa" }
    it { should_not be_nil }
  end
end
