
### 7\. WebSocket Subscription Flow

This sequence diagram details the process of a user subscribing to on-chain events, like account updates or log messages, via the WebSocket client. It shows the initial subscription request and the subsequent asynchronous notifications from the Solana node.

```mermaid
sequenceDiagram
    participant User
    participant WSClient as WebSocket Client
    participant SolanaNode as Solana WS Node

    User->>WSClient: subscribe_account(pubkey)
    WSClient->>SolanaNode: Send JSON-RPC Request (e.g., accountSubscribe)
    SolanaNode-->>WSClient: {"jsonrpc":"2.0","result":12345,"id":1} (Subscription ID)
    WSClient-->>User: {:ok, subscription_id}

    loop Asynchronous Notifications
        SolanaNode-->>WSClient: Notification (Account Data Update)
        WSClient->>WSClient: Decode and Format Notification
        WSClient-->>User: Push Message to User's Process
    end

    User->>WSClient: unsubscribe(subscription_id)
    WSClient->>SolanaNode: Send JSON-RPC Request (e.g., accountUnsubscribe)
    SolanaNode-->>WSClient: {"jsonrpc":"2.0","result":true,"id":2}
    WSClient-->>User: :ok
```

-----

### 8\. IDL to Elixir Module Generation

This diagram illustrates the workflow of the IDL parser and code generator. It shows how a Solana program's IDL (in JSON format) is processed to automatically generate a corresponding Elixir module, complete with type definitions and instruction encoders/decoders. This is a crucial part of the developer experience for integrating new programs.

```mermaid
graph LR
    subgraph Input
        A[Anchor IDL JSON File]
    end

    subgraph "ExSolana.IDL"
        B(Parser) -- reads --> A;
        B -- parsed AST --> C(Generator);
    end

    subgraph "Code Generation"
        C -- generates --> D{Elixir Module};
    end

    subgraph "Generated Module (`lib/ex_solana/programs/my_program.ex`)"
        D --> E[Program ID & Address];
        D --> F[Structs for Accounts & Types];
        D --> G[Functions to Build Instructions];
        D --> H[Decoder for Instructions & Events];
    end

    style A fill:#f9f,stroke:#333,stroke-width:2px,color:#000
    style D fill:#ccf,stroke:#333,stroke-width:2px,color:#000
```

-----

### 9\. RPC Request Middleware Pipeline

This diagram shows how an RPC request passes through a series of middleware modules before being sent to the Solana node. This architecture allows for cross-cutting concerns like caching, retries, and logging to be handled in a clean, composable way.

```mermaid
graph TD
    A[User calls `RPC.get_account_info`] --> B{Middleware Pipeline};

    subgraph "Middleware Pipeline"
        direction LR
        B -- request --> M1(Cache Middleware);
        M1 -- request --> M2(Retry Middleware);
        M2 -- request --> M3(Logger Middleware);
        M3 -- request --> Client(HTTPoison Client);

        Client -- response --> M3;
        M3 -- response --> M2;
        M2 -- response --> M1;
        M1 -- response --> B;
    end

    M1 -- Cache Hit --> B;
    Client -- sends HTTP POST --> E[Solana RPC Node];

    B -- result --> F[User receives result];

    style M1 fill:#bbf,stroke:#333,stroke-width:1px,color:#000
    style M2 fill:#bfb,stroke:#333,stroke-width:1px,color:#000
    style M3 fill:#fbb,stroke:#333,stroke-width:1px,color:#000
```


Of course. The two diagrams you created provide an excellent high-level overview and a detailed look into the transaction decoding pipeline. To complement them, here are two more diagrams that illustrate other crucial aspects of the `ex_solana` library: the **RPC request lifecycle** and the **IDL-to-code generation process**.

### 1. RPC Request Lifecycle

This sequence diagram details how the library handles an outgoing RPC request, such as fetching an account balance. It illustrates the flow through the middleware stack, including how the optional caching layer intercepts requests to avoid redundant network calls.

```mermaid
sequenceDiagram
    actor User
    participant RPC as ExSolana.RPC
    participant Middleware as RPC.Middleware
    participant Cache as RPC.RequestCache
    participant Tesla
    participant SolanaNode as Solana RPC Node

    User->>RPC: send(client, Request.get_balance(address))
    RPC->>RPC: encode(request)
    RPC->>Tesla: post("/", encoded_request)

    Tesla->>Cache: call(env, next)
    alt Cache Hit
        Cache->>Cache: Read from file (e.g., priv/rpc_cache/...)
        Cache-->>Tesla: {:ok, cached_response}
    else Cache Miss
        Cache->>Middleware: call(env, next)
        Middleware->>Tesla: run(env, next)
        Tesla->>SolanaNode: HTTP POST Request
        SolanaNode-->>Tesla: JSON RPC Response
        Tesla-->>Middleware: {:ok, http_response}
        Middleware->>Middleware: Decode B58, Extract result
        Middleware-->>Cache: {:ok, processed_response}
        Cache->>Cache: Write to file
        Cache-->>Tesla: {:ok, processed_response}
    end

    Tesla-->>RPC: {:ok, final_response}
    RPC-->>User: {:ok, balance}
```

### 2. IDL-to-Code Generation Workflow

This flowchart explains the process of converting a Solana program's IDL (Interface Definition Language) from a JSON file into structured, usable Elixir modules. This is a key feature for developers building on top of `ExSolana`, as it automates the creation of program-specific decoders and analyzers.

```mermaid
graph TD
    A[IDL JSON File<br/><i>e.g., raydium_amm.json</i>] --> B(IDL.Parser);
    B -- Parses --> C[Core IDL Struct<br/><i>%ExSolana\.IDL\.Core</i>];
    C --> D{ProgramBehaviour Macro};

    subgraph "Code Generation via Macros"
        D --> E[GenerateIXDecoders];
        D --> F[GenerateAccountDecoders];
        D --> G[GenerateEventDecoders];
        D --> H[GenerateInvocationAnalyzers];
        D --> I[GenerateConstants];
    end

    E -- Emits Code --> J((Generated Elixir Module));
    F -- Emits Code --> J;
    G -- Emits Code --> J;
    H -- Emits Code --> J;
    I -- Emits Code --> J;

    J --> K[Written to File<br/><i>e.g., lib/ex_solana/programs/raydium_poolV4.ex</i>];

    style A fill:#f8cecc,stroke:#b85450,stroke-width:2px,color:#000
    style C fill:#fff2cc,stroke:#d6b656,stroke-width:2px,color:#000
    style K fill:#d5e8d4,stroke:#82b366,stroke-width:2px,color:#000
```