defmodule MinioServer.Downloader do
  @moduledoc false
  require Logger

  versions_file = Application.compile_env(:minio_server, :versions_file, "versions.json")
  @external_resource versions_file
  @versions versions_file
            |> File.read!()
            |> Jason.decode!()

  @mc %{
    version: "2020-07-31T23-34-13Z",
    checksums: %{
      "darwin-amd64" => "3588eb91a1a20f34258838eaf528b1d93869da5cdf94c9df87cbe81b569ca104",
      "windows-amd64" => "e2489420d54c406caff986d6d1a67eeeeda155dd894769d9a721d3053da1f3b3",
      "linux-amd64" => "b430c1cfcbf9aa0b0edddf0777b4c3e6d48b9827ea82973fc7d1a728587ad263",
      "linux-arm" => "6cf4456ae5a512d99560df1d521ddca7b5f892f5854d197433f48647e54b2442",
      "linux-arm64" => "6845183d21e7ac9352731dd0a311b6fd3ca72bdb6593363d6eb762cc4bd73efe"
    }
  }

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
  Download the server binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.
  * `:version` - Specify the version to download. Defaults to most recent.

  """
  @spec download_server(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  def download_server(arch, opts \\ []) do
    download_client = !Keyword.get(opts, :skip_client, false)
    version = Keyword.get(opts, :version, most_recent_version())

    if arch not in available_architectures() do
      raise "Invalid architecture"
    end

    if version not in available_versions() do
      raise "Invalid version"
    end

    filename = MinioServer.executable_path(arch)
    checksum = checksum!(arch, version)

    if download_client do
      download_client(arch, opts)
    end

    handle_downloading(:server, arch, version, filename, checksum, opts)
  end

  @doc """
  Download the client binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.

  """
  @spec download_client(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  def download_client(arch, opts \\ []) do
    if arch not in available_architectures() do
      raise "Invalid architecture"
    end

    filename = MinioServer.executable_path(arch) |> Path.dirname() |> Path.join("mc")
    checksum = Map.fetch!(@mc.checksums, arch)

    handle_downloading(:client, arch, @mc.version, filename, checksum, opts)
  end

  defp check_filename_status(filename, force) do
    cond do
      File.exists?(filename) and not force -> :exists
      File.exists?(filename) and force -> :replace
      true -> :download
    end
  end

  defp handle_downloading(type, arch, version, filename, checksum, opts) do
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

        url = url_for_release(type, arch, version)
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

  defp r(request_id, timeout) do
    receive do
      {:http, {^request_id, :saved_to_file}} ->
        :ok

      msg ->
        IO.inspect(msg)
        r(request_id, timeout)
    after
      timeout -> :timeout
    end
  end

  defp file_checksum(filename) do
    File.stream!(filename, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn line, acc -> :crypto.hash_update(acc, line) end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp url_for_release(:server, arch, version) do
    "https://dl.min.io/server/minio/release/#{arch}/archive/minio.RELEASE.#{version}"
  end

  defp url_for_release(:client, arch, version) do
    "https://dl.min.io/client/mc/release/#{arch}/archive/mc.RELEASE.#{version}"
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
      url = "https://dl.min.io/server/minio/release/#{arch}/archive/"
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
      url = url_for_release(:server, arch, version) <> ".sha256sum"

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
