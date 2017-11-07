require "json"
require "../src/*"
conf : Hash(String, String)
begin
        raise "Hey! You must specify file name as a first parameter" if ARGV.size==0
        rows=File.read_lines(ARGV[0])
        rows.reject! { |line| line =~ /^\s*(?:#.*)?$/ }
        conf=rows.map{ |line|
                if
                 line.match(/^([^#=\s]+)\s*=\s*(?:(?<Q>["'`])((?:(?!\k<Q>|\\).|\\.)*)\k<Q>)(?:\s+(?:#.*)?)?$/)
                        [$1,$3]
                elsif line.match(/^([^#=\s]+)\s*=\s*([^#\s"']+)(?:\s+(?:#.*)?)?/)
                        [$1,$2]
                else
                        raise "invalid-formatted config line: #{line}"
                end
        }.to_h

        p conf

	zapi=Monitoring::Zabipi.new(conf["ZBX_URL"], conf["ZBX_LOGIN"], conf["ZBX_PASS"]);
	printf(%[Zabbix API version implemented by %s is %s\n], conf["ZBX_URL"], zapi.version)

	zans=zapi.do("trigger.get",{"triggerids"=>[110502],"expandDescription"=>1,"output"=>["description"]})
	
	# Output some field of the object with the desired index in result set
	# ( .result is an Array of JSON::Any)
	printf(%[Description for the first found trigger: <<%s>>\n], zans.result[0]["description"])

	# Output result in JSON form
	puts "Reformated result in JSON presentation:\n"+zans.result.map{ |t| [t["triggerid"], t["description"]] }.to_h.to_json
	zsend_data=[{key: "test.metric", value: "hello!"}]
	puts "Sending data to Zabbix server: <<#{zsend_data.to_json}>>"
	zsend=Monitoring::Zabisend.new(conf["ZBX_SERVER"])
	print "Zabbix sender answer:\n"
	p zsend.req("test-zbx-snd",zsend_data)
	
	at_exit {
		zapi.do("user.logout", [] of Int32)
	}

rescue ex
        puts ex.message
        exit(1)
end
