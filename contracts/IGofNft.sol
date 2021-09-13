// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IGofNft {
    function getBoardFactor(uint256 _tokenId) external view returns(uint256);
}
