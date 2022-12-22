// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

// import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

error LimitOrder__InvalidStopLossTakeProfit();
error LimitOrder__InvalidAllowance();
error LimitOrder__DoubleOrderForTradingPairFromUser();
error LimitOrder__InvalidTradingPair();
error LimitOrder__UpKeepNotNeeded();
error LimitOrder__ZeroEthSent();

contract LimitOrder is AutomationCompatibleInterface {
    event LimitOrderPlaced(
        address indexed user,
        string indexed tradingPair,
        int256 stopLoss,
        int256 takeProfit,
        uint256 amountInWei,
        uint256 orderTimestamp
    );
    event LimitOrderCanceled(
        address indexed user,
        string indexed tradingPair,
        uint256 timestamp
    );
    event LimitOrderExpired(
        address indexed user,
        string indexed tradingPair,
        uint256 timestamp
    );
    event UserApprove(address indexed user, uint256 amount);
    event LimitOrderExecuted(
        address indexed user,
        string indexed tradingPair,
        int256 price,
        uint256 timestamp
    );

    // struct that keeps info about order characteristics
    struct OrderMetadata {
        address user;
        string tradingPair;
        int256 stopLoss;
        int256 takeProfit;
        uint256 amountInWei;
        uint256 orderTimestamp; // keep track of when order was placed and cancel it if enough time has passed
    }

    mapping(address => mapping(string => OrderMetadata)) private s_userToOrders; // user to trading pair to limit order
    mapping(address => uint256) private s_allowance; // how much in wei user allowed to spend
    OrderMetadata[] private s_orders; // array of all orders
    OrderMetadata[] private s_executedOrders; // to keep track of performUpKeep and for testing purposes

    mapping(string => AggregatorV3Interface) public s_pairsToAggregator; // addresses of price feeds
    string[] public s_tradingPairs; // array of available trading pairs
    uint256 public constant TIMELIMIT = 5 days; // how long is an order valid

    constructor() {
        setTradingPairsAndPriceFeedAddresses();
    }

    /**
     * @notice You are to set stopLoss to -1 and take profit to an almost infinite number
     * in order to say function that you don't need specified type of broker order
     * Prices are set in NOT human-readable form
     * for example 120000000000 for ETH/USD, not 1200 without decimals
     */
    function setOrder(
        string memory _tradingPair,
        int256 _stopLoss,
        int256 _takeProfit
    ) public payable {
        if (msg.value == 0) {
            revert LimitOrder__ZeroEthSent();
        }

        // check for valid trading pair from user
        if (!isTradingPairAvailable(_tradingPair)) {
            revert LimitOrder__InvalidTradingPair();
        }

        // check for appropriate allowance for limit order
        // notice: allowance is set for all limit orders from user
        if (!isEnoughAllowance(msg.sender, msg.value)) {
            revert LimitOrder__InvalidAllowance();
        }

        // check for valid stop loss (below current price) and take profit (above current price)
        if (!isValidStopLossTakeProfit(_stopLoss, _takeProfit, _tradingPair)) {
            revert LimitOrder__InvalidStopLossTakeProfit();
        }

        // checks if user wants to place order for a trading pair for which there is already an order from this user
        if (isDoubleOrderFromUser(msg.sender, _tradingPair)) {
            revert LimitOrder__DoubleOrderForTradingPairFromUser();
        }

        OrderMetadata memory newOrder = OrderMetadata(
            msg.sender,
            _tradingPair,
            _stopLoss,
            _takeProfit,
            msg.value,
            block.timestamp
        );
        // add new order
        s_userToOrders[msg.sender][_tradingPair] = newOrder;
        s_orders.push(newOrder);

        emit LimitOrderPlaced(
            msg.sender,
            _tradingPair,
            _stopLoss,
            _takeProfit,
            msg.value,
            block.timestamp
        );
    }

    /**
     * @notice get latest price from chainlink price feeds for a given trading pair
     */
    function getLatestPrice(
        string memory _tradingPair
    ) public view returns (int) {
        (, int price, , , ) = s_pairsToAggregator[_tradingPair]
            .latestRoundData();
        return price;
    }

    /**
     * @notice get number of decimals from chainlink price feeds for a given trading pair
     */
    function decimals(string memory _tradingPair) public view returns (uint8) {
        return s_pairsToAggregator[_tradingPair].decimals();
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * In order to reduce the cost of execution, all complex computation is placed in checkUpKeep
     * because it's a view function and costs no gas
     * there is link to tutorial
     * https://docs.chain.link/chainlink-automation/flexible-upkeeps
     * The main idea is do for loop on s_orders array and save indexes those need to be cancel or execute
     * in new memory array
     * Then array is passed to performUpKeep as parameter performData
     * This way we don't do for loop on huge s_orders array in performUpKeep
     * which costs a lot of gas
     * We do for loop just on small set of s_orders indexes these need to be cancel or execute
     * @return upkeepNeeded flag whether upKeep needed or not
     * @return performData abi encode pack of 2 memory arrays: indexes and flags whether order needs to be executed or cancelled
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // get number of elements requiring updates
        uint256 counter;
        for (uint256 i = 0; i < s_orders.length; i++) {
            if (
                isOrderNeedsExecution(
                    s_orders[i].user,
                    s_orders[i].tradingPair
                ) || isOrderExpired(s_orders[i].user, s_orders[i].tradingPair)
            ) {
                counter++;
            }
        }

        // initialize array of elements requiring update as long as the type of update
        uint256[] memory indexes = new uint256[](counter);
        bool[] memory needExecution = new bool[](counter);
        upkeepNeeded = false;
        uint256 indexCounter;

        for (uint256 i = 0; i < s_orders.length; i++) {
            if (
                isOrderNeedsExecution(s_orders[i].user, s_orders[i].tradingPair)
            ) {
                // if one order is met price requirements then upKeep is needed
                upkeepNeeded = true;
                // store the index which needs action as long as the action type
                indexes[indexCounter] = i;
                needExecution[indexCounter] = true;
                indexCounter++;
            } else if (
                isOrderExpired(s_orders[i].user, s_orders[i].tradingPair)
            ) {
                // if one order is expired then upKeep is needed
                upkeepNeeded = true;
                // store the index which needs action as long as the action type
                indexes[indexCounter] = i;
                needExecution[indexCounter] = false;
                indexCounter++;
            }
        }
        performData = abi.encode(indexes, needExecution);
        return (upkeepNeeded, performData);
    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * In order to reduce the cost of execution, all complex computation is placed in checkUpKeep
     * because it's a view function and costs no gas
     * there is link to tutorial
     * https://docs.chain.link/chainlink-automation/flexible-upkeeps
     * The main idea is do for loop on s_orders array and save indexes those need to be cancel or execute
     * in new memory array
     * Then array is passed to performUpKeep as parameter performData
     * This way we don't do for loop on huge s_orders array in performUpKeep
     * which costs a lot of gas
     * We do for loop just on small set of s_orders indexes these need to be cancel or execute
     * @notice Since everybody can call performUpKeep and pass any argument inside,
     * we must do some require statements in order to validate performData input
     * @param performData parameter from checkUpKeep
     * abi encode pack of 2 memory arrays: indexes and flags whether order needs to be executed or cancelled
     */
    function performUpkeep(bytes calldata performData) external override {
        /*
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert LimitOrder__UpKeepNotNeeded();
        }
        */
        (uint256[] memory indexes, bool[] memory needExecution) = abi.decode(
            performData,
            (uint256[], bool[])
        );
        // validate performData input
        require(
            indexes.length == needExecution.length,
            "arrays' lengths are not equal"
        );
        // validate upKeepNeeded
        if (indexes.length == 0) {
            revert LimitOrder__UpKeepNotNeeded();
        }

        for (uint256 i = 0; i < indexes.length; i++) {
            if (needExecution[i]) {
                // validate performData input
                require(
                    isOrderNeedsExecution(
                        s_orders[indexes[i]].user,
                        s_orders[indexes[i]].tradingPair
                    ),
                    "Provided data not correct"
                );
                executeOrder(
                    s_orders[indexes[i]].user,
                    s_orders[indexes[i]].tradingPair
                );
                emit LimitOrderExecuted(
                    s_orders[indexes[i]].user,
                    s_orders[indexes[i]].tradingPair,
                    getLatestPrice(s_orders[indexes[i]].tradingPair),
                    block.timestamp
                );
                // place element in executedOrders array for testing purposes
                s_executedOrders.push(s_orders[indexes[i]]);
            } else {
                // validate performData input
                require(
                    isOrderExpired(
                        s_orders[indexes[i]].user,
                        s_orders[indexes[i]].tradingPair
                    ),
                    "Provided data not correct"
                );
                emit LimitOrderExpired(
                    s_orders[indexes[i]].user,
                    s_orders[indexes[i]].tradingPair,
                    block.timestamp
                );
            }
        }
        // we delete order from storage variables in separate loop for comfort
        for (int256 i = int256(indexes.length - 1); i > -1; i--) {
            removeExpiredOrExecutedOrder(
                s_orders[indexes[uint256(i)]].user,
                s_orders[indexes[uint256(i)]].tradingPair,
                indexes[uint256(i)]
            );
        }
    }

    /** @dev There was no task to actually implement order executing functionality
     */
    function executeOrder(address _user, string memory _tradingPair) private {}

    /** @dev This function is called from performUpKeep
     * Function performs removing order from storage variables
     * @param index index of order in s_orders array
     */
    function removeExpiredOrExecutedOrder(
        address _user,
        string memory _tradingPair,
        uint256 index
    ) private {
        require(
            s_userToOrders[_user][_tradingPair].amountInWei != 0,
            "Order doesn't exist"
        );
        s_allowance[_user] -= s_userToOrders[_user][_tradingPair].amountInWei;
        s_userToOrders[_user][_tradingPair] = OrderMetadata(
            address(0x0),
            "",
            0,
            0,
            0,
            0
        );
        s_orders[index] = s_orders[s_orders.length - 1];
        s_orders.pop();
    }

    /**
     * @notice functionality for user to remove his order along with allowance
     */
    function removeOrder(string memory _tradingPair) public {
        require(
            s_userToOrders[msg.sender][_tradingPair].amountInWei != 0,
            "Order doesn't exist"
        );
        s_allowance[msg.sender] -= s_userToOrders[msg.sender][_tradingPair]
            .amountInWei;
        s_userToOrders[msg.sender][_tradingPair] = OrderMetadata(
            address(0x0),
            "",
            0,
            0,
            0,
            0
        );

        uint256 index = 0;
        OrderMetadata[] memory orders = s_orders;
        // for loop to find index of order and then remove it from array
        for (uint256 i = 0; i < orders.length; i++) {
            if (
                orders[i].user == msg.sender &&
                keccak256(abi.encodePacked(orders[i].tradingPair)) ==
                keccak256(abi.encodePacked(_tradingPair))
            ) {
                index = i;
            }
        }
        s_orders[index] = s_orders[s_orders.length - 1];
        s_orders.pop();

        emit LimitOrderCanceled(msg.sender, _tradingPair, block.timestamp);
    }

    /**
     * @notice this function must be called first to approve contract for limit order transaction
     * after this function user has to call setOrder function with same amount of eth sent
     * amount must be in wei
     */
    function approve(uint256 _amount) public {
        require(_amount > 0, "Allowance must be greater than zero");
        s_allowance[msg.sender] += _amount;
        emit UserApprove(msg.sender, _amount);
    }

    /** @notice function to check if order meets stop loss or take profit requirements
     * and needs to be executed
     */
    function isOrderNeedsExecution(
        address _user,
        string memory _tradingPair
    ) public view returns (bool) {
        int256 _latestPrice = getLatestPrice(_tradingPair);
        return (
            (s_userToOrders[_user][_tradingPair].stopLoss >= _latestPrice ||
                s_userToOrders[_user][_tradingPair].takeProfit <= _latestPrice)
                ? true
                : false
        );
    }

    /**
     * @notice check if order expired
     */
    function isOrderExpired(
        address _user,
        string memory _tradingPair
    ) public view returns (bool) {
        return (
            s_userToOrders[_user][_tradingPair].orderTimestamp + TIMELIMIT >
                block.timestamp
                ? true
                : false
        );
    }

    /**
     * @dev called from main function setOrder
     * function checks if user wants to place an order
     * for a trading pair for which there is already an order from this user
     */
    function isDoubleOrderFromUser(
        address _user,
        string memory _tradingPair
    ) public view returns (bool) {
        return (
            s_userToOrders[_user][_tradingPair].amountInWei == 0 ? false : true
        );
    }

    /**
     * @notice via calling this function you can check if you can set limit order for a desirable trading pair
     * @dev this function is called in getOrder function to check if user has passed valid trading pair
     */
    function isTradingPairAvailable(
        string memory _tradingPair
    ) public view returns (bool) {
        string[] memory tradingPairs = s_tradingPairs;
        for (uint i = 0; i < tradingPairs.length; i++) {
            if (
                keccak256(abi.encodePacked(tradingPairs[i])) ==
                keccak256(abi.encodePacked(_tradingPair))
            ) {
                return true;
            }
        }
        return false;
    }

    /** @notice function to validate stop loss and take profit against of current price
     */
    function isValidStopLossTakeProfit(
        int256 _stopLoss,
        int256 _takeProfit,
        string memory _tradingPair
    ) public view returns (bool) {
        int256 _latestPrice = getLatestPrice(_tradingPair);
        return (
            (_stopLoss < _latestPrice && _takeProfit > _latestPrice)
                ? true
                : false
        );
    }

    /** @notice function to check if user has enough allowance to place limit order for desirable amount of wei
     */
    function isEnoughAllowance(
        address _user,
        uint256 _value
    ) public view returns (bool) {
        uint256 totalSentEth = 0;
        string[] memory tradingPairs = s_tradingPairs;
        for (uint8 i = 0; i < tradingPairs.length; i++) {
            totalSentEth += s_userToOrders[_user][tradingPairs[i]].amountInWei;
        }
        return (s_allowance[_user] >= _value + totalSentEth ? true : false);
    }

    /**
     * @dev function is called from the constructor
     * Smart contract is designed to work on goerli testnet
     */
    function setTradingPairsAndPriceFeedAddresses() private {
        s_tradingPairs = ["BTC/ETH", "ETH/USD", "LINK/ETH"];
        s_pairsToAggregator["BTC/ETH"] = AggregatorV3Interface(
            0x779877A7B0D9E8603169DdbD7836e478b4624789
        );
        s_pairsToAggregator["ETH/USD"] = AggregatorV3Interface(
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );
        s_pairsToAggregator["LINK/ETH"] = AggregatorV3Interface(
            0xb4c4a493AB6356497713A78FFA6c60FB53517c63
        );
    }

    function getUserOrder(
        address _user,
        string memory _tradingPair
    ) public view returns (OrderMetadata memory) {
        return s_userToOrders[_user][_tradingPair];
    }

    function getAllowance(address _user) public view returns (uint256) {
        return s_allowance[_user];
    }

    function getExecutedOrder(
        uint256 _index
    ) public view returns (OrderMetadata memory) {
        return s_executedOrders[_index];
    }
}
