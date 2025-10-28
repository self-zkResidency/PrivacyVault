## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

# ✅ PrivacyVault Deployed Successfully

---

## Deploy Details

### **Dirección del Contrato** 
`0x6EFB6d952013e9b97a756295a33F3718BD71d0b2`
[Ver en Celoscan](https://sepolia.celoscan.io/address/0x6EFB6d952013e9b97a756295a33F3718BD71d0b2#code)

### **Red: Celo Sepolia (Chain ID: 11142220)**

### **Configuración del Deploy**
- **Hub Self**: `0x16ECBA51e18a4a7e61fdC417f0d47AFEeDfbed74`
- **Scope Seed**: `nomi-money`
- **Relayer**: `0x4A3f4D82a075434b24ff2920C573C704af776f6A`
- **Owner**: `0x4A3f4D82a075434b24ff2920C573C704af776f6A`

### **Scope Hash**
`4607975776627248998301084322452715517197231780639306486488199544010280601088`

### **Verification Config ID**
`0xc0bfc2788be86217dccd2f8a595ea69d7a9ae4e39ac5cd6732946c0f38f60f1e`

### **Configuración de Verificación**
- **Países Prohibidos**: USA, IRAN, AFGHANISTAN, NORTH_KOREA
- **Edad Mínima**: 18 años
- **Verificación OFAC**: Habilitada
- **Período de Elegibilidad**: 3 días

### **Arquitectura**
- **Tipo**: Non-custodial, audit-friendly, Nightfall-oriented
- **Integración**: Nightfall 4 + Self Verification
- **Tokens**: Compatible con cualquier stablecoin
- **Flujo**: Intent-based deposit system
