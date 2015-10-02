ipam-api
========

Obtain an address from IPAM/DNS
================================
    curl -X GET -H 'X-Api-Key: secret' -k https://localhost:7070/ipam/address/windows

Remove an address from IPAM/DNS
===============================
    curl - DELETE -H 'X-Api-Key: secret' -d '{ "osfamily" : "windows" }' -k https://localhost:7070/ipam/address/cwtest0016.local

Add a subnet to IPAM
==============================
    curl -k -X PUT -H 'X-Api-Key: secret' -H 'Content-Type: application/json' -d '{"gateway":"192.168.1.1", "nameserver":"192.168.1.201", "subnet":"192.168.1.1", "mask":"255.255.255.0"}' http://localhost:7070/ipam/address/subnet

Manually reserve an address in IPAM
===================================
    redis-cli
    keys *
    hget "192.168.1.1" "allocated"
    hset "192.168.2.3" "allocated" "true"
    save

Architecture
============
The IPAM service consists of a Sinatra RESTful front-end to a Redis datastore. 

* When a request is made to obtain an IP Address from IPAM it is automatically added to DNS. 
* When a request is made to remove an IP Address from IPAM it is automatically removed from DNS.

Data Model
==========
Redis(0): Contains all the IPs in the system  

    "3.1.2.3" { :ipaddress => "3.1.2.3", :subnet => "255.255.252.0", :gateway => "3.1.1.1", :nameserver => "3.3.3.3", :allocated => "false", :datacenter => "DC1", :score => 0 }
    "3.1.2.4" { :ipaddress => "3.1.2.4", :subnet => "255.255.252.0", :gateway => "3.1.1.1", :nameserver => "3.3.3.3", :allocated => "false", :datacenter => "DC1", :score => 0 }
    "3.1.2.5" { :ipaddress => "3.1.2.5", :subnet => "255.255.252.0", :gateway => "3.1.1.1", :nameserver => "3.3.3.3", :allocated => "false", :datacenter => "DC1", :score => 0 }

Redis(1): User info is stored.  

    "admin" {:type => "admin", :password => "password"}
    "user"  {:type => "user", :password => "pass"}

Redis(2): contains various large sets  

    "datacenters" ["DC1", "DC2", ...]

Redis(3): Contains all datacenters as sets with subnets in the sets  

    "DC1" ["192.168.1.1", "10.0.0.1", ...]
    "DC2" ["136.168.1.1"]

Redis(4): Contains the subnets as sets with all ips in the subnet in the set  

    "192.168.1.1" ["192.168.1.1", ..., "192.168.1.254"]
    "10.0.0.1"    ["10.0.0.1", ..., "10.0.0.254"]

Redis(5): Contains subnets with allocated ips as sets  

    "10.0.0.1"    ["10.0.0.2", "10.0.0.34"]

Insertion and Removal of Data
============================
Adding a datacenter:  

    select 2
    sadd "datacenters" name_of_datacenter

Removing a datacenter:  

    select 3
    smembers name_of_datacenter
    if any members are listed:
        can't remove
    else:
        select 2
        srem "datacenters" name_of_datacenter

Adding a subnet:  

    select 3
    sadd name_of_datacenter name_of_subnet
    select 0
    add ips
    select 4
    sadd name_of_subnet [ips]

Removing a subnet:  

    select 5
    smembers name_of_subnet
    if any members are listed:
        can't remove
    else:
        select 4
        get ips with smembers name_of_subnet
        for each ip:  
            select 0  
            del ip  
            select 4  
            srem name_of_subnet ip  
        select 3
        srem name_of_datacenter name_of_subnet
      
Allocation of Ip:  

    select 0
    hset ip "allocated" "true"
    select 5
    sadd name_of_subnet ip

Unallocate Ip:  

    select 0
    hset ip "allocated" "false"
    select 5
    srem name_of_subnet ip

Move subnet to new datacenter:  

    select 4
    keys = smembers name_of_subnet
    select 0
    for ip in keys:  
        hset ip "datacenter" name_of_datacenter
    select 3
    smove old_datacenter new_datacenter name_of_subnet

Dynamic Hostnames
=================

There is a "counter" key in the redis datastore which starts at "0" and is incremented each time an IP address is reserved. This counter becomes interpolated in to the returned hostname, e.g. hostname0001.local.

Data Protection
===============
In the event of data corruption or data loss in the Redis database the impact is that new machine provisioning will break. Lost data can be re-constructed from DNS records, thus no explicit backups are performed. 

Scoring Algorithm
=================
A constraint of the current Redis data model is that IP addresses are allocated in a non-continuous fashion. e.g. 
A VM is provisioned with an IP address of 192.168.1.34 - it is subsequently deleted. 

The next VM to be provisioned would get an IP address of 192.168.1.35. This - combined with the DNS TTL creates a 
condition where EMC Networker's internal DNS cache will still have the old PTR record for the duration of the TTL. 

The scoring algorithm gives each IP address in Redis a starting score of zero. When an IP address is reserved the score is incremented by 1. When the IPAM service looks for the next available IP address it seeks an address with the lowest score. Thereby ensuring that the same IP address is not immediately re-allocated again.

Web Interface
=============
IPAM has a web interface on the /ipam url. There is also a dashboard on the /dashboard url (which is linked from the home page)

Web Interface Architecture
==========================
The Web interface is an ajax application that calls /status.json to obtain a list of all IP addresses in the backend datastore.
The IP addresses are then processed in javascript and rendered in to a table. The dashboard follows the same architecture except the IP addresses are calculated and totaled. The web interface uses bootstrap for layout. Each web page (or ERB view in sinatra) has a corrisponding javascript file.
ipam
