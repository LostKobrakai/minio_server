defmodule MinioServer.Downloader do
  require Logger

  def handle_downloading(type, arch, version, url, filename, checksum, opts)
      when type in [:server, :client] do
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

        File.mkdir_p(Path.dirname(filename))
        download(url, filename, checksum, timeout)
    end
  end

  defp check_filename_status(filename, force) do
    cond do
      File.exists?(filename) and not force -> :exists
      File.exists?(filename) and force -> :replace
      true -> :download
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
end
