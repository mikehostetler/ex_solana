defmodule ReqLLM.Coverage.Google.ImageGenerationTest do
  use ExUnit.Case, async: true

  import ReqLLM.Test.Helpers

  @moduletag :coverage
  @moduletag provider: "google"
  @moduletag timeout: 180_000

  @model_spec "google:gemini-2.0-flash-exp-image-generation"

  setup_all do
    LLMDB.load(allow: :all, custom: %{})
    :ok
  end

  @tag scenario: :image_basic
  @tag model: "gemini-2.0-flash-exp-image-generation"
  test "generate_image/3 returns a Response with one image part" do
    {:ok, response} =
      ReqLLM.generate_image(
        @model_spec,
        "A simple blue square",
        fixture_opts("image_basic")
      )

    [part] = ReqLLM.Response.images(response)
    assert part.type == :image
    assert part.media_type == "image/png"
    assert is_binary(part.data) and byte_size(part.data) > 0
  end
end
