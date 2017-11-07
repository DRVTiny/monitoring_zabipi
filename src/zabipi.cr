require "./zabipi/*"
require "json"
require "uri"
require "cossack"

module Monitoring
	DFLT_ZBXTRAP_TCP_PORT=10051_u16
	ZABBIX_SENDER_SIGN="ZBXD"
    DFLT_ZBX_API_RURL="/api_jsonrpc.php"
    
    class HTTPException < Exception
            @status_type : String = "Illegal HTTP status code"
            @status_code : Int32 = 999
            @status_types=["Informational","Success","Redirection","Client-side error","Server-side error"]
            def initialize(@status_code)
                begin
                        @status_type = @status_types[@status_code/100-1]
                rescue
                        raise "Illegal HTTP status code received"
                end
            end
            
            def type ()
                    @status_type
            end
            
            def code ()
                    @status_code
            end
    end

    class ZAPIException < Exception
    end

    class ConnException < Exception
            getter message
            def initialize (msg : String)
                    @message="Connection error: "+msg
            end
    end
    
	class ZAPIRequest
		getter :result
		@result : JSON::Any
		def initialize(@ua : Cossack::Client, @zapi_url : URI, @raw_request : String)
            resp=@ua.post(@zapi_url.path.to_s, @raw_request) do |req|
                req.headers["Content-type"]="application/json"
            end
            raise HTTPException.new(resp.status) unless resp.status==200
            zbxResp=JSON.parse(resp.body)
            if err=zbxResp["error"]?
                    raise ZAPIException.new(zbxResp["error"].as_s)
            elsif ! zbxResp["result"]?
                    raise ZAPIException.new("no result")
            end
            @result=zbxResp["result"]
		end
	end
	
    class ZAPIAnswer
            @result : (JSON::Any | Nil)
            
            def initialize (@ua : Cossack::Client, @zapi_url : URI, @raw_request : String)
            end
            
            def result
            	    r : JSON::Any
                    r=if @result.is_a?(JSON::Any)
                    	@result || JSON.parse("[]")
                      else
                      	ZAPIRequest.new(@ua, @zapi_url, @raw_request).result
                      end
                    @result=r
            end
    end

    class Zabipi
    	    @version : String
            @sAuthToken : (String | Nil)
            @oUserAgent : Cossack::Client
            @oAPIUrl : URI
            @sAPIRelUrl : String
            getter :oUserAgent, :sAuthToken, :oAPIUrl, :version
            property :debug
            def initialize (apiUrl : String, login : String, password : String, @debug=false)
                @oAPIUrl=URI.parse apiUrl
                @oAPIUrl.scheme="http" if @oAPIUrl.scheme.nil?
                @oAPIUrl.scheme=@oAPIUrl.scheme.to_s.downcase
                @oAPIUrl.host="localhost" if @oAPIUrl.host.nil?
                @oAPIUrl.port=(@oAPIUrl.scheme.to_s.downcase=="https" ? 443 : 80) if @oAPIUrl.port.nil?
                @oAPIUrl.path=DFLT_ZBX_API_RURL if @oAPIUrl.path.nil?
                @sAPIRelUrl=@oAPIUrl.path.to_s
                puts "host=#{@oAPIUrl.host}, port=#{@oAPIUrl.port}, rurl=#{@sAPIRelUrl}" if @debug
                @oUserAgent=Cossack::Client.new(@oAPIUrl.scheme.to_s+"://"+@oAPIUrl.host.to_s+":"+@oAPIUrl.port.to_s)
                @version=ZAPIRequest
                	.new(@oUserAgent, @oAPIUrl, Hash{"jsonrpc"=>"2.0","method"=>"apiinfo.version","id"=>1,"params"=>[] of UInt8}.to_json)
                	.result.as_s
                puts "zapiVersion=#{@version}" if @debug
                @sAuthToken=ZAPIRequest
                	.new(@oUserAgent, @oAPIUrl, Hash{"jsonrpc"=>"2.0","method"=>"user.login","id"=>1,"params"=>{"password"=>password,"user"=>login}}.to_json)
                	.result.as_s
                puts "authToken=#{@sAuthToken}" if @debug
            end
            
            def do (method : String, pars : (Hash | Array))
                    return ZAPIAnswer.new(@oUserAgent, @oAPIUrl, Hash{"jsonrpc"=>"2.0","method"=>method,"id"=>0,"params"=>pars,"auth"=>@sAuthToken}.to_json)
            end
    end
    
	class Zabisend
		lib C
            struct ZbxSenderHdr
                z_sign : StaticArray(UInt8, 4)
                z_stop_byte : UInt8
                z_payload_l : UInt8
            end
		end

		def initialize(@zabbix_server : String, @zabbix_trappers_port : UInt16=DFLT_ZBXTRAP_TCP_PORT)
		end
		def req(hostname : String, whatever)
			data=[] of Hash(String, Int32 | Int64 | String)
			tsNow=Time.now.epoch
			whatever.each do |e|
				h=Hash(String, Int32 | Int64 | String).new
				if e.is_a?(NamedTuple) || e.is_a?(Hash)
					e.keys.each { |k| h[k.to_s] = e[k] }
					h["clock"] ||= tsNow
				elsif e.is_a?(Array)
					h["key"]=e[0]
					h["value"]=e[1]
					h["clock"] = e[2]? || tsNow
				else
					raise "You must pass: Array of (NamedTuple, Hash or Array)"
				end
				h["host"] ||= hostname
				h["clock"] ||= tsNow
				data << h
			end
			sock = Socket.tcp(Socket::Family::INET)
			sock.connect @zabbix_server, @zabbix_trappers_port
			sock.write_utf8({"request"=>"sender data","data"=>data}.to_json.to_slice)
			zhdr=C::ZbxSenderHdr.new
			sock.read(Slice.new(Pointer(UInt8).new(pointerof(zhdr).address), sizeof(C::ZbxSenderHdr)))
			raise "Signature not found: Zabbix sender header is invalid" unless zhdr.z_sign.map {|c| c.unsafe_chr}.join == ZABBIX_SENDER_SIGN
			raise "Delimiter after signature is absent: Zabbix sender header is invalid" unless zhdr.z_stop_byte==1
			raise "According to Zabbix sender header there is no payload, but it must be here" unless zhdr.z_payload_l>0			
			sock.skip(sizeof(C::ZbxSenderHdr)+1)
			nb=sock.read(jans=Bytes.new(zhdr.z_payload_l))
			raise "Cant read JSON response: not enough data readed from the socket" unless nb==zhdr.z_payload_l
			ans=JSON.parse(String.new(jans))
			sock.close
			return ans
		end
	end
end
