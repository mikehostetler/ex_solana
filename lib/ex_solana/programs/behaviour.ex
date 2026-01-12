defmodule ExSolana.ProgramBehaviour do
  @moduledoc """
  Defines the behavior for Solana program instruction decoders.
  """

  require Logger

  @doc """
  Enables this behavior and provides default implementations.
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts, module: __MODULE__], location: :keep, generated: true do
      @behaviour ExSolana.ProgramBehaviour

      alias ExSolana.Program.IDLMacros

      require IDLMacros

      if is_nil(opts[:program_id]) do
        raise ArgumentError, "program_id is required"
      end

      @external_idl_file_path Keyword.get(opts, :idl_path, nil)
      @idl ExSolana.IDL.Parser.parse_file!(@external_idl_file_path)
      @log_prefix Keyword.get(opts, :log_prefix, "Program Log: ")
      @valid_opts opts
      @name if @idl, do: @idl.name

      @impl true
      def id, do: ExSolana.pubkey!(@valid_opts[:program_id])

      @impl true
      def name, do: @name

      @impl true
      def network, do: @valid_opts[:network] || :mainnet

      if !is_nil(@idl) do
        IDLMacros.generate_constants(@idl)
        IDLMacros.generate_event_decoders(@idl, @log_prefix)
        IDLMacros.generate_ix_decoders(@idl)
        IDLMacros.generate_account_decoders(@idl)
        # ExSolana.Program.IDLMacros.generate_ix_creators(@idl)
        IDLMacros.generate_invocation_analyzers(@idl)
      end

      @impl true
      def decode_ix(data), do: {:unknown_ix, %{data: data}}

      @impl true
      def decode_events(logs), do: {:unknown_event, %{logs: logs}}

      @impl true
      def decode_account(data), do: {:unknown_default_account, %{data: data}}

      @impl true
      def create_ix(ix, params), do: {:error, "Not implemented"}

      # TODO: Deprecate
      @impl true
      def analyze_invocation(invocation, _decoded_txn), do: {:unknown_action, %{}}

      @impl true
      def analyze_ix(decoded_parsed_ix, _decoded_txn), do: {:unknown_action, %{}}

      defoverridable id: 0,
                     name: 0,
                     network: 0,
                     decode_ix: 1,
                     decode_events: 1,
                     create_ix: 2,
                     decode_account: 1,
                     analyze_invocation: 2,
                     analyze_ix: 2
    end
  end

  @doc """
  Returns the program's public key.

  ## Returns
    An ExSolana.Pubkey struct representing the program's public key
  """
  @callback id() :: ExSolana.Key.t()

  @doc """
  Returns the program's name.

  ## Returns
    A string representing the program's name
  """
  @callback name() :: String.t()

  @doc """
  Returns the program's network.

  ## Returns
    An atom representing the program's network
  """
  @callback network() :: atom()
  @doc """
  Creates an instruction for the program.

  ## Parameters
    - ix: An atom representing the type of instruction to create
    - params: A map of parameters for the instruction

  ## Returns
    {:ok, binary()} if the instruction was created successfully
    {:error, String.t()} if the instruction could not be created
  """
  @callback create_ix(ix :: atom(), params :: map()) :: {:ok, binary()} | {:error, String.t()}

  @doc """
  CALLBACK - Decodes a single instruction for the program.

  ## Parameters
    - data: Binary data of the instruction

  ## Returns
    `{instruction_type, params}` where:
    - `instruction_type` is an atom representing the type of instruction
    - `params` is a map of decoded parameters for the instruction
  """
  @callback decode_ix(data :: binary) :: {atom, map}

  @doc """
  Decodes a single account for the program.

  ## Parameters
    - data: Binary data of the account

  ## Returns
    `{account_type, params}` where:
    - `account_type` is an atom representing the type of account
    - `params` is a map of decoded parameters for the account
  """
  @callback decode_account(data :: binary) :: {atom, map}

  @doc """
  Decodes program events.

  ## Parameters
    - events: A list of strings representing the events

  ## Returns
    `{event_type, params}` where:
    - `event_type` is an atom representing the type of event
    - `params` is a map of decoded parameters for the event
  """

  @callback decode_events(logs :: [String.t()]) :: [{atom, map}]

  @doc """
  Analyzes an invocation and extracts program-specific information.

  ## Parameters
    - invocation: A map representing a program invocation
    - decoded_txn: A map representing a decoded transaction

  ## Returns
    An updated invocation map containing analysis results
  """
  @callback analyze_invocation(invocation :: map, decoded_txn :: map) :: map
  @callback analyze_ix(decoded_parsed_ix :: map, decoded_txn :: map) :: map
end
