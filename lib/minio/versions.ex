defmodule MinioServer.Versions do
  @moduledoc """
  Create version listings of minio binaries based on their cdn and the checksums.

  Does skip version before 2020.
  """
  alias MinioServer.Config

  @type type :: :client | :server
  @typep setup :: %{
           binary: String.t(),
           versions_file: String.t(),
           versions_url: (String.t() -> String.t()),
           release_url: (String.t(), String.t() -> String.t())
         }

  @doc """
  Create a versions file for client or server binaries.
  """
  @spec create_versions_file(type, keyword) :: :ok | {:error, term}
  def create_versions_file(type, opts \\ []) when type in [:client, :server] do
    setup = Enum.into(opts, download_setup(type))
    arches = Config.available_architectures()

    versions = fetch_release_versions_available_in_all_architectures(arches, setup)
    versions_and_checksums = fetch_checksums(arches, versions, setup)

    File.write(setup.versions_file, Jason.encode!(versions_and_checksums, pretty: true))
  end

  @spec fetch_release_versions_available_in_all_architectures(list, setup) :: MapSet.t()
  defp fetch_release_versions_available_in_all_architectures(arches, setup) do
    arches
    |> Task.async_stream(fn arch ->
      listing =
        arch
        |> setup.versions_url.()
        |> request([{"Accept", "application/json"}])
        |> Jason.decode!()

      files = for %{"IsDir" => false, "Name" => name} <- listing, into: MapSet.new(), do: name

      prefix = "#{setup.binary}.RELEASE."
      size = byte_size(prefix)

      for <<^prefix::binary-size(size), version::binary-size(20)>> <- files,
          match?(<<year::binary-size(4), _::binary>> when year >= "2020", version),
          MapSet.member?(files, "#{setup.binary}.RELEASE.#{version}.sha256sum"),
          into: MapSet.new() do
        version
      end
    end)
    |> Enum.map(fn {:ok, mapset} -> mapset end)
    |> Enum.reduce(&MapSet.intersection/2)
  end

  @spec fetch_checksums(list, MapSet.t(), setup) :: map()
  defp fetch_checksums(arches, versions, setup) do
    for version <- versions,
        arch <- arches do
      {version, arch}
    end
    |> Task.async_stream(fn {version, arch} ->
      result = request(setup.release_url.(arch, version) <> ".sha256sum")
      name = "#{setup.binary}.RELEASE.#{version}"
      [checksum, ^name] = String.split(result)
      {version, arch, checksum}
    end)
    |> Enum.group_by(
      fn {:ok, {version, _, _}} -> version end,
      fn {:ok, {_, arch, checksum}} -> {arch, checksum} end
    )
    |> Map.new(fn {k, list} -> {k, Map.new(list)} end)
  end

  @spec request(String.t(), list) :: String.t()
  defp request(url, headers \\ []) do
    headers = for {header, value} <- headers, do: {~c"#{header}", ~c"#{value}"}

    {:ok, {200, body}} =
      :httpc.request(:get, {String.to_charlist(url), headers}, [], full_result: false)

    List.to_string(body)
  end

  @doc false
  @spec download_setup(type) :: setup
  def download_setup(:client) do
    %{
      binary: "mc",
      versions_file: "versions-client.json",
      versions_url: fn arch -> "https://dl.min.io/client/mc/release/#{arch}/archive/" end,
      release_url: fn arch, version ->
        "https://dl.min.io/client/mc/release/#{arch}/archive/mc.RELEASE.#{version}"
      end
    }
  end

  def download_setup(:server) do
    %{
      binary: "minio",
      versions_file: "versions-server.json",
      versions_url: fn arch -> "https://dl.min.io/server/minio/release/#{arch}/archive/" end,
      release_url: fn arch, version ->
        "https://dl.min.io/server/minio/release/#{arch}/archive/minio.RELEASE.#{version}"
      end
    }
  end
end
