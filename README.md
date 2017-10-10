# zabipi

Zabbix API library for Crystal

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  zabipi:
    github: DRVTiny/monitoring_zabipi
```

## Usage

```crystal
require "json"
require "monitoring_zabipi"

zbx=Monitoring::Zabipi.new("http://example.com/zabbix/api_jsonrpc.php","your_frontend_login","your_frontend_password")

zans=zbx.do("trigger.get",{"triggerids"=>[21634,4708,9160],"expandDescription"=>1,"output"=>["description"]})

# Hint: in real world you MUST check zans.result before doing anything with
# it, and yes, you MUST handle exceptions (TODO: add exception handling
# example in README)
puts "description for the first found trigger: #{zans.result[0]["description"]}"
puts zans.result.map{ |t| [t["triggerid"], t["description"]] }.to_h.to_json
```

## Limitations

For now, it is in (very) early development stage.

* API usage without authentication is not supported /N.I.Y.

## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/DRVTiny/monitoring_zabipi/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [DRVTiny](https://github.com/DRVTiny) Andrey A. Konovalov - creator, maintainer
