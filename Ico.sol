// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

contract Crowdsale {
    event Mint(address indexed to, uint256 amount);
    event Refund(address indexed to);

    string public constant NAME = "Anatoly";
    string public constant SYMBOL = "NTL";
    uint256 public immutable i_endOfIco;
    uint256 public immutable i_exchangeRate; // 1 ETH = i_exchangeRate tokens
    uint256 public immutable i_hardCap;
    uint8 public constant i_decimals = 18;

    bool public s_isIcoActive;
    uint256 private _totalSupply;
    address private immutable _owner;
    mapping(address => uint256) private _balances;

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    constructor(
        uint256 exchangeRate,
        uint32 numberOfDays,
        uint256 hardCap // sent in tokens
    ) {
        i_exchangeRate = exchangeRate;
        i_endOfIco = block.timestamp + numberOfDays * 24 * 60 * 60;
        i_hardCap = hardCap;
        s_isIcoActive = true;
        _owner = msg.sender;
    }

    /** @dev Get ETH from sender, then mint token for him, then send money to contract owner
     */
    function ico() external payable {
        require(
            _totalSupply + ((msg.value * i_exchangeRate) / i_decimals) * 18 < i_hardCap, // 18 is decimals in ETH
            "hardcap is full"
        );
        require(s_isIcoActive && block.timestamp <= i_endOfIco, "Crowdsale is off");
        _mint(msg.sender, ((msg.value * i_exchangeRate) / i_decimals) * 18);
    }

    function _mint(address sender, uint256 amount) private {
        _totalSupply += amount;
        _balances[sender] += amount;
        emit Mint(sender, amount);
    }

    /** @dev after closing ICO 10% of tokens will be send to owner
     *
     */
    function closeIco() external onlyOwner {
        require(s_isIcoActive, "It's already closed");
        s_isIcoActive = false;
        _withdraw();
        _sendTokenToOwnerAfterFinish();
    }

    function _withdraw() internal {
        (bool sent, ) = payable(_owner).call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    /** @dev although this function does not have any require and checking
     *  @dev that owner could already get 10% of hardcap after ending of crowdsale
     *  @dev since this function is private, it can only be called by function closeIco
     *  @dev which in turn have require statement preventing token team from unfair play
     */
    function _sendTokenToOwnerAfterFinish() private {
        _totalSupply += _totalSupply / 10;
        _mint(_owner, _totalSupply / 10);
        emit Mint(_owner, _totalSupply / 10);
    }

    function refund() public {
        require(_balances[msg.sender] != 0, "Your account is empty");
        require(s_isIcoActive, "ICO has ended");
        uint256 tokenAmount = _balances[msg.sender];
        _balances[msg.sender] = 0;
        _totalSupply -= tokenAmount;
        (bool sent, ) = payable(msg.sender).call{
            value: ((tokenAmount / i_exchangeRate) * i_decimals) / 18
        }("");
        require(sent, "Failed to send Ether");
        emit Refund(msg.sender);
    }

    function getBalanceOfUser(address user) public view returns (uint256) {
        return _balances[user];
    }

    function getOwner() public view returns (address) {
        return _owner;
    }

    function getTotalSupply() public view returns (uint256) {
        return _totalSupply;
    }
}
