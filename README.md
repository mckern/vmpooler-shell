## vmpooler.sh: a Bash [vmpooler](https://github.com/puppetlabs/vmpooler/) client

### WHY WOULD YOU DO THAT?!

* Minimal dependencies (a single binary, used for parsing JSON)
* Fun
* Profit

### How does it work?

You're going to need a configuration file, named `~/.vmpooler/config.json`. It'll need a couple of values:

```json
{
  "vmpooler_token": "<redacted token>",
  "vmpooler_url": "https://vmpooler.example.com"
}
```

Here's the basic commands:

```
mckern@flexo ~ $ vmpooler.sh -h
List Pooler Platforms:
  platforms

Pooler VM Management:
  checkout <platform tag>
  destroy <lease name>
  lifespan <lease name> <duration>
  status <lease name>
  leases

Pooler VM Connectivity:
  ssh <lease name>
  scp <file(s)> <lease name>:<path>

Pooler Auth Token Management:
  authorize <ldap username>
  deauthorize <token>
  tokens <ldap username>

Developmental metadata:
  todo
mckern@flexo ~ $
```

### License

`vmpooler.sh` is licensed under the terms of the Apache Public License 2.0
