// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";

contract OneMio721 is ERC721 {
    constructor(
        address _contractOwner,
        address payable _withdrawWallet
    ) ERC721("ThetaMillion", "TM") {
        require(_contractOwner != address(0));
        require(_withdrawWallet != address(0));

        contractOwner = _contractOwner;
        withdrawWallet = _withdrawWallet;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://nft.thetamillion.com/spot";
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

    uint public constant weiPixelPrice = 1000000000000000000; // 1 -> 1000000000000000000

    uint public constant pixelsPerCell = 400; // 20x20

    bool[50][50] public grid; // grid of taken spots

    // can withdraw the funds
    address contractOwner;

    address payable withdrawWallet;

    struct Spot {
        uint8 x;
        uint8 y;
        uint8 width;
        uint8 height;
        string title;
        string image;
        string link;
    }
    struct SpotWithOwner {
        Spot spot;
        address owner;
    }

    Spot[] public spots;

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

    function buySpot(
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link
    ) public payable returns (uint tokenId) {
        uint cost = uint256(width) *
            uint256(height) *
            pixelsPerCell *
            weiPixelPrice;
        require(cost > 0);
        require(msg.value >= cost);

        // Loop over relevant grid entries
        for (uint i = 0; i < width; ) {
            for (uint k = 0; k < height; ) {
                if (grid[x + i][y + k]) {
                    // the spot is taken
                    revert("The spot is already taken.");
                }
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

    function updateSpot(
        uint tokenId,
        string memory title,
        string memory image,
        string memory link
    ) public {
        require(msg.sender == ERC721.ownerOf(tokenId));
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
}
