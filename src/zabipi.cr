require "./zabipi/*"
require "json"
require "uri"
require "cossack"

module MonitoringC
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

    class ZAPIAnswer
            @result : (JSON::Any | Nil)
            
            def initialize (@ua : Cossack::Client, @api_url : URI, @raw_request : String)
            end
            
            def result
            	    r : JSON::Any
                    r=if @result.is_a?(JSON::Any)
                    	@result || JSON.parse("[]")
                      else
                      	self.req
                      end
                    @result=r
            end
            
            protected def req
                    resp=@ua.post(@api_url.path.to_s, @raw_request) do |req|
                    	req.headers["Content-type"]="application/json"
                    end
                    raise HTTPException.new(resp.status) unless resp.status==200
                    zbxResp=JSON.parse(resp.body)
                    if err=zbxResp["error"]?
                            raise ZAPIException.new(zbxResp["error"].as_s)
                    elsif ! zbxResp["result"]?
                            raise ZAPIException.new("no result")
                    end
                    return zbxResp["result"]
            end
    end

    class Zabipi
    	    DFLT_ZBX_API_RURL="/api_jsonrpc.php"
            @sAuthToken : (String | Nil)
            @oUserAgent : Cossack::Client
            @oAPIUrl : URI
            @sAPIRelUrl : String
            getter :oUserAgent, :sAuthToken, :oAPIUrl
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
                resp=@oUserAgent.post(
                    @sAPIRelUrl,
                    Hash{"jsonrpc"=>"2.0","method"=>"user.login","id"=>1,"params"=>{"password"=>password,"user"=>login}}.to_json
                ) do |req|
                    req.headers["Content-type"]="application/json"
                end
                raise HTTPException.new(resp.status) unless resp.status==200
                @sAuthToken=JSON.parse(resp.body)["result"].as_s
                puts "authToken=#{@sAuthToken}" if @debug
            end
            
            def do (method : String, pars : (Hash | Array))
                    return ZAPIAnswer.new(@oUserAgent, @oAPIUrl, Hash{"jsonrpc"=>"2.0","method"=>method,"id"=>0,"params"=>pars,"auth"=>@sAuthToken}.to_json)
            end
    end
end
