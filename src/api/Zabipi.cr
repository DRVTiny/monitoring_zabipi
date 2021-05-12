require "json"
require "uri"
require "http/client"

module Monitoring
  DFLT_ZBX_API_RURL          = "/api_jsonrpc.php"
  JSRPC_ERR_CODE_PARSE_ERROR = -32700

  class HTTPException < Exception
    @status_type : String = "Illegal HTTP status code"
    @status_code : Int32 = 999
    @status_types = ["Informational", "Success", "Redirection", "Client-side error", "Server-side error"]

    def initialize(@status : HTTP::Status)
      ix = (@status.code * 0.01).to_i32 - 1
      raise "Illegal HTTP status code received" if ix > (@status_types.size - 1)
      @status_type = @status_types[ix]
    end

    def type
      @status_type
    end

    def code
      @status_code
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
      resp = @ua.post(@zapi_url.path.to_s, HTTP::Headers{"Content-Type" => "application/json"}, form: @raw_request)
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
      r : JSON::Any
      r = if @result.is_a?(JSON::Any)
            @result || JSON.parse("[]")
          else
            ZAPIRequest.new(@ua, @zapi_url, @raw_request).result
          end
      @result = r
    end
  end

  class Zabipi
    @version : String
    @sAuthToken : String?
    @oUserAgent : HTTP::Client
    @oAPIUrl : URI
    @sAPIRelUrl : String
    getter :oUserAgent, :sAuthToken, :oAPIUrl, :version
    property :debug

    def initialize(apiUrl : String, login : String, password : String, @debug = false)
      @oAPIUrl = URI.parse ( apiUrl =~ /\.[^\/.]+$/ ? apiUrl : ( apiUrl[-1] == '/' ? "" : "/" ) + "api_jsonrpc.php" )
      urlScheme = (@oAPIUrl.scheme || "http").downcase
      @oAPIUrl.scheme = urlScheme
      @oAPIUrl.host = "localhost" if @oAPIUrl.host.nil?
      @oAPIUrl.port = (@oAPIUrl.scheme == "https" ? 443 : 80) if @oAPIUrl.port.nil?
      @sAPIRelUrl = @oAPIUrl.path || DFLT_ZBX_API_RURL
      puts "zabipi init-d with: host=#{@oAPIUrl.host}, port=#{@oAPIUrl.port}, rurl=#{@sAPIRelUrl}" if @debug
      @oUserAgent = HTTP::Client.new(urlScheme + "://" + @oAPIUrl.host.to_s + ":" + @oAPIUrl.port.to_s)
      @version = ZAPIRequest
        .new(@oUserAgent, @oAPIUrl, Hash{"jsonrpc" => "2.0", "method" => "apiinfo.version", "id" => 1, "params" => [] of UInt8}.to_json)
        .result.as_s
      puts "zapiVersion=#{@version}" if @debug
      @sAuthToken = ZAPIRequest
        .new(@oUserAgent, @oAPIUrl, Hash{"jsonrpc" => "2.0", "method" => "user.login", "id" => 1, "params" => {"password" => password, "user" => login}}.to_json)
        .result.as_s
      puts "authToken=#{@sAuthToken}" if @debug
    end

    def do(method : String, pars : (Hash | Array) = [] of UInt8)
      return ZAPIAnswer.new(@oUserAgent, @oAPIUrl, Hash{
        "jsonrpc" => "2.0",
        "method"  => method,
        "id"      => 0,
        "params"  => pars,
        "auth"    => @sAuthToken,
      }.to_json)
    end
  end
end
