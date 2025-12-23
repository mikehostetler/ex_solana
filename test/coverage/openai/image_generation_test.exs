defmodule ReqLLM.Coverage.OpenAI.ImageGenerationTest do
  use ExUnit.Case, async: true

  import ReqLLM.Test.Helpers

  @moduletag :coverage
  @moduletag provider: "openai"
  @moduletag timeout: 180_000

  @model_spec "openai:gpt-image-1"

  setup_all do
    LLMDB.load(allow: :all, custom: %{})
    :ok
  end

  @tag scenario: :image_basic
  @tag model: "gpt-image-1"
  test "generate_image/3 returns a Response with one image part" do
    {:ok, response} =
      ReqLLM.generate_image(
        @model_spec,
        "A simple red square",
        fixture_opts("image_basic")
      )

    [part] = ReqLLM.Response.images(response)
    assert part.type == :image
    assert is_binary(part.media_type) and part.media_type != ""
    assert is_binary(part.data) and byte_size(part.data) > 0
  end
end
