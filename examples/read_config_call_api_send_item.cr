require "json"
require "../src/**"

begin
    raise "Hey! You must specify [file name] as a first parameter and [triggerids_list_separated_by_commas] as a second one" unless ARGV.size == 2
    triggerids = (ARGV[1]? || "").split(/\s*,\s*/).map {|trg| trg.to_u32 }

    zapi = Monitoring::Zabipi.new( ARGV[0] )
    
    printf( %[Zabbix API version implemented by %s is %s\n], zapi.api_url, zapi.version )

    zans = zapi.do("trigger.get", {"triggerids" => triggerids, "expandDescription" => 1, "output" => ["description"]})
		if (result = zans.result).size > 0
      # Output some field of the object with the desired index in result set
      # ( .result is an Array of JSON::Any)
      printf(%[Description for the first found trigger: <<%s>>\n], zans.result[0]["description"])

      # Output result in JSON form
      puts "Reformated result in JSON presentation:\n" + zans.result.as_a.map { |t| {t["triggerid"].as_s, t["description"]} } .to_h.to_json
    else
    	puts "It's a pitty, but no triggers with such triggerids found"
    end
    
    # Invalid API request
    begin
    	zapi.req("host.create",{"triggerids"=>[110502],"expandDescription"=>1,"output"=>["description"]})
    rescue zex : Monitoring::ZAPIException
    	puts "Zabbix API exception test: code: #{zex.code} message: #{zex.message}"
    end
    
    zsend_data = [{key: "test.metric", value: "hello!"}]
    puts "Sending data to Zabbix server: <<#{zsend_data.to_json}>>"
    zsend = Monitoring::Zabisend.new( zapi.maybe_zbx_server )
    puts "Zabbix sender answer:"
    p zsend.req("test-zbx-snd", zsend_data)

    at_exit {
        zapi.req("user.logout")
    }
rescue ex
    puts ex.message
    exit 1
end
