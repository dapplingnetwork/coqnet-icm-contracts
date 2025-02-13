# BRIDGING (NATIVE <=> ERC20)

| Coqnet            | Native Token Remote                        |
| ----------------- | ------------------------------------------ |
| Implemenation     | 0x1C0d2019347fc55B679967cF21aaa7d7D02726A7 |
| Transparent Proxy | 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 |
| Proxy Admin       | 0xa8828b18DF7815E40B27F86f877af9B53816797b |
| Owner             | 0x6b207141f47d749321C40D023F5981fdc5E2434d |
|                   |

| C-chain           | ERC20 Token Home                           |
| ----------------- | ------------------------------------------ |
| Implemenation     | 0x1a6F3002b1340B84B6eC9454b2C6fbB18a6E8a07 |
| Transparent Proxy | 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 |
| Proxy Admin       | 0xB9aa2745920F56c268D2749fAcc99DfdFC55f8A8 |
| Owner             | 0x6b207141f47d749321C40D023F5981fdc5E2434d |
|                   |

## NATIVE REMOTE (COQNET)

### Deploy Native Remote Impl

```sh
    forge create contracts/ictt/TokenRemote/NativeTokenRemoteUpgradeable.sol:NativeTokenRemoteUpgradeable --rpc-url coqnet --private-key $PK --broadcast --constructor-args 1

```

### Deploy Proxy

```sh
   forge create lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --rpc-url coqnet --private-key $PK --broadcast --constructor-args 0x1C0d2019347fc55B679967cF21aaa7d7D02726A7 0x6b207141f47d749321C40D023F5981fdc5E2434d 0x

```

### Initialize

```sh
    cast send 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 "initialize((address,address,uint256,bytes32,address,uint8),string,uint256,uint256)" "(0xE329B5Ff445E4976821FdCa99D6897EC43891A6c, 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf, 1, 0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652, 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2,18)" COQ 1000100ether 0  --rpc-url coqnet --private-key $PK
```

### Register With Home

```sh
    cast send  0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 "registerWithHome((address,uint256))" "(0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98,0)" --rpc-url coqnet --private-key $PK
```

### Send Native

```sh
    cast send 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98 "send((bytes32,address,address,address,uint256,uint256,uint256,address))" "(0x0427d4b22a2a78bcddd456742caf91b56badbff985ee19aef14573e7343fd652, 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2, 0x38C5479620f6C2f29677F04d89E356cF6E75CFde, 0x0000000000000000000000000000000000000000, 0, 0, 10000000,0x0000000000000000000000000000000000000000)" --value 300ether --rpc-url coqnet --private-key $PK
```

## ERC20 HOME (C-CHAIN)

### Deploy ERC20 Home Impl

```sh
    forge create contracts/ictt/TokenHome/ERC20TokenHomeUpgradeable.sol:ERC20TokenHomeUpgradeable --rpc-url avax --private-key $PK --broadcast --constructor-args 1
```

### Deploy Proxy

```sh
   forge create lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy --rpc-url avax --private-key $PK --broadcast --constructor-args 0x1a6F3002b1340B84B6eC9454b2C6fbB18a6E8a07 0x6b207141f47d749321C40D023F5981fdc5E2434d 0x

```

### Initialize

```sh
    cast send 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 "initialize(address,address,uint256,address,uint8)" 0x7C43605E14F391720e1b37E49C78C4b03A488d98 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf 1 0x420FcA0121DC28039145009570975747295f2329 18 --rpc-url avax --private-key $PK
```

### Send ERC20 COQ Inu

```sh
    cast send 0x420FcA0121DC28039145009570975747295f2329 "approve(address,uint256)" 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 100ether --rpc-url avax --private-key $PK

    cast send 0x7D5041b9e8F144b2b3377A722dF5DD6eaF447cF2 "send((bytes32,address,address,address,uint256,uint256,uint256,address), uint256)" "(0x898b8aa8353f2b79ee1de07c36474fcee339003d90fa06ea3a90d9e88b7d7c33, 0x2c76Ab64981E1d4304fC064a7dC3Be4aA3266c98, 0x38C5479620f6C2f29677F04d89E356cF6E75CFde, 0x0000000000000000000000000000000000000000, 0, 0, 10000000,0x0000000000000000000000000000000000000000)" 100ether --rpc-url avax --private-key $PK
```
