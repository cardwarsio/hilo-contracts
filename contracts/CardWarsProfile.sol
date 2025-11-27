// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./libraries/StringLib.sol";
import "./interfaces/IHiLo.sol";
import "./CardWarsHiLo.sol";

contract CardWarsProfile is Ownable, AccessControl {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address public hiloContract;

    // Farcaster account linking (immutable)
    struct FarcasterLink {
        uint256 fid;
        string username;
        string displayName;
        uint256 linkedAt;
        bool isLinked;
    }
    mapping(address => FarcasterLink) public farcasterLinks;
    mapping(uint256 => address) public fidToWallet;
    mapping(address => bool) public hasLinkedFarcaster;

    // User profile information (mutable by user)
    struct UserProfile {
        string name;
        string xHandle;
        string avatarUrl;
        uint256 updatedAt;
    }
    mapping(address => UserProfile) public userProfiles;

    event FarcasterLinked(
        address indexed wallet,
        uint256 indexed fid,
        string username,
        string displayName,
        uint256 indexed timestamp
    );

    event ProfileUpdated(
        address indexed wallet,
        string name,
        string xHandle,
        string avatarUrl,
        uint256 indexed timestamp
    );

    constructor(address _hiloContract) Ownable(msg.sender) {
        if (_hiloContract == address(0)) {
            revert("InvalidAddress");
        }
        hiloContract = _hiloContract;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function setHiLoContract(
        address _hiloContract
    ) external onlyRole(OPERATOR_ROLE) {
        if (_hiloContract == address(0)) {
            revert("InvalidAddress");
        }
        hiloContract = _hiloContract;
    }

    function linkFarcasterAccount(
        uint256 fid,
        string memory username,
        string memory displayName,
        bytes memory signature,
        string memory name,
        string memory xHandle,
        string memory avatarUrl
    ) external {
        require(
            !hasLinkedFarcaster[msg.sender],
            "Farcaster account already linked"
        );
        require(
            fidToWallet[fid] == address(0),
            "FID already linked to another wallet"
        );
        require(fid > 0, "Invalid FID");
        require(bytes(username).length > 0, "Username cannot be empty");

        string memory message = string(
            abi.encodePacked(
                "CardWars - Link Farcaster Account\n\n",
                "Wallet Address: ",
                StringLib.addressToString(msg.sender),
                "\nFarcaster FID: ",
                StringLib.uint256ToString(fid),
                "\nUsername: @",
                username,
                "\nDisplay Name: ",
                displayName,
                "\nProfile Name: ",
                name,
                "\nX Handle: @",
                xHandle,
                "\nAvatar URL: ",
                avatarUrl
            )
        );

        bytes32 messageHash = keccak256(bytes(message));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        address signer = ethSignedMessageHash.recover(signature);
        require(signer == msg.sender, "Invalid signature");

        farcasterLinks[msg.sender] = FarcasterLink({
            fid: fid,
            username: username,
            displayName: displayName,
            linkedAt: block.timestamp,
            isLinked: true
        });

        fidToWallet[fid] = msg.sender;
        hasLinkedFarcaster[msg.sender] = true;

        if (
            bytes(name).length > 0 ||
            bytes(xHandle).length > 0 ||
            bytes(avatarUrl).length > 0
        ) {
            userProfiles[msg.sender] = UserProfile({
                name: name,
                xHandle: xHandle,
                avatarUrl: avatarUrl,
                updatedAt: block.timestamp
            });
            emit ProfileUpdated(
                msg.sender,
                name,
                xHandle,
                avatarUrl,
                block.timestamp
            );
        }

        emit FarcasterLinked(
            msg.sender,
            fid,
            username,
            displayName,
            block.timestamp
        );
    }

    function updateProfile(
        string memory name,
        string memory xHandle,
        string memory avatarUrl
    ) external {
        userProfiles[msg.sender] = UserProfile({
            name: name,
            xHandle: xHandle,
            avatarUrl: avatarUrl,
            updatedAt: block.timestamp
        });
        emit ProfileUpdated(
            msg.sender,
            name,
            xHandle,
            avatarUrl,
            block.timestamp
        );
    }

    function getUserProfile(
        address wallet
    )
        external
        view
        returns (
            string memory name,
            string memory xHandle,
            string memory avatarUrl,
            uint256 updatedAt
        )
    {
        UserProfile memory profile = userProfiles[wallet];
        return (
            profile.name,
            profile.xHandle,
            profile.avatarUrl,
            profile.updatedAt
        );
    }

    function getLinkedFarcaster(
        address wallet
    )
        external
        view
        returns (
            uint256 fid,
            string memory username,
            string memory displayName,
            uint256 linkedAt
        )
    {
        FarcasterLink memory link = farcasterLinks[wallet];
        return (link.fid, link.username, link.displayName, link.linkedAt);
    }

    function getLinkedWallet(
        uint256 fid
    ) external view returns (address wallet) {
        return fidToWallet[fid];
    }

    function isLinked(address wallet) external view returns (bool) {
        return hasLinkedFarcaster[wallet];
    }

    function getUsersWithProfile()
        external
        view
        returns (address[] memory)
    {
        if (address(hiloContract) == address(0)) {
            return new address[](0);
        }

        address[] memory allPlayers = CardWarsHiLo(payable(hiloContract)).getAllPlayers();
        uint256 maxIterations = allPlayers.length > 1000 ? 1000 : allPlayers.length;
        address[] memory usersWithProfile = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            UserProfile memory profile = userProfiles[allPlayers[i]];
            if (
                bytes(profile.name).length > 0 ||
                bytes(profile.xHandle).length > 0 ||
                bytes(profile.avatarUrl).length > 0
            ) {
                usersWithProfile[count] = allPlayers[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = usersWithProfile[i];
        }
        return result;
    }

    function getUsersWithFarcaster()
        external
        view
        returns (address[] memory)
    {
        if (address(hiloContract) == address(0)) {
            return new address[](0);
        }

        address[] memory allPlayers = CardWarsHiLo(payable(hiloContract)).getAllPlayers();
        uint256 maxIterations = allPlayers.length > 1000 ? 1000 : allPlayers.length;
        address[] memory usersWithFarcaster = new address[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            if (hasLinkedFarcaster[allPlayers[i]]) {
                usersWithFarcaster[count] = allPlayers[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = usersWithFarcaster[i];
        }
        return result;
    }

    function getTopProfiles(
        uint256 limit
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory updatedAts
        )
    {
        if (address(hiloContract) == address(0)) {
            return (new address[](0), new uint256[](0));
        }

        address[] memory allPlayers = CardWarsHiLo(payable(hiloContract)).getAllPlayers();
        uint256 maxIterations = allPlayers.length > 1000 ? 1000 : allPlayers.length;
        address[] memory sortedPlayers = new address[](maxIterations);
        uint256[] memory timestamps = new uint256[](maxIterations);
        uint256 count = 0;

        for (uint256 i = 0; i < maxIterations; i++) {
            UserProfile memory profile = userProfiles[allPlayers[i]];
            if (profile.updatedAt > 0) {
                sortedPlayers[count] = allPlayers[i];
                timestamps[count] = profile.updatedAt;
                count++;
            }
        }

        uint256 resultCount = count < limit ? count : limit;

        for (uint256 i = 0; i < resultCount; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < count; j++) {
                if (timestamps[j] > timestamps[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                address tempAddr = sortedPlayers[i];
                uint256 tempTime = timestamps[i];
                sortedPlayers[i] = sortedPlayers[maxIndex];
                timestamps[i] = timestamps[maxIndex];
                sortedPlayers[maxIndex] = tempAddr;
                timestamps[maxIndex] = tempTime;
            }
        }

        addresses = new address[](resultCount);
        updatedAts = new uint256[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            addresses[i] = sortedPlayers[i];
            updatedAts[i] = timestamps[i];
        }
    }
}
