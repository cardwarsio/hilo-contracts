// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IClan {
    enum MembershipStatus {
        Pending, // Application pending
        Active, // Member of clan
        Removed // Removed from clan (can reapply after cooldown)
    }

    struct Clan {
        uint256 clanId;
        address leader;
        string name;
        string description;
        uint256 createdAt;
        uint256 totalScore; // Sum of all members' superGemPoints (for HiLo game)
        uint256 battleScore; // Sum of battle points from clan members
        uint256 totalWins; // Sum of all members' totalWins
        uint256 memberCount;
    }

    struct ClanMember {
        address member;
        MembershipStatus status;
        uint256 joinedAt;
        uint256 removedAt; // When removed (for cooldown calculation)
    }

    struct ClanApplication {
        address applicant;
        uint256 appliedAt;
        bool pending;
    }

    struct ClanInvitation {
        address invitee;
        address inviter;
        uint256 invitedAt;
        bool pending;
    }

    event ClanCreated(
        uint256 indexed clanId,
        address indexed leader,
        string name,
        uint256 timestamp
    );

    event ClanApplicationSubmitted(
        uint256 indexed clanId,
        address indexed applicant,
        uint256 timestamp
    );

    event ClanApplicationAccepted(
        uint256 indexed clanId,
        address indexed applicant,
        address indexed leader,
        uint256 timestamp
    );

    event ClanApplicationRejected(
        uint256 indexed clanId,
        address indexed applicant,
        address indexed leader,
        uint256 timestamp
    );

    event ClanMemberRemoved(
        uint256 indexed clanId,
        address indexed member,
        address indexed leader,
        uint256 timestamp
    );

    event ClanLeaderboardUpdated(
        uint256 indexed clanId,
        uint256 totalScore,
        uint256 totalWins,
        uint256 timestamp
    );

    event ClanCosmeticApplied(
        uint256 indexed clanId,
        uint256 indexed marketplaceItemId,
        string cosmeticType,
        uint256 timestamp
    );

    event ClanNameChanged(
        uint256 indexed clanId,
        string oldName,
        string newName,
        address indexed leader,
        uint256 timestamp
    );

    event ClanDisbanded(
        uint256 indexed clanId,
        address indexed leader,
        uint256 timestamp
    );

    event ClanInvitationSent(
        uint256 indexed clanId,
        address indexed invitee,
        address indexed inviter,
        uint256 timestamp
    );

    event ClanInvitationAccepted(
        uint256 indexed clanId,
        address indexed invitee,
        address indexed inviter,
        uint256 timestamp
    );

    event ClanInvitationRejected(
        uint256 indexed clanId,
        address indexed invitee,
        address indexed inviter,
        uint256 timestamp
    );

    event LeadershipTransferred(
        uint256 indexed clanId,
        address indexed oldLeader,
        address indexed newLeader,
        uint256 timestamp
    );

    function userClan(address user) external view returns (uint256);

    function addBattleScore(uint256 clanId, uint256 battlePoints) external;

    function applyCosmetic(
        uint256 clanId,
        uint256 marketplaceItemId,
        string memory cosmeticType
    ) external;

    function getClanCosmetic(
        uint256 clanId,
        string memory cosmeticType
    ) external view returns (uint256);

    function getClanActiveCosmetics(
        uint256 clanId
    ) external view returns (string[] memory);

    function changeClanName(uint256 clanId, string memory newName) external;

    function getClanInfo(
        uint256 clanId
    )
        external
        view
        returns (
            uint256 clanId_,
            address leader,
            string memory name,
            string memory description,
            uint256 createdAt,
            uint256 totalScore,
            uint256 battleScore,
            uint256 totalWins,
            uint256 memberCount,
            address[] memory members
        );

    function getTopClans(uint256 limit) external view returns (Clan[] memory);

    function inviteMember(uint256 clanId, address invitee) external;

    function acceptInvitation(uint256 clanId) external;

    function rejectInvitation(uint256 clanId) external;

    function getPendingInvitations(address user) external view returns (uint256[] memory);

    function getSentInvitations(uint256 clanId) external view returns (address[] memory);

    function getClanMembersWithStats(
        uint256 clanId
    )
        external
        view
        returns (
            address[] memory members,
            uint256[] memory battleWins,
            uint256[] memory battleLosses,
            uint256[] memory battleWinRates
        );

    function getPlayersWithoutClan()
        external
        view
        returns (address[] memory);

    function getTopPlayersByClan(
        uint256 clanId,
        uint256 limit,
        uint8 sortBy
    )
        external
        view
        returns (
            address[] memory addresses,
            uint256[] memory totalWins,
            uint256[] memory battleWins,
            uint256[] memory superGemPoints
        );

    function getClanLeaders()
        external
        view
        returns (address[] memory);

    function getClansByMember(address member) external view returns (uint256[] memory);

    function transferLeadership(uint256 clanId, address newLeader) external;
}
