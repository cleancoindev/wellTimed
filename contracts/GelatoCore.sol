pragma solidity ^0.5.10;

import './Interfaces/IProxyRegistry.sol';
import './Interfaces/DappSys/IDSGuardFactory.sol';
import './DappSys/DSProxy.sol';
import './DappSys/DSGuard.sol';
import './Interfaces/Triggers-Actions/IGelatoAction.sol';
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import '@openzeppelin/contracts-ethereum-package/contracts/drafts/Counters.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';


contract GelatoUserProxies is Initializable
{
    /// @dev non-deploy base contract
    constructor() internal {}

    IProxyRegistry public proxyRegistry;
    IDSGuardFactory public guardFactory;

    bytes4 public proxyExecSelector;

    function _initialize()
        internal
        initializer
    {
        /// @notice all addresses are for ROPSTEN testing
        proxyRegistry = IProxyRegistry(0x65503e9408baD6FB0B12144cBe5AF28a26169309);
        guardFactory = IDSGuardFactory(0xffaF24bf2F44689ea8Dd3AF35b32DD9cFF5cf0B6);
        proxyExecSelector = bytes4(keccak256("execute(address,bytes)"));
    }

    // _____________ Creating Gelato User Proxies 1/3 ______________________
    /// @dev requires user to have no proxy
    modifier userHasNoProxy {
        require(proxyRegistry.proxies(msg.sender) == DSProxy(0),
            "GelatoUserProxies: user already has a proxy"
        );
        _;
    }

    event LogDevirginize(address userProxy, address userProxyGuard);
    /**
     * @dev this function should be called for users that have nothing deployed yet
     * @return the address of the deployed DSProxy aka userAccount
     * @notice user EOA tx afterwards: userProxy.setAuthority(userProxyGuard)
     */
    function devirginize()
        external
        userHasNoProxy
        returns(address userProxy, address userProxyGuardAddress)
    {
        userProxy = proxyRegistry.build(msg.sender);
        DSGuard userProxyGuard = guardFactory.newGuard();
        userProxyGuard.permit(address(this), userProxy, bytes32(proxyExecSelector));
        userProxyGuard.setOwner(address(userProxy));
        userProxyGuardAddress = address(userProxyGuard);
        emit LogDevirginize(userProxy, userProxyGuardAddress);
    }

    event LogGuard(address userProxyGuard);
    /**
     * @dev this function should be called for users that have a proxy but no guard
     * @return the address of the deployed DSProxy aka userAccount
     * @notice user EOA tx afterwards: userProxy.setAuthority(userProxyGuard)
     */
    function guard()
        external
        returns(address userProxyGuardAddress)
    {
        DSProxy userProxy = proxyRegistry.proxies(msg.sender);
        require(userProxy != DSProxy(0),
            "GelatoUserProxies.guard: user has no proxy deployed -> devirginize()"
        );
        require(userProxy.authority() == DSAuthority(0),
            "GelatoUserProxies.guard: user already has a DSAuthority"
        );
        DSGuard userProxyGuard = guardFactory.newGuard();
        userProxyGuard.permit(address(this), address(userProxy), bytes32(proxyExecSelector));
        userProxyGuard.setOwner(address(userProxy));
        userProxyGuardAddress = address(userProxyGuard);
        emit LogGuard(userProxyGuardAddress);
    }

    /**
     * @dev 3rd option: user already has a DSGuard
     * => permit(gelatoCore, address(userProxy), proxyExecSelector) via frontend
     */
    // ================
}



/**
 * @title GelatoCoreAccounting
 */
contract GelatoCoreAccounting is Ownable,
                                 ReentrancyGuard
{
    /// @dev non-deploy base contract
    constructor() internal {}

    using SafeMath for uint256;

    //_____________ Gelato ExecutionClaim Economics _______________________
    mapping(address => uint256) internal userProxyDeposit;
    mapping(address => uint256) internal executorPrice;
    mapping(address => uint256) internal executorClaimLifespan;
    mapping(address => uint256) internal executorBalance;
    //_____________ Constant gas values _____________
    uint256 internal gasOutsideGasleftChecks;
    uint256 internal gasInsideGasleftChecks;
    uint256 internal canExecMaxGas;
    uint256 internal proxyExecuteGas;
    // =========================


    /**
     * @dev sets the initial gas cost values that are used by several core functions
     * param _gasOutsideGasleftChecks: gas cost to be determined and set by owner
     * param _gasInsideGasleftChecks: gas cost to be determined and set by owner
     * param _canExecMaxGas: gas cost to be determined and set by owner
     */
    function _initialize()
        internal
        initializer
    {
        Ownable.initialize(msg.sender);
        ReentrancyGuard.initialize();
        gasOutsideGasleftChecks = 40000 + 17331;
        gasInsideGasleftChecks = 100000 - gasOutsideGasleftChecks;
        canExecMaxGas = 100000;
        proxyExecuteGas = 100000;
    }

    /**
     * @dev throws if the passed address is not a registered executor
     * @param _executor: the address to be checked against executor registrations
     */
    modifier onlyRegisteredExecutors(address _executor) {
        require(executorPrice[_executor] != 0 && executorClaimLifespan[_executor] != 0,
            "GelatoCoreAccounting.onlyRegisteredExecutors: failed"
        );
        _;
    }

    // _______ Execution Gas Caps ____________________________________________
    /**
     * @dev calculates gas requirements based off _actionGasStipend
     * @param _actionGasStipend the gas forwarded with the action call
     * @return the minimum gas required for calls to gelatoCore.execute()
     */
    function _getMinExecutionGasRequirement(uint256 _actionGasStipend)
        internal
        view
        returns(uint256)
    {
        return (gasOutsideGasleftChecks
                + gasInsideGasleftChecks
                + canExecMaxGas
                + proxyExecuteGas
                .add(_actionGasStipend)
        );
    }
    /// @dev interface to internal fn _getMinExecutionGasRequirement
    function getMinExecutionGasRequirement(uint256 _actionGasStipend)
        external
        view
        returns(uint256)
    {
        return _getMinExecutionGasRequirement(_actionGasStipend);
    }
    // =======

    // _______ Important Data to be included as msg.value for minting __________
    /**
     * @dev calculates the deposit payable for minting on gelatoCore
     * @param _action the action contract to be executed
     * @param _selectedExecutor the executor that should call the action
     * @return executorFeePayable
     */
    function getMintingDepositPayable(address _action,
                                      address _selectedExecutor
    )
        external
        view
        returns(uint256 mintingDepositPayable)
    {
        uint256 actionGasStipend = IGelatoAction(_action).getActionGasStipend();
        uint256 executionMinGas = _getMinExecutionGasRequirement(actionGasStipend);
        mintingDepositPayable = executionMinGas.mul(executorPrice[_selectedExecutor]);
    }
    // =======

    // __________ Interface for State Reads ___________________________________
    function getuserProxyDeposit(address _userProxy) external view returns(uint256) {
        return userProxyDeposit[_userProxy];
    }
    function getExecutorPrice(address _executor) external view returns(uint256) {
        return executorPrice[_executor];
    }
    function getExecutorBalance(address _executor) external view returns(uint256) {
        return executorBalance[_executor];
    }
    function getGasOutsideGasleftChecks() external view returns(uint256) {
        return gasOutsideGasleftChecks;
    }
    function getGasInsideGasleftChecks() external view returns(uint256) {
        return gasInsideGasleftChecks;
    }
    function getCanExecMaxGas() external view returns(uint256) {
        return canExecMaxGas;
    }
    function getProxyExecuteGas() external view returns(uint256) {
        return proxyExecuteGas;
    }
    // =========================

    // ____________ Interface for STATE MUTATIONS ________________________________________
    //_____________ Interface for Executor __________
    event LogSetExecutorPrice(uint256 executorPrice,
                              uint256 newExecutorPrice
    );
    function setExecutorPrice(uint256 _newExecutorGasPrice)
        external
    {
        emit LogSetExecutorPrice(executorPrice[msg.sender], _newExecutorGasPrice);
        executorPrice[msg.sender] = _newExecutorGasPrice;
    }

    event LogSetExecutorClaimLifespan(uint256 executorClaimLifespan,
                                      uint256 newExecutorClaimLifespan
    );
    function setExecutorClaimLifespan(uint256 _newExecutorClaimLifespan)
        external
    {
        emit LogSetExecutorClaimLifespan(executorClaimLifespan[msg.sender],
                                         _newExecutorClaimLifespan
        );
        executorClaimLifespan[msg.sender] = _newExecutorClaimLifespan;
    }

    event LogSetExecutorBalanceWithdrawal(address indexed executor,
                                          uint256 withdrawAmount
    );
    function withdrawExecutorBalance()
        external
        nonReentrant
    {
        // Checks
        uint256 currentExecutorBalance = executorBalance[msg.sender];
        require(currentExecutorBalance > 0,
            "GelatoCoreAccounting.withdrawExecutorBalance: failed"
        );
        // Effects
        executorBalance[msg.sender] = 0;
        // Interaction
        msg.sender.transfer(currentExecutorBalance);
        emit LogSetExecutorBalanceWithdrawal(msg.sender,
                                          currentExecutorBalance
        );
    }
    // =========
}



/**
 * @title GelatoCore
 */
contract GelatoCore is GelatoUserProxies,
                       GelatoCoreAccounting
{
    ///@dev initializer/constructor fn (upgradeability)
    function initialize()
        public
        initializer
    {
        GelatoUserProxies._initialize();
        GelatoCoreAccounting._initialize();
    }

    // Unique ExecutionClaim Ids
    using Counters for Counters.Counter;

    Counters.Counter private executionClaimIds;

    function getCurrentExecutionClaimId()
        external
        view
        returns(uint256 currentId)
    {
        currentId = executionClaimIds.current();
    }

    // executionClaimId => userProxyByExecutionClaimId
    mapping(uint256 => address) private userProxyByExecutionClaimId;

    /**
     * @dev interface to read from the userProxyByExecutionClaimId state variable
     * @param _executionClaimId: the unique executionClaimId
     * @return address of userProxy whose executionClaim _executionClaimId maps to.
     */
    function getProxyWithExecutionClaimId(uint256 _executionClaimId)
        external
        view
        returns(address)
    {
        return userProxyByExecutionClaimId[_executionClaimId];
    }
    // executionClaimId => bytes32 executionClaimHash
    mapping(uint256 => bytes32) private hashedExecutionClaims;

    /**
     * @dev interface to read from the hashedExecutionClaims state variable
     * @param _executionClaimId: the unique executionClaimId
     * @return the bytes32 hash of the executionClaim with _executionClaimId
     */
    function getHashedExecutionClaim(uint256 _executionClaimId)
        external
        view
        returns(bytes32)
    {
        return hashedExecutionClaims[_executionClaimId];
    }

    // $$$$$$$$$$$ mintExecutionClaim() API  $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
    event LogNewExecutionClaimMinted(address indexed selectedExecutor,
                                     uint256 indexed executionClaimId,
                                     address indexed userProxy,
                                     bytes actionPayload,
                                     uint256 executeGas,
                                     uint256 executionClaimExpiryDate,
                                     uint256 executorFee
    );
    event LogTriggerActionMinted(uint256 indexed executionClaimId,
                                 address indexed trigger,
                                 bytes triggerPayload,
                                 address indexed action
    );

    function mintExecutionClaim(address _trigger,
                                bytes calldata _triggerPayload,
                                address _action,
                                bytes calldata _actionPayload,
                                address payable _selectedExecutor

    )
        external
        payable
        onlyRegisteredExecutors(_selectedExecutor)
        nonReentrant
    {
        // ______ Authenticate msg.sender is proxied user or their proxy _______
        address userProxy;
        {
            ///@dev check if msg.sender is a user (EOA)
            if (msg.sender == tx.origin) {
                userProxy = address(proxyRegistry.proxies(msg.sender));
                require(userProxy != address(0),
                    "GelatoCore.mintExecutionClaim: msg.sender has no proxy"
                );
            } else {
                DSProxyFactory proxyFactory
                    = DSProxyFactory(0xD105F797EDE92594Ffc1617EB3BAd7d182AeDC25);
                require(proxyFactory.isProxy(msg.sender),
                    "GelatoCore.mintExecutionClaim: msg.sender is not a proxy"
                );
                userProxy = msg.sender;
            }
        }
        // =============
        // ______ Charge Minting Deposit _______________________________________
        uint256 actionGasStipend = IGelatoAction(_action).getActionGasStipend();
        {
            uint256 executionMinGas = _getMinExecutionGasRequirement(actionGasStipend);
            uint256 executorFeePayable
                = executionMinGas.mul(executorPrice[_selectedExecutor]);
            require(msg.value == executorFeePayable,
                "GelatoCore.mintExecutionClaim: executorFeePayable failed"
            );
        }
        userProxyDeposit[userProxy] = userProxyDeposit[userProxy].add(msg.value);
        // =============
        // ______ Mint new executionClaim ______________________________________
        Counters.increment(executionClaimIds);
        uint256 executionClaimId = executionClaimIds.current();
        userProxyByExecutionClaimId[executionClaimId] = userProxy;
        // =============
        // ______ ExecutionClaim Hashing ______________________________________
        uint256 executionClaimExpiryDate
            = now.add(executorClaimLifespan[_selectedExecutor]);
        {
            // Include executionClaimId: avoid hash collisions
            bytes32 executionClaimHash
                = keccak256(abi.encodePacked(_trigger,
                                             _triggerPayload,
                                             userProxy,
                                             _actionPayload,
                                             executionClaimId,
                                             _selectedExecutor,
                                             proxyExecuteGas.add(actionGasStipend),
                                             executionClaimExpiryDate,
                                             msg.value
            ));
            hashedExecutionClaims[executionClaimId] = executionClaimHash;
        }
        // =============
        emit LogNewExecutionClaimMinted(_selectedExecutor,
                                        executionClaimId,
                                        userProxy,
                                        _actionPayload,
                                        proxyExecuteGas.add(actionGasStipend),
                                        executionClaimExpiryDate,
                                        msg.value
        );
        emit LogTriggerActionMinted(executionClaimId, _trigger, _triggerPayload, _action);
    }
    // $$$$$$$$$$$$$$$ mintExecutionClaim() API END


    // ********************* EXECUTE FUNCTION SUITE *********************
    //  checked by canExecute and returned as a uint256 from User
    enum CanExecuteCheck {
        WrongCalldataOrAlreadyDeleted,  // also returns if a not-selected executor calls fn
        UserProxyOutOfFunds,
        NonExistantExecutionClaim,
        ExecutionClaimExpired,
        TriggerReverted,
        NotExecutable,
        Executable
    }

    function _canExecute(address _trigger,
                         bytes memory _triggerPayload,
                         address _userProxy,
                         bytes memory _actionPayload,
                         uint256 _executeGas,
                         uint256 _executionClaimId,
                         uint256 _executionClaimExpiryDate,
                         uint256 _executorFee
    )
        private
        view
        returns (uint8)
    {
        // _____________ Static CHECKS __________________________________________
        // Compute executionClaimHash from calldata
        bytes32 computedExecutionClaimHash
            = keccak256(abi.encodePacked(_trigger,
                                         _triggerPayload,
                                         _userProxy,
                                         _actionPayload,
                                         _executionClaimId,
                                         msg.sender,  // selected? executor
                                         _executeGas,
                                         _executionClaimExpiryDate,
                                         _executorFee
        ));
        // Check passed calldata and that msg.sender is selected executor
        if(computedExecutionClaimHash != hashedExecutionClaims[_executionClaimId]) {
            return uint8(CanExecuteCheck.WrongCalldataOrAlreadyDeleted);
        }
        // Require user proxy to have balance to pay executor
        if (userProxyDeposit[_userProxy] < _executorFee) {
            return uint8(CanExecuteCheck.UserProxyOutOfFunds);
        }
        // Require execution claim to exist / not be cancelled
        if (userProxyByExecutionClaimId[_executionClaimId] == address(0)) {
            return uint8(CanExecuteCheck.NonExistantExecutionClaim);
        }
        if (_executionClaimExpiryDate < now) {
            return uint8(CanExecuteCheck.ExecutionClaimExpired);
        }
        // =========
        // _____________ Dynamic CHECKS __________________________________________
        // Call to trigger view function (returns(bool))
        (bool success,
         bytes memory returndata) = (_trigger.staticcall
                                             .gas(100000)
                                             (_triggerPayload)
        );
        if (!success) {
            return uint8(CanExecuteCheck.TriggerReverted);
        } else {
            bool executable = abi.decode(returndata, (bool));
            if (executable) {
                return uint8(CanExecuteCheck.Executable);
            } else {
                return uint8(CanExecuteCheck.NotExecutable);
            }
        }
        // ==============
    }
    // canExecute interface for executors
    function canExecute(address _trigger,
                        bytes calldata _triggerPayload,
                        address _userProxy,
                        bytes calldata _actionPayload,
                        uint256 _executeGas,
                        uint256 _executionClaimId,
                        uint256 _executionClaimExpiryDate,
                        uint256 _executorFee
    )
        external
        view
        returns (uint8)
    {
        return _canExecute(_trigger,
                           _triggerPayload,
                           _userProxy,
                           _actionPayload,
                           _executeGas,
                           _executionClaimId,
                           _executionClaimExpiryDate,
                           _executorFee
        );
    }

    // ********************* EXECUTE FUNCTION SUITE *************************
    event LogCanExecuteFailed(uint256 indexed executionClaimId,
                              address payable indexed executor,
                              uint256 indexed canExecuteResult
    );
    event LogExecutionResult(uint256 indexed executionClaimId,
                             bytes returndata,
                             address payable indexed executor
    );
    event LogClaimExecutedAndDeleted(uint256 indexed executionClaimId,
                                     address indexed userProxy,
                                     address payable indexed executor,
                                     uint256 gasUsedEstimate,
                                     uint256 gasPriceUsed,
                                     uint256 executionCostEstimate,
                                     uint256 executorPayout
    );

    enum ExecutionResult {
        Success,
        Failure,
        CanExecuteFailed
    }

    function execute(address _trigger,
                     bytes calldata _triggerPayload,
                     address payable _userProxy,
                     bytes calldata _actionPayload,
                     address _action,
                     uint256 _executeGas,
                     uint256 _executionClaimId,
                     uint256 _executionClaimExpiryDate,
                     uint256 _executorFee

    )
        external
        nonReentrant
        returns(uint8 executionResult)
    {
        // Ensure that executor sends enough gas for the execution
        uint256 startGas = gasleft();
        require(startGas >= _getMinExecutionGasRequirement(_executeGas),
            "GelatoCore.execute: Insufficient gas sent"
        );
        // _______ canExecute() check ______________________________________________
        {
            uint8 canExecuteResult = _canExecute(_trigger,
                                                 _triggerPayload,
                                                 _userProxy,
                                                 _actionPayload,
                                                 _executeGas,
                                                 _executionClaimId,
                                                 _executionClaimExpiryDate,
                                                 _executorFee
            );
            if (canExecuteResult != uint8(CanExecuteCheck.Executable)) {
                emit LogCanExecuteFailed(_executionClaimId,
                                         msg.sender,
                                         canExecuteResult
                );
                return uint8(ExecutionResult.CanExecuteFailed);
            }
        }
        // ========
        // _________________________________________________________________________
        // From this point on, this transaction SHOULD NOT REVERT, nor run out of gas,
        //  and the User will be charged for a deterministic gas cost

        // **** EFFECTS 1 ****
        // When re-entering, executionHash will be bytes32(0)
        delete hashedExecutionClaims[_executionClaimId];

        // _________  _action.call() _______________________________________________
        {
            bytes memory returndata = DSProxy(_userProxy).execute.gas(2000000)
                                                         (_action, _actionPayload
            );
            emit LogExecutionResult(_executionClaimId,
                                    returndata,
                                    msg.sender // executor
            );
            if (returndata.length == 0) {
                executionResult = uint8(ExecutionResult.Failure);
            } else {
                executionResult = uint8(ExecutionResult.Success);
            }
        }
        // ========
        {
            uint256 endGas = gasleft();
            // Calaculate how much gas we used up in this function.
            // executorGasRefundEstimate: factor in gas refunded via `delete` ops
            // @DEV UPDATE WITH NEW FUNC
            uint256 gasUsedEstimate = (startGas.sub(endGas)
                                               .add(gasOutsideGasleftChecks)
            );
            uint256 executionCostEstimate = gasUsedEstimate.mul(tx.gasprice);
            emit LogClaimExecutedAndDeleted(_executionClaimId,
                                            _userProxy,
                                            msg.sender,  // executor
                                            gasUsedEstimate,
                                            tx.gasprice,
                                            executionCostEstimate,
                                            _executorFee
            );
        }
        // **** EFFECTS 2 ****
        // Delete userProxy Id here, was still needed inside _userProxy.call()
        delete userProxyByExecutionClaimId[_executionClaimId];
        // Balance Updates (INTERACTIONS)
        userProxyDeposit[_userProxy] = userProxyDeposit[_userProxy].sub(_executorFee);
        executorBalance[msg.sender] = executorBalance[msg.sender].add(_executorFee);
        // ====
    }
    // ************** execute() END
    // ********************* EXECUTE FUNCTION SUITE END


    // ********************* cancelExecutionClaim() *********************
    event LogExecutionClaimCancelled(uint256 indexed executionClaimId,
                                     address indexed userProxy,
                                     address indexed cancelor
    );
    function cancelExecutionClaim(address _trigger,
                                  bytes calldata _triggerPayload,
                                  address payable _userProxy,
                                  bytes calldata _actionPayload,
                                  uint256 _executionClaimId,
                                  address payable _selectedExecutor,
                                  uint256 _executeGas,
                                  uint256 _executionClaimExpiryDate,
                                  uint256 _executorFee
    )
        external
        nonReentrant
    {
        {
            address userProxyOwner = DSProxy(_userProxy).owner();
            if (msg.sender != userProxyOwner) {
                require(_executionClaimExpiryDate <= now && msg.sender == _selectedExecutor,
                    "GelatoCore.cancelExecutionClaim: only selected executor post expiry"
                );
            }
        }
        {
            bytes32 computedExecutionClaimHash
                = keccak256(abi.encodePacked(_trigger,
                                             _triggerPayload,
                                             _userProxy,
                                             _actionPayload,
                                             _executionClaimId,
                                             _selectedExecutor,  // selected? executor
                                             _executeGas,
                                             _executionClaimExpiryDate,
                                             _executorFee
            ));
            require(computedExecutionClaimHash == hashedExecutionClaims[_executionClaimId],
                "GelatoCore.cancelExecutionClaim: hash compare failed"
            );
        }
        delete userProxyByExecutionClaimId[_executionClaimId];
        delete hashedExecutionClaims[_executionClaimId];
        emit LogExecutionClaimCancelled(_executionClaimId,
                                        _userProxy,
                                        msg.sender
        );
        msg.sender.transfer(_executorFee);
    }
    // ********************* cancelExecutionClaim() END
}