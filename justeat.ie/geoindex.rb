require 'rubygems'
require 'mongo'
require 'json'

include Mongo


    @db = Connection.new('192.241.140.67').db('smartbands')
    @justeat = @db.collection('justeat.it')
    @stores = @justeat[:stores]
    @stores_with_location = @justeat[:stores_with_location]
    @geo = @justeat[:geoindex]


    @stores.find().each do |s|
      #puts s['store']['info']['lat'].to_s
      lat = s['store']['info']['lat'].to_s
      lng = s['store']['info']['lat'].to_s
      point = { :loc => { :type => "Point",
                          :coordinates => [lat,lng]
                         } }
      
      s1 = s
      s1['store']['info']['location'] = point
      
      
      
      @stores_with_location.insert s1
      
      
      #@geo.insert point
    end
    
    
    
    