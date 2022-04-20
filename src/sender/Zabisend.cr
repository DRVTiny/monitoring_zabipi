require "socket"
require "json"

macro unix_ts
  {% if compare_versions(Crystal::VERSION, "0.27.0") >= 0 %}
    {% if compare_versions(Crystal::VERSION, "0.30.0") < 0 %}
      Time.now.to_unix
    {% else %}
      Time.local.to_unix
    {% end %}
  {% else %}
    Time.now.epoch
  {% end %}
end

module Monitoring
  DFLT_ZBXTRAP_TCP_PORT = 10051_u16
  ZBX_HEADER_SIGN   	= "ZBXD"
  ZBX_HEADER_VERSION	= 1_u8

  class Zabisend
    def initialize(@zabbix_server : String, @zabbix_trappers_port : UInt16 = DFLT_ZBXTRAP_TCP_PORT)
    end

    def req(hostname : String, whatever)
      data = [] of Hash(String, Int32 | Int64 | String)
      ts_now = unix_ts
      whatever.each do |e|
        h = Hash(String, Int32 | Int64 | String).new
        if e.is_a?(NamedTuple) || e.is_a?(Hash)
          e.keys.each { |k| h[k.to_s] = e[k] }
          h["clock"] ||= ts_now
        elsif e.is_a?(Array)
          h["key"] = e[0]
          h["value"] = e[1]
          h["clock"] = e[2]? || ts_now
        else
          raise "You must pass: Array of (NamedTuple, Hash or Array)"
        end
        h["host"] ||= hostname
        h["clock"] ||= ts_now
        data << h
      end # <- iter on payload datastructure
      slc_json_req = {
        "request" => "sender data",
        "data"    => data,
        "clock"   => ts_now,
      }.to_json.to_slice
      
      sock = Socket.tcp(Socket::Family::INET)
      sock.connect @zabbix_server, @zabbix_trappers_port
      sock.write(ZBX_HEADER_SIGN.to_slice)
      sock.write_byte(ZBX_HEADER_VERSION)

      sock.write_bytes(slc_json_req.size.to_u64, IO::ByteFormat::LittleEndian)
      sock.write_string(slc_json_req)
      
      sock.read(z_hdr_sign = Slice(UInt8).new(ZBX_HEADER_SIGN.size))
      raise "Unknown signature received from Zabbix server" unless z_hdr_sign == ZBX_HEADER_SIGN.to_slice
      z_hdr_version = sock.read_byte
      raise "Dont know how to work with zabbix header version #{z_hdr_version}" unless z_hdr_version == ZBX_HEADER_VERSION
      payload_l = sock.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
      raise "According to Zabbix sender header there is no payload, but it must be here" unless payload_l > 0
      nb = sock.read(jans = Slice(UInt8).new(payload_l))
      raise "Cant read JSON response: want to read #{payload_l} bytes, but #{nb} bytes received" unless nb == payload_l
      ans = JSON.parse(String.new(jans))
      sock.close
      return ans
    end
  end # <- class Zabisend
end
