defmodule Mix.Tasks.MinioServer.Download do
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
    version: :string
  ]

  @aliases [
    f: :force
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    versions = MinioServer.Downloader.available_versions()
    arches = MinioServer.Downloader.available_architectures()

    version =
      case opts[:version] do
        nil ->
          Mix.shell().info("Available versions:")

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
          MinioServer.Downloader.most_recent_version()

        version ->
          String.trim(version)
      end

    unless version in versions do
      Mix.shell().error("Invalid selection")
      exit(:shutdown)
    end

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
      Mix.shell().error("Invalid selection")
      exit(:shutdown)
    end

    MinioServer.Downloader.download(arch, Keyword.put(opts, :version, version))
  end
end
