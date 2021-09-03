# With ideas from from https://github.com/zeam-vm/cpu_info/blob/master/lib/cpu_info.ex
defmodule MinioServer.CpuInfo do
  def cpu_type do
    cpu_type_sub((os_type()))
  end

  defp cpu_type_sub(:unknown) do
    cpu_type =
      :erlang.system_info(:system_architecture) |> List.to_string() |> String.split("-") |> hd

    %{
      cpu_type: cpu_type,
    }
  end

  defp cpu_type_sub(:windows) do
    :erlang.system_info(:system_architecture) |> List.to_string() |> String.split("-") |> hd

  end

  defp cpu_type_sub(:linux) do
    :erlang.system_info(:system_architecture) |> List.to_string() |> String.split("-") |> hd
  end

  defp cpu_type_sub(:freebsd) do
    confirm_executable("uname")

    cpu_type =
      case System.cmd("uname", ["-m"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname does not work."
      end

    cpu_type
  end

  defp cpu_type_sub(:macos) do
    confirm_executable("uname")

    cpu_type =
      try do
        case System.cmd("uname", ["-m"]) do
          {result, 0} -> result |> String.trim()
          _ -> nil
        end
      rescue
        _e in ErlangError -> nil
      end

    cpu_type
  end

  defp confirm_executable(command) do
    if is_nil(System.find_executable(command)) do
      raise RuntimeError, message: "#{command} isn't found."
    end
  end

  def os_type do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:unix, :freebsd} -> :freebsd
      {:win32, _} -> :windows
      _ -> :unknown
    end
  end
end
