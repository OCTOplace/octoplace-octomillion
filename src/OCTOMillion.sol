// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC4907.sol";
import "./SpotWithOwner.sol";
import "./IOneMio721.sol";

/*
   (\(\ 
   ( -.-)    —  Made by Omsify
   o_(")(")
*/

/// @audit IMPORTANT! After ERC721 transfer remove the token from marketplace to prevent renting scams.

/// @author Omsify
/// @title OCTOMillion
/// @notice ThetaMillion contract with OCTO extension to claim and rent.
/// @dev First the users of ThetaMillion can claim the spots equal to their ones on this board.
/// @dev After the contract owner starts the public sale, users can only buy new spots, claiming is closed.
contract OCTOMillion is ERC4907 {
    struct RentalOffer {
        uint256 tokenId;
        uint256 price;
        uint64 rentTime;
        address payable owner;
        bool isActive;
    }

    /* = ThetaMillion storage variables = */
    uint public constant weiPixelPrice = 1000000000000000000; // 1 -> 1000000000000000000
    uint public constant pixelsPerCell = 400; // 20x20
    bool[50][50] public grid; // grid of taken spots

    // can withdraw the funds
    address internal contractOwner;
    address payable withdrawWallet;
    Spot[] public spots;

    /* = OCTOMillion storage variables = */
    /// @dev Update to valid link.
    string constant SPOT_BASE_URI = "https://nft.thetamillion.com/spot";
    IOneMio721 private thetaMillion;

    // If false, only ThetaMillion NFT holders can claim their token.
    bool private isOnSale = false;

    /// @dev Is equal spot (by tokenId) of ThetaMilion already claimed
    /// @dev from this contract?
    mapping(uint256 => bool) isSpotClaimed;

    // Rental marketplace
    mapping(uint256 => RentalOffer) private idToRentalOffer;

    // ThetaMillion
    event ThetaMillionPublish(
        uint indexed id,
        address indexed owner,
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string title,
        string image,
        string link,
        bool update
    );

    // OCTOMillion
    event RentalOfferCreated(
        uint256 indexed tokenId,
        uint256 price,
        uint64 rentTime,
        address nftOwner
    );
    event RentalOfferCancelled(uint256 indexed tokenId, address nftOwner);
    event RentalOfferFulfilled(
        uint256 indexed tokenId,
        uint256 price,
        address nftOwner,
        address newUser
    );

    /// @dev Allow function call only IF:
    /// @dev IF tokenId has ERC4907 user: msg.sender is the user
    /// @dev ELSE: msg.sender is tokenId owner.
    modifier onlyUserOrOwner(uint256 tokenId) {
        if (userOf(tokenId) != address(0)) // There is current NFT user
        {
            require(
                msg.sender == userOf(tokenId),
                "You're not the user of NFT"
            );
        }
        // There is no current NFT user
        else {
            require(
                msg.sender == ERC721.ownerOf(tokenId),
                "You're not the owner of NFT"
            );
        }
        _;
    }

    constructor(
        address _contractOwner,
        address payable _withdrawWallet,
        IOneMio721 _thetaMillion
    ) ERC4907("OctoMillion", "OM") {
        require(_contractOwner != address(0));
        require(_withdrawWallet != address(0));
        require(address(_thetaMillion) != address(0));

        contractOwner = _contractOwner;
        withdrawWallet = _withdrawWallet;

        thetaMillion = _thetaMillion;
    }

    function tokenURI(
        uint tokenId
    ) public view override returns (string memory) {
        Spot storage spot = spots[tokenId];
        return
            string(
                abi.encodePacked(
                    _baseURI(),
                    "-",
                    Strings.toString(tokenId),
                    "-",
                    Strings.toString(spot.x),
                    "-",
                    Strings.toString(spot.y),
                    "-",
                    Strings.toString(spot.width),
                    "-",
                    Strings.toString(spot.height),
                    ".json"
                )
            );
    }

    function getSpot(
        uint tokenId
    ) public view returns (SpotWithOwner memory spotInfo) {
        Spot storage spot = spots[tokenId];
        spotInfo = SpotWithOwner(spot, ERC721.ownerOf(tokenId));
        return spotInfo;
    }

    function getSpotsLength() public view returns (uint) {
        return spots.length;
    }

    /// @dev Buy spot
    /// @notice It should be sale period and the spot shouldn't be bought yet.
    function buySpot(
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link
    ) public payable virtual returns (uint256 createdTokenId) {
        require(isOnSale, "It's not sale period yet");

        uint cost = uint256(width) *
            uint256(height) *
            pixelsPerCell *
            weiPixelPrice;
        require(cost > 0, "Width and height should be > 0");
        require(msg.value >= cost, "Not enough ether sent");

        createdTokenId = _createNewSpot(
            x,
            y,
            width,
            height,
            title,
            image,
            link
        );

        return createdTokenId;
    }

    /// @dev ThetaMillion users are able to claim equal spot on
    /// @dev Octoplace when it's not sale period yet
    function claimSpot(
        uint256 tokenId
    ) external returns (uint256 createdTokenId) {
        require(!isOnSale, "Claim period already ended");
        require(!isSpotClaimed[tokenId], "This spot is already claimed");
        require(
            msg.sender == thetaMillion.ownerOf(tokenId),
            "You're not the token owner"
        );

        isSpotClaimed[tokenId] = true;

        SpotWithOwner memory spotToClaim = thetaMillion.getSpot(tokenId);

        // Sends the new spot to msg.sender
        createdTokenId = _createNewSpot(
            spotToClaim.spot.x,
            spotToClaim.spot.y,
            spotToClaim.spot.width,
            spotToClaim.spot.height,
            spotToClaim.spot.title,
            spotToClaim.spot.image,
            spotToClaim.spot.link
        );

        return createdTokenId;
    }

    /// @dev sets public sale status.
    /// @param status — new public sale status.
    function setSaleStatus(bool status) external {
        require(msg.sender == contractOwner);
        isOnSale = status;
    }

    function updateSpot(
        uint tokenId,
        string memory title,
        string memory image,
        string memory link
    ) public onlyUserOrOwner(tokenId) {
        Spot storage spot = spots[tokenId];
        spot.title = title;
        spot.image = image;
        spot.link = link;

        emit ThetaMillionPublish(
            tokenId,
            msg.sender,
            spot.x,
            spot.y,
            spot.width,
            spot.height,
            spot.title,
            spot.image,
            spot.link,
            true
        );
    }

    // withdraw allows the owner to transfer out the balance of the contract.
    function withdraw() public {
        require(msg.sender == contractOwner);
        withdrawWallet.transfer(address(this).balance);
    }

    /* = Rental functions = */

    function createRentalOffer(
        uint256 tokenId,
        uint256 price,
        uint64 rentTime
    ) external {
        require(
            userOf(tokenId) == address(0),
            "Previous rental has not yet ended"
        );
        require(
            msg.sender == ERC721.ownerOf(tokenId),
            "You're not the NFT owner"
        );
        require(price > 0, "Price should be > 0");
        require(rentTime > 0, "Rent time should be > 0");

        idToRentalOffer[tokenId] = RentalOffer(
            tokenId,
            price,
            rentTime,
            payable(msg.sender),
            true
        );

        emit RentalOfferCreated(tokenId, price, rentTime, msg.sender);
    }

    function cancelRentalOffer(uint256 tokenId) external {
        require(
            userOf(tokenId) == address(0),
            "Previous rental has not yet ended"
        );
        require(
            msg.sender == ERC721.ownerOf(tokenId),
            "You're not the NFT owner"
        );

        idToRentalOffer[tokenId].isActive = false;

        emit RentalOfferCancelled(tokenId, msg.sender);
    }

    function fullfillRentalOffer(uint256 tokenId) external payable {
        RentalOffer memory rentalOffer = idToRentalOffer[tokenId];

        require(rentalOffer.isActive == true, "Rental offer is not active");
        require(msg.value == rentalOffer.price, "Wrong price");
        require(rentalOffer.tokenId == tokenId); // Remove token id in rental offer later.

        idToRentalOffer[tokenId].isActive = false;

        // Set the new NFT user
        UserInfo storage info = _users[tokenId];
        uint64 expires = uint64(block.timestamp) + rentalOffer.rentTime;
        info.user = msg.sender;
        info.expires = expires;

        emit UpdateUser(tokenId, msg.sender, expires);

        emit RentalOfferFulfilled(
            tokenId,
            rentalOffer.price,
            rentalOffer.owner,
            msg.sender
        );
    }

    /// @dev ERC4907 setUser() override for NFT owner not to able
    /// @dev to revoke the rental or change the renter.
    function setUser(
        uint256 tokenId,
        address user,
        uint64 expires
    ) public virtual override {
        require(
            userOf(tokenId) == address(0),
            "Previous rental has not yet ended"
        );
        super.setUser(tokenId, user, expires);
    }

    /* === Private functions === */

    /// @dev Creates new spot and gives the NFT to msg.sender.
    /// @dev Implementation copied from ThetaMillionContract.
    function _createNewSpot(
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link
    ) private returns (uint256 tokenId) {
        for (uint i = 0; i < width; ) {
            for (uint k = 0; k < height; ) {
                if (grid[x + i][y + k]) {
                    // the spot is taken
                    revert("The spot is already taken.");
                }
                /// @gas Poor gas...
                grid[x + i][y + k] = true;
                unchecked {
                    k++;
                }
            }
            unchecked {
                i++;
            }
        }

        Spot memory spot = Spot(x, y, width, height, title, image, link);
        spots.push(spot);
        tokenId = spots.length - 1;

        _mint(msg.sender, tokenId);

        emit ThetaMillionPublish(
            tokenId,
            msg.sender,
            x,
            y,
            width,
            height,
            title,
            image,
            link,
            false
        );

        return tokenId;
    }

    function _baseURI() internal pure override returns (string memory) {
        return SPOT_BASE_URI;
    }
}
