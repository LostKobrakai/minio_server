defmodule Mix.Tasks.MinioServer.Download do
  require Logger

  @moduledoc """
  Mix task for downloading minio binaries.

  ## Command line options

  * `-f`, `--force` - Replace any existing binary
  * `--version <version>` - Preselect a version
  * `--arch <architecture>` - Preselect an architecture

  """
  @shortdoc "Downloader of minio binaries."
  use Mix.Task

  @switches [
    force: :boolean,
    arch: :string,
    version: :string,
    client: :boolean,
    timeout: :integer
  ]

  @aliases [
    f: :force
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    if Keyword.get(opts, :client) do
      download_client(opts)
    else
      download_server(opts)
    end
  end

  def download_server(opts) do
    arch = input_arch(opts)
    server_version = input_server_version(opts)
    Logger.info("SERVER: #{server_version}")
    MinioServer.DownloaderServer.download(arch, Keyword.put(opts, :version, server_version))
  end

  def download_client(opts) do
    arch = input_arch(opts)
    client_version = input_client_version(opts)
    Logger.info("CLIENT: #{client_version}")
    MinioServer.DownloaderClient.download(arch, Keyword.put(opts, :version, client_version))
  end

  def input_server_version(opts) do
    versions = MinioServer.Config.available_server_versions()

    version =
      case opts[:version] do
        nil ->
          Mix.shell().info("Available server versions:")

          indexed_versions =
            for {version, index} <- Enum.with_index(versions, 1),
                into: %{},
                do: {index, version}

          indexed_versions
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(fn {index, version} ->
            Mix.shell().info("#{index}: #{version}")
          end)

          index =
            Mix.shell().prompt("Select versions to download: ")
            |> String.trim()
            |> Integer.parse()
            |> case do
              {int, _} -> int
              :error -> 0
            end

          Map.get(indexed_versions, index)

        "latest" ->
          MinioServer.Config.most_recent_server_version()

        version ->
          String.trim(version)
      end

    unless version in versions do
      Mix.shell().error("Invalid server version: #{version}")
      exit(:shutdown)
    end

    version
  end

  def input_client_version(opts) do
    versions = MinioServer.Config.available_client_versions()

    version =
      case opts[:version] do
        nil ->
          Mix.shell().info("Available client versions:")

          indexed_versions =
            for {version, index} <- Enum.with_index(versions, 1),
                into: %{},
                do: {index, version}

          indexed_versions
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(fn {index, version} ->
            Mix.shell().info("#{index}: #{version}")
          end)

          index =
            Mix.shell().prompt("Select versions to download: ")
            |> String.trim()
            |> Integer.parse()
            |> case do
              {int, _} -> int
              :error -> 0
            end

          Map.get(indexed_versions, index)

        "latest" ->
          MinioServer.Config.most_recent_client_version()

        version ->
          String.trim(version)
      end

    unless version in versions do
      Mix.shell().error("Invalid client version: #{version}")
      exit(:shutdown)
    end

    version
  end

  def input_arch(opts) do
    arches = MinioServer.Config.available_architectures()

    arch =
      case opts[:arch] do
        nil ->
          Mix.shell().info("Available architectures:")

          indexed_arches =
            for {arch, index} <- Enum.with_index(arches, 1),
                into: %{},
                do: {index, arch}

          indexed_arches
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(fn {index, arch} ->
            Mix.shell().info("#{index}: #{arch}")
          end)

          index =
            Mix.shell().prompt("Select architecture to download: ")
            |> String.trim()
            |> Integer.parse()
            |> case do
              {int, _} -> int
              :error -> 0
            end

          Map.get(indexed_arches, index)

        arch ->
          String.trim(arch)
      end

    unless arch in arches do
      Mix.shell().error("Invalid arch: #{arch}")
      exit(:shutdown)
    end

    arch
  end
end
