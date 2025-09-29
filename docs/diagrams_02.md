### 1. High-Level Architecture

This diagram provides a top-level overview of the main components of the `ExSolana` library and how they interact with each other and the Solana blockchain.

```mermaid
graph LR
    subgraph User Application
        A[Transaction Builder] --> B{ExSolana Core};
    end

    subgraph ExSolana Library
        B --> C[RPC Client];
        B --> D[Geyser Client];
        B --> E[Jito Client];
        B --> F[WebSocket Client];

        C --> G[RPC Request Helpers & Codecs];
        D --> H[Geyser Protobuf & Broadway Pipeline];
        E --> I[Jito Protobuf & Searcher/BlockEngine Clients];
        F --> J[WebSocket Request Builder];

        K[IDL Parser] --> L[Program Decoders];
        M[Transaction Decoder] --> L;
        H --> M;
        G --> M;
    end

    subgraph External Services
        N[Solana RPC Node];
        O[Solana Geyser Plugin];
        P[Jito Block Engine];
    end

    C --> N;
    D --> O;
    E --> P;
    F --> N;

    style B fill:#f9f,stroke:#333,stroke-width:2px,color:#000
    style K fill:#ccf,stroke:#333,stroke-width:2px,color:#000
    style M fill:#ccf,stroke:#333,stroke-width:2px,color:#000
```

### 2. Directory Structure

This diagram illustrates the folder hierarchy of the `ex_solana` repository, giving a clear view of how the files are organized.

```mermaid
graph TD
    subgraph ex_solana
        core --> account.ex
        core --> block.ex
        core --> instruction.ex
        core --> key.ex
        core --> transaction.ex
        core --> tx_builder.ex

        decoder --> txn_decoder.ex
        decoder --> ix_parser.ex
        decoder --> log_parser.ex

        geyser --> yellowstone_client.ex
        geyser --> broadway_producer.ex
        geyser --> proto

        idl --> parser.ex
        idl --> generator.ex

        ix --> jupiter_swap.ex
        ix --> transfer.ex

        jito --> searcher_client.ex
        jito --> block_engine_client.ex
        jito --> proto

        programs --> program_macro.ex
        programs --> native
        programs --> spl
        programs --> raydium

        rpc --> request
        rpc --> middleware.ex
        rpc --> blockhash_server.ex

        trading --> portfolio.ex
        trading --> profit_loss.ex

        util --> helpers.ex

        websocket --> request.ex
    end
```

### 3. Transaction Building Flow

This sequence diagram shows the steps involved in creating, signing, and sending a transaction using the `Transaction.Builder`.

```mermaid
sequenceDiagram
    participant User
    participant TxBuilder as Transaction.Builder
    participant BlockhashServer
    participant RPCClient as RPC Client
    participant SolanaNode as Solana RPC Node

    User->>TxBuilder: new()
    User->>TxBuilder: payer(payer_key)
    User->>TxBuilder: add_instruction(ix1)
    User->>TxBuilder: add_signer(signer1)
    User->>TxBuilder: blockhash()
    TxBuilder->>BlockhashServer: get_latest_blockhash()
    BlockhashServer-->>TxBuilder: latest_blockhash
    User->>TxBuilder: build()
    TxBuilder->>TxBuilder: Create Transaction Struct
    TxBuilder->>TxBuilder: Validate Limits (size, accounts, etc.)
    TxBuilder->>TxBuilder: Encode to Binary
    TxBuilder-->>User: Encoded Transaction

    User->>RPCClient: send_transaction(encoded_tx)
    RPCClient->>SolanaNode: POST / (sendTransaction)
    SolanaNode-->>RPCClient: Transaction Signature
    RPCClient-->>User: Transaction Signature
```

### 4. Geyser Data Processing Pipeline

This diagram illustrates the flow of data from the Yellowstone Geyser service through the Broadway processing pipeline.

```mermaid
graph TD
    A[Yellowstone Geyser] -- gRPC Stream --> B(Geyser.Producer);
    B -- Broadway Messages --> C{CachingPipeline};

    subgraph "Broadway Processors"
        P1(Processor 1)
        P2(Processor 2)
        P3(Processor ...)
    end

    C --> P1;
    C --> P2;
    C --> P3;

    P1 -- Raw Binary Data --> D[Cache to File];
    P2 -- Raw Binary Data --> D;
    P3 -- Raw Binary Data --> D;

    style A fill:#bbf,stroke:#333,stroke-width:2px,color:#000
    style D fill:#bfb,stroke:#333,stroke-width:2px,color:#000
```

### 5. Program Interaction and Decoding

This class diagram shows the relationship between the `ProgramBehaviour` module and its various implementations for different on-chain programs. It also shows how the transaction decoder utilizes these program-specific modules.

```mermaid
classDiagram
    direction LR

    class ProgramBehaviour {
        <<Interface>>
        +id()
        +decode_ix(data)
        +decode_account(data)
        +decode_events(logs)
        +analyze_ix(invocation, txn)
    }

    class TransactionDecoder {
        +decode(transaction)
    }

    class IxAnalyzer {
        +analyze(instructions)
    }

    class SystemProgram {
        <<Program>>
    }
    class SplToken {
        <<Program>>
    }
    class AssociatedToken {
        <<Program>>
    }
    class RaydiumPoolV4 {
        <<Program>>
    }
    class JupiterSwap {
        <<Program>>
    }

    ProgramBehaviour <|-- SystemProgram
    ProgramBehaviour <|-- SplToken
    ProgramBehaviour <|-- AssociatedToken
    ProgramBehaviour <|-- RaydiumPoolV4
    ProgramBehaviour <|-- JupiterSwap

    TransactionDecoder ..> IxAnalyzer : uses
    IxAnalyzer ..> ProgramBehaviour : uses
```

### 6. Jito Bundle Submission Flow

This sequence diagram outlines the process of creating a Jito bundle and submitting it to the Jito Block Engine via the available regional clients.

```mermaid
sequenceDiagram
    participant User
    participant JitoBundle as Jito.Bundle
    participant ExSolana.Jito
    participant Jito.SearcherClient (NY)
    participant Jito.SearcherClient (AMS)
    participant Jito.SearcherClient (...)
    participant JitoBlockEngine as Jito Block Engine

    User->>JitoBundle: build([tx1, tx2])
    JitoBundle-->>User: {:ok, bundle}

    User->>ExSolana.Jito: submit_bundle(bundle)
    ExSolana.Jito->>ExSolana.Jito: Select highest priority region (e.g., NY)
    ExSolana.Jito->>Jito.SearcherClient (NY): send_bundle(bundle)
    Jito.SearcherClient (NY)->>JitoBlockEngine: gRPC SendBundle
    JitoBlockEngine-->>Jito.SearcherClient (NY): {:ok, uuid}
    Jito.SearcherClient (NY)-->>ExSolana.Jito: {:ok, uuid}
    ExSolana.Jito-->>User: {:ok, uuid}

    Note over ExSolana.Jito,JitoBlockEngine: If a region fails or is rate-limited, it tries the next one in priority order.
```
