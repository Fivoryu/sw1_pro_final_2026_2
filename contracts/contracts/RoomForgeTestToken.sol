// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Local-only demo token. One whole token unit represents one displayed COP.
contract RoomForgeTestToken is ERC20, Ownable {
    constructor(address initialOwner)
        ERC20("RoomForge Test Token", "RFT")
        Ownable(initialOwner)
    {}

    function decimals() public pure override returns (uint8) {
        return 2;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
