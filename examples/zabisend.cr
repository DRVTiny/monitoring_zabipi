require "json"
require "../src/sender/Zabisend"

zsend_data = [{key: "test.metric", value: "hello!"}]
puts "Sending data to Zabbix server: <<#{zsend_data.to_json}>>"
zsend = Monitoring::Zabisend.new( "localhost" )
puts "Zabbix sender answer:"
p zsend.req("test-zbx-snd", zsend_data)
