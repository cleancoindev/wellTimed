import React, {useContext, useEffect} from "react";

// Contexts
import { useWeb3Context } from "web3-react";
import ProxyContext from '../contexts/ProxyContext'

import { Button, makeStyles } from "@material-ui/core";
import { ethers } from "ethers";
import {
	GELATO_CORE
} from "../constants/contractAddresses";

// ABIs
import gelatoCoreABI from "../constants/ABIs/gelatoCore.json";

// Wallet Connect
import WalletConnectQRCodeModal from "@walletconnect/qrcode-modal";

const useStyles = makeStyles(theme => ({
  root: {
    display: "flex",
    justifyContent: "flex-end",
    margin: "20px 10px",
  },
  button: {
    marginRight: '5px'
  }

}));

function ConnectBtn(props) {
  const classes = useStyles();
  const context = useWeb3Context();
  const userIsRegistered = useContext(ProxyContext)
  const updateUserIsRegistered = props.updateUserIsRegistered
  const fetchExecutionClaims = props.fetchExecutionClaims

  // If wallet connect, display QR code if no connection is found
  if (context.active && context.connectorName === "WalletConnect") {
    if (!context.account) {
      WalletConnectQRCodeModal.open(
        context.connector.walletConnector.uri,
        () => {}
      );
    } else {
      try {
        WalletConnectQRCodeModal.close();
      } catch {}
    }
  }

  // Run only once
  // useEffect(() => {
  //   context.setFirstValidConnector(["MetaMask", "Infura"]);
  // }, [])

  // Run as long as context is false
  useEffect(() => {
    // Fetch Past events
    fetchExecutionClaims()
  }, [context.active])

  function LogInMetaMask() {
    return (
      <Button
        variant="contained"
        color="primary"
        className={classes.button}
        onClick={() => {
          context.setFirstValidConnector(["MetaMask"]);
        }}
      >
        Metamask
      </Button>
  );
  }

  function LogInWalletConnect() {
    return (
      <Button
        variant="contained"
        color="primary"
        className={classes.button}
        onClick={() => {

          // context.setFirstValidConnector(["MetaMask"]);
          context.setFirstValidConnector(["WalletConnect"]);
        }}
      >
        WalletConnect
      </Button>
  );
  }

  function LogOut() {
    switch(context.networkId)
    {
      // case 3:
      //   checkIfUserHasProxy()

      //   return (
      //     <Button
      //       variant="contained"
      //       color="secondary"
      //       onClick={() => {
      //         context.unsetConnector();
      //       }}
      //     >
      //       Disconnect
      //     </Button>
      //   );

      case 4:
        checkIfUserHasProxy()

        return (
          <Button
            variant="contained"
            color="secondary"
            onClick={() => {
              context.unsetConnector();
            }}
          >
            Disconnect
          </Button>
        );

      default:
        return (
          <Button
            variant="contained"
            color="secondary"
            onClick={() => {
              context.unsetConnector();
            }}
          >
            Rinkeby Network only
          </Button>
        );
    }
  }

  async function checkIfUserHasProxy() {
    const signer = context.library.getSigner();
    const gelatoCoreAddress = GELATO_CORE[context.networkId];
		const gelatoCoreContract = new ethers.Contract(
			gelatoCoreAddress,
			gelatoCoreABI,
			signer
    );
    // IF user has a proxy => DEFAULT === FALSE
    let isUser = false
    try {
      isUser = await gelatoCoreContract.isUser(context.account);
    } catch(error) {
      console.log(error)
    }
    if (isUser === false && userIsRegistered === true)
    {
      updateUserIsRegistered(false)
    }
    else if (isUser === true && userIsRegistered === false)
    {
      updateUserIsRegistered(true)
    }
  }

  return (
    <React.Fragment>
      {(context.active || (context.error && context.connectorName)) && (
        <div className={classes.root}>
          <LogOut></LogOut>
        </div>
      )}
      {!context.active && (
        <div className={classes.root}>
          <LogInMetaMask></LogInMetaMask>
          <br></br>
          <LogInWalletConnect></LogInWalletConnect>
        </div>

      )}
    </React.Fragment>
  );
}

export default ConnectBtn;
