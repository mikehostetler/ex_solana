### High-Level Architecture

This diagram provides an overview of the main components of the library and how they relate to each other. It shows the core data structures, communication layers (RPC, Geyser, Jito), the decoding engine, and abstractions for on-chain programs.

```mermaid
graph TD
    subgraph CoreDataStructures["Core Data Structures"]
        A[Account]
        K[Key]
        TX[Transaction]
        IX[Instruction]
    end

    subgraph CommunicationLayer["Communication Layer"]
        RPC[RPC Client]
        G[Geyser Consumer]
        J[Jito Client]
    end

    subgraph ProgramAbstractions["Program Abstractions"]
        direction LR
        P[Programs]
        SPL[SPL Token]
        Raydium[Raydium]
        Jupiter[Jupiter]
        PumpFun[Pump.fun]
    end

    subgraph DecodingEngine["Decoding Engine"]
        D[Decoder]
        IDL[IDL Parser]
        Ana[Analyzer]
        Parser[Parsers]
    end

    G --> D
    RPC --> K
    RPC --> TX
    J --> TX
    D --> Parser
    Parser --> Ana
    Ana --> P
    P --- IDL
    P --> SPL
    P --> Raydium
    P --> Jupiter
    P --> PumpFun
    TX -- contains --> IX
    IX -- uses --> A
    IX -- uses --> K

    style CoreDataStructures fill:#dae8fc,stroke:#6c8ebf,stroke-width:2px,color:#000
    style CommunicationLayer fill:#d5e8d4,stroke:#82b366,stroke-width:2px,color:#000
    style DecodingEngine fill:#ffe6cc,stroke:#d79b00,stroke-width:2px,color:#000
    style ProgramAbstractions fill:#f8cecc,stroke:#b85450,stroke-width:2px,color:#000
```

-----

### Transaction Decoding Flow

This diagram illustrates the step-by-step process of how a raw transaction from a Geyser stream is parsed, decoded, analyzed, and ultimately converted into structured, human-readable actions.

```mermaid
flowchart TD
    A[Geyser Stream<br/><i>SubscribeUpdateTransaction</i>] --> B{TxnDecoder};
    B --> C{LogParser};
    C -- Log Tree --> D{IxParser};
    B -- Decoded Transaction --> D;
    D -- Parsed Instructions --> E{IxAnalyzer};

    subgraph Program-Specific Analysis
        direction LR
        F[SPL Token Decoder]
        G[Raydium Decoder]
        H[Jupiter Decoder]
        I[...]
    end

    E -->|Program Lookup| F;
    E -->|Program Lookup| G;
    E -->|Program Lookup| H;
    E -->|Program Lookup| I;

    F -- Analyzed Action --> J{TxnActions Extractor};
    G -- Analyzed Action --> J;
    H -- Analyzed Action --> J;
    I -- Analyzed Action --> J;

    J --> K[Structured Action Structs<br/><i>e.g., TokenSwap, SolTransfer</i>];
    J --> L[Human-Readable Summary];

    style A fill:#f5f5f5,stroke:#333,stroke-width:2px,color:#000
    style K fill:#d5e8d4,stroke:#82b366,stroke-width:2px,color:#000
    style L fill:#dae8fc,stroke:#6c8ebf,stroke-width:2px,color:#000
```

