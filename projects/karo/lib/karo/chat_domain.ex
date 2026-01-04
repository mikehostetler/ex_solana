defmodule Karo.ChatDomain do
  @moduledoc """
  Ash domain for Karo chat persistence including conversations, messages, and scheduled actions.
  """

  use Ash.Domain, otp_app: :karo

  require Ash.Query
  import Ash.Expr, only: [ref: 1]

  alias Karo.Resources.Conversation
  alias Karo.Resources.Message

  resources do
    resource Conversation
    resource Message
    resource Karo.Resources.ScheduledAction
  end

  @doc """
  Gets an existing conversation by Discord key, or creates a new one if not found.

  The conversation_key is a tuple of `{guild_id, channel_id, thread_id}`.
  """
  @spec get_or_create_conversation(
          {String.t() | nil, String.t(), String.t() | nil},
          map()
        ) :: {:ok, Conversation.t()} | {:error, term()}
  def get_or_create_conversation({guild_id, channel_id, thread_id}, attrs \\ %{}) do
    query =
      Conversation
      |> Ash.Query.filter(discord_channel_id == ^channel_id)
      |> filter_nullable(:discord_guild_id, guild_id)
      |> filter_nullable(:discord_thread_id, thread_id)

    case Ash.read(query, domain: __MODULE__) do
      {:ok, [conversation]} ->
        {:ok, conversation}

      {:ok, []} ->
        create_attrs =
          Map.merge(attrs, %{
            discord_guild_id: guild_id,
            discord_channel_id: channel_id,
            discord_thread_id: thread_id,
            last_activity_at: DateTime.utc_now()
          })

        Conversation
        |> Ash.Changeset.for_create(:create, create_attrs)
        |> Ash.create(domain: __MODULE__)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a message in a conversation.

  Extracts discord_user_id from meta if present, stores remaining meta in metadata field.
  """
  @spec create_message(String.t(), atom(), String.t(), map()) ::
          {:ok, Message.t()} | {:error, term()}
  def create_message(conversation_id, role, content, meta \\ %{}) do
    {discord_user_id, metadata} = Map.pop(meta, :discord_user_id)

    attrs = %{
      conversation_id: conversation_id,
      role: role,
      content: content,
      discord_user_id: discord_user_id,
      metadata: metadata
    }

    Message
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(domain: __MODULE__)
  end

  @doc """
  Lists recent messages for a conversation, ordered by inserted_at ascending.

  Options:
    - `:limit` - Maximum number of messages to return (default: 50)
  """
  @spec list_recent_messages(String.t(), keyword()) ::
          {:ok, [Message.t()]} | {:error, term()}
  def list_recent_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Message
    |> Ash.Query.filter(conversation_id == ^conversation_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read(domain: __MODULE__)
  end

  @doc """
  Closes a conversation by setting status to :closed.
  """
  @spec close_conversation(String.t()) :: {:ok, Conversation.t()} | {:error, term()}
  def close_conversation(conversation_id) do
    with {:ok, conversation} <- Ash.get(Conversation, conversation_id, domain: __MODULE__) do
      conversation
      |> Ash.Changeset.for_update(:update, %{
        status: :closed,
        last_activity_at: DateTime.utc_now()
      })
      |> Ash.update(domain: __MODULE__)
    end
  end

  @doc """
  Updates last_activity_at timestamp on a conversation.
  """
  @spec touch_conversation(String.t()) :: {:ok, Conversation.t()} | {:error, term()}
  def touch_conversation(conversation_id) do
    with {:ok, conversation} <- Ash.get(Conversation, conversation_id, domain: __MODULE__) do
      conversation
      |> Ash.Changeset.for_update(:update, %{last_activity_at: DateTime.utc_now()})
      |> Ash.update(domain: __MODULE__)
    end
  end

  defp filter_nullable(query, field, nil) do
    Ash.Query.filter(query, is_nil(^ref(field)))
  end

  defp filter_nullable(query, field, value) do
    Ash.Query.filter(query, ^ref(field) == ^value)
  end
end
