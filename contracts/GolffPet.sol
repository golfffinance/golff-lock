//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import "./base64.sol";

contract GolffPet is ERC721Enumerable, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    EnumerableSet.AddressSet private minters;

    string constant private preRevealImageUrl = 'ipfs://Qma1CQepRezX6kAuw3YDdCx23qNUQdaDbXccQfgLRdp8iG';

    string public revealedCollectionBaseURL;
    // user_address--id
    mapping(address => uint256) public claimHolders;
    // id--user_address
    mapping(uint256 => address) public claimTokenOwners;


    uint256 constant private MAX_SPACE_SUPPLY = 99;

    uint256 constant private HIGHER_TOKEN_COUNT = 1;

    uint256 constant private MEDIUM_TOKEN_COUNT = 3;

    uint256 constant private INFERIOR_TOKEN_COUNT = 5;

    uint256[] private boardFactor = [1010000000000000000, 1020000000000000000, 1030000000000000000, 1050000000000000000];

    string[] private combatEffectiveness = ["100", "200", "300", "500"];

    string[] private rarity = ["90/99", "5/99", "3/99", "1/99"];

    mapping(uint256 => uint256) private attributeIndex;

    mapping(uint256 => uint256) private boardFactorCount;


    event Claim(address indexed owner, uint256 tokenId);

    constructor() ERC721('Golff Pet', "Golff Pet") {

    }

    function claim() public returns (uint256){
        require(totalSupply() + 1 <= MAX_SPACE_SUPPLY, "GolffPet:claim would exceed max supply");
        require(isMinter(msg.sender), 'GolffPet:claim only allowed from Space');
        require(!isClaimed(msg.sender), 'GolffPet:already claimed');
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);
        setAttributeIndex(newTokenId);
        claimHolders[msg.sender] = newTokenId;
        claimTokenOwners[newTokenId] = msg.sender;
        emit Claim(msg.sender, newTokenId);
        return newTokenId;
    }

    function isClaimed(address account) public view returns (bool) {
        require(account != address(0), 'GolffPet:account is the zero address');
        return claimHolders[account] != 0;
    }

    function isMinter(address account) public view returns (bool) {
        require(account != address(0), 'GolffPet:account is the zero address');
        return EnumerableSet.contains(minters, account);
    }

    function surplus() public view returns (uint256) {
        return MAX_SPACE_SUPPLY - _tokenIds.current();
    }

    function setAttributeIndex(uint256 tokenId) private returns (uint256) {
        uint256 index = pluck(tokenId);
        if (index == 1) {
            uint256 count = boardFactorCount[index];
            if (count < INFERIOR_TOKEN_COUNT) {
                boardFactorCount[index] = count + 1;
            } else {
                index = 0;
            }
        } else if (index == 2) {
            uint256 count = boardFactorCount[index];
            if (count < MEDIUM_TOKEN_COUNT) {
                boardFactorCount[index] = count + 1;
            } else {
                index = 0;
            }
        } else if (index == 3) {
            uint256 count = boardFactorCount[index];
            if (count < HIGHER_TOKEN_COUNT) {
                boardFactorCount[index] = count + 1;
            } else {
                index = 0;
            }
        }
        attributeIndex[tokenId] = index;
        return index;
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        bytes memory tokenName = abi.encodePacked('Golff Pet #', Strings.toString(_tokenId));
        bytes memory content = abi.encodePacked('{"name":"', tokenName, '"');
        if (keccak256(abi.encodePacked(revealedCollectionBaseURL)) == keccak256(abi.encodePacked(''))) {
            content = abi.encodePacked(content,
                ', ',
                '"description": "An unrevealed Ape Harbour Surfboard"',
                ', ',
                '"image": "', preRevealImageUrl, '"',
                '}');
        } else {
            if (getBoardFactor(_tokenId) == boardFactor[2] || getBoardFactor(_tokenId) == boardFactor[3]) {
                content = abi.encodePacked(content,
                    ', ',
                    '"description": "this is description"',
                    ', ',
                    '"attributes": [{"trait_type": "Combat Effectiveness", "value": "', getCombatEffectiveness(_tokenId), '"},{"trait_type": "Rarity", "value": "', getRarity(_tokenId), '"}]',
                    ', ',
                    '"image": "', revealedCollectionBaseURL, Strings.toString(_tokenId), '.gif"',
                    '}');
            } else {
                content = abi.encodePacked(content,
                    ', ',
                    '"description": "this is description"',
                    ', ',
                    '"attributes": [{"trait_type": "Combat Effectiveness", "value": "', getCombatEffectiveness(_tokenId), '"},{"trait_type": "Rarity", "value": "', getRarity(_tokenId), '"}]',
                    ', ',
                    '"image": "', revealedCollectionBaseURL, Strings.toString(_tokenId), '.png"',
                    '}');
            }
        }
        string memory result = string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(content)
            )
        );
        return result;
    }

    function getBoardFactor(uint256 tokenId) public view returns (uint256){
        require(_tokenIds.current() >= tokenId, 'GolffPet:query for nonexistent token');
        return boardFactor[attributeIndex[tokenId]];
    }

    function getCombatEffectiveness(uint256 tokenId) public view returns (string memory){
        return combatEffectiveness[attributeIndex[tokenId]];
    }

    function getRarity(uint256 tokenId) public view returns (string memory){
        return rarity[attributeIndex[tokenId]];
    }

    function pluck(uint256 tokenId) private view returns (uint256) {
        uint256 rand = random(toString(tokenId));
        uint256 index = 0;
        uint256 greatness = rand % 41;
        if (greatness >= 32) {
            index = index + 1;
        }
        if (greatness >= 37) {
            index = index + 1;
        }
        if (greatness >= 40) {
            index = index + 1;
        }
        return index;
    }

    function random(string memory input) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }

    function toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }


    function setRevealedCollectionBaseURL(string memory _ipfsHash) onlyOwner public {
        revealedCollectionBaseURL = string(abi.encodePacked('ipfs://', _ipfsHash, '/'));
    }

    function addMinters(address[] memory account) public onlyOwner {
        for (uint i; i < account.length; i++) {
            EnumerableSet.add(minters, account[i]);
        }
    }
}