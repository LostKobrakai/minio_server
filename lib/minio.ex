defmodule MinioServer do
  @moduledoc """
  Documentation for `MinioServer`.

  ## Usage

      # Config can be used directly with :ex_aws/:ex_aws_s3
      s3_config = [
        access_key_id: "minio_key",
        secret_access_key: "minio_secret",
        scheme: "http://",
        region: "local",
        host: "127.0.0.1",
        port: 9000,
        # Minio specific
        minio_path: "data" # Defaults to minio in your mix project
      ]

      # In a supervisor
      children = [
        {MinioServer, s3_config}
      ]

      # or manually
      {:ok, _} = MinioServer.start_link(s3_config)

  """
  use Supervisor
  require Logger

  @type architecture :: String.t()
  @type version :: String.t()

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    key = Keyword.fetch!(init_arg, :access_key_id)
    secret = Keyword.fetch!(init_arg, :secret_access_key)
    host = Keyword.get(init_arg, :host, "127.0.0.1")
    port = Keyword.get(init_arg, :port, 9000)
    ui = Keyword.get(init_arg, :ui, true)
    minio_path = Keyword.get(init_arg, :minio_path, Path.expand("minio", "."))
    minio_executable = Keyword.get(init_arg, :minio_executable, minio_executable())

    children = [
      {MuonTrap.Daemon,
       [
         minio_executable,
         ["server", "--json", "--quiet", "--address", "#{host}:#{port}", minio_path],
         [
           log_output: :info,
           log_prefix: "[minio] ",
           env: [
             {"MINIO_ACCESS_KEY", key},
             {"MINIO_SECRET_KEY", secret},
             {"MINIO_BROWSER", if(ui, do: "on", else: "off")}
           ]
         ]
       ]}
    ]

    Logger.info("Running minio server at #{host}:#{port}")

    if ui do
      Logger.info("Access minio server UI at http://#{host}:#{port}")
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Path to the executable binaries downloaded."
  @spec executable_path(MinioServer.architecture()) :: Path.t()
  def executable_path(arch) do
    Application.app_dir(:minio_server, "priv/minio/#{arch}/minio")
  end

  @doc "A list of all the available architectures downloadable."
  @spec available_architectures :: [MinioServer.architecture()]
  defdelegate available_architectures(), to: MinioServer.Downloader

  @doc """
  Download the binary for a selected architecture

  ## Opts

  * `:force` - Replace already existing binaries. Defaults to `false`.
  * `:timeout` - Time the download is allowed to take. Defaults to `:infinity`.

  """
  @spec download(MinioServer.architecture(), keyword()) :: :exists | :ok | :timeout
  defdelegate download(arch, opts \\ []), to: MinioServer.Downloader

  @spec minio_executable :: Path.t()
  defp minio_executable do
    case major_os_type() do
      # For other types please configure the binary manually
      :mac -> executable_path("darwin-amd64")
      :win -> executable_path("windows-amd64")
      :unix -> executable_path("linux-amd64")
    end
  end

  defp major_os_type do
    case :os.type() do
      {:win32, _} -> :win
      {:unix, :darwin} -> :mac
      {other, _} -> other
    end
  end
end
