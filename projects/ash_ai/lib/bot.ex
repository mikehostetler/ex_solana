defmodule ChatBot do
  def iex_chat(actor \\ nil) do
    AshAi.iex_chat(nil, actor: actor, otp_app: :my_app)
  end
end
