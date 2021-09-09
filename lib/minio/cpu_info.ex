# With ideas from from https://github.com/zeam-vm/cpu_info/blob/master/lib/cpu_info.ex
defmodule MinioServer.CpuInfo do
  def cpu_type do
    cpu_type_sub(os_type())
  end

  defp cpu_type_sub(os_type) when os_type in [:windows, :linux, :unknown] do
    :erlang.system_info(:system_architecture) |> List.to_string() |> String.split("-") |> hd
  end

  defp cpu_type_sub(os_type) when os_type in [:freebsd, :macos] do
    confirm_executable("uname")

    case System.cmd("uname", ["-m"]) do
      {result, 0} -> result |> String.trim()
      _ -> raise RuntimeError, message: "uname does not work."
    end
  end

  defp confirm_executable(command) do
    unless System.find_executable(command) do
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
