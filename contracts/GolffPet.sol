//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./base64.sol";
import "./IPoolLock.sol";
import "./IGofVault.sol";

contract GolffPet is ERC721Enumerable, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    address public pool_lock_address;

    address public gof_vault_address;

    bytes32 public merkleRoot;

    string public revealedCollectionBaseURL;
    // user_address--id
    mapping(address => uint256) public claimHolders;
    // id--user_address
    mapping(uint256 => address) public claimTokenOwners;

    uint256 constant public MAX_SPACE_SUPPLY = 99;

    uint256 constant private HIGHER_TOKEN_COUNT = 1;

    uint256 constant private MEDIUM_TOKEN_COUNT = 3;

    uint256 constant private INFERIOR_TOKEN_COUNT = 5;

    uint256[] private boardFactor = [1050000000000000000, 1060000000000000000, 1070000000000000000, 1100000000000000000];

    string[] private combatEffectiveness = ["500", "600", "700", "1000"];

    string[] private rarity = ["90/99", "5/99", "3/99", "1/99"];

    mapping(uint256 => uint256) private attributeIndex;

    mapping(uint256 => uint256) private boardFactorCount;

    uint256 private lockGofAmount = 500000000000000000000;

    event Claim(address indexed owner, uint256 tokenId);

    constructor(string memory _ipfsHash,bytes32 merkleRoot_ ,address pool_lock_address_, address gof_vault_address_) ERC721('Golff Pet', "Golff Pet") {
        merkleRoot = merkleRoot_;
        setRevealedCollectionBaseURL(_ipfsHash);
        pool_lock_address =pool_lock_address_;
        gof_vault_address = gof_vault_address_;
    }

    function claim(uint256 index, bytes32[] calldata merkleProof) public returns (uint256){
        require(totalSupply() + 1 <= MAX_SPACE_SUPPLY, "GolffPet:claim would exceed max supply");
        require(!isClaimed(msg.sender), 'GolffPet:already claimed');
        uint256 amount = 1000000000000000000;
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'GolffPet: Invalid proof');
        uint256 poolLockAmount = IPoolLock(pool_lock_address).lockBalance(msg.sender);
        poolLockAmount = poolLockAmount + IPoolLock(pool_lock_address).balance(msg.sender);
        if (poolLockAmount<lockGofAmount){
            uint256 GtokenAmount = IGofVault(gof_vault_address).balanceOf(msg.sender);
            require(GtokenAmount>0 , 'GolffPet: Gof pledge less than 500');
            uint256 vaultAmount = GtokenAmount * IGofVault(gof_vault_address).getPricePerFullShare() /1e18;
            require(vaultAmount>=lockGofAmount , 'GolffPet: Gof pledge less than 500');
        }
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
        bytes memory imgUrl = abi.encodePacked(revealedCollectionBaseURL,toString(_tokenId),".png");
        if (getBoardFactor(_tokenId) == boardFactor[2] || getBoardFactor(_tokenId) == boardFactor[3]) {
            imgUrl = abi.encodePacked(revealedCollectionBaseURL,toString(_tokenId),".gif");
        }

        bytes memory content = abi.encodePacked('{"name":"Golff Pet #', toString(_tokenId), '","description": "To celebrate the first anniversary of Golff, \'Golff Pet NFT\' is hereby launched to bring exclusive rights and interests to holders. Golff users who meet specific criterias can generate different NFTs randomly. NFT Holders can join the Golff VIP community with the priority experience of Golff products, and get a long-term revenue bonus in the Golff ecology.","attributes": [{"trait_type": "Combat Effectiveness", "value": "', getCombatEffectiveness(_tokenId), '"},{"trait_type": "Rarity", "value": "', getRarity(_tokenId), '"}],"image": "', imgUrl, '"}');

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
        require(_tokenIds.current() >= tokenId, 'GolffPet:query for nonexistent token');
        return combatEffectiveness[attributeIndex[tokenId]];
    }

    function getRarity(uint256 tokenId) public view returns (string memory){
        require(_tokenIds.current() >= tokenId, 'GolffPet:query for nonexistent token');
        return rarity[attributeIndex[tokenId]];
    }

    function pluck(uint256 tokenId) public view returns (uint256) {
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

}