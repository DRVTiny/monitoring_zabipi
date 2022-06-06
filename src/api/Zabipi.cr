require "json"
require "uri"
require "openssl"
require "http/client"
require "log"

module Monitoring
  DFLT_ZBX_API_RURL          = "/api_jsonrpc.php"
  JSRPC_ERR_CODE_PARSE_ERROR = -32700
  DBG = Log.for("Monitoring")
  class HTTPException < Exception
    STATUS_TYPES = ["Informational", "Success", "Redirection", "Client-side", "Server-side"]  
    
    property status_type : String = "Illegal HTTP status code"
    property status_code : Int32   

    def initialize(@status : HTTP::Status)
      @status_code = @status.code
      ix = (@status_code * 0.01).to_i32 - 1
      raise "Illegal HTTP status code received" if ix > (STATUS_TYPES.size - 1)
      @status_type = STATUS_TYPES[ix]
    end

    def type
      @status_type
    end

    def code
      @status_code
    end

    def to_s : String
       %Q[HTTP Error: status=#{@status}, code=#{@status_code} type="#{@status_type}"]
    end

    def to_s(io : IO)
      io << "HTTP Error: " << "status=#{@status}, " <<  "code=" << @status_code.to_s << ", type=" << @status_type
    end
  end
  
  class ZAPIException < Exception
    property code : Int32, data : String?
    ERR_CODE_UNKNOWN = -8

    def initialize(**jsrpc_error)
      raise "Received invalid JSRPC error object" unless (msg = jsrpc_error[:message]?) && (code = jsrpc_error[:code]?)
      raw = jsrpc_error[:raw]?
      @message = msg.to_s + (raw ? " POSTed to Zabbix API: << #{raw} >>" : "")
      @code = code.is_a?(Int32) ? code : ERR_CODE_UNKNOWN
      data = jsrpc_error[:data]?
      @data = !data.nil? && data.is_a?(String) ? data : data.try &.to_json
    end
  end

  class ConnException < Exception
    getter message

    def initialize(msg : String)
      @message = "Connection error: " + msg
    end
  end

  class JSRPC(T)
    include JSON::Serializable
    getter jsonrpc : String = "2.0"
    property id : UInt64 = 0
    property method : String
    property auth : String? = nil
    property params : T
    def initialize(@method, @params, id = 0_u64, auth = nil)
      @id = id
      @auth = auth
    end
  end
  
  class ZAPIRequest
    getter :result
    @result : JSON::Any
    
    def initialize(@ua : HTTP::Client, @zapi_url : URI, @raw_request : String)
      resp = @ua.post(@zapi_url.path.to_s, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: @raw_request)
      raise HTTPException.new(resp.status) unless resp.status == HTTP::Status::OK
      zbx_resp = JSON.parse(resp.body)
      if err = zbx_resp["error"]?
        raise ZAPIException.new(raw: @raw_request, message: zbx_resp["error"]["message"], code: zbx_resp["error"]["code"].as_i, data: zbx_resp["error"]["data"])
      elsif !zbx_resp["result"]?
        raise ZAPIException.new(message: "no result", code: JSRPC_ERR_CODE_PARSE_ERROR)
      end
      @result = zbx_resp["result"]
    end
  end

  class ZAPIAnswer
    @result : JSON::Any?
    
    def initialize(@ua : HTTP::Client, @zapi_url : URI, @raw_request : String)
    end

    def result
      if (r = @result).is_a?(JSON::Any)
        return r
      else
        @result = ZAPIRequest.new(@ua, @zapi_url, @raw_request).result
      end
    end
  end

  class Zabipi
    @http_client : HTTP::Client
    
    getter    auth_token : String?
    getter    api_url : URI, api_rel_url : String
    getter    version : String
    getter    cmd_id : UInt64 = 0
    
    property  maybe_zbx_server : String
    property  debug : Bool
    
    def initialize(zenv_file : String)
      conf = read_zenv(zenv_file)
      initialize(
        conf["ZBX_URL"],
        conf["ZBX_LOGIN"],
        conf["ZBX_PASS"],
        debug: if conf["DEBUG"]? 
          conf["DEBUG"] =~ /^(?i:[yt1])/ ? true : false
        else
          false
        end,
        zabbix_server: conf["ZBX_SERVER"]?
      )
    end
    
    def initialize(apiUrl : String, login : String, password : String, @debug = false, @verify_cert = true, @url_auto_adjust = true, @auth_now = true, zabbix_server = nil)
      @api_url = if @url_auto_adjust
                    URI.parse ( apiUrl =~ /\.[^\/.]+$/ ? apiUrl : ( apiUrl[-1] == '/' ? "" : "/" ) + "api_jsonrpc.php" )
                 else
                    URI.parse ( apiUrl )
                 end
      urlScheme = (@api_url.scheme || "http").downcase
      @api_url.scheme = urlScheme
      @api_url.host = "localhost" if @api_url.host.nil?
      @maybe_zbx_server = zabbix_server ? zabbix_server : @api_url.host.not_nil!
      @api_url.port = (@api_url.scheme == "https" ? 443 : 80) if @api_url.port.nil?
      
      @api_rel_url = @api_url.path.size > 0 ? @api_url.path : @url_auto_adjust ? (@api_url.path = DFLT_ZBX_API_RURL) : ""
      DBG.info { "zabipi init-d with: host=#{@api_url.host}, port=#{@api_url.port}, rurl=#{@api_rel_url}" } if @debug
      
      tls_ctx = OpenSSL::SSL::Context::Client.new
      tls_ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE unless @verify_cert
      @http_client = HTTP::Client.new( @api_url, tls: tls_ctx )
      @version =
        begin
          req("apiinfo.version").as_s
        rescue ex : HTTPException
          raise "When trying to call to Zabbix API (url=#{@api_url}): #{ex}"
        end
      DBG.info { "Zabbix API Version: #{@version}" } if @debug
      if @auth_now
        @auth_token = req("user.login", {"password" => password, "user" => login}).as_s
        DBG.info { "Zabbix API AuthToken: #{@auth_token}" } if @debug
      end
    end

    def do(method : String, pars : (Hash | Array | NamedTuple) = [] of UInt8)
      return ZAPIAnswer.new(
        @http_client,
        @api_url,
        JSRPC(typeof(pars)).new(
          method: method,
          params: pars,
          id:     (@cmd_id += 1),
          auth:   @auth_token
        ).to_json
      )
    end
    
    def req(method : String, pars : (Hash | Array | NamedTuple) = [] of UInt64)
      return ZAPIRequest.new(
        @http_client, 
        @api_url,
        JSRPC(typeof(pars)).new(
          method: method,
          params: pars,
          id:     (@cmd_id += 1),
          auth:   @auth_token
        ).to_json
      ).result
    end
    
    private def read_zenv(zenv_path : String) : Hash(String, String)
      rows = File.read_lines(zenv_path)
      rows.reject! { |line| line =~ /^\s*(?:#.*)?$/ }
      conf = rows.map do |line|
          if line.match(/^([^#=\s]+)\s*=\s*(?:(?<Q>["'`])((?:(?!\k<Q>|\\).|\\.)*)\k<Q>)(?:\s+(?:#.*)?)?$/)
            [$1, $3]
          elsif 	line.match(/^([^#=\s]+)\s*=\s*([^#\s"']+)(?:\s+(?:#.*)?)?/)
            [$1, $2]
          else
            raise "invalid-formatted config line: #{line}"
          end
      end.to_h
    end
  end
end
