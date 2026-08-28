# lib/all_hands_sing_along/rooms/sync.ex
defmodule AllHandsSingAlong.Rooms.Sync do
  @moduledoc """
  Playhead and LRC helpers. The browser applies the same position math
  so tests can cover timing without a DOM.
  """

  @type lyric_line :: %{time_ms: non_neg_integer(), text: String.t()}

  @spec client_position_ms(integer(), integer(), integer(), integer(), boolean()) ::
          non_neg_integer()
  def client_position_ms(position_ms, _server_time_ms, _client_time_ms, _offset_ms, false)
      when is_integer(position_ms) do
    max(0, position_ms)
  end

  def client_position_ms(position_ms, server_time_ms, client_time_ms, offset_ms, true)
      when is_integer(position_ms) and is_integer(server_time_ms) and is_integer(client_time_ms) and
             is_integer(offset_ms) do
    max(0, position_ms + (client_time_ms - server_time_ms) + offset_ms)
  end

  @spec current_line([lyric_line()], integer()) :: lyric_line()
  def current_line(lyrics, position_ms) when is_list(lyrics) and is_integer(position_ms) do
    lyrics
    |> Enum.filter(fn line -> line.time_ms <= position_ms end)
    |> List.last()
    |> Kernel.||(%{time_ms: 0, text: ""})
  end

  @spec parse_lrc(String.t() | nil) :: [lyric_line()]
  def parse_lrc(nil), do: []
  def parse_lrc(""), do: []

  def parse_lrc(text) when is_binary(text) do
    text
    |> String.split(["\n", "\r\n"], trim: true)
    |> Enum.flat_map(&parse_lrc_line/1)
    |> Enum.sort_by(& &1.time_ms)
  end

  defp parse_lrc_line(line) do
    case Regex.run(~r/\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)/, line) do
      [_, mm, ss, frac, text] when frac != "" ->
        [%{time_ms: to_ms(mm, ss, frac), text: String.trim(text)}]

      [_, mm, ss, _frac, text] ->
        [%{time_ms: to_ms(mm, ss, "0"), text: String.trim(text)}]

      [_, mm, ss, text] ->
        [%{time_ms: to_ms(mm, ss, "0"), text: String.trim(text)}]

      _ ->
        []
    end
  end

  defp to_ms(mm, ss, frac) do
    minutes = String.to_integer(mm)
    seconds = String.to_integer(ss)
    frac_ms = frac_to_ms(frac)
    minutes * 60_000 + seconds * 1_000 + frac_ms
  end

  defp frac_to_ms(frac) when byte_size(frac) == 1, do: String.to_integer(frac) * 100
  defp frac_to_ms(frac) when byte_size(frac) == 2, do: String.to_integer(frac) * 10

  defp frac_to_ms(frac) when byte_size(frac) >= 3,
    do: frac |> String.slice(0, 3) |> String.to_integer()

  defp frac_to_ms(_), do: 0
end
