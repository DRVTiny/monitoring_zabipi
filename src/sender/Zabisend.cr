macro unix_ts
  {% if compare_versions(Crystal::VERSION, "0.27.0") >= 0 %}
    Time.now.to_unix
  {% else %}
    Time.now.epoch
  {% end %}
end

module Monitoring
  DFLT_ZBXTRAP_TCP_PORT = 10051_u16
  ZABBIX_SENDER_SIGN    = "ZBXD"

  class Zabisend
    lib C
      # Zabbix sender protocol 2 / response header format
      struct ZbxSenderHdr
        z_sign : StaticArray(UInt8, 4) # Zabbix signature, 4 bytes ("ZBXD")
        z_stop_byte : UInt8            # Zabbix "end-of-signature" stop byte, normally z_stop_byte == 1
        z_payload_l : UInt8            # Zabbix response length: no more than 255 bytes :(
      end
    end

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
      sock = Socket.tcp(Socket::Family::INET)
      sock.connect @zabbix_server, @zabbix_trappers_port
      sock.write_utf8({
        "request" => "sender data",
        "data"    => data,
        "clock"   => ts_now,
      }.to_json.to_slice)
      zhdr = C::ZbxSenderHdr.new
      sock.read(Slice.new(Pointer(UInt8).new(pointerof(zhdr).address), sizeof(C::ZbxSenderHdr)))

      raise "Signature not found: Zabbix sender header is invalid" unless zhdr.z_sign.map { |c| c.unsafe_chr }.join == ZABBIX_SENDER_SIGN
      raise "Delimiter after signature is absent: Zabbix sender header is invalid" unless zhdr.z_stop_byte == 1
      raise "According to Zabbix sender header there is no payload, but it must be here" unless zhdr.z_payload_l > 0

      sock.skip(sizeof(C::ZbxSenderHdr) + 1)
      nb = sock.read(jans = Bytes.new(zhdr.z_payload_l))
      raise "Cant read JSON response: not enough data readed from the socket" unless nb == zhdr.z_payload_l
      ans = JSON.parse(String.new(jans))
      sock.close
      return ans
    end
  end # <- class Zabisend

end
