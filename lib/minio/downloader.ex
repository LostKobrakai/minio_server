defmodule MinioServer.Downloader do
  @moduledoc false
  require Logger

  versions_file = Application.compile_env(:minio_server, :versions_file, "versions.json")
  @external_resource versions_file
  @versions versions_file
            |> File.read!()
            |> Jason.decode!()

  @doc "A list of all the available architectures downloadable."
  @spec available_architectures :: [MinioServer.architecture()]
  def available_architectures do
    ["windows-amd64", "darwin-amd64", "linux-amd64", "linux-arm", "linux-arm64"]
  end

  @doc "A list of all the available versions of minio."
  @spec available_versions :: [MinioServer.version()]
  def available_versions do
    @versions |> Map.keys() |> Enum.sort(:desc)
  end

  @doc "The most recent available version of minio."
  @spec most_recent_version :: MinioServer.version()
  def most_recent_version() do
    List.first(available_versions())
  end

  @doc """
  Download the binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.

  """
  @spec download(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  def download(arch, opts \\ []) do
    version = Keyword.get(opts, :version, most_recent_version())
    force = Keyword.get(opts, :force, false)
    timeout = Keyword.get(opts, :timeout, :infinity)

    if arch not in available_architectures() do
      raise "Invalid architecture"
    end

    if version not in available_versions() do
      raise "Invalid version"
    end

    filename = MinioServer.executable_path(arch)
    checksum = checksum!(arch, version)

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
            Logger.info(
              "Download of minio binary for #{arch} (version #{version}): Replacing existing."
            )

          :download ->
            Logger.info("Download of minio binary for #{arch} (version #{version}).")
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
    "#{url_for_architecture(arch)}minio.RELEASE.#{version}"
  end

  defp url_for_architecture(arch) do
    "https://dl.min.io/server/minio/release/#{arch}/archive/"
  end

  defp checksum!(arch, version) do
    @versions
    |> Map.fetch!(version)
    |> Map.fetch!(arch)
  end

  @doc """
  Create a json file listing versions of minio based on their cdn and the checksums.

  Does only list versions 2020+, which are available in all `available_architectures()`.
  """
  def create_versions_file(path \\ "versions.json") do
    versions_and_checksums =
      fetch_release_versions_available_in_all_architectures()
      |> fetch_checksums()

    File.write(path, Jason.encode!(versions_and_checksums))
  end

  defp fetch_release_versions_available_in_all_architectures do
    for arch <- available_architectures() do
      url = url_for_architecture(arch)
      headers = [{'Accept', 'application/json'}]

      {:ok, {200, body}} =
        :httpc.request(:get, {String.to_charlist(url), headers}, [], full_result: false)

      data = body |> List.to_string() |> Jason.decode!()
      map = for %{"IsDir" => false, "Name" => name} = file <- data, into: %{}, do: {name, file}

      for {<<"minio.RELEASE.", version::binary-size(20)>>, _file} <- map,
          match?(<<year::binary-size(4), _::binary>> when year >= "2020", version),
          Map.has_key?(map, "minio.RELEASE.#{version}.sha256sum"),
          into: MapSet.new() do
        version
      end
    end
    |> Enum.reduce(&MapSet.intersection/2)
  end

  defp fetch_checksums(versions) do
    for version <- versions, arch <- available_architectures() do
      {version, arch}
    end
    |> Task.async_stream(fn {version, arch} ->
      url = url_for_release(arch, version) <> ".sha256sum"

      {:ok, {200, body}} =
        :httpc.request(:get, {String.to_charlist(url), []}, [], full_result: false)

      [checksum, <<"minio.RELEASE.", ^version::binary-size(20)>>] =
        body |> List.to_string() |> String.split()

      {version, arch, checksum}
    end)
    |> Enum.group_by(
      fn {:ok, {version, _, _}} -> version end,
      fn {:ok, {_, arch, checksum}} -> {arch, checksum} end
    )
    |> Map.new(fn {k, list} -> {k, Map.new(list)} end)
  end
end
