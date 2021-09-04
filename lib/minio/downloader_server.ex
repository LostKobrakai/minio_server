defmodule MinioServer.DownloaderServer do
  @moduledoc false
  alias MinioServer.Config
  require Logger

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
    url = url_for_release(arch, version)

    MinioServer.Downloader.handle_downloading(:server, arch, version, url, filename, checksum, opts)
  end

  defp url_for_release(arch, version) do
    "https://dl.min.io/server/minio/release/#{arch}/archive/minio.RELEASE.#{version}"
  end

  defp checksum!(arch, version) do
    Config.server_versions()
    |> Map.fetch!(version)
    |> Map.fetch!(arch)
  end
end
