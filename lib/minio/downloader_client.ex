defmodule MinioServer.DownloaderClient do
  @moduledoc false
  require Logger
  alias MinioServer.Config

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

    filename = Config.executable_path(arch) |> Path.dirname() |> Path.join("mc")
    checksum = checksum!(arch, version)
    url = url_for_release(arch, version)

    MinioServer.Downloader.handle_downloading(:client, arch, version, url, filename, checksum, opts)
  end

  defp url_for_release(arch, version) do
    "https://dl.min.io/client/mc/release/#{arch}/archive/mc.RELEASE.#{version}"
  end

  defp checksum!(arch, version) do
    Config.client_versions()
    |> Map.fetch!(version)
    |> Map.fetch!(arch)
  end
end
