import React, { useContext } from "react";
import { ethers } from "ethers";

// Import Components

import TimeOrderWrapper from './TimeOrderWrapper'

import { CoinProvider } from "../contexts/CoinContext";
import { coins } from '../constants/coins'



import {TimeProvider} from "../contexts/TimeContext"

import { OrderProvider } from "../contexts/OrderContext";

// Helper
import { simpleDecoder, simpleMultipleDecoder, decoder } from '../helpers'

// ABIS
import gelatoCoreABI from "../constants/ABIs/gelatoCore.json";
import proxyRegistryABI from "../constants/ABIs/proxy-registry.json";

// Import addresses
import {
	DS_PROXY_REGISTRY,
	GELATO_CORE,
	EXECUTOR
} from "../constants/contractAddresses";

import {triggerTimestampPassed} from '../constants/triggers'

// Import ContextParents
import { ProxyProvider } from "../contexts/ProxyContext";

// Context so we access the users account & provider
import { useWeb3Context } from "web3-react";


// const style = makeStyles({
//   card: {
//     margin: "25px"
//   },
//   arrow: {
//     marginTop: "20px"
//   },
//   title: {
//     textAlign: "left"
//   }
// });

function Page() {
  const context = useWeb3Context();


  // let ordersFromLocalStorage
  // if (context.active) {
  //   console.log("isActive")
  //   let fetchedLocalStorage = JSON.parse(localStorage.getItem(`triggered-${context.account}`))
  //   if (fetchedLocalStorage !== null)
  //   {
  //     ordersFromLocalStorage = fetchedLocalStorage
  //   }
  //   else {
  //     ordersFromLocalStorage = []
  //   }
  //   console.log(ordersFromLocalStorage)
  // } else {
  //   ordersFromLocalStorage = []
  // }

  // Used to display orders Table in orders
  const [orders, setOrders] = React.useState([{swap: "", when: "", status: ""}])


  const [activeCoins, setActivCoins] = React.useState({
    triggerFrom: {
      symbol: "KNC",
      name: "KyberNetwork",
      address: "0x4e470dc7321e84ca96fcaedd0c8abcebbaeb68c6",
      decimals: 18,
      id: "0x4e470dc7321e84ca96fcaedd0c8abcebbaeb68c6",
      mainnet: "0xdd974d5c2e2928dea5f71b9825b8b646686bd200",
      logo: function(address) {
        return `https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/${address}/logo.png`;
      },
      reserves_src: [
        "0x63825c174ab367968EC60f061753D3bbD36A0D8F",
        "0x21433Dec9Cb634A23c6A4BbcCe08c83f5aC2EC18",
        "0xD6000fda0b38f4Bff4CfAb188E0bd18e8725a5e7",
        "0xA467b88BBF9706622be2784aF724C4B44a9d26F4"
      ],
      reserves_dest: [
        "0x63825c174ab367968EC60f061753D3bbD36A0D8F",
        "0x21433Dec9Cb634A23c6A4BbcCe08c83f5aC2EC18",
        "0xD6000fda0b38f4Bff4CfAb188E0bd18e8725a5e7",
        "0xA467b88BBF9706622be2784aF724C4B44a9d26F4"
      ]
    },
    triggerTo: "",
    actionFrom: {
      symbol: "LINK",
      name: "Chain Link",
      address: "0xb4f7332ed719eb4839f091eddb2a3ba309739521",
      decimals: 18,
      id: "0xb4f7332ed719eb4839f091eddb2a3ba309739521",
      mainnet: "0x514910771af9ca656af840dff83e8264ecf986ca",
      reserves_src: ["0xEB52Ce516a8d054A574905BDc3D4a176D3a2d51a"],
      reserves_dest: ["0xEB52Ce516a8d054A574905BDc3D4a176D3a2d51a"],
      logo: function(address) {
        return `https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/${address}/logo.png`;
      }},
    actionTo: {
      symbol: "KNC",
      name: "KyberNetwork",
      address: "0x4e470dc7321e84ca96fcaedd0c8abcebbaeb68c6",
      decimals: 18,
      id: "0x4e470dc7321e84ca96fcaedd0c8abcebbaeb68c6",
      logo: function(address) {
        return `https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/${address}/logo.png`;
      },
      reserves_src: [
        "0x63825c174ab367968EC60f061753D3bbD36A0D8F",
        "0x21433Dec9Cb634A23c6A4BbcCe08c83f5aC2EC18",
        "0xD6000fda0b38f4Bff4CfAb188E0bd18e8725a5e7",
        "0xA467b88BBF9706622be2784aF724C4B44a9d26F4"
      ],
      reserves_dest: [
        "0x63825c174ab367968EC60f061753D3bbD36A0D8F",
        "0x21433Dec9Cb634A23c6A4BbcCe08c83f5aC2EC18",
        "0xD6000fda0b38f4Bff4CfAb188E0bd18e8725a5e7",
        "0xA467b88BBF9706622be2784aF724C4B44a9d26F4"
      ]
    }
  });
  const [selectedTokenDetails, setSelectedTokenDetails] = React.useState({needAllowance: false, sufficientBalance: false})

  // Used for checking if user has a proxy + guard contract(3), proxy contract (2), or no proxy contract at all (1) - default (0)
  const [proxyStatus, setProxyStatus] = React.useState(0);

  const [time, setTime] = React.useState({
    numOrders: 2,
    intervalTime: 10,
    intervalType: 'minutes'
  });

  const timePackage = {time, setTime}

  function updateProxyStatus(newProxyStatus) {
    // console.log(`Setting new Proxy Status in Page.js`);
    // console.log(`${newProxyStatus}`);
    setProxyStatus(newProxyStatus);
  }

  function updateActiveCoins(coins) {
    // console.log(`Setting coins in Page.js`);
    // console.log(`${coins}`);
    setActivCoins(coins);
  }

  function updateSelectedTokenDetails(newSelectedTokenDetails) {
    // console.log(`Updating Selected Token Details`);
    // console.log(`${newSelectedTokenDetails}`);
    setSelectedTokenDetails(newSelectedTokenDetails)
  }

  function createRows(
		actionSellToken,
		actionBuyToken,
		actionSellAmount,
		timestamp
	) {

    let actionSellTokenSymbol
    let actionBuyTokenSymbol
    let decimals


    actionSellToken = ethers.utils.getAddress(actionSellToken)
    actionBuyToken = ethers.utils.getAddress(actionBuyToken)
    // console.log(coins[3])
    coins[3].forEach(coin => {
      let coinAddress = ethers.utils.getAddress(coin.address)
      if (coinAddress === actionSellToken) {
        actionSellTokenSymbol = coin.symbol
        decimals = coin.decimals
      }
      else if (coinAddress === actionBuyToken) {
        actionBuyTokenSymbol = coin.symbol
      }
    })


    let orderCopy = [...orders];


    let date = new Date(timestamp * 1000);
    const timestampString = `${date.toLocaleDateString()} - ${date.toLocaleTimeString()}`;

    let userfriendlyAmount = ethers.utils.formatUnits(actionSellAmount, decimals)

    const newOrder = {
      swap: `${actionSellTokenSymbol.toString()} ${userfriendlyAmount.toString()} => ${actionBuyTokenSymbol.toString()}`,
      when: timestampString,
      status: "open"
    };

    return newOrder

    }

  async function fetchExecutionClaims() {
    if (context.active) {

      const signer = context.library.getSigner()
      const gelatoCoreAddress = GELATO_CORE[context.networkId]
      const gelatoCore = new ethers.Contract(gelatoCoreAddress, gelatoCoreABI, signer)

      const proxyRegistryAddress = DS_PROXY_REGISTRY[context.networkId];
      const proxyRegistryContract = new ethers.Contract(
        proxyRegistryAddress,
        proxyRegistryABI,
        signer
      );

      const proxyAddress = await proxyRegistryContract.proxies(
        context.account
      );

      // Create Filter
      let topic1 = ethers.utils.id(gelatoCore.interface.events.LogNewExecutionClaimMinted.signature);
      let topic2 = ethers.utils.id(gelatoCore.interface.events.LogTriggerActionMinted.signature);
      let topic3 = ethers.utils.id('LogClaimExecutedBurnedAndDeleted(uint256,address,address,uint256,uint256,uint256,uint256)');

      let abi1 = [
        "event LogNewExecutionClaimMinted(address indexed selectedExecutor, uint256 indexed executionClaimId, address indexed userProxy, bytes executePayload, uint256 executeGas, uint256 executionClaimExpiryDate, uint256 executorFee)"
      ];
      let abi2 = [
        "event LogTriggerActionMinted(uint256 indexed executionClaimId, address indexed trigger, bytes triggerPayload, address indexed action)"
      ];
      let abi3 = [
        "event LogClaimExecutedBurnedAndDeleted(uint256 indexed executionClaimId, address indexed userProxy, address indexed executor, uint256 gasUsedEstimate, uint256 gasPriceUsed, uint256 executionCostEstimate, uint256 executorPayout)"
      ];


      let iface1 = new ethers.utils.Interface(abi1)
      let iface2 = new ethers.utils.Interface(abi2)
      let iface3 = new ethers.utils.Interface(abi3)

      const filter1 = {
        address: gelatoCoreAddress,
        fromBlock: 6660070,
        topics: [topic1]
      };

      const filter2 = {
        address: gelatoCoreAddress,
        fromBlock: 6660070,
        topics: [topic2]
      };

      const filter3 = {
        address: gelatoCoreAddress,
        fromBlock: 6660070,
        topics: [topic3]
      };

      const userLogs1 = []

      const logs1 = await signer.provider.getLogs(filter1);
      logs1.forEach((log) => {
        let returnedLog = iface1.parseLog(log)
        // console.log(returnedLog)
        let values = returnedLog.values;
        if (values[2] === proxyAddress) {
          userLogs1.push(values)
        }
        // Do something with decoded data
      });



      const userLogs2 = []

      const logs2 = await signer.provider.getLogs(filter2);
      logs2.forEach((log) => {
        userLogs1.forEach(log2 => {
          let returnedLog = iface2.parseLog(log)
          // console.log(returnedLog)
          let values = returnedLog.values;

          if (values[0].eq(log2[1])) {
            let combinedEvent = [values, log2]
            userLogs2.push(combinedEvent)
          }

        })
        // Do something with decoded data
      });

      // Minted execution claims of user

      // Now check which one already got executed
      const userLogs3 = []

      const logs3 = await signer.provider.getLogs(filter3);
      logs3.forEach((log) => {
        userLogs2.forEach(log2 => {
          let returnedLog = iface3.parseLog(log)
          // console.log(returnedLog)
          let values = returnedLog.values;
          if (!values[0].eq(log2[0][0])) {
            let combinedEvent = [values, log2]
            userLogs3.push(combinedEvent)
          }
      });
      })


      const userOrders = []
      if (userLogs3.length === 0 && userLogs2.length > 0)
      {
        userLogs2.forEach(claim => {
          let triggerPayload = claim[0].triggerPayload

          // WHEN:
          let decodedTimestamp = simpleDecoder(triggerPayload, triggerTimestampPassed.dataTypes)

          // SWAP:
          let actionPayload = claim[1][3].toString()
          let dataTypes = ['address', 'address', 'address', 'uint256', 'uint256']
          // let decodedAction = simpleMultipleDecoder(actionPayload, dataTypes)
          try {
            let decodedAction = decoder(actionPayload, dataTypes)
            let order = {when: decodedTimestamp, swap: decodedAction, status: 'open'}
            userOrders.push(order)
          } catch(err)
          {
            console.log(err)
          }


        })

      }
      else {
        // console.log("Logs3")
        // console.log(userLogs3)
      }
      // Store in orders
      let orderCopy = [...orders];

      userOrders.forEach(order => {
        let newOrder = createRows(order.swap[1], order.swap[2], order.swap[3], order.when)
        orderCopy.push(newOrder)
      })

      return setOrders(orderCopy)

  }
  }

  const ordersContext = {
    orders: orders,
    fetchExecutionClaims: fetchExecutionClaims,
    setOrders: setOrders
  }

  // function updateRows(newRows) {
  //   setRows(newRows)
  // }


  // function fetchOrderFromLocalStorage() {
  //   console.log("fetchOrderFromLocalStorage")
  //   if (localStorage.getItem(`triggered-${context.account}`) !== null) {
  //     const ordersInStorage = localStorage.getItem(`triggered-${context.account}`)
  //     return(ordersInStorage)

  //   }
  // }
  return (
    <React.Fragment>
      <ProxyProvider value={proxyStatus}>
        <CoinProvider value={activeCoins}>
          <OrderProvider value={ordersContext}>
            <TimeProvider value={timePackage}>
              <TimeOrderWrapper proxyStatus={proxyStatus} networkId={context.networkId} updateProxyStatus={updateProxyStatus} updateSelectedTokenDetails={updateSelectedTokenDetails} selectedTokenDetails={selectedTokenDetails} updateActiveCoins={updateActiveCoins} fetchExecutionClaims={fetchExecutionClaims} >
              </TimeOrderWrapper>
            </TimeProvider>
          </OrderProvider>
        </CoinProvider>
      </ProxyProvider>
    </React.Fragment>
  );
}

export default Page;
