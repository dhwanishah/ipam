#!/usr/bin/ruby

# redis mass insert documented here 
# http://redis.io/topics/mass-insert

def gen_redis_proto(*cmd)
    proto = ""
    proto << "*"+cmd.length.to_s+"\r\n"
    cmd.each{|arg|
        proto << "$"+arg.to_s.bytesize.to_s+"\r\n"
        proto << arg.to_s+"\r\n"
    }
    proto
end

#Redis datastore
#"3.1.2.3" { :ipaddress => "3.1.2.3", :subnet => "255.255.252.0", :gateway => "3.1.1.1", :nameserver => "3.3.3.3", :allocated => "false", :score => 0 }

#puts gen_redis_proto("SET","mykey","Hello World!").inspect
(2...10).each{|n|
    STDOUT.write(gen_redis_proto("HSET","192.168.1.#{n}",":ipaddress => '192.168.1.#{n}', :subnet => '255.255.255.0', :gateway => '192.168.1.1', :nameserver => '3.3.3.3', :allocated => 'false', :score => 0"))
}
