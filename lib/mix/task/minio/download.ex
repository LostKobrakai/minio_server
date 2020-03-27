defmodule Mix.Tasks.MinioServer.Download do
  @moduledoc """
  Mix task for downloading minio binaries.

  ## Command line options

  * `-f`, `--force` - Replace any existing binary

  """
  @shortdoc "Downloader of minio binaries."
  use Mix.Task

  @switches [
    force: :boolean,
    arch: :string
  ]

  @aliases [
    f: :force
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    arches = MinioServer.Downloader.available_architectures()

    arch =
      case opts[:arch] do
        nil ->
          Mix.shell().info("Available architectures:")

          indexed_arches =
            for {arch, index} <- Enum.with_index(arches, 1),
                into: %{},
                do: {Integer.to_string(index), arch}

          Enum.map(indexed_arches, fn {index, arch} ->
            Mix.shell().info("#{index}: #{arch}")
          end)

          index =
            Mix.shell().prompt("Select architecture to download: ")
            |> String.trim()

          Map.get(indexed_arches, index)

        arch ->
          String.trim(arch)
      end

    if arch in arches do
      MinioServer.Downloader.download(arch, opts)
    else
      Mix.shell().error("Invalid selection")
    end
  end
end
