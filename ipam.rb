require 'rubygems'
require 'sinatra'
require 'json'
require 'redis'
require 'rest-client'
require 'resolv'
require 'yaml'
require 'erb'
require 'bcrypt'
require 'ipaddress' #https://github.com/bluemonk/ipaddress

use Rack::MethodOverride

enable :sessions
@@config = YAML.load(File.open("ipam.yml"))

# Redis hash key is the ipv4 /32
# "3.101.1.10" { :ipaddress => "3.101.1.10", :subnet => "255.255.254.0", :gateway => "3.101.1.1", :nameserver => "3.100.100.100", :allocated => "false", :score => 0}

@@redis = Redis.new
@@hash = Hash.new

#before do
#  cache_control :must_revalidate
#end

def reserve_address(ipaddress)
  @@redis.select(0)
  #increment score to indicated it has been used. Needed for networker cache bug
  new_score = @@redis.hget(ipaddress,"score")
  new_score = new_score.to_i + 1
  @@redis.hmset(ipaddress, "allocated", "true", "score", new_score)
  subnet = @@redis.hget(ipaddress, "subnet")
  @@redis.select(5)
  @@redis.sadd(subnet, ipaddress)
end

def release_address(fqdn)
  @@redis.select(0)
  ipaddress = Resolv.getaddress fqdn
  @@redis.hset(ipaddress, "allocated", "false")
  subnet = @@redis.hget(ipaddress, "subnet")
  @@redis.select(5)
  @@redis.srem(subnet, ipaddress)
end

def ipam_address
  @@redis.select(0)
  keys = @@redis.keys("192.*")
  free_addresses = Array.new 
  keys.each do |k|
    puts k 
    if @@redis.hget(k, "allocated") =~ /false/
      # Set address allocation to true
      # pump into 2 dimensional array
      free_addresses << [@@redis.hmget(k, "score"), @@redis.hmget(k, "ipaddress")] 
    end
  end
  return_ip = free_addresses.sort_by{|k|k[0]}.first[1]
  reserve_address(return_ip)
  puts return_ip
  return return_ip 
end

def build_hash(result, operatingsystem)
  redis_counter = @@redis.get("counter")
  @@redis.incr("counter")
  counter = "%04d" % redis_counter

  if operatingsystem =~ /linux/i
    @@hash[:hostname] = "#{@@config["linux"]["hostname_prefix"]}#{counter}"
    @@hash[:domain] = @@config["linux"]["domain"]
  end

  if operatingsystem =~ /windows/i
    @@hash[:hostname] = "#{@@config["windows"]["hostname_prefix"]}#{counter}"
    @@hash[:domain] = @@config["windows"]["domain"]
  end
  
  @@hash[:ipaddress] = @@redis.hget(result, "ipaddress")
  @@hash[:mask] = @@redis.hget(result, "mask")
  @@hash[:gateway] = @@redis.hget(result, "gateway")
  @@hash[:nameserver] = @@redis.hget(result, "nameserver")
  @@hash
end

def create_subnet(subnet, mask, gateway, datacenter, name_server)
  puts "[INFO]: SUBNET: #{subnet}  MASK: #{mask} GATEWAY:#{gateway} DATACENTER: #{datacenter} NAME SERVER:#{name_server}" 
  
  @@redis.select(3)
  @@redis.sadd(datacenter,subnet)
  
  @@redis.select(0)
  ip = IPAddress "#{subnet}/#{mask}"

  ip.each_host do |host|
    @@redis.select(0)
    @@redis.hmset(host, "ipaddress", host, "subnet", subnet, "mask", mask, "gateway", gateway, "datacenter" , datacenter,  "nameserver" , name_server , "allocated" , false, "score" , 0)
    if @@redis.hget(host, "ipaddress") =~ host 
      puts "[INFO] Entered #{host} into datastore" 
    end
    @@redis.select(4)    
    @@redis.sadd(subnet, host)
  end

  return true
end

def remove_subnet(subnet)
  @@redis.select(5)
  if @@redis.smembers(subnet).length == 0
    puts "[INFO] REMOVING #{subnet}" 
    @@redis.select(4)
    ips = @@redis.smembers(subnet)
    @@redis.select(0)
    datacenter = @@redis.hget(ips[0], "datacenter")
    ips.each do |ip|
      @@redis.select(0)
      @@redis.del(ip)
      @@redis.select(4)
      @@redis.srem(subnet, ip)
    end
    @@redis.select(3)
    @@redis.srem(datacenter, subnet)
    return true
  else
    return false
  end
end

def create_datacenter(datacenter)
  puts "[INFO]: DATACENTER: #{datacenter}"
  @@redis.select(2)
  @@redis.sadd("datacenters", datacenter)
  if @@redis.sismember("datacenters", datacenter) =~ 1
    puts "[INFO] Entered #{datacenter} into datastore"
  end
  return true
end

def remove_datacenter(datacenter)
  @@redis.select(3)
  if @@redis.exists(datacenter) == false
    puts "[INFO] REMOVING #{datacenter}"
    @@redis.select(2)
    @@redis.srem("datacenters", datacenter)
    return true
  else
    return false
  end
end

#use Rack::Auth::Basic, "Restricted Area" do |username, password|
#  username == 'admins' and password == 'passwords'
#end

before '/ipam/address*' do

  # X-Api-Key
  error 401 unless env['HTTP_X_API_KEY'] =~ /#{@@config["x_api_key"]}/
end

get '/ipam/address/:os' do
  request_hash = build_hash(ipam_address, params[:os]).to_json
  rest_request = {:fqdn => "#{@@hash[:hostname]}.#{@@hash[:domain]}", :ipaddress => "#{@@hash[:ipaddress]}", :osfamily => params[:os]}.to_json

  RestClient.post @@config["dns_endpoint"], {:fqdn => "#{@@hash[:hostname]}.#{@@hash[:domain]}", :ip => "#{@@hash[:ipaddress]}", :osfamily => params[:os]}.to_json,
    :content_type => :json,
    :'X-Api-Key' => @@config["x_api_key"]
  request_hash
end

delete '/ipam/address/:fqdn' do
  request_params = JSON.parse(request.body.read)
  ipaddress = Resolv.getaddress params[:fqdn]

  # RestClient does not support sending an entity body with HTTP DELETE, so use curl(1) 
  %x{curl -k -X DELETE -H 'X-Api-Key: #{@@config["x_api_key"]}' -d '{ "fqdn":"#{params[:fqdn]}", "ip":"#{ipaddress}", "osfamily":"#{request_params["osfamily"]}" }' #{@@config["dns_endpoint"]}}

  release_address(params[:fqdn])
end

post '/ipam/reserve/:ipaddress' do
  @@redis.select(0)
  status 404 unless @@redis.hexists(params[:ipaddress], "allocated")

  if @@redis.hexists(params[:ipaddress], "allocated")
    reserve_address(params[:ipaddress])
    puts "[INFO] : Reserved IP : #{params[:ipaddress]}"
    status 200

  else
    puts "[ERROR] : Could NOT Reserve IP : #{params[:ipaddress]}"
    status 500
  end
end

post '/ipam/unreserve/:ipaddress' do 
  @@redis.select(0)
  status 404 unless @@redis.hexists(params[:ipaddress], "allocated")
 
  if @@redis.hexists(params[:ipaddress], "allocated")
    release_address(params[:ipaddress])
    puts "[INFO] : Un Reserved IP : #{params[:ipaddress]}"
    status 200

  else
    puts "[ERROR] : Could NOT UN Reserve IP : #{params[:ipaddress]}"
    status 500
  end
end
 # unless session['login?']
    #halt "Access denied"
  # redirect '/login'
  #end
#end

def return_msg(err_msg, redirect_pg)
  #pass = BCrypt::Engine.hash_secret('my password', 'yes')
  pass = BCrypt::Password.create("my password")
  new = BCrypt::Password.new(pass)
  if new == "my password"
    a = "#{pass} or #{new}"
  else 
    a = "n"
  end
  #pas = 1
  "<script>
     alert('#{err_msg}');
     window.location = '#{redirect_pg}';
   </script>"
end

def require_login
  redirect('/login') unless is_authenticated?
end

def is_authenticated?
  return !!session['login?']
end

def require_admin
  redirect('/ipam') unless is_admin?
end

def is_admin?
  return session['auth_level'] == 'admin'
end

def listUsers
  @@redis.select(1)
  key = @@redis.keys("*")
end

before /^(?!\/(login|register|$))/ do
  require_login
end

before '/admin/*' do
  require_admin
end

get '/' do
  erb :splash
end

get '/login' do
  if is_authenticated?
    redirect '/ipam'
  else
    erb :login
  end
end

get '/register' do
  if is_authenticated?
    redirect '/ipam'
  else
    erb :register
  end
end

get '/logout' do
  session['login?'] = nil
  #cookies[:l] = 0
  redirect '/login'
end

post '/login' do
  username = params[:username]
  password = params[:password]
  @@redis.select(1)
  if @@redis.hexists(username, "password")
    dbpass = @@redis.hget(params[:username], "password")
    dbpass_e = BCrypt::Password.new(dbpass)
    #upass_e = BCrypt::Password.new(password)
  else
    dbpass = nil
  end 
  if dbpass != nil and dbpass_e == password
    session['login?'] = username
    session['auth_level'] = @@redis.hget(params[:username], "type")
    #cookies[:l] = 1
    redirect '/ipam'
  else
    return_msg('The credentials are wrong.', '/login')
  end
  #@@redis.select(0)
end

post '/register' do
  username = params[:username]
  password = params[:password]
  password_again = params[:password_again]
  user_role = params[:user_role]
  admin_key = params[:admin_key]
  @@redis.select(1)
  usernameExist = @@redis.hexists(params[:username], "password")
  if !usernameExist#@@redis.hexists(params[:username], "password")
    if username != "" and password != "" and password_again != ""
      if password == password_again
	pass_encr = BCrypt::Password.create(password)
        if user_role == "Admin" and admin_key == "p4ss"
          @@redis.hmset(username, "password", pass_encr, "type", "admin")
          return_msg('You have been registered as an Admin user.', '/login')
        elsif user_role == "Standard" 
          @@redis.hmset(username, "password", pass_encr, "type", "standard")
          return_msg('You have been registered as a Standard user.', '/login')
        else
          return_msg('There was an error, you have to select a Role and provide a valid key if admin role was chosen.', '/register')
        end
      else
        return_msg('The two passwords do not match.', '/register')
      end 
    else
      return_msg('All fields are required.', '/register')
    end
  else 
    return_msg('This username already exists', '/register')
  end
  #@@redis.select(0)
end

post '/userProfile' do
  currentUser = session['login?']
  currentpass = params[:current_password]
  password = params[:password_edit]
  confirm_pass = params[:passwordConfirm_edit]
  @@redis.select(1)
  curr_usrPass = @@redis.hget(currentUser, "password")
  curr_usrPassE = BCrypt::Password.new(curr_usrPass)
  if curr_usrPass != nil and curr_usrPassE == currentpass
    if password != nil and password != ""
      if password == confirm_pass
        pass_encr = BCrypt::Password.create(password)
        @@redis.hmset(currentUser, "password", pass_encr)
        return_msg('Password changed.', '/userProfile')
      else 
        return_msg('The two passwords do not match.', '/userProfile')
      end
    else 
      return_msg('The fields cannot be blank.', '/userProfile')
    end
  else
      return_msg('Current password is not correct.', '/userProfile')
  end
end

get '/ipam' do
  erb :ipam
end

get '/dashboard' do
  erb :dashboard
end

get '/userProfile' do
  erb :userProfile
end

get '/admin/addSubnet' do
  erb :addSubnet
end

get '/admin/removeSubnet' do
  erb :removeSubnet
end

get '/admin/addDatacenter' do
  erb :addDatacenter
end

get '/admin/removeDatacenter' do
  erb :removeDatacenter
end

get '/admin/manageUsers' do
  @@redis.select(1)
  @username = @@redis.keys("*")
  @ctr = 1
  erb :manageUsers
end

get '/admin/manageUsers/edit/:username' do
  @@redis.select(1)
  @username = params[:username]
  erb :editUser
end

post '/admin/manageUsers/edit/:username' do
  @@redis.select(1)
  username = params[:username]
  password = params[:password_edit]
  confirm_pass = params[:passwordConfirm_edit]
  if password != nil and password != ""
    if password == confirm_pass
      pass_encr = BCrypt::Password.create(password)
      @@redis.hmset(username, "password", pass_encr)
      return_msg('Password changed.', "/admin/manageUsers")
    else
      return_msg('The two passwords do not match.', "/admin/manageUsers/edit/#{username}")
    end
  else
    return_msg('The fields cannot be blank.', "/admin/manageUsers/edit/#{username}")
  end
end

get '/admin/manageUsers/del/:username' do
  @@redis.select(1)
  @username = params[:username]
  erb :delUser
end

post '/admin/manageUsers/del/:username' do
  @@redis.select(1)
  @username = params[:username]
  @@redis.del(@username)
  return_msg('The user has been removed', '/admin/manageUsers')
end


post '/subnet' do
  subnet = params[:subnet]
  gateway = params[:gateway]
  nameserver = params[:nameserver]
  mask = params[:mask]
  datacenter = params[:datacenter]

  puts "[INFO] POST ADD Subnet: #{subnet} Gateway: #{gateway} Datacenter: #{datacenter} Name Server : #{nameserver} Mask: #{mask}"
  #not sure if I should call the api or just call the code that the api would
  if create_subnet(subnet, mask, gateway, datacenter, nameserver)
    status 201
    return_msg("The Subnet #{subnet} has been added", '/ipam')
  else
    return_msg("Error Creating Subnet #{subnet}", '/addSubnet')
    status 500
  end
end

delete '/subnet' do
  subnet = params[:subnet]

  puts "[INFO] DELETE REMOVE  Subnet: #{subnet}"
  #not sure if I should call the api or just call the code that the api would
  if remove_subnet(subnet)
    status 201
    return_msg("The Subnet #{subnet} has been removed", '/ipam')
  else
    return_msg("Error REMOVING Subnet #{subnet}", '/removeSubnet')
    status 500
  end
end

post '/datacenter' do
  datacenter = params[:datacenter]

  puts "[INFO] POST ADD Datacenter: Datacenter: #{datacenter}"
  #not sure if I should call the api or just call the code that the api would
  if create_datacenter(datacenter)
    status 201
    return_msg("The Data Center #{datacenter} has been added", '/ipam')
  else
    return_msg("Error Creating Data Center #{datacenter}\nDoes the Data Center already exist?", '/addDatacenter')
    status 500
  end
end

delete '/datacenter' do
  datacenter = params[:datacenter]

  puts "[INFO] DELETE REMOVE  Datacenter: #{datacenter}"
  #not sure if I should call the api or just call the code that the api would
  if remove_datacenter(datacenter)
    status 200
    return_msg("The Datacenter #{datacenter} has been removed", '/ipam')
  else
    return_msg("Error REMOVING datacenter #{datacenter}", '/removeDatacenter')
    status 404
  end
end

get '/status.json' do
  @@redis.select(0) 
  datastore = Array.new
  keys = @@redis.keys("*")
  keys.each do |k|
    datastore << @@redis.hgetall(k)
  end
  
  datastore.to_json
end

get '/ips.json' do
  @@redis.select(0) 
  datastore = Array.new
  keys = @@redis.keys("*")
  keys.each do |k|
    datastore << @@redis.hgetall(k)
  end
  
  datastore.to_json
end

get '/datacenters.json' do
  @@redis.select(2)
  datastore = Array.new
  keys = @@redis.smembers("datacenters")
  keys.each do |k|
    @@redis.select(3)
    datastore << {'name' => k, 'subnets' => @@redis.smembers(k)}
  end

  datastore.to_json
end

get '/subnets.json' do
  @@redis.select(4)
  datastore = Array.new
  keys = @@redis.keys("*")
  keys.each do |k|
    count = @@redis.scard(k)
    @@redis.select(5)
    allocated = @@redis.scard(k)
    datastore << {'subnet' => k, 'allocated'=> allocated, 'count'=> count, 'free' => (count-allocated)}
    @@redis.select(4) 
  end

  datastore.to_json
end

put '/ipam/address/subnet' do 
  
  data = JSON.parse request.body.read
  
  gateway = data['gateway']
  nameserver = data['nameserver']
  subnet = data['subnet']
  mask = data['mask'] 
  datacenter = data['datacenter']

  if create_subnet(subnet, mask, gateway, datacenter, nameserver)
    puts "[INFO] Created SUBNET: #{subnet} MASK: #{mask} GATEWAY: #{gateway} DATACENTER: #{datacenter} NAME SERVER: #{nameserver}"
    status 201
  else 
    puts "[ERROR] Creating subnet : #{subnet} MASK: #{mask} GATEWAY: #{gateway} DATACENTER: #{datacenter} NAME SERVER: #{nameserver}"
    status 500
  end
end
