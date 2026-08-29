# lib/all_hands_sing_along/catalog/demucs_stem_adapter.ex
defmodule AllHandsSingAlong.Catalog.DemucsStemAdapter do
  @moduledoc false

  @behaviour AllHandsSingAlong.Catalog.StemAdapter

  require Logger

  @impl true
  def available? do
    python = python_executable()
    is_binary(python) and demucs_importable?(python)
  end

  def isolate(input_path) when is_binary(input_path), do: isolate(input_path, nil)

  @impl true
  def isolate(input_path, progress) when is_binary(input_path) do
    python = python_executable()
    tmp = Path.join(System.tmp_dir!(), "stems-" <> Ecto.UUID.generate())

    with :ok <- ensure_installed(python),
         :ok <- File.mkdir_p(tmp) do
      {exe, args} = command(python, input_path, tmp)

      case run_demucs(exe, args, progress) do
        {:ok, _output} ->
          result = find_output(tmp)
          cleanup(tmp, result)
          result

        {:error, output, _status} ->
          File.rm_rf(tmp)
          Logger.warning("demucs failed: #{String.slice(to_string(output), 0, 500)}")
          {:error, classify_error(output)}
      end
    else
      {:error, :not_installed} = error ->
        Logger.warning("demucs is not installed for python #{python_executable()}")
        error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp python_executable do
    configured = Keyword.get(config(), :python, "python3")

    candidates =
      [
        configured,
        System.find_executable(configured),
        Path.join(File.cwd!(), ".venv/bin/python"),
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/opt/python@3.12/bin/python3.12",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        System.find_executable("python3")
      ]
      |> Enum.filter(&(is_binary(&1) and File.exists?(&1)))
      |> Enum.uniq()

    Enum.find(candidates, &demucs_importable?/1) || List.first(candidates) || configured
  end

  defp demucs_importable?(python) do
    match?({_, 0}, System.cmd(python, ["-c", "import demucs"], stderr_to_stdout: true))
  rescue
    _ -> false
  end

  defp ensure_installed(python) do
    if demucs_importable?(python), do: :ok, else: {:error, :not_installed}
  end

  defp command(python, input_path, tmp) do
    {python, ["-m", "demucs", "--two-stems=vocals", "-o", tmp, input_path]}
  end

  defp run_demucs(exe, args, progress) do
    port =
      Port.open(
        {:spawn_executable, exe},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, args},
          {:env, [{~c"PYTHONUNBUFFERED", ~c"1"}]}
        ]
      )

    collect_demucs(port, "", progress)
  end

  defp collect_demucs(port, acc, progress) do
    receive do
      {^port, {:data, data}} when is_binary(data) ->
        maybe_report_percent(data, progress)
        collect_demucs(port, acc <> data, progress)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, status}} ->
        {:error, acc, status}
    after
      3_600_000 ->
        Port.close(port)
        {:error, acc, :timeout}
    end
  end

  defp maybe_report_percent(_data, progress) when not is_function(progress, 1), do: :ok

  defp maybe_report_percent(data, progress) do
    case parse_percent(data) do
      pct when is_integer(pct) -> progress.(pct)
      _ -> :ok
    end
  end

  defp parse_percent(text) when is_binary(text) do
    cond do
      match = Regex.run(~r/(\d{1,3})\s*%/, text) ->
        match |> Enum.at(1) |> String.to_integer() |> min(100)

      match = Regex.run(~r/(\d+)\s*\/\s*(\d+)/, text) ->
        num = match |> Enum.at(1) |> String.to_integer()
        den = match |> Enum.at(2) |> String.to_integer()
        if den > 0, do: min(100, round(num / den * 100)), else: nil

      true ->
        nil
    end
  end

  defp parse_percent(_), do: nil

  defp find_output(tmp) do
    case Path.wildcard(Path.join(tmp, "**/no_vocals.*")) do
      [path | _] -> {:ok, path}
      [] -> {:error, :no_output}
    end
  end

  defp classify_error(output) when is_binary(output) do
    down = String.downcase(output)

    cond do
      String.contains?(down, "no module named 'demucs'") -> :not_installed
      String.contains?(down, "no module named demucs") -> :not_installed
      String.contains?(down, "demucs") and String.contains?(down, "not found") -> :not_installed
      String.contains?(down, "no module named 'numpy'") -> :missing_numpy
      String.contains?(down, "no module named numpy") -> :missing_numpy
      true -> :stem_failed
    end
  end

  defp classify_error(_), do: :stem_failed

  defp cleanup(tmp, {:ok, path}) do
    keep = Path.basename(path)

    Path.wildcard(Path.join(tmp, "**/*"))
    |> Enum.each(fn file ->
      if File.regular?(file) and Path.basename(file) != keep do
        File.rm(file)
      end
    end)

    :ok
  end

  defp cleanup(tmp, _) do
    File.rm_rf(tmp)
    :ok
  end

  defp config do
    Application.get_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.StemSeparator, [])
  end
end
