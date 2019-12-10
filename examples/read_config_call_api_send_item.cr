require "json"
require "../src/**"
conf : Hash(String, String)
begin
    raise "Hey! You must specify [file name] as a first parameter and [triggerids_list_separated_by_commas] as a second one" unless ARGV.size == 2
    triggerids = (ARGV[1]? || "").split(/\s*,\s*/).map {|trg| trg.to_u32 }
    rows = File.read_lines(ARGV[0])
    rows.reject! { |line| line =~ /^\s*(?:#.*)?$/ }
    conf = rows.map{ |line|
        if 		line.match(/^([^#=\s]+)\s*=\s*(?:(?<Q>["'`])((?:(?!\k<Q>|\\).|\\.)*)\k<Q>)(?:\s+(?:#.*)?)?$/)
	        [$1, $3]
        elsif 	line.match(/^([^#=\s]+)\s*=\s*([^#\s"']+)(?:\s+(?:#.*)?)?/)
    		[$1, $2]
        else
 	       	raise "invalid-formatted config line: #{line}"
        end
    }.to_h

    zapi = Monitoring::Zabipi.new(conf["ZBX_URL"], conf["ZBX_LOGIN"], conf["ZBX_PASS"]);
    printf( %[Zabbix API version implemented by %s is %s\n], conf["ZBX_URL"], zapi.version )

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

    begin
    	zans_inv_req = zapi.do("host.create",{"triggerids"=>[110502],"expandDescription"=>1,"output"=>["description"]})
    	p zans_inv_req.result
    rescue zex : Monitoring::ZAPIException
    	puts "Zabbix API exception test: code: #{zex.code} message: #{zex.message}"
    end
    
    zsend_data = [{key: "test.metric", value: "hello!"}]
    puts "Sending data to Zabbix server: <<#{zsend_data.to_json}>>"
    zsend = Monitoring::Zabisend.new( conf["ZBX_SERVER"] )
    puts "Zabbix sender answer:"
    p zsend.req("test-zbx-snd", zsend_data)

    at_exit {
        zapi.do("user.logout")
    }

rescue ex
    puts ex.message
    exit(1)
end
