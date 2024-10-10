package local

import (
	"context"
	"crypto/ecdsa"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"math/big"
	"os"
	"slices"
	"sort"
	"time"

	"github.com/ava-labs/avalanchego/api/info"
	"github.com/ava-labs/avalanchego/config"
	"github.com/ava-labs/avalanchego/ids"
	"github.com/ava-labs/avalanchego/tests/fixture/tmpnet"
	"github.com/ava-labs/avalanchego/upgrade"
	"github.com/ava-labs/avalanchego/utils/constants"
	"github.com/ava-labs/avalanchego/utils/crypto/secp256k1"
	"github.com/ava-labs/avalanchego/vms/platformvm"
	"github.com/ava-labs/avalanchego/vms/secp256k1fx"
	pwallet "github.com/ava-labs/avalanchego/wallet/chain/p/wallet"
	"github.com/ava-labs/avalanchego/wallet/subnet/primary"
	"github.com/ava-labs/subnet-evm/accounts/abi/bind"
	"github.com/ava-labs/subnet-evm/core/types"
	"github.com/ava-labs/subnet-evm/ethclient"
	"github.com/ava-labs/subnet-evm/rpc"
	subnetEvmTestUtils "github.com/ava-labs/subnet-evm/tests/utils"
	teleportermessenger "github.com/ava-labs/teleporter/abi-bindings/go/teleporter/TeleporterMessenger"
	teleporterregistry "github.com/ava-labs/teleporter/abi-bindings/go/teleporter/registry/TeleporterRegistry"
	"github.com/ava-labs/teleporter/tests/interfaces"
	"github.com/ava-labs/teleporter/tests/utils"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/log"
	. "github.com/onsi/gomega"
)

var _ interfaces.LocalNetwork = &LocalNetwork{}

// Implements Network, pointing to the network setup in local_network_setup.go
type LocalNetwork struct {
	teleporterContractAddress common.Address
	primaryNetworkInfo        *interfaces.SubnetTestInfo
	subnetsInfo               map[ids.ID]*interfaces.SubnetTestInfo

	extraNodes []*tmpnet.Node // to add as more subnet validators in the tests

	globalFundedKey *ecdsa.PrivateKey
	pChainWallet    pwallet.Wallet

	// Internal vars only used to set up the local network
	tmpnet *tmpnet.Network
}

const (
	fundedKeyStr = "56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"
	timeout      = 120 * time.Second
)

type SubnetSpec struct {
	Name                       string
	EVMChainID                 uint64
	TeleporterContractAddress  common.Address
	TeleporterDeployedBytecode string
	TeleporterDeployerAddress  common.Address
	NodeCount                  int
}

// TODONOW: Decouple Teleporter from the network interface
func NewLocalNetwork(
	ctx context.Context,
	name string,
	warpGenesisTemplateFile string,
	subnetSpecs []SubnetSpec,
	extraNodeCount int, // for use by tests, eg to add new subnet validators
) *LocalNetwork {
	var err error

	// Create extra nodes to be used to add more validators later
	extraNodes := subnetEvmTestUtils.NewTmpnetNodes(extraNodeCount)

	var allNodes []*tmpnet.Node
	allNodes = append(allNodes, extraNodes...) // to be appended w/ subnet validators

	fundedKey, err := hex.DecodeString(fundedKeyStr)
	Expect(err).Should(BeNil())
	globalFundedKey, err := secp256k1.ToPrivateKey(fundedKey)
	Expect(err).Should(BeNil())

	globalFundedECDSAKey := globalFundedKey.ToECDSA()
	Expect(err).Should(BeNil())

	var subnets []*tmpnet.Subnet
	for _, subnetSpec := range subnetSpecs {
		nodes := subnetEvmTestUtils.NewTmpnetNodes(subnetSpec.NodeCount)
		allNodes = append(allNodes, nodes...)

		subnet := subnetEvmTestUtils.NewTmpnetSubnet(
			subnetSpec.Name,
			utils.InstantiateGenesisTemplate(
				warpGenesisTemplateFile,
				subnetSpec.EVMChainID,
				subnetSpec.TeleporterContractAddress,
				subnetSpec.TeleporterDeployedBytecode,
				subnetSpec.TeleporterDeployerAddress,
			),
			utils.WarpEnabledChainConfig,
			nodes...,
		)
		subnet.OwningKey = globalFundedKey
		subnets = append(subnets, subnet)
	}

	network := subnetEvmTestUtils.NewTmpnetNetwork(
		name,
		allNodes,
		utils.WarpEnabledChainConfig,
		subnets...,
	)
	Expect(network).ShouldNot(BeNil())

	// Activate Etna
	upgrades := upgrade.Default
	upgrades.EtnaTime = time.Now().Add(-1 * time.Minute)
	upgradeJSON, err := json.Marshal(upgrades)
	Expect(err).Should(BeNil())

	upgradeBase64 := base64.StdEncoding.EncodeToString(upgradeJSON)
	network.DefaultFlags.SetDefaults(tmpnet.FlagsMap{
		config.UpgradeFileContentKey: upgradeBase64,
	})

	avalancheGoBuildPath, ok := os.LookupEnv("AVALANCHEGO_BUILD_PATH")
	Expect(ok).Should(Equal(true))

	ctx, cancelBootstrap := context.WithCancel(ctx)
	defer cancelBootstrap()
	err = tmpnet.BootstrapNewNetwork(
		ctx,
		os.Stdout,
		network,
		"",
		avalancheGoBuildPath+"/avalanchego",
		avalancheGoBuildPath+"/plugins",
	)
	Expect(err).Should(BeNil())

	// Issue transactions to activate the proposerVM fork on the chains
	for _, subnet := range network.Subnets {
		utils.SetupProposerVM(ctx, globalFundedECDSAKey, network, subnet.SubnetID)
	}

	localNetwork := &LocalNetwork{
		primaryNetworkInfo: &interfaces.SubnetTestInfo{},
		subnetsInfo:        make(map[ids.ID]*interfaces.SubnetTestInfo),
		extraNodes:         extraNodes,
		globalFundedKey:    globalFundedECDSAKey,
		tmpnet:             network,
	}
	for _, subnet := range network.Subnets {
		localNetwork.setSubnetValues(subnet)
	}
	localNetwork.setPrimaryNetworkValues()

	// Create the P-Chain wallet to issue transactions
	kc := secp256k1fx.NewKeychain(globalFundedKey)
	localNetwork.GetSubnetsInfo()
	var subnetIDs []ids.ID
	for _, subnet := range localNetwork.GetSubnetsInfo() {
		subnetIDs = append(subnetIDs, subnet.SubnetID)
	}
	wallet, err := primary.MakeWallet(ctx, &primary.WalletConfig{
		URI:          localNetwork.GetPrimaryNetworkInfo().NodeURIs[0],
		AVAXKeychain: kc,
		EthKeychain:  kc,
		SubnetIDs:    subnetIDs,
	})
	Expect(err).Should(BeNil())
	localNetwork.pChainWallet = wallet.P()

	// TODONOW: Convert all subnets to permissionless validation

	return localNetwork
}

// Should be called after setSubnetValues for all subnets
func (n *LocalNetwork) setPrimaryNetworkValues() {
	// Get the C-Chain node URIs.
	// All subnet nodes validate the C-Chain, so we can include them all here
	var nodeURIs []string
	for _, subnetInfo := range n.subnetsInfo {
		nodeURIs = append(nodeURIs, subnetInfo.NodeURIs...)
	}
	for _, extraNode := range n.extraNodes {
		uri, err := n.tmpnet.GetURIForNodeID(extraNode.NodeID)
		Expect(err).Should(BeNil())
		nodeURIs = append(nodeURIs, uri)
	}

	cChainBlockchainID, err := info.NewClient(nodeURIs[0]).GetBlockchainID(context.Background(), "C")
	Expect(err).Should(BeNil())
	Expect(cChainBlockchainID).ShouldNot(Equal(ids.Empty))

	chainWSURI := utils.HttpToWebsocketURI(nodeURIs[0], cChainBlockchainID.String())
	chainRPCURI := utils.HttpToRPCURI(nodeURIs[0], cChainBlockchainID.String())
	if n.primaryNetworkInfo != nil && n.primaryNetworkInfo.WSClient != nil {
		n.primaryNetworkInfo.WSClient.Close()
	}
	chainWSClient, err := ethclient.Dial(chainWSURI)
	Expect(err).Should(BeNil())
	if n.primaryNetworkInfo != nil && n.primaryNetworkInfo.RPCClient != nil {
		n.primaryNetworkInfo.RPCClient.Close()
	}
	chainRPCClient, err := ethclient.Dial(chainRPCURI)
	Expect(err).Should(BeNil())
	chainIDInt, err := chainRPCClient.ChainID(context.Background())
	Expect(err).Should(BeNil())

	n.primaryNetworkInfo.SubnetID = constants.PrimaryNetworkID
	n.primaryNetworkInfo.BlockchainID = cChainBlockchainID
	n.primaryNetworkInfo.NodeURIs = nodeURIs
	n.primaryNetworkInfo.WSClient = chainWSClient
	n.primaryNetworkInfo.RPCClient = chainRPCClient
	n.primaryNetworkInfo.EVMChainID = chainIDInt

	// TeleporterMessenger is set in SetTeleporterContractAddress
	// TeleporterRegistryAddress is set in DeployTeleporterRegistryContracts
}

func (n *LocalNetwork) setSubnetValues(subnet *tmpnet.Subnet) {
	blockchainID := subnet.Chains[0].ChainID

	var chainNodeURIs []string
	for _, validatorID := range subnet.ValidatorIDs {
		uri, err := n.tmpnet.GetURIForNodeID(validatorID)
		Expect(err).Should(BeNil(), "failed to get URI for node ID %s", validatorID)
		Expect(uri).ShouldNot(HaveLen(0))
		chainNodeURIs = append(chainNodeURIs, uri)
	}

	chainWSURI := utils.HttpToWebsocketURI(chainNodeURIs[0], blockchainID.String())
	chainRPCURI := utils.HttpToRPCURI(chainNodeURIs[0], blockchainID.String())

	subnetID := subnet.SubnetID

	if n.subnetsInfo[subnetID] != nil && n.subnetsInfo[subnetID].WSClient != nil {
		n.subnetsInfo[subnetID].WSClient.Close()
	}
	chainWSClient, err := ethclient.Dial(chainWSURI)
	Expect(err).Should(BeNil())
	if n.subnetsInfo[subnetID] != nil && n.subnetsInfo[subnetID].RPCClient != nil {
		n.subnetsInfo[subnetID].RPCClient.Close()
	}
	chainRPCClient, err := ethclient.Dial(chainRPCURI)
	Expect(err).Should(BeNil())
	chainIDInt, err := chainRPCClient.ChainID(context.Background())
	Expect(err).Should(BeNil())

	// Set the new values in the subnetsInfo map
	if n.subnetsInfo[subnetID] == nil {
		n.subnetsInfo[subnetID] = &interfaces.SubnetTestInfo{}
	}
	n.subnetsInfo[subnetID].SubnetName = subnet.Name
	n.subnetsInfo[subnetID].SubnetID = subnetID
	n.subnetsInfo[subnetID].BlockchainID = blockchainID
	n.subnetsInfo[subnetID].NodeURIs = chainNodeURIs
	n.subnetsInfo[subnetID].WSClient = chainWSClient
	n.subnetsInfo[subnetID].RPCClient = chainRPCClient
	n.subnetsInfo[subnetID].EVMChainID = chainIDInt

	// TeleporterMessenger is set in SetTeleporterContractAddress
	// TeleporterRegistryAddress is set in DeployTeleporterRegistryContracts
}

func (n *LocalNetwork) deployTeleporterToChain(
	ctx context.Context,
	subnetInfo interfaces.SubnetTestInfo,
	transactionBytes []byte,
	deployerAddress common.Address,
	contractAddress common.Address,
	fundedKey *ecdsa.PrivateKey,
) {
	// Fund the deployer address
	fundAmount := big.NewInt(0).Mul(big.NewInt(1e18), big.NewInt(11)) // 11 AVAX
	fundDeployerTx := utils.CreateNativeTransferTransaction(
		ctx, subnetInfo, fundedKey, deployerAddress, fundAmount,
	)
	utils.SendTransactionAndWaitForSuccess(ctx, subnetInfo, fundDeployerTx)

	log.Info("Finished funding Teleporter deployer", "blockchainID", subnetInfo.BlockchainID.Hex())

	// Deploy Teleporter contract
	rpcClient, err := rpc.DialContext(
		ctx,
		utils.HttpToRPCURI(subnetInfo.NodeURIs[0], subnetInfo.BlockchainID.String()),
	)
	Expect(err).Should(BeNil())
	defer rpcClient.Close()

	txHash := common.Hash{}
	err = rpcClient.CallContext(ctx, &txHash, "eth_sendRawTransaction", hexutil.Encode(transactionBytes))
	Expect(err).Should(BeNil())
	utils.WaitForTransactionSuccess(ctx, subnetInfo, txHash)

	teleporterCode, err := subnetInfo.RPCClient.CodeAt(ctx, contractAddress, nil)
	Expect(err).Should(BeNil())
	Expect(len(teleporterCode)).Should(BeNumerically(">", 2)) // 0x is an EOA, contract returns the bytecode

	log.Info("Finished deploying Teleporter contract", "blockchainID", subnetInfo.BlockchainID.Hex())
}

// DeployTeleporterContractToCChain deploys the Teleporter contract to the C-Chain.
// The caller is responsible for generating the deployment transaction information
func (n *LocalNetwork) DeployTeleporterContractToCChain(
	transactionBytes []byte,
	deployerAddress common.Address,
	contractAddress common.Address,
	fundedKey *ecdsa.PrivateKey,
) {
	log.Info("Deploying Teleporter contract to C-Chain", "contractAddress", contractAddress.String())

	ctx := context.Background()
	n.deployTeleporterToChain(
		ctx,
		n.GetPrimaryNetworkInfo(),
		transactionBytes,
		deployerAddress,
		contractAddress,
		fundedKey,
	)

	log.Info("Deployed Teleporter contracts to C-Chain")
}

// DeployTeleporterContractToAllChains deploys the Teleporter contract to the C-Chain and all subnets.
// The caller is responsible for generating the deployment transaction information
func (n *LocalNetwork) DeployTeleporterContractToAllChains(
	transactionBytes []byte,
	deployerAddress common.Address,
	contractAddress common.Address,
	fundedKey *ecdsa.PrivateKey,
) {
	log.Info("Deploying Teleporter contract to C-Chain and all subnets", "contractAddress", contractAddress.String())

	ctx := context.Background()
	for _, subnetInfo := range n.GetAllSubnetsInfo() {
		n.deployTeleporterToChain(ctx, subnetInfo, transactionBytes, deployerAddress, contractAddress, fundedKey)
	}

	log.Info("Deployed Teleporter contracts to C-Chain and all subnets")
}

func (n *LocalNetwork) InitializeBlockchainIDOnAllChains(
	fundedKey *ecdsa.PrivateKey,
) {
	log.Info("Initializing blockchainID on C-Chain and all subnets")
	ctx := context.Background()
	for _, subnetInfo := range n.GetAllSubnetsInfo() {
		opts, err := bind.NewKeyedTransactorWithChainID(fundedKey, subnetInfo.EVMChainID)
		Expect(err).Should(BeNil())
		tx, err := subnetInfo.TeleporterMessenger.InitializeBlockchainID(opts)
		Expect(err).Should(BeNil())
		utils.WaitForTransactionSuccess(ctx, subnetInfo, tx.Hash())
	}
}

func (n *LocalNetwork) DeployTeleporterRegistryContracts(
	teleporterAddress common.Address,
	deployerKey *ecdsa.PrivateKey,
) {
	log.Info("Deploying TeleporterRegistry contract to subnets")
	ctx := context.Background()

	entries := []teleporterregistry.ProtocolRegistryEntry{
		{
			Version:         big.NewInt(1),
			ProtocolAddress: teleporterAddress,
		},
	}

	subnets := n.GetAllSubnetsInfo()
	for _, subnetInfo := range subnets {
		opts, err := bind.NewKeyedTransactorWithChainID(deployerKey, subnetInfo.EVMChainID)
		Expect(err).Should(BeNil())
		teleporterRegistryAddress, tx, teleporterRegistry, err := teleporterregistry.DeployTeleporterRegistry(
			opts, subnetInfo.RPCClient, entries,
		)
		Expect(err).Should(BeNil())
		// Wait for the transaction to be mined
		utils.WaitForTransactionSuccess(ctx, subnetInfo, tx.Hash())

		if subnetInfo.SubnetID == constants.PrimaryNetworkID {
			n.primaryNetworkInfo.TeleporterRegistryAddress = teleporterRegistryAddress
			n.primaryNetworkInfo.TeleporterRegistry = teleporterRegistry
		} else {
			n.subnetsInfo[subnetInfo.SubnetID].TeleporterRegistryAddress = teleporterRegistryAddress
			n.subnetsInfo[subnetInfo.SubnetID].TeleporterRegistry = teleporterRegistry
		}

		log.Info("Deployed TeleporterRegistry contract",
			"subnet", subnetInfo.SubnetID.Hex(),
			"address", teleporterRegistryAddress.Hex(),
		)
	}

	log.Info("Deployed TeleporterRegistry contracts to all subnets")
}

// Returns all subnet info sorted in lexicographic order of SubnetName.
func (n *LocalNetwork) GetSubnetsInfo() []interfaces.SubnetTestInfo {
	subnetsInfo := make([]interfaces.SubnetTestInfo, 0, len(n.subnetsInfo))
	for _, subnetInfo := range n.subnetsInfo {
		subnetsInfo = append(subnetsInfo, *subnetInfo)
	}
	sort.Slice(subnetsInfo, func(i, j int) bool {
		return subnetsInfo[i].SubnetName < subnetsInfo[j].SubnetName
	})
	return subnetsInfo
}

func (n *LocalNetwork) GetPrimaryNetworkInfo() interfaces.SubnetTestInfo {
	return *n.primaryNetworkInfo
}

// Returns subnet info for all subnets, including the primary network
func (n *LocalNetwork) GetAllSubnetsInfo() []interfaces.SubnetTestInfo {
	subnets := n.GetSubnetsInfo()
	return append(subnets, n.GetPrimaryNetworkInfo())
}

func (n *LocalNetwork) GetTeleporterContractAddress() common.Address {
	return n.teleporterContractAddress
}

func (n *LocalNetwork) SetTeleporterContractAddress(newTeleporterAddress common.Address) {
	n.teleporterContractAddress = newTeleporterAddress
	subnets := n.GetAllSubnetsInfo()
	for _, subnetInfo := range subnets {
		teleporterMessenger, err := teleportermessenger.NewTeleporterMessenger(
			n.teleporterContractAddress, subnetInfo.RPCClient,
		)
		Expect(err).Should(BeNil())
		if subnetInfo.SubnetID == constants.PrimaryNetworkID {
			n.primaryNetworkInfo.TeleporterMessenger = teleporterMessenger
		} else {
			n.subnetsInfo[subnetInfo.SubnetID].TeleporterMessenger = teleporterMessenger
		}
	}
}

func (n *LocalNetwork) GetFundedAccountInfo() (common.Address, *ecdsa.PrivateKey) {
	fundedAddress := crypto.PubkeyToAddress(n.globalFundedKey.PublicKey)
	return fundedAddress, n.globalFundedKey
}

func (n *LocalNetwork) IsExternalNetwork() bool {
	return false
}

func (n *LocalNetwork) SupportsIndependentRelaying() bool {
	// Messages can be relayed by the test application for local
	// networks with connections to each node.
	return true
}

func (n *LocalNetwork) RelayMessage(ctx context.Context,
	sourceReceipt *types.Receipt,
	source interfaces.SubnetTestInfo,
	destination interfaces.SubnetTestInfo,
	expectSuccess bool,
) *types.Receipt {
	// Fetch the Teleporter message from the logs
	sendEvent, err := utils.GetEventFromLogs(sourceReceipt.Logs, source.TeleporterMessenger.ParseSendCrossChainMessage)
	Expect(err).Should(BeNil())

	signedWarpMessage := utils.ConstructSignedWarpMessage(ctx, sourceReceipt, source, destination)

	// Construct the transaction to send the Warp message to the destination chain
	signedTx := utils.CreateReceiveCrossChainMessageTransaction(
		ctx,
		signedWarpMessage,
		sendEvent.Message.RequiredGasLimit,
		n.teleporterContractAddress,
		n.globalFundedKey,
		destination,
	)

	log.Info("Sending transaction to destination chain")
	if !expectSuccess {
		return utils.SendTransactionAndWaitForFailure(ctx, destination, signedTx)
	}

	receipt := utils.SendTransactionAndWaitForSuccess(ctx, destination, signedTx)

	// Check the transaction logs for the ReceiveCrossChainMessage event emitted by the Teleporter contract
	receiveEvent, err := utils.GetEventFromLogs(
		receipt.Logs,
		destination.TeleporterMessenger.ParseReceiveCrossChainMessage,
	)
	Expect(err).Should(BeNil())
	Expect(receiveEvent.SourceBlockchainID[:]).Should(Equal(source.BlockchainID[:]))
	return receipt
}

func (n *LocalNetwork) setAllSubnetValues() {
	subnetIDs := n.GetSubnetsInfo()
	Expect(len(subnetIDs)).Should(Equal(2))

	for _, subnetInfo := range n.subnetsInfo {
		subnet := n.tmpnet.GetSubnet(subnetInfo.SubnetName)
		Expect(subnet).ShouldNot(BeNil())
		n.setSubnetValues(subnet)
	}

	n.setPrimaryNetworkValues()
}

func (n *LocalNetwork) TearDownNetwork() {
	log.Info("Tearing down network")
	Expect(n).ShouldNot(BeNil())
	Expect(n.tmpnet).ShouldNot(BeNil())
	Expect(n.tmpnet.Stop(context.Background())).Should(BeNil())
}

func (n *LocalNetwork) AddSubnetValidators(ctx context.Context, subnetID ids.ID, count uint) {
	Expect(count > 0).Should(BeTrue(), "can't add 0 validators")
	Expect(uint(len(n.extraNodes)) >= count).Should(
		BeTrue(),
		"not enough extra nodes to use",
	)

	subnet := n.tmpnet.Subnets[slices.IndexFunc(
		n.tmpnet.Subnets,
		func(s *tmpnet.Subnet) bool { return s.SubnetID == subnetID },
	)]

	// consume some of the extraNodes
	var newValidatorNodes []*tmpnet.Node
	newValidatorNodes = append(newValidatorNodes, n.extraNodes[0:count]...)
	n.extraNodes = n.extraNodes[count:]

	apiURI, err := n.tmpnet.GetURIForNodeID(subnet.ValidatorIDs[0])
	Expect(err).Should(BeNil())

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	err = subnet.AddValidators(
		ctx,
		os.Stdout,
		apiURI,
		newValidatorNodes...,
	)
	Expect(err).Should(BeNil())

	for _, node := range newValidatorNodes {
		subnet.ValidatorIDs = append(subnet.ValidatorIDs, node.NodeID)
		node.Flags[config.TrackSubnetsKey] = subnetID.String()
	}

	tmpnet.WaitForActiveValidators(ctx, os.Stdout, platformvm.NewClient(n.tmpnet.Nodes[0].URI), subnet)

	nodeIdsToRestart := make([]ids.NodeID, len(newValidatorNodes))
	for i, node := range newValidatorNodes {
		nodeIdsToRestart[i] = node.NodeID
	}
	n.RestartNodes(ctx, nodeIdsToRestart)

	n.setAllSubnetValues()
}

// Restarts the nodes with the given nodeIDs. If nodeIDs is empty, restarts all nodes.
func (n *LocalNetwork) RestartNodes(ctx context.Context, nodeIDs []ids.NodeID) {
	log.Info("Restarting nodes", "nodeIDs", nodeIDs)
	var nodes []*tmpnet.Node
	if len(nodeIDs) == 0 {
		nodes = n.tmpnet.Nodes
	} else {
		for _, nodeID := range nodeIDs {
			for _, node := range n.tmpnet.Nodes {
				if node.NodeID == nodeID {
					nodes = append(nodes, node)
				}
			}
		}
	}

	for _, node := range nodes {
		ctx, cancel := context.WithCancel(ctx)
		defer cancel()
		err := node.SaveAPIPort()
		Expect(err).Should(BeNil())

		err = node.Stop(ctx)
		Expect(err).Should(BeNil())

		err = n.tmpnet.StartNode(ctx, os.Stdout, node)
		Expect(err).Should(BeNil())
	}

	log.Info("Waiting for all nodes to report healthy")
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	for _, node := range nodes {
		err := tmpnet.WaitForHealthy(ctx, node)
		Expect(err).Should(BeNil())
	}

	n.setAllSubnetValues()
}

func (n *LocalNetwork) SetChainConfigs(chainConfigs map[string]string) {
	for chainIDStr, chainConfig := range chainConfigs {
		if chainIDStr == utils.CChainPathSpecifier {
			var cfg tmpnet.FlagsMap
			err := json.Unmarshal([]byte(chainConfig), &cfg)
			if err != nil {
				log.Error(
					"failed to unmarshal chain config",
					"error", err,
					"chainConfig", chainConfig,
				)
			}
			n.tmpnet.ChainConfigs[utils.CChainPathSpecifier] = cfg
			continue
		}

		for _, subnet := range n.tmpnet.Subnets {
			for _, chain := range subnet.Chains {
				if chain.ChainID.String() == chainIDStr {
					chain.Config = chainConfig
				}
			}
		}
	}
	err := n.tmpnet.Write()
	if err != nil {
		log.Error("failed to write network", "error", err)
	}
	for _, subnet := range n.tmpnet.Subnets {
		err := subnet.Write(n.tmpnet.GetSubnetDir(), n.tmpnet.GetChainConfigDir())
		if err != nil {
			log.Error("failed to write subnets", "error", err)
		}
	}
}

func (n *LocalNetwork) GetNetworkID() uint32 {
	return n.tmpnet.Genesis.NetworkID
}

func (n *LocalNetwork) Dir() string {
	return n.tmpnet.Dir
}

func (n *LocalNetwork) GetPChainWallet() pwallet.Wallet {
	return n.pChainWallet
}
