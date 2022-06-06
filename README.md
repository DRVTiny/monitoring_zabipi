# zabipi

Zabbix API wrapper libarary for Crystal

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  zabipi:
    github: DRVTiny/monitoring_zabipi
```

## Usage

(Look at examples/read_config_call_api_send_item.cr for more practically
meaningful example including Monitoring::Zabisend usage for sendind data 
to zabbix trap)

```crystal
require "json"
require "zabipi"

zbx = Monitoring::Zabipi.new("http://example.com/zabbix/api_jsonrpc.php","your_frontend_login","your_frontend_password")
# or:
# zbx = Monitoring::Zabipi.new( PATH_TO_ZENV_CONFIG_FILE )
# Where ZENV_CONFIG may contain something like this:
#   ZBX_URL='https://zabbix.mycorp.com'
#   ZBX_LOGIN='zapi-user'
#   ZBX_PASS='zapi-password'
#   DEBUG=true

result = zbx.req("trigger.get", {"triggerids" => [21634,4708,9160], "expandDescription" => 1, "output" => ["description"]}).as_a

# Hint: in real world you MUST check zans.result before doing anything with
# it, and yes, you MUST handle exceptions (TODO: add exception handling
# example in README)
puts "description for the first found trigger: #{result[0]["description"]}"
puts result.map{ |t| [t["triggerid"], t["description"]] }.to_h.to_json
```

## Limitations

Tell me, if you find them.

## Contributing

1. Fork it ( https://github.com/DRVTiny/monitoring_zabipi/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [DRVTiny](https://github.com/DRVTiny) Andrey A. Konovalov - creator, maintainer
