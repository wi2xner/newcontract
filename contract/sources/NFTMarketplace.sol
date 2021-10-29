//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFTMarketplace is Ownable, ERC721, ERC721Enumerable, ERC721URIStorage {
    using Address for address;
    using SafeMath for uint;
    using Counters for Counters.Counter;
    using Strings for uint;
    Counters.Counter private _tokenIds;

    ////////////////////////
    ///     VARIABLES    ///
    ////////////////////////

    /**
     *  Collection
     */
    uint public maxSupply;
    uint public reservedSupply = 0;
    uint public reservedMaxSupply;
    uint public presaleSupply = 0;
    uint public presaleMaxSupply;
    uint public price;
    uint public maxMintRequest;

    /**
     *  NFT
     */
    struct TinyBones {
        uint id;
        uint birth;
        address minter;
        string uri;
    }
    TinyBones[] public tinyBones;
    string public baseTokenURI;
    string public baseExtension;

    /**
     *  Sale
     */
    address public presalePartnersAddress;
    bool private _saleOpen = false;
    bool private _presaleOpen = false;

    /**
     *  Reflective
     */
    uint public availableFunds;
    uint public reflectionBalance;
    uint public totalDividend;
    uint public fees = 6;

    ////////////////////////
    ///    CONSTRUCTOR   ///
    ////////////////////////

    constructor(
        uint _maxSupply,
        uint _reservedMaxSupply,
        uint _presaleMaxSupply,
        uint _price,
        uint _maxMintRequest,
        string memory _baseTokenURI,
        string memory _baseExtension,
        address _presalePartnersAddress
    ) ERC721("Tiny Bones Club", "TBC") {
        maxSupply = _maxSupply;
        reservedMaxSupply = _reservedMaxSupply;
        presaleMaxSupply = _presaleMaxSupply;
        price = _price;
        maxMintRequest = _maxMintRequest;
        baseTokenURI = _baseTokenURI;
        baseExtension = _baseExtension;
        presalePartnersAddress = _presalePartnersAddress;
    }

    ////////////////////////
    ///     MAPPINGS     ///
    ////////////////////////

    /**
     *  lastDividendAt
        @dev Return dividend claimed for a token ID.
     */
    mapping(uint => uint) public lastDividendAt;

    ////////////////////////
    ///      EVENTS      ///
    ////////////////////////

    /**
     *  Mint
        @dev Emit a token id and a minter.
     */
    event Mint(uint tokenId, address to);

    ////////////////////////
    ///      PUBLIC      ///
    ////////////////////////

    /**
     *  mint
        @dev Mint a new token.
     *  @param _amount: uint | Amount to be minted.
     */
    function mint(uint _amount) public payable {
        // Get Owner
        address owner = owner();

        // Checks
        require(!Address.isContract(_msgSender()), "mint: Can't mint from a contract address.");
        require(_amount > 0, "mint: Requested mint amount must be greater than zero.");
        require(_tokenIds.current() < maxSupply, "mint: Max mint supply reached.");
        require(_amount.add(_tokenIds.current()) <= maxSupply, "mint: Requested mint amount overflows maximum mint supply.");
        if(_msgSender() != owner) {
            require(reservedSupply == reservedMaxSupply, "mint: Sale can't start untill reserved supply has been minted.");
            require(msg.value >= _amount.mul(price), "mint: Insufficient value sent.");
            require(_amount <= maxMintRequest, "mint: Requested mint amount is bigger than max authorized mint request.");
            if(_saleOpen == false) {
                // Pre-sale
                // require(_presaleOpen, "mint: Pre-sale are closed.");
                // require(presaleSupply < presaleMaxSupply, "mint: Pre-sale max mint supply reached.");
                // require(_amount.add(presaleSupply) <= presaleMaxSupply, "mint: Requested mint amount will overflow presale max mint supply.");
                // require(IERC721(presalePartnersAddress).balanceOf(_msgSender()) > 0, "mint: You are not eligible to pre-sale.");
                // presaleSupply = presaleSupply.add(_amount);
            } else {
                // Sale
                require(_saleOpen, "mint: Sales are closed.");
            }
        } else {
            // Owner reserved mint
            require(reservedSupply < reservedMaxSupply, "mint: Maximum reserved mint supply reached.");
            require(_amount.add(reservedSupply) <= reservedMaxSupply, "mint: Requested mint amount overflows reserved maximum mint supply.");
            reservedSupply = reservedSupply.add(_amount);
        }
        // Funds
        uint localfees = 0;

        // Mint
        for(uint i = 0; i < _amount; i++) {
            // Get URI
            string memory newTokenURI = string(
                abi.encodePacked(
                    baseTokenURI,
                    Strings.toString(_tokenIds.current()),
                    baseExtension
                )
            );

            // Push
            tinyBones.push(
                TinyBones(
                    _tokenIds.current(),
                    block.timestamp,
                    _msgSender(),
                    newTokenURI
                )
            );

            // Mint & Set URI
            _safeMint(_msgSender(), _tokenIds.current());
            _setTokenURI(_tokenIds.current(), newTokenURI);

            // Reflective
            if(_msgSender() != owner) {
                lastDividendAt[_tokenIds.current()] = totalDividend;
                reflectDividend((price.div(100)).mul(fees));
                localfees = localfees.add((price.div(100)).mul(fees));
            } else {
                lastDividendAt[_tokenIds.current()] = 0;
            }

            // Event
            emit Mint(_tokenIds.current(), _msgSender());

            // Increment Supply
            _tokenIds.increment();
        }

        // Update available funds
        availableFunds = availableFunds.add(msg.value.sub(localfees));
    }

    function getTinyBones(uint _tokenId) public view returns (TinyBones memory) {
        return tinyBones[_tokenId];
    }

    /**
     *  eligibleForPresale
        @dev Returns true if address is eligible for pre-sale.
     */
    function eligibleForPresale(address _minter) public view returns (bool) {
        require(IERC721(presalePartnersAddress).balanceOf(_minter) > 0, "eligibleForPresale: Not eligible for presale.");
        return true;
    }

    ////////////////////////
    ///    REFLECTIVE    ///
    ////////////////////////

    /**
     *  claimRewards
        @dev Claim available rewards based on tokens holded.
     */
    function claimRewards() public {
        require(_msgSender() != owner(),"claimRewards: Owner can't claim rewards.");
        uint count = balanceOf(_msgSender());
        uint balance = 0;
        for (uint i = 0; i < count; i++) {
            uint tokenId = tokenOfOwnerByIndex(_msgSender(), i);
            if(tokenId >= reservedMaxSupply) {
                balance = balance.add(getReflectionBalance(tokenId));
            }
            lastDividendAt[tokenId] = totalDividend;
        }
        payable(_msgSender()).transfer(balance);
    }

    /**
     *  getReflectionBalance
        @dev Check reflection balance available for a token.
     *  @param _tokenId: uint | Token to check.
     */
    function getReflectionBalance(uint _tokenId) public view returns (uint)
    {
        return totalDividend.sub(lastDividendAt[_tokenId]);
    }

    /**
     *  reflectDividend
        @dev Dispatch fees to reflection & dividend.
     *  @param _amount: uint | Amount to dispatch.
     */
    function reflectDividend(uint _amount) private {
        reflectionBalance = reflectionBalance.add(_amount);
        totalDividend = totalDividend.add(_amount.div(_tokenIds.current().sub(reservedMaxSupply).add(1)));
    }

    ////////////////////////
    ///      OWNER       ///
    ////////////////////////

    /**
     *  setSaleOpen
        @dev Set a new status for saleOpen.
     *  @param _status: bool | New status.
     */
    function setSaleOpen(bool _status) public onlyOwner {
        _saleOpen = _status;
    }

    /**
     *  setPresaleOpen
        @dev Set a new status for preSaleOpen.
     *  @param _status: bool | New status.
     */
    function setPresaleOpen(bool _status) public onlyOwner {
        _presaleOpen = _status;
    }

    /**
     *  setBaseTokenURI
        @dev Set a new base URI for tokens.
     *  @param _baseURI: string | New base URI.
     */
    function setBaseTokenURI(string memory _baseURI) public onlyOwner {
        require(_tokenIds.current() == 0, "setBaseTokenURI: Can't change URI once mint started.");
        baseTokenURI = _baseURI;
    }

    /**
     *  setPresalePartnersAddress
        @dev Set a new presale partners contract address.
     *  @param _partnersAddress: address | New partners address.
     */
    function setPresalePartnersAddress(address _partnersAddress) public onlyOwner {
        require(Address.isContract(_partnersAddress), "setPresalePartnersAddress: Must provide a valid contract address.");
        presalePartnersAddress = _partnersAddress;
    }

    /**
     *  withdrawFunds
        @dev Withdraw available contract funds or all funds to owner's address.
     *  @param _allFunds: bool | Withdraw all funds if true.
     */
    function withdrawFunds(bool _allFunds) public onlyOwner{
        if(_allFunds) {
            payable(owner()).transfer(address(this).balance);
        } else {
            uint copyAvailableFunds = availableFunds;
            availableFunds = 0;
            payable(owner()).transfer(copyAvailableFunds);
        }
    }

    ////////////////////////
    ///     OVERRIDE     ///
    ////////////////////////

    function _burn(uint tokenId)
        internal
        virtual
        override(ERC721, ERC721URIStorage)
    {
        return ERC721URIStorage._burn(tokenId);
    }

    function tokenURI(uint tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}