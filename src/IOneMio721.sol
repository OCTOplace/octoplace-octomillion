// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SpotWithOwner.sol";

interface IOneMio721 {
    function getSpot(
        uint tokenId
    ) external view returns (SpotWithOwner memory spotInfo);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}
