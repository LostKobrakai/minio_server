# Minio Server

Elixir wrapper around [Minio](https://min.io/). It starts the minio server alongside
your elixir application.

```elixir
# Config can be used directly with :ex_aws/:ex_aws_s3
s3_config = [
  access_key_id: "minio_key",
  secret_access_key: "minio_secret",
  scheme: "http://",
  region: "local",
  host: "127.0.0.1",
  port: 9000,
  # Minio specific
  minio_path: "data" # Defaults to ./minio in your mix project
]

# In a supervisor
children = [
  {MinioServer, s3_config}
]

# or manually
{:ok, _} = MinioServer.start_link(s3_config)
```

## Minio binary

The minio binary is not included in the package to save on space. But you can
easily download them using a mix task:

```sh
# with menu to select arch / version
mix minio_server.download

# download the latest SERVER binary matching the current machine
mix minio_server.download --arch auto --version latest

# download the latest SERVER binary for darwin-amd64
mix minio_server.download --arch darwin-amd64 --version latest

# download the latest CLIENT binary for darwin-amd64
mix minio_server.download --client --arch darwin-amd64 --version latest
```

## Minio Versions (dev)

To simplify updating available versions for client / server binaries, there are following commands available:

```elixir
MinioServer.Versions.create_versions_file(:client)
MinioServer.Versions.create_versions_file(:server)
```

## Livecycle Configuration

Minio does support lifecycle configuration, which I'm using to expire abandoned
uploads / multipart chunks. 

### Example

Setup of a new bucket with `temp/` folder.

```elixir
config = s3()

{:ok, _} =
  ExAws.S3.put_bucket("default", Keyword.fetch!(config, :region))
  |> ExAws.request(config)

livecycle_rules = [
  %{
    id: "temp-folder-cleanup",
    enabled: true,
    filter: %{
      prefix: "temp/"
    },
    actions: %{
      expiration: %{
        trigger: {:days, 1},
        expired_object_delete_marker: true
      },
      abort_incomplete_multipart_upload: %{
        trigger: {:days, 1}
      }
    }
  }
]

{:ok, _} =
  ExAws.S3.put_bucket_lifecycle("default", livecycle_rules)
  |> ExAws.request(config)
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `minio_server` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:minio_server, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/minio_server](https://hexdocs.pm/minio_server).
