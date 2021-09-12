defmodule MinioServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :minio_server,
      version: "0.1.3",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Minio Server",
      source_url: "https://github.com/LostKobrakai/minio_server",
      description: "Elixir wrapper around a minio server instance",
      package: package(),
      aliases: [
        # Create the priv folder before compilation
        "compile.app": [
          fn _ -> File.mkdir_p!("priv") end,
          "compile.app"
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:muontrap, "~> 0.5.0"},
      {:jason, "~> 1.1"},
      {:ex_aws, "~> 2.0", optional: true},
      {:ex_aws_s3, "~> 2.2", only: [:dev, :test]},
      {:hackney, "~> 1.15", only: [:dev, :test]},
      {:sweet_xml, "~> 0.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      # These are the default files included in the package
      files:
        ~w(lib .formatter.exs mix.exs versions-client.json versions-server.json README* LICENSE*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/LostKobrakai/minio_server"}
    ]
  end
end
