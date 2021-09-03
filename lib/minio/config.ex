defmodule MinioServer.Config do
  @doc "A list of all the available architectures downloadable."
  @spec available_architectures :: [MinioServer.architecture()]
  def available_architectures do
    ["windows-amd64", "darwin-amd64", "darwin-arm64", "linux-amd64", "linux-arm", "linux-arm64"]
  end

  ####### SERVER ########
  server_versions_file = Application.compile_env(:minio_server, :versions_file, "versions-server.json")
  @external_resource server_versions_file
  @server_versions server_versions_file
            |> File.read!()
            |> Jason.decode!()
  def server_versions do
    @server_versions
  end

  @doc "A list of all the available versions of minio."
  @spec available_server_versions :: [MinioServer.version()]
  def available_server_versions do
    @server_versions |> Map.keys() |> Enum.sort(:desc)
  end

  @doc "The most recent available version of minio."
  @spec most_recent_server_version :: MinioServer.version()
  def most_recent_server_version() do
    List.first(available_server_versions())
  end

  ####### CLIENT ########

  client_versions_file = Application.compile_env(:minio_server, :versions_file, "versions-client.json")
  @external_resource client_versions_file
  @client_versions client_versions_file
            |> File.read!()
            |> Jason.decode!()

  def client_versions do
    @client_versions
  end

  @doc "A list of all the available versions of minio."
  @spec available_client_versions :: [MinioServer.version()]
  def available_client_versions do
    @client_versions |> Map.keys() |> Enum.sort(:desc)
  end

  @doc "The most recent available version of minio."
  @spec most_recent_client_version :: MinioServer.version()
  def most_recent_client_version() do
    List.first(available_server_versions())
  end
end
