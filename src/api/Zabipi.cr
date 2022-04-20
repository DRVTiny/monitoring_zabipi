require "json"
require "uri"
require "openssl"
require "http/client"


module Monitoring
  DFLT_ZBX_API_RURL          = "/api_jsonrpc.php"
  JSRPC_ERR_CODE_PARSE_ERROR = -32700

  class HTTPException < Exception
    @status_type : String = "Illegal HTTP status code"
    @status_code : Int32
    @status_types = ["Informational", "Success", "Redirection", "Client-side error", "Server-side error"]

    def initialize(@status : HTTP::Status)
      @status_code = @status.code
      ix = (@status_code * 0.01).to_i32 - 1
      raise "Illegal HTTP status code received" if ix > (@status_types.size - 1)
      @status_type = @status_types[ix]
    end

    def type
      @status_type
    end

    def code
      @status_code
    end

    def to_s : String
      "HTTP Code: #{@status_code}, Type of HTTP error: #{@status_type}"
    end

    def to_s(io : IO)
      io << "HTTP Code: " <<  @status_code.to_s << ", Type of HTTP error: " << @status_type
    end
  end

  class ZAPIException < Exception
    property code : Int32, data : String?
    ERR_CODE_UNKNOWN = -8

    def initialize(**jsrpc_error)
      raise "Received invalid JSRPC error object" unless (msg = jsrpc_error[:message]?) && (code = jsrpc_error[:code]?)
      @message = msg.to_s
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

  class ZAPIRequest
    getter :result
    @result : JSON::Any
    
    def initialize(@ua : HTTP::Client, @zapi_url : URI, @raw_request : String)
      pp @zapi_url
      puts "#{@zapi_url.path.to_s}"
      resp = @ua.post(@zapi_url.path.to_s, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: @raw_request)
      pp resp
      raise HTTPException.new(resp.status) unless resp.status == HTTP::Status::OK
      zbxResp = JSON.parse(resp.body)
      if err = zbxResp["error"]?
        raise ZAPIException.new(message: zbxResp["error"]["message"], code: zbxResp["error"]["code"].as_i, data: zbxResp["error"]["data"])
      elsif !zbxResp["result"]?
        raise ZAPIException.new(message: "no result", code: JSRPC_ERR_CODE_PARSE_ERROR)
      end
      @result = zbxResp["result"]
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
    
    getter auth_token : String?, api_url : URI, api_rel_url : String, version : String
    property maybe_zbx_server : String
    property debug : Bool
    
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
    
    def initialize(apiUrl : String, login : String, password : String, @debug = false, zabbix_server = nil)
      @api_url = URI.parse ( apiUrl =~ /\.[^\/.]+$/ ? apiUrl : ( apiUrl[-1] == '/' ? "" : "/" ) + "api_jsonrpc.php" )
      urlScheme = (@api_url.scheme || "http").downcase
      @api_url.scheme = urlScheme
      @api_url.host = "localhost" if @api_url.host.nil?
      @maybe_zbx_server = zabbix_server ? zabbix_server : @api_url.host.not_nil!
      @api_url.port = (@api_url.scheme == "https" ? 443 : 80) if @api_url.port.nil?
      @api_rel_url = @api_url.path.size > 0 ? @api_url.path : (@api_url.path = DFLT_ZBX_API_RURL)
      puts "zabipi init-d with: host=#{@api_url.host}, port=#{@api_url.port}, rurl=#{@api_rel_url}" if @debug
      
      tls_ctx = OpenSSL::SSL::Context::Client.new
      tls_ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      @http_client = HTTP::Client.new( @api_url, tls: tls_ctx )
      puts "HERE!"
      
      @version = ZAPIRequest
        .new(@http_client, @api_url, Hash{"jsonrpc" => "2.0", "method" => "apiinfo.version", "id" => 1, "params" => [] of UInt8}.to_json)
        .result.as_s
      
      puts "zapiVersion=#{@version}" if @debug
      @auth_token = ZAPIRequest
        .new(@http_client, @api_url, Hash{"jsonrpc" => "2.0", "method" => "user.login", "id" => 1, "params" => {"password" => password, "user" => login}}.to_json)
        .result.as_s
      puts "authToken=#{@auth_token}" if @debug
    end

    def do(method : String, pars : (Hash | Array) = [] of UInt8)
      return ZAPIAnswer.new(@http_client, @api_url, Hash{
        "jsonrpc" => "2.0",
        "method"  => method,
        "id"      => 0,
        "params"  => pars,
        "auth"    => @auth_token,
      }.to_json)
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
