defmodule MinioServer.Admin do
  @moduledoc """
  Functions for administrating an minio instance using `mc`.
  """
  @alias "minio_server"

  alias MinioServer.Config

  @doc "Print shell alias for given config to use with own `mc` binary"
  def alias_export(config) do
    {env, value} = host_env(config)
    "export #{env}='#{value}'"
  end

  @doc """
  Create an user, pucket, full-access policy in one.
  """
  def add_user_owned_bucket(user, secret, config) do
    bucket = "user-#{user}"
    policy = "fullaccess_#{bucket}"
    tmp_policy_path = Path.join([System.tmp_dir!(), "#{policy}.json"])
    File.write!(tmp_policy_path, canned_bucket_policy_full_access(bucket))

    cmd(config, ["mb", "--ignore-existing", "#{@alias}/#{bucket}"])
    cmd(config, ["admin", "policy", "add", @alias, policy, tmp_policy_path])
    cmd(config, ["admin", "user", "add", @alias, user, secret])
    cmd(config, ["admin", "policy", "set", @alias, policy, "user=#{user}"])
    :ok
  end

  defp canned_bucket_policy_full_access(bucket) do
    %{
      "Version" => "2012-10-17",
      "Statement" => [
        %{
          "Action" => "s3:*",
          "Effect" => "Allow",
          "Resource" => [
            "arn:aws:s3:::#{bucket}",
            "arn:aws:s3:::#{bucket}/*"
          ],
          "Sid" => ""
        }
      ]
    }
    |> Jason.encode!()
  end

  @doc """
  Run a command using the internal `mc` binary.
  """
  def cmd(config, cmd, opts \\ []) do
    opts =
      Keyword.merge([env: [host_env(config)], into: IO.stream(:stdio, :line)], opts, fn
        :env, v1, v2 -> v1 ++ v2
        :into, _, into -> into
      end)

    System.cmd(mc(), ["--config-dir", config_dir()] ++ cmd, opts)
  end

  defp host_env(config) do
    key = Keyword.fetch!(config, :access_key_id)
    secret = Keyword.fetch!(config, :secret_access_key)
    host = Keyword.get(config, :host, "127.0.0.1")
    port = Keyword.get(config, :port, 9000)

    {"MC_HOST_#{@alias}", "http://#{key}:#{secret}@#{host}:#{port}"}
  end

  defp mc do
    Config.minio_executable()
    |> Path.dirname()
    |> Path.join("mc")
  end

  defp config_dir do
    Config.minio_executable()
    |> Path.dirname()
    |> Path.join(".mc")
  end
end
