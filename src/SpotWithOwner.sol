// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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
