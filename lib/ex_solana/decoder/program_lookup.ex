defmodule ExSolana.Decoder.ProgramLookup do
  # https://github.com/solana-labs/explorer/blob/master/app/utils/programs.ts
  @moduledoc false
  @program_info %{
    <<0::256>> => "System Program",
    <<1::256>> => "Vote Program",
    "11111111111111111111111111111111" => "System Program",
    "ComputeBudget111111111111111111111111111111" => "Compute Budget Program",
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" => "Token Program",
    "So11111111111111111111111111111111111111112" => "Wrapped SOL (SOL)",
    "SysvarRent111111111111111111111111111111111" => "Sysvar: Rent",
    "SysvarC1ock11111111111111111111111111111111" => "Sysvar: Clock",
    "SysvarStakeHistory1111111111111111111111111" => "Sysvar: Stake History",
    "SysvarRecentB1ockHashes11111111111111111111" => "Sysvar: Recent Blockhashes",
    "SysvarFeesxxxxxx1111111111111111111111111" => "Sysvar: Fees",
    "BPFLoader2111111111111111111111111111111111" => "BPF Loader 2",
    "srmqPvymJeFKQ4zGQed1GFppgkRHL9kaELCbyksJtPX" => "Openbook Program",
    "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8" => "Raydium AMM",
    "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL" => "Associated Token Program",
    "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr" => "Memo Program",
    "22Y43yTVxuUkoRKdm9thyRhQ3SdgQS7c7kB6UNCiaczD" => "Serum Swap Program",
    "27haf8L6oxUeXrHrgEgsexjSY5hbVUWEmvv9Nyxg8vQv" => "Raydium Liquidity Pool Program v2",
    "3XXuUFfweXBwFgFfYaejLvZE4cGZiHgKiGfMtdxNzYmv" => "Clockwork Thread Program v1",
    "9HzJyW1qZsEiSfMUf6L2jo3CcTKAyBmSyKdwQeYisHrC" => "Raydium IDO Program",
    "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP" => "Orca Swap Program v2",
    "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin" => "Serum Dex Program v3",
    "AddressLookupTab1e1111111111111111111111111" => "Address Lookup Table Program",
    "BJ3jrUzddfuSrZHXSCxMUUQsjKEyLmuuyZebkcaFp2fg" => "Serum Dex Program v1",
    "BrEAK7zGZ6dM71zUDACDqJnekihmwF15noTddWTsknjC" => "Break Solana Program",
    "CLoCKyJ6DXBJqqu2VWx9RLbgnwwR6BMHHuyasVmfMzBh" => "Clockwork Thread Program v2",
    "Config1111111111111111111111111111111111111" => "Config Program",
    "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1" => "Orca Swap Program v1",
    "EUqojwWA2rd19FZrzeBncJsm38Jm1hEhE3zsmX3bRc2o" => "Serum Dex Program v2",
    "Ed25519SigVerify111111111111111111111111111" => "Ed25519 SigVerify Precompile",
    "EhhTKczWMGQt46ynNeRX1WfeagwwJd7ufHvCDjRxjo5Q" => "Raydium Staking Program",
    "Feat1YXHhH6t1juaWF74WLcfv4XoNocjXA6sPWHNgAse" => "Feature Proposal Program",
    "KeccakSecp256k11111111111111111111111111111" => "Secp256k1 SigVerify Precompile",
    "LendZqTs7gn5CTSJU1jWKhKuVpjJGom45nnwPb2AMTi" => "Lending Program",
    "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo" => "Memo Program v1",
    "RVKd61ztZW9GUwhRbbLoYVRE5Xf1B2tVscKqwZqXgEr" => "Raydium Liquidity Pool Program v1",
    "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy" => "Stake Pool Program",
    "Stake11111111111111111111111111111111111111" => "Stake Program",
    "SwaPpA9LAaLfeLi3a68M4DjnLqgtticKg6CnyNwgAC8" => "Swap Program",
    "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" => "Token-2022 Program",
    "Vote111111111111111111111111111111111111111" => "Vote Program",
    "WvmTNLpGMVbwJVYztYL4Hnsy82cJhQorxjnnXcRm3b6" => "Serum Pool",
    "auctxRXPeJoc4817jDhf4HbjnhEcr1cCXenosMhK5R8" => "NFT Auction Program",
    "cmtDvXumGCrqC1Age74AVPhSRVXJMd8PJS91L8KbNCK" => "State Compression Program",
    "cndy3Z4yapfJBmL3ShUp5exZKqR3z33thTzeNMm2gRZ" => "NFT Candy Machine Program V2",
    "cndyAnrLdpjq1Ssp1z8xxDsB8dxe7u4HL5Nxi2K5WXZ" => "NFT Candy Machine Program",
    "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s" => "Token Metadata Program",
    "namesLPneVptA9Z5rqUDD9tMTWEJwofgaYwp8cawRkX" => "Name Service Program",
    "p1exdMJcjVao65QdewkaZRUnU6VPSXhus9n2GzWfh98" => "Metaplex Program",
    "vau1zxA2LbssAUEF7Gpw91zMM1LvXrvpzJtmZ58rPsn" => "Token Vault Program"
  }

  @doc """
  Looks up the human-friendly name for a given program ID.
  Returns the program ID if no match is found.

  ## Examples

      iex> ExSolana.Decoder.ProgramLookup.get_program_name("11111111111111111111111111111111")
      "System Program"

      iex> ExSolana.Decoder.ProgramLookup.get_program_name("UnknownProgramXXXXXXXXXXXXXXXXXXXXXXXXXX")
      "UnknownProgramXXXXXXXXXXXXXXXXXXXXXXXXXX"

  """
  @spec get_program_name(String.t()) :: String.t()
  def get_program_name(program_id) do
    Map.get(@program_info, program_id, program_id)
  end

  @doc """
  Returns a list of all known program IDs.

  ## Example

      iex> ExSolana.Decoder.ProgramLookup.list_program_ids()
      ["11111111111111111111111111111111", "22Y43yTVxuUkoRKdm9thyRhQ3SdgQS7c7kB6UNCiaczD", ...]

  """
  @spec list_program_ids() :: [String.t()]
  def list_program_ids do
    Map.keys(@program_info)
  end

  @doc """
  Returns a list of all known program names.

  ## Example

      iex> ExSolana.Decoder.ProgramLookup.list_program_names()
      ["System Program", "Serum Swap Program", ...]

  """
  @spec list_program_names() :: [String.t()]
  def list_program_names do
    Map.values(@program_info)
  end
end
