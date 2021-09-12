defmodule MinioServer.DownloaderClient do
  @moduledoc """
  Downloader for `mc` clients
  """
  require Logger
  alias MinioServer.Config
  alias MinioServer.Versions

  @doc """
  Download the client binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.

  """
  @spec download(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  def download(arch, opts \\ []) do
    if arch not in Config.available_architectures() do
      raise "Invalid architecture, pick from #{inspect(Config.available_architectures())}"
    end

    version = Keyword.get(opts, :version, Config.most_recent_client_version())

    if version not in Config.available_client_versions() do
      raise "Invalid version, pick from #{inspect(Config.available_client_versions())}"
    end

    filename = Config.executable_path(arch, "mc")
    checksum = checksum!(arch, version)
    url = Versions.download_setup(:client).release_url.(arch, version)

    MinioServer.Downloader.handle_downloading(
      :client,
      arch,
      version,
      url,
      filename,
      checksum,
      opts
    )
  end

  defp checksum!(arch, version) do
    Config.client_versions()
    |> Map.fetch!(version)
    |> Map.fetch!(arch)
  end
end
