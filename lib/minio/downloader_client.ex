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

    handle_downloading(arch, version, filename, checksum, opts)
  end

  defp check_filename_status(filename, force) do
    cond do
      File.exists?(filename) and not force -> :exists
      File.exists?(filename) and force -> :replace
      true -> :download
    end
  end

  defp handle_downloading(arch, version, filename, checksum, opts) do
    force = Keyword.get(opts, :force, false)
    timeout = Keyword.get(opts, :timeout, :timer.seconds(300))

    case check_filename_status(filename, force) do
      :exists ->
        Logger.info("Download of minio client binary for #{arch} skipped: already exists.")
        :exists

      task ->
        case task do
          :replace ->
            File.rm(filename)

            Logger.info(
              "Download of minio client binary for #{arch} (version #{version}): Replacing existing."
            )

          :download ->
            Logger.info("Download of minio client binary for #{arch} (version #{version}).")
        end

        url = url_for_release(arch, version)
        File.mkdir_p(Path.dirname(filename))

        download(url, filename, checksum, timeout)
    end
  end

  defp download(url, filename, checksum, timeout) do
    # No SSL verification needed, as we're testing the file checksum

    {:ok, request_id} =
      :httpc.request(
        :get,
        {String.to_charlist(url), []},
        [],
        sync: false,
        stream: String.to_charlist(filename),
        receiver: self()
      )

    result =
      receive do
        {:http, {^request_id, :saved_to_file}} ->
          :ok

        {:http, {^request_id, err}} ->
          {:error, {:http, err}}
      after
        timeout ->
          :httpc.cancel_request(request_id)
          :timeout
      end

    with :ok <- result,
         :ok <- validate_checksum(filename, checksum) do
      File.chmod(filename, 0o755)
      Logger.info("Checksum matched. MinioServer binary was successfully downloaded.")
    else
      :timeout ->
        File.rm(filename)
        Logger.error("Download failed. Timeout.")
        :ok

      {:error, {:http, err}} ->
        IO.inspect(err)
        Logger.error("Download failed.")
        :ok

      {:error, {:checksum, :mismatch}} ->
        Logger.info("Checksum did not match. Downloaded file was removed.")
        :ok = File.rm(filename)
        :ok
    end
  end

  defp validate_checksum(filename, checksum) do
    if file_checksum(filename) == checksum do
      :ok
    else
      {:error, {:checksum, :mismatch}}
    end
  end

  defp file_checksum(filename) do
    File.stream!(filename, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn line, acc -> :crypto.hash_update(acc, line) end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
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
