defmodule ExSolana.Error do
  @moduledoc """
  Unified error handling for ExSolana using Splode.

  ## Error Types

  Five consolidated error types cover all failure scenarios:

  | Error | Use Case |
  |-------|----------|
  | `InvalidKeyError` | Invalid public keys, signatures, or key encoding |
  | `RPCError` | RPC communication failures, timeouts, rate limits |
  | `TransactionError` | Transaction building, signing, or submission failures |
  | `IDLError` | IDL parsing or generation failures |
  | `ValidationError` | General validation failures for inputs and configs |

  ## Usage

      # Key validation errors
      ExSolana.Error.invalid_key_error("Invalid public key", key: "abc")

      # RPC errors
      ExSolana.Error.rpc_error("Network timeout", kind: :timeout)

      # Transaction errors
      ExSolana.Error.transaction_error("Signature verification failed")

      # IDL errors
      ExSolana.Error.idl_error("Invalid IDL format")

      # Validation errors
      ExSolana.Error.validation_error("Invalid parameter", field: :network)

  ## Splode Error Classes

  Errors are classified for aggregation (in order of precedence):
  - `:invalid` - Validation failures (keys, inputs, configs)
  - `:rpc` - RPC communication failures
  - `:transaction` - Transaction operation failures
  - `:idl` - IDL processing failures
  - `:internal` - Unexpected system failures
  """

  # ============================================================================
  # Splode Error Classes
  # ============================================================================

  defmodule Invalid do
    @moduledoc false
    use Splode.ErrorClass, class: :invalid
  end

  defmodule RPC do
    @moduledoc false
    use Splode.ErrorClass, class: :rpc
  end

  defmodule Transaction do
    @moduledoc false
    use Splode.ErrorClass, class: :transaction
  end

  defmodule IDL do
    @moduledoc false
    use Splode.ErrorClass, class: :idl
  end

  defmodule Internal do
    @moduledoc false
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      defexception [:message, :details]

      @impl true
      def exception(opts) do
        %__MODULE__{
          message: Keyword.get(opts, :message, "Unknown error"),
          details: Keyword.get(opts, :details, %{})
        }
      end
    end
  end

  use Splode,
    error_classes: [
      invalid: Invalid,
      rpc: RPC,
      transaction: Transaction,
      idl: IDL,
      internal: Internal
    ],
    unknown_error: Internal.UnknownError

  # ============================================================================
  # Error Structs
  # ============================================================================

  defmodule InvalidKeyError do
    @moduledoc """
    Error for invalid key operations.

    ## Fields

    - `message` - Human-readable error message
    - `key` - The invalid key value (if available)
    - `reason` - Specific reason for failure: `:decode`, `:encode`, `:length`, `:checksum`
    - `details` - Additional context
    """
    defexception [:message, :key, :reason, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            key: String.t() | nil,
            reason: :decode | :encode | :length | :checksum | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid key"),
        key: Keyword.get(opts, :key),
        reason: Keyword.get(opts, :reason),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RPCError do
    @moduledoc """
    Error for RPC communication failures.

    ## Fields

    - `message` - Human-readable error message
    - `kind` - Category: `:network`, `:timeout`, `:rate_limit`, `:response`
    - `code` - RPC error code (if available)
    - `details` - Additional context
    """
    defexception [:message, :kind, :code, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            kind: :network | :timeout | :rate_limit | :response | nil,
            code: integer() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "RPC error"),
        kind: Keyword.get(opts, :kind),
        code: Keyword.get(opts, :code),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule TransactionError do
    @moduledoc """
    Error for transaction operation failures.

    ## Fields

    - `message` - Human-readable error message
    - `phase` - Where failure occurred: `:build`, `:sign`, `:submit`, `:confirm`
    - `signature` - Transaction signature (if available)
    - `details` - Additional context
    """
    defexception [:message, :phase, :signature, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            phase: :build | :sign | :submit | :confirm | nil,
            signature: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Transaction error"),
        phase: Keyword.get(opts, :phase),
        signature: Keyword.get(opts, :signature),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule IDLError do
    @moduledoc """
    Error for IDL processing failures.

    ## Fields

    - `message` - Human-readable error message
    - `phase` - Where failure occurred: `:parse`, `:generate`
    - `program_id` - Program ID (if available)
    - `details` - Additional context
    """
    defexception [:message, :phase, :program_id, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            phase: :parse | :generate | nil,
            program_id: String.t() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "IDL error"),
        phase: Keyword.get(opts, :phase),
        program_id: Keyword.get(opts, :program_id),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule ValidationError do
    @moduledoc """
    Error for general validation failures.

    ## Fields

    - `message` - Human-readable error message
    - `field` - The invalid field name
    - `value` - The invalid value (if available)
    - `details` - Additional context
    """
    defexception [:message, :field, :value, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            field: atom() | nil,
            value: any() | nil,
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Validation failed"),
        field: Keyword.get(opts, :field),
        value: Keyword.get(opts, :value),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InternalError do
    @moduledoc """
    Error for unexpected internal failures.

    ## Fields

    - `message` - Human-readable error message
    - `details` - Additional context
    """
    defexception [:message, :details]

    @type t :: %__MODULE__{
            message: String.t(),
            details: map()
          }

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Internal error"),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  # ============================================================================
  # Error Constructors
  # ============================================================================

  @doc """
  Creates an invalid key error.

  ## Options

  - `:key` - The invalid key value
  - `:reason` - Specific reason: `:decode`, `:encode`, `:length`, `:checksum`
  - `:details` - Additional context map

  ## Examples

      invalid_key_error("Invalid base58 encoding", key: "abc")
      invalid_key_error("Key too short", reason: :length)
  """
  @spec invalid_key_error(String.t(), keyword()) :: InvalidKeyError.t()
  def invalid_key_error(message, opts \\ []) do
    InvalidKeyError.exception(
      message: message,
      key: Keyword.get(opts, :key),
      reason: Keyword.get(opts, :reason),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates an RPC error.

  ## Options

  - `:kind` - Category: `:network`, `:timeout`, `:rate_limit`, `:response`
  - `:code` - RPC error code
  - `:details` - Additional context map

  ## Examples

      rpc_error("Network timeout", kind: :timeout)
      rpc_error("Rate limited", kind: :rate_limit, code: 429)
  """
  @spec rpc_error(String.t(), keyword()) :: RPCError.t()
  def rpc_error(message, opts \\ []) do
    RPCError.exception(
      message: message,
      kind: Keyword.get(opts, :kind),
      code: Keyword.get(opts, :code),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates a transaction error.

  ## Options

  - `:phase` - Where failure occurred: `:build`, `:sign`, `:submit`, `:confirm`
  - `:signature` - Transaction signature
  - `:details` - Additional context map

  ## Examples

      transaction_error("Signature verification failed", phase: :sign)
      transaction_error("Transaction not confirmed", phase: :confirm)
  """
  @spec transaction_error(String.t(), keyword()) :: TransactionError.t()
  def transaction_error(message, opts \\ []) do
    TransactionError.exception(
      message: message,
      phase: Keyword.get(opts, :phase),
      signature: Keyword.get(opts, :signature),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates an IDL error.

  ## Options

  - `:phase` - Where failure occurred: `:parse`, `:generate`
  - `:program_id` - Program ID
  - `:details` - Additional context map

  ## Examples

      idl_error("Invalid JSON", phase: :parse)
      idl_error("Unknown type", phase: :generate, program_id: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
  """
  @spec idl_error(String.t(), keyword()) :: IDLError.t()
  def idl_error(message, opts \\ []) do
    IDLError.exception(
      message: message,
      phase: Keyword.get(opts, :phase),
      program_id: Keyword.get(opts, :program_id),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates a validation error.

  ## Options

  - `:field` - The invalid field name
  - `:value` - The invalid value
  - `:details` - Additional context map

  ## Examples

      validation_error("Invalid network", field: :network)
      validation_error("Invalid commitment level", field: :commitment, value: "invalid")
  """
  @spec validation_error(String.t(), keyword()) :: ValidationError.t()
  def validation_error(message, opts \\ []) do
    ValidationError.exception(
      message: message,
      field: Keyword.get(opts, :field),
      value: Keyword.get(opts, :value),
      details: Keyword.get(opts, :details, %{})
    )
  end

  @doc """
  Creates an internal error.

  ## Options

  - `:details` - Additional context map

  ## Examples

      internal_error("Unexpected failure")
      internal_error("Database connection failed", details: %{retry: true})
  """
  @spec internal_error(String.t(), keyword()) :: InternalError.t()
  def internal_error(message, opts \\ []) do
    InternalError.exception(
      message: message,
      details: Keyword.get(opts, :details, %{})
    )
  end
end
