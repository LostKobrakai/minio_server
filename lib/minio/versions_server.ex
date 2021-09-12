defmodule MinioServer.VersionsServer do
  alias MinioServer.Config

  @doc """
  Create a json file listing versions of minio server based on their cdn and the checksums.

  Does only list versions 2020+, which are available in all `available_architectures()`.
  """
  def create_versions_file(path \\ "versions-server.json") do
    versions_and_checksums =
      fetch_release_versions_available_in_all_architectures()
      |> fetch_checksums()

    File.write(path, Jason.encode!(versions_and_checksums, pretty: true))
  end

  defp fetch_release_versions_available_in_all_architectures do
    for arch <- Config.available_architectures() do
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
    for version <- versions, arch <- Config.available_architectures() do
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

  defp url_for_release(:server, arch, version) do
    "https://dl.min.io/server/minio/release/#{arch}/archive/minio.RELEASE.#{version}"
  end
end
