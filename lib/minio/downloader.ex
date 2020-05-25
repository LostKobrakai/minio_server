defmodule MinioServer.Downloader do
  @moduledoc false
  require Logger

  @version %{
    name: "2020-03-25T07-03-04Z",
    checksum: %{
      "windows-amd64" => "e60b8b43ee0b831434827c484de7e7b46033f0a875676d93ca42618c7bb10e2f",
      "darwin-amd64" => "c57b00f314cd83691e952e3df26e14f03bf8ade865a81d1d7736560fac8b1e4c",
      "linux-amd64" => "e034842fec710b115ce40e02df3b2e0bcb3360c5691224a21a42828fcd9e8793",
      "linux-arm" => "c60c1010a36ad2c4902d4305b106398341d8d3780e776be17f1915386d63208f",
      "linux-arm64" => "c8265f7aa3071cb0fb8ac90e989d6458eb315a373567e227dbd7da43e814f79a"
    }
  }

  @doc "A list of all the available architectures downloadable."
  @spec available_architectures :: [MinioServer.architecture()]
  def available_architectures do
    Map.keys(@version.checksum)
  end

  @doc """
  Download the binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.

  """
  @spec download(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  def download(arch, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    timeout = Keyword.get(opts, :timeout, :infinity)

    if arch not in available_architectures() do
      raise "Invalid architecture"
    end

    filename = MinioServer.executable_path(arch)
    checksum = checksum!(arch)

    task =
      cond do
        File.exists?(filename) and not force -> :exists
        File.exists?(filename) and force -> :replace
        true -> :download
      end

    if task == :replace, do: File.rm(filename)

    case task do
      :exists ->
        Logger.info("Download of minio binary for #{arch} skipped: already exists.")
        :exists

      task ->
        case task do
          :replace ->
            Logger.info("Download of minio binary for #{arch}: Replacing existing.")

          :download ->
            Logger.info("Download of minio binary for #{arch}.")
        end

        url = url_for_release(arch, @version.name)
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
        [timeout: timeout],
        sync: false,
        stream: String.to_charlist(filename),
        receiver: self()
      )

    receive do
      {:http, {^request_id, :saved_to_file}} -> :ok
    after
      timeout -> :timeout
    end

    if file_checksum(filename) == checksum do
      File.chmod(filename, 0o755)
      Logger.info("Checksum matched. MinioServer binary was successfully downloaded.")
      :ok
    else
      Logger.info("Checksum did not match. Downloaded file was removed.")
      :ok = File.rm(filename)
    end
  end

  defp file_checksum(filename) do
    File.stream!(filename, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn line, acc -> :crypto.hash_update(acc, line) end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp url_for_release(arch, version) do
    "https://dl.min.io/server/minio/release/#{arch}/archive/minio.RELEASE.#{version}"
  end

  defp checksum!(arch) do
    Map.fetch!(@version.checksum, arch)
  end
end
