require "./zabipi/*"
require "json"
require "uri"
require "http/client"

module Monitoring
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
            
            def initialize (@ua : HTTP::Client, @api_url : URI, @raw_request : String)
            end
            
            def result
            	    r : JSON::Any
                    r=if @result.is_a?(JSON::Any)
                    	@result || JSON.parse("[]")
                      else
                      	self.req(1)
                      end
                    @result=r
            end
            
            protected def req
                    @ua.exec("POST", @api_url.path.to_s,
                            headers: HTTP::Headers{"Content-type"=>"application/json"},
                            body: @raw_request
                    ) do |resp|
                            raise HTTPException.new(resp.status_code) unless resp.status_code==200
                            if r=resp.body_io.gets
                                    zbxResp=JSON.parse(r)
                                    if err=zbxResp["error"]?
                                            raise ZAPIException.new(zbxResp["error"].as_s)
                                    elsif ! zbxResp["result"]?
                                            raise ZAPIException.new("no result")
                                    end
                                    return zbxResp["result"]
                            else			
                                    raise ConnException.new("Connection error: server not responded")
                            end
                    end
            end
            
            protected def req (some : Int32)
#            	    oAPIUrl=URI.parse @api_url
            	    HTTP::Client.new(@api_url) do |client|
                        client.exec("POST", @api_url.path.to_s,
                                headers: HTTP::Headers{"Content-type"=>"application/json"},
                                body: @raw_request
                        ) do |resp|
                                raise HTTPException.new(resp.status_code) unless resp.status_code==200
                                if r=resp.body_io.gets
                                        zbxResp=JSON.parse(r)
                                        if err=zbxResp["error"]?
                                                raise ZAPIException.new(zbxResp["error"].as_s)
                                        elsif ! zbxResp["result"]?
                                                raise ZAPIException.new("no result")
                                        end
                                        return zbxResp["result"]
                                else			
                                        raise ConnException.new("Connection error: server not responded")
                                end
                        end
                    end
            end            
    end

    class Zabipi
            @authToken : (String | Nil)
            @host : (String | Nil)
            @port : Int32
            @ua : HTTP::Client
            @oAPIUrl : URI
            def initialize (@apiUrl : String, login : String, password : String, @debug=false)
                    @oAPIUrl=URI.parse @apiUrl
                    @host=@oAPIUrl.host || raise "You must specify host part in URL string passed to ZabbixAPI constructor"
                    @port=@oAPIUrl.port || (@oAPIUrl.scheme.to_s.downcase=="https" ? 443 : 80)
                    @oAPIUrl.path=@oAPIUrl.path.to_s.size>0 ? @oAPIUrl.path.to_s : "/"
                    puts "host=#{@host}, port=#{@port}, rurl=#{@oAPIUrl.path}" if @debug
                    @ua=HTTP::Client.new(@oAPIUrl)
                    @ua.exec("POST",
                    	    	@oAPIUrl.path.to_s,
                            	headers: HTTP::Headers{"Content-type"=>"application/json"},
                            	body: Hash{"jsonrpc"=>"2.0","method"=>"user.login","id"=>1,"params"=>{"password"=>password,"user"=>login}}.to_json
                    ) do |resp|
                      raise HTTPException.new(resp.status_code) unless resp.status_code==200
                      @authToken=""
                      if r=resp.body_io.gets
                            @authToken=JSON.parse(r)["result"].as_s
                            puts "authToken=#{@authToken}" if @debug
                      end
                    end
            end
            
            def do (method : String, pars : (Hash | Array))
                    return ZAPIAnswer.new(@ua, @oAPIUrl, Hash{"jsonrpc"=>"2.0","method"=>method,"id"=>0,"params"=>pars,"auth"=>@authToken}.to_json)
            end
    end
end
