// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/OCTOMillion.sol";
import "../src/IOneMio721.sol";

import "../src/ThetaMillion.sol";

// TODO: test update
/// @author Omsify
contract OCTOMillionTest is Test {
    uint public constant weiPixelPrice = 1000000000000000000; // 1 -> 1000000000000000000
    uint public constant pixelsPerCell = 400; // 20x20

    OCTOMillion octoMillion;
    OneMio721 thetaMillion;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address aliceFriend = makeAddr("aliceFriend");

    // ThetaMillion admin
    address tmAdmin = makeAddr("tmAdmin");

    // Events
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
    event UpdateUser(
        uint256 indexed tokenId,
        address indexed user,
        uint64 expires
    );

    function setUp() public {
        vm.prank(tmAdmin);
        thetaMillion = new OneMio721(tmAdmin, payable(tmAdmin));

        vm.prank(admin);
        octoMillion = new OCTOMillion(
            admin,
            payable(admin),
            IOneMio721(address(thetaMillion))
        );
        octoMillion = new OCTOMillion(
            admin,
            payable(admin),
            IOneMio721(address(thetaMillion))
        );
    }

    function testBuy(
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link,
        uint256 ethValue
    ) public {
        uint256 cost = uint256(width) *
            uint256(height) *
            pixelsPerCell *
            weiPixelPrice;

        vm.assume(width != 0 && height != 0);
        vm.assume(ethValue >= cost);
        vm.assume(
            uint256(x) + uint256(width) < 50 &&
                uint256(y) + uint256(height) < 50
        );

        vm.startPrank(alice);
        vm.expectRevert("It's not sale period yet");
        octoMillion.buySpot(x, y, width, height, title, image, link);
        vm.stopPrank();

        buyOCTOSpot(alice, x, y, width, height, title, image, link, ethValue);
    }

    function testClaim(
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link,
        uint256 ethValue
    ) public {
        // = buy ThetaMillion spot =

        uint256 cost = uint256(width) *
            uint256(height) *
            pixelsPerCell *
            weiPixelPrice;

        vm.assume(width != 0 && height != 0);
        vm.assume(ethValue >= cost);
        vm.assume(
            uint256(x) + uint256(width) < 50 &&
                uint256(y) + uint256(height) < 50
        );
        vm.deal(alice, ethValue);

        vm.prank(alice);
        thetaMillion.buySpot{value: ethValue}(
            x,
            y,
            width,
            height,
            title,
            image,
            link
        );
        OneMio721.SpotWithOwner memory tmSpotPacked = thetaMillion.getSpot(0);
        SpotWithOwner memory tmSpotUnpacked = SpotWithOwner(
            Spot(
                tmSpotPacked.spot.x,
                tmSpotPacked.spot.y,
                tmSpotPacked.spot.width,
                tmSpotPacked.spot.height,
                tmSpotPacked.spot.title,
                tmSpotPacked.spot.image,
                tmSpotPacked.spot.link
            ),
            tmSpotPacked.owner
        );
        SpotWithOwner memory testSpot = SpotWithOwner(
            Spot(x, y, width, height, title, image, link),
            alice
        );
        assertEq(thetaMillion.ownerOf(0), alice);
        assertEq(thetaMillion.getSpotsLength(), 1);
        assertTrue(spotWithOwnerEquals(tmSpotUnpacked, testSpot));

        // = Test OctoMillion claim =
        vm.startPrank(bob);
        vm.expectRevert("You're not the token owner");
        octoMillion.claimSpot(0);
        vm.stopPrank();

        vm.startPrank(alice);
        octoMillion.claimSpot(0);
        vm.stopPrank();

        assertEq(octoMillion.ownerOf(0), alice);
        assertEq(octoMillion.getSpotsLength(), 1);
        assertTrue(spotWithOwnerEquals(octoMillion.getSpot(0), testSpot));
        assertTrue(spotWithOwnerEquals(octoMillion.getSpot(0), tmSpotUnpacked));
    }

    function testRent(
        uint256 otherTokenId,
        uint256 rentPrice,
        uint64 rentTime,
        uint256 otherPrice,
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link,
        uint256 ethValue
    ) public {
        vm.assume(otherTokenId != 0);
        vm.assume(otherPrice != rentPrice);
        // Prevent rentTime overflow
        vm.assume(uint64(block.timestamp) < type(uint64).max - rentTime);
        // Dirty way to prevent fuzzer values overflows.
        rentPrice = bound(rentPrice, 0, (type(uint256).max) / 10);
        otherPrice = bound(otherPrice, 0, (type(uint256).max) / 10);
        ethValue = bound(ethValue, 0, (type(uint256).max) / 10);

        buyOCTOSpot(alice, x, y, width, height, title, image, link, ethValue);

        vm.startPrank(alice);
        vm.expectRevert("ERC721: invalid token ID");
        octoMillion.createRentalOffer(otherTokenId, rentPrice, rentTime);

        if (rentPrice == 0) {
            vm.expectRevert("Price should be > 0");
            octoMillion.createRentalOffer(0, rentPrice, rentTime);
        } else {
            if (rentTime == 0) {
                vm.expectRevert("Rent time should be > 0");
                octoMillion.createRentalOffer(0, rentPrice, rentTime);
            } else {
                vm.expectEmit(true, true, true, true, address(octoMillion));
                emit RentalOfferCreated(0, rentPrice, rentTime, alice);

                octoMillion.createRentalOffer(0, rentPrice, rentTime);

                vm.stopPrank();
                // Alice should not be able to transfer the NFT while it's in rental offer
                shouldNotBeAbleToTransferNFT(alice, aliceFriend, 0);

                vm.deal(bob, rentPrice >= otherPrice ? rentPrice : otherPrice);
                vm.startPrank(bob);
                vm.expectRevert("Wrong price");
                octoMillion.fullfillRentalOffer{value: otherPrice}(0);

                uint256 aliceBalanceBefore = address(alice).balance;

                vm.expectEmit(true, true, false, false, address(octoMillion));
                emit UpdateUser(0, bob, uint64(block.timestamp) + rentTime);
                octoMillion.fullfillRentalOffer{value: rentPrice}(0);

                assertEq(
                    address(alice).balance,
                    aliceBalanceBefore + rentPrice
                );
                assertTrue(octoMillion.isInRentalOrOffer(0));

                vm.stopPrank();

                // Alice should not be able to transfer the NFT while it's in rental
                shouldNotBeAbleToTransferNFT(alice, aliceFriend, 0);

                // Test spot updating
                // Bob should be able to update when it's the renting period
                vm.startPrank(bob);
                octoMillion.updateSpot(0, "NEW TITLE", "NEW IMAGE", "NEW LINK");
                SpotWithOwner memory testSpot = SpotWithOwner(
                    Spot(
                        x,
                        y,
                        width,
                        height,
                        "NEW TITLE",
                        "NEW IMAGE",
                        "NEW LINK"
                    ),
                    alice
                );
                assertTrue(
                    spotWithOwnerEquals(octoMillion.getSpot(0), testSpot)
                );
                vm.stopPrank();
                // Alice should not be able to update while it is the renting period
                vm.startPrank(alice);
                vm.expectRevert("You're not the user of NFT");
                octoMillion.updateSpot(0, "alice", "ALIce", "ALICE!!!");
                vm.stopPrank();

                // Bob shouldn't be able to update when the renting period has ended
                vm.warp(uint64(block.timestamp) + rentTime + 1);
                vm.startPrank(bob);
                vm.expectRevert("You're not the owner of NFT");
                octoMillion.updateSpot(0, "bob", "I'm Bob", "The bobby bob");
                vm.stopPrank();

                // Alice should be able to update when the renting period has ended
                vm.startPrank(alice);
                octoMillion.updateSpot(
                    0,
                    "This spot is ",
                    "very rare. You",
                    "can't get it anywhere"
                );
                testSpot = SpotWithOwner(
                    Spot(
                        x,
                        y,
                        width,
                        height,
                        "This spot is ",
                        "very rare. You",
                        "can't get it anywhere"
                    ),
                    alice
                );
                assertTrue(
                    spotWithOwnerEquals(octoMillion.getSpot(0), testSpot)
                );
                vm.stopPrank();

                // Bob shouldn't be able to fullfill expired offer
                vm.deal(bob, rentPrice);
                vm.startPrank(bob);
                vm.expectRevert("Rental offer is not active");
                octoMillion.fullfillRentalOffer{value: rentPrice}(0);
                vm.stopPrank();
            }
        }
    }

    function buyOCTOSpot(
        address buyer,
        uint8 x,
        uint8 y,
        uint8 width,
        uint8 height,
        string memory title,
        string memory image,
        string memory link,
        uint256 ethValue
    ) internal {
        uint256 cost = uint256(width) *
            uint256(height) *
            pixelsPerCell *
            weiPixelPrice;

        vm.assume(width != 0 && height != 0);
        vm.assume(ethValue >= cost);
        vm.assume(
            uint256(x) + uint256(width) < 50 &&
                uint256(y) + uint256(height) < 50
        );

        vm.prank(admin);
        octoMillion.setSaleStatus(true);

        vm.deal(buyer, ethValue);

        vm.startPrank(buyer);
        octoMillion.buySpot{value: ethValue}(
            x,
            y,
            width,
            height,
            title,
            image,
            link
        );
        vm.stopPrank();

        uint256 spotsAmount = octoMillion.getSpotsLength();
        SpotWithOwner memory testSpot = SpotWithOwner(
            Spot(x, y, width, height, title, image, link),
            buyer
        );
        assertEq(octoMillion.ownerOf(spotsAmount - 1), buyer);
        assertEq(spotsAmount, 1);
        assertTrue(spotWithOwnerEquals(octoMillion.getSpot(0), testSpot));
    }

    function shouldNotBeAbleToTransferNFT(
        address nftOwner,
        address to,
        uint256 tokenId
    ) internal {
        vm.startPrank(nftOwner);
        vm.expectRevert("The NFT is currently in rental or rental offer");
        octoMillion.transferFrom(nftOwner, to, tokenId);
        vm.expectRevert("The NFT is currently in rental or rental offer");
        octoMillion.safeTransferFrom(nftOwner, to, tokenId);
        vm.expectRevert("The NFT is currently in rental or rental offer");
        octoMillion.safeTransferFrom(nftOwner, to, tokenId, "");
        vm.stopPrank();
    }

    function spotWithOwnerEquals(
        SpotWithOwner memory _first,
        SpotWithOwner memory _second
    ) internal view returns (bool) {
        return (keccak256(
            abi.encodePacked(
                _first.spot.x,
                _first.spot.y,
                _first.spot.width,
                _first.spot.height,
                _first.spot.title,
                _first.spot.image,
                _first.spot.link,
                _first.owner
            )
        ) ==
            keccak256(
                abi.encodePacked(
                    _second.spot.x,
                    _second.spot.y,
                    _second.spot.width,
                    _second.spot.height,
                    _second.spot.title,
                    _second.spot.image,
                    _second.spot.link,
                    _second.owner
                )
            ));
    }
}
