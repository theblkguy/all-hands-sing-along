# test/all_hands_sing_along/catalog/demucs_stem_adapter_test.exs
defmodule AllHandsSingAlong.Catalog.DemucsStemAdapterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AllHandsSingAlong.Catalog.DemucsStemAdapter

  @fixture Path.join(:code.priv_dir(:all_hands_sing_along), "static/audio/fixture.wav")

  setup do
    tmp = Path.join(System.tmp_dir!(), "ahsa-guide-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.StemSeparator)

    on_exit(fn ->
      File.rm_rf(tmp)

      Application.put_env(
        :all_hands_sing_along,
        AllHandsSingAlong.Catalog.StemSeparator,
        original
      )
    end)

    {:ok, tmp: tmp}
  end

  test "mix_guide_vocal/3 writes a mixed wav when ffmpeg is installed", %{tmp: tmp} do
    {instrumental, vocals, output} = stem_paths(tmp)
    File.cp!(@fixture, instrumental)
    File.cp!(@fixture, vocals)

    if System.find_executable("ffmpeg") do
      assert {:ok, ^output} = DemucsStemAdapter.mix_guide_vocal(instrumental, vocals, output)
      assert File.regular?(output)
      assert File.stat!(output).size > 0
    else
      log =
        capture_log(fn ->
          assert {:error, :missing_ffmpeg} =
                   DemucsStemAdapter.mix_guide_vocal(instrumental, vocals, output)
        end)

      assert log =~ "ffmpeg is not installed"
    end
  end

  test "mix_guide_vocal/3 errors when the vocal stem is missing", %{tmp: tmp} do
    {instrumental, vocals, output} = stem_paths(tmp)
    File.cp!(@fixture, instrumental)

    assert {:error, :stem_failed} =
             DemucsStemAdapter.mix_guide_vocal(instrumental, vocals, output)
  end

  test "mix_guide_vocal/3 errors when ffmpeg is disabled", %{tmp: tmp} do
    {instrumental, vocals, output} = stem_paths(tmp)
    File.cp!(@fixture, instrumental)
    File.cp!(@fixture, vocals)

    config =
      Application.get_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.StemSeparator, [])

    Application.put_env(
      :all_hands_sing_along,
      AllHandsSingAlong.Catalog.StemSeparator,
      Keyword.put(config, :ffmpeg, false)
    )

    log =
      capture_log(fn ->
        assert {:error, :missing_ffmpeg} =
                 DemucsStemAdapter.mix_guide_vocal(instrumental, vocals, output)
      end)

    assert log =~ "ffmpeg is not installed"
  end

  defp stem_paths(tmp) do
    {
      Path.join(tmp, "no_vocals.wav"),
      Path.join(tmp, "vocals.wav"),
      Path.join(tmp, "guide.wav")
    }
  end
end
