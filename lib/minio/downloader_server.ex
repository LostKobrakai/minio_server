defmodule MinioServer.DownloaderServer do
  @moduledoc """
  Downloader for `minio` server binaries
  """
  require Logger
  alias MinioServer.Config
  alias MinioServer.Versions

  @doc """
  Download the server binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.
  * `:version` - Specify the version to download. Defaults to most recent.

  """
  @spec download(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  def download(arch, opts \\ []) do
    version = Keyword.get(opts, :version, Config.most_recent_server_version())

    if arch not in Config.available_architectures() do
      raise "Invalid architecture, pick from #{inspect(Config.available_architectures())}"
    end

    if version not in Config.available_server_versions() do
      raise "Invalid version, pick from #{inspect(Config.available_server_versions())}"
    end

    filename = Config.executable_path(arch)
    checksum = checksum!(arch, version)
    url = Versions.download_setup(:server).release_url.(arch, version)

    MinioServer.Downloader.handle_downloading(
      :server,
      arch,
      version,
      url,
      filename,
      checksum,
      opts
    )
  end

  defp checksum!(arch, version) do
    Config.server_versions()
    |> Map.fetch!(version)
    |> Map.fetch!(arch)
  end
end
