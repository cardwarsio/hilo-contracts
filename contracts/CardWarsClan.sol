// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IClan.sol";
import "./interfaces/IHiLo.sol";
import "./interfaces/IBattle.sol";
import "./CardWarsHiLo.sol";
import "./CardWarsMarketplace.sol";
import "./utils/Errors.sol";
import "./utils/Constants.sol";
import "./libraries/CEILib.sol";

contract CardWarsClan is
    IClan,
    ReentrancyGuard,
    Pausable,
    Ownable,
    AccessControl
{
    using CEILib for CEILib.CEIContext;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }

    fallback() external payable {
        revert("Function not found");
    }

    CardWarsHiLo public hiloContract;

    uint256 public constant MAX_CLAN_MEMBERS = 8;
    uint256 public constant REMOVAL_COOLDOWN = 7 days;

    uint256 public clanCounter;
    mapping(uint256 => Clan) public clans;
    mapping(address => uint256) public userClan; // user => clanId (0 = no clan)
    mapping(uint256 => mapping(address => ClanMember)) public clanMembers; // clanId => member => ClanMember
    mapping(uint256 => address[]) public clanMemberList; // clanId => member addresses
    mapping(uint256 => ClanApplication[]) public clanApplications; // clanId => applications
    mapping(uint256 => mapping(address => uint256)) public applicationIndex; // clanId => applicant => index
    mapping(uint256 => mapping(string => uint256)) public clanCosmetics; // clanId => cosmeticType => marketplaceItemId
    mapping(uint256 => string[]) public clanActiveCosmetics; // clanId => active cosmetic types
    mapping(uint256 => mapping(address => ClanInvitation))
        public clanInvitations; // clanId => invitee => ClanInvitation
    mapping(address => uint256[]) public pendingInvitations; // user => clanIds where they are invited
    mapping(uint256 => address[]) public sentInvitations; // clanId => invitee addresses
    CardWarsMarketplace public marketplaceContract;

    constructor(address payable _hiloContract) Ownable(msg.sender) {
        if (_hiloContract == address(0)) {
            revert InvalidAddress();
        }
        hiloContract = CardWarsHiLo(_hiloContract);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function createClan(
        string memory name,
        string memory description
    ) external payable nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (userClan[msg.sender] != 0) {
            revert AlreadyInClan();
        }
        if (bytes(name).length == 0 || bytes(name).length > 32) {
            revert InvalidClanName();
        }
        if (bytes(description).length > 200) {
            revert InvalidDescription();
        }
        if (msg.value != Constants.CLAN_CREATION_FEE) {
            revert InvalidAmount();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        clanCounter++;
        uint256 clanId = clanCounter;

        clans[clanId] = Clan({
            clanId: clanId,
            leader: msg.sender,
            name: name,
            description: description,
            createdAt: block.timestamp,
            totalScore: 0,
            battleScore: 0,
            totalWins: 0,
            memberCount: 1
        });

        userClan[msg.sender] = clanId;
        clanMembers[clanId][msg.sender] = ClanMember({
            member: msg.sender,
            status: MembershipStatus.Active,
            joinedAt: block.timestamp,
            removedAt: 0
        });

        clanMemberList[clanId].push(msg.sender);

        _updateClanStats(clanId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanCreated(clanId, msg.sender, name, block.timestamp);
    }

    function applyToClan(uint256 clanId) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (clans[clanId].clanId == 0) {
            revert ClanNotFound();
        }
        if (userClan[msg.sender] != 0) {
            revert AlreadyInClan();
        }
        if (clans[clanId].memberCount >= MAX_CLAN_MEMBERS) {
            revert ClanFull();
        }

        ClanMember memory existingMember = clanMembers[clanId][msg.sender];
        if (existingMember.status == MembershipStatus.Active) {
            revert AlreadyInClan();
        }
        if (existingMember.status == MembershipStatus.Removed) {
            if (existingMember.removedAt + REMOVAL_COOLDOWN > block.timestamp) {
                revert CooldownNotExpired();
            }
        }

        if (applicationIndex[clanId][msg.sender] != 0) {
            uint256 appIndex = applicationIndex[clanId][msg.sender] - 1;
            if (clanApplications[clanId][appIndex].pending) {
                revert ApplicationNotPending();
            }
        }

        ctx.completeChecks();

        ctx.requireEffects();
        clanApplications[clanId].push(
            ClanApplication({
                applicant: msg.sender,
                appliedAt: block.timestamp,
                pending: true
            })
        );

        applicationIndex[clanId][msg.sender] = clanApplications[clanId].length;

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanApplicationSubmitted(clanId, msg.sender, block.timestamp);
    }

    function acceptApplication(
        uint256 clanId,
        address applicant
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Clan storage clan = clans[clanId];

        ctx.requireChecks();
        if (clan.leader != msg.sender) {
            revert Unauthorized();
        }
        if (clan.memberCount >= MAX_CLAN_MEMBERS) {
            revert();
        }

        uint256 appIdx = applicationIndex[clanId][applicant];
        if (appIdx == 0) {
            revert();
        }
        appIdx--;

        ClanApplication storage application = clanApplications[clanId][appIdx];
        if (!application.pending) {
            revert();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        application.pending = false;

        userClan[applicant] = clanId;
        clanMembers[clanId][applicant] = ClanMember({
            member: applicant,
            status: MembershipStatus.Active,
            joinedAt: block.timestamp,
            removedAt: 0
        });

        clanMemberList[clanId].push(applicant);
        clan.memberCount++;

        _updateClanStats(clanId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanApplicationAccepted(
            clanId,
            applicant,
            msg.sender,
            block.timestamp
        );
    }

    function rejectApplication(
        uint256 clanId,
        address applicant
    ) external nonReentrant whenNotPaused {
        Clan storage clan = clans[clanId];

        if (clan.leader != msg.sender) {
            revert Unauthorized();
        }

        uint256 appIdx = applicationIndex[clanId][applicant];
        if (appIdx == 0) {
            revert();
        }
        appIdx--;

        ClanApplication storage application = clanApplications[clanId][appIdx];
        if (!application.pending) {
            revert();
        }

        application.pending = false;

        emit ClanApplicationRejected(
            clanId,
            applicant,
            msg.sender,
            block.timestamp
        );
    }

    function removeMember(
        uint256 clanId,
        address member
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Clan storage clan = clans[clanId];

        ctx.requireChecks();
        if (clan.leader != msg.sender) {
            revert Unauthorized();
        }
        if (member == msg.sender) {
            revert();
        }

        ClanMember storage clanMember = clanMembers[clanId][member];
        if (clanMember.status != MembershipStatus.Active) {
            revert();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        clanMember.status = MembershipStatus.Removed;
        clanMember.removedAt = block.timestamp;

        userClan[member] = 0;
        clan.memberCount--;

        _removeFromMemberList(clanId, member);
        _updateClanStats(clanId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanMemberRemoved(clanId, member, msg.sender, block.timestamp);
    }

    function leaveClan() external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        uint256 clanId = userClan[msg.sender];
        if (clanId == 0) {
            revert NotInClan();
        }

        Clan storage clan = clans[clanId];
        if (clan.leader == msg.sender) {
            revert LeaderCannotLeave();
        }

        ClanMember storage clanMember = clanMembers[clanId][msg.sender];
        if (clanMember.status != MembershipStatus.Active) {
            revert NotInClan();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        clanMember.status = MembershipStatus.Removed;
        clanMember.removedAt = block.timestamp;

        userClan[msg.sender] = 0;
        clan.memberCount--;

        _removeFromMemberList(clanId, msg.sender);
        _updateClanStats(clanId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanMemberRemoved(clanId, msg.sender, msg.sender, block.timestamp);
    }

    function disbandClan(uint256 clanId) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        Clan storage clan = clans[clanId];
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        if (clan.leader != msg.sender) {
            revert Unauthorized();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        // Free all members
        address[] memory members = clanMemberList[clanId];
        for (uint256 i = 0; i < members.length; i++) {
            if (
                clanMembers[clanId][members[i]].status ==
                MembershipStatus.Active
            ) {
                userClan[members[i]] = 0;
                clanMembers[clanId][members[i]].status = MembershipStatus
                    .Removed;
                clanMembers[clanId][members[i]].removedAt = block.timestamp;
            }
        }

        // Clear clan data (set leader to zero address to mark as disbanded)
        address oldLeader = clan.leader;
        clan.leader = address(0);
        clan.memberCount = 0;
        clan.totalScore = 0;
        clan.battleScore = 0;
        clan.totalWins = 0;

        // Clear member list
        delete clanMemberList[clanId];

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanDisbanded(clanId, oldLeader, block.timestamp);
    }

    function _updateClanStats(uint256 clanId) internal {
        Clan storage clan = clans[clanId];
        address[] memory members = clanMemberList[clanId];

        uint256 totalScore = 0;
        uint256 totalWins = 0;

        for (uint256 i = 0; i < members.length; i++) {
            if (
                clanMembers[clanId][members[i]].status ==
                MembershipStatus.Active
            ) {
                (
                    ,
                    ,
                    ,
                    ,
                    uint256 totalWinsMember,
                    uint256 superGemPointsMember,

                ) = hiloContract.getUserStats(members[i]);
                totalScore += superGemPointsMember;
                totalWins += totalWinsMember;
            }
        }

        clan.totalScore = totalScore;
        clan.totalWins = totalWins;

        emit ClanLeaderboardUpdated(
            clanId,
            totalScore,
            totalWins,
            block.timestamp
        );
    }

    function _removeFromMemberList(uint256 clanId, address member) internal {
        address[] storage members = clanMemberList[clanId];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == member) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }
    }

    function getClanMembers(
        uint256 clanId
    ) external view returns (address[] memory) {
        if (clans[clanId].clanId == 0) {
            revert ClanNotFound();
        }
        return clanMemberList[clanId];
    }

    function getClanApplications(
        uint256 clanId
    ) external view returns (ClanApplication[] memory) {
        if (clans[clanId].clanId == 0) {
            revert ClanNotFound();
        }
        return clanApplications[clanId];
    }

    function getTopClans(uint256 limit) external view returns (Clan[] memory) {
        if (limit == 0) {
            return new Clan[](0);
        }
        if (clanCounter == 0) {
            return new Clan[](0);
        }
        uint256 maxLimit = limit > 100 ? 100 : limit;
        uint256 maxClans = clanCounter > 500 ? 500 : clanCounter;
        uint256 count = maxClans < maxLimit ? maxClans : maxLimit;
        Clan[] memory topClans = new Clan[](count);

        uint256[] memory scores = new uint256[](maxClans);
        uint256[] memory indices = new uint256[](maxClans);

        for (uint256 i = 1; i <= maxClans; i++) {
            scores[i - 1] = clans[i].battleScore;
            indices[i - 1] = i;
        }

        for (uint256 i = 0; i < count; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < maxClans; j++) {
                if (scores[j] > scores[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                uint256 tempScore = scores[i];
                uint256 tempIndex = indices[i];
                scores[i] = scores[maxIndex];
                indices[i] = indices[maxIndex];
                scores[maxIndex] = tempScore;
                indices[maxIndex] = tempIndex;
            }
            topClans[i] = clans[indices[i]];
        }

        return topClans;
    }

    function updateClanStats(uint256 clanId) external {
        _updateClanStats(clanId);
    }

    function changeClanName(
        uint256 clanId,
        string memory newName
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        Clan storage clan = clans[clanId];
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        if (msg.sender != clan.leader) {
            revert Unauthorized();
        }
        if (bytes(newName).length == 0 || bytes(newName).length > 32) {
            revert InvalidClanName();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        string memory oldName = clan.name;
        clan.name = newName;

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanNameChanged(
            clanId,
            oldName,
            newName,
            msg.sender,
            block.timestamp
        );
    }

    function transferLeadership(
        uint256 clanId,
        address newLeader
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        Clan storage clan = clans[clanId];
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        if (msg.sender != clan.leader) {
            revert Unauthorized();
        }
        if (newLeader == address(0)) {
            revert InvalidAddress();
        }
        if (newLeader == msg.sender) {
            revert(); // Cannot transfer to self
        }

        ClanMember memory newLeaderMember = clanMembers[clanId][newLeader];
        if (newLeaderMember.status != MembershipStatus.Active) {
            revert(); // New leader must be an active member
        }

        ctx.completeChecks();

        ctx.requireEffects();
        address oldLeader = clan.leader;
        clan.leader = newLeader;

        ctx.completeEffects();

        ctx.requireInteractions();
        emit LeadershipTransferred(
            clanId,
            oldLeader,
            newLeader,
            block.timestamp
        );
    }

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
        )
    {
        Clan memory clan = clans[clanId];
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        return (
            clan.clanId,
            clan.leader,
            clan.name,
            clan.description,
            clan.createdAt,
            clan.totalScore,
            clan.battleScore,
            clan.totalWins,
            clan.memberCount,
            clanMemberList[clanId]
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setHiloContract(address payable _hiloContract) external onlyOwner {
        if (_hiloContract == address(0)) {
            revert InvalidAddress();
        }
        hiloContract = CardWarsHiLo(_hiloContract);
    }

    address public battleContract;

    function setBattleContract(address _battleContract) external onlyOwner {
        if (_battleContract == address(0)) {
            revert InvalidAddress();
        }
        battleContract = _battleContract;
    }

    function setMarketplaceContract(
        address _marketplaceContract
    ) external onlyOwner {
        if (_marketplaceContract == address(0)) {
            revert InvalidAddress();
        }
        marketplaceContract = CardWarsMarketplace(_marketplaceContract);
    }

    function adminWithdraw(uint256 _amount) external onlyOwner nonReentrant {
        CEILib.CEIContext memory ctx;
        ctx.init();

        ctx.requireChecks();
        if (address(this).balance < _amount) {
            revert InsufficientContractBalance();
        }
        ctx.completeChecks();

        ctx.requireEffects();
        ctx.completeEffects();

        ctx.requireInteractions();
        (bool success, ) = payable(owner()).call{value: _amount}("");
        if (!success) {
            revert TransferNotAllowed();
        }
    }

    function addBattleScore(uint256 clanId, uint256 battlePoints) external {
        if (msg.sender != battleContract && msg.sender != owner()) {
            revert Unauthorized();
        }
        Clan storage clan = clans[clanId];
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        clan.battleScore += battlePoints;
        emit ClanLeaderboardUpdated(
            clanId,
            clan.totalScore,
            clan.totalWins,
            block.timestamp
        );
    }

    function applyCosmetic(
        uint256 clanId,
        uint256 marketplaceItemId,
        string memory cosmeticType
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Clan storage clan = clans[clanId];

        ctx.requireChecks();
        if (clan.leader != msg.sender) {
            revert Unauthorized();
        }
        if (address(marketplaceContract) == address(0)) {
            revert InvalidAddress();
        }

        CardWarsMarketplace.MarketplaceItem memory item = marketplaceContract
            .getItem(marketplaceItemId);

        if (item.id == 0) {
            revert ItemDoesNotExist();
        }
        if (!item.active) {
            revert ItemNotActive();
        }
        if (item.itemType != CardWarsMarketplace.ItemType.ClanCosmetic) {
            revert InvalidItemType();
        }

        // Check if user has purchased this specific item
        uint256 itemPurchaseCount = marketplaceContract
            .getUserItemPurchaseCount(msg.sender, marketplaceItemId);
        if (itemPurchaseCount == 0) {
            revert InsufficientBalance();
        }

        ctx.completeChecks();

        ctx.requireEffects();
        if (clanCosmetics[clanId][cosmeticType] == 0) {
            clanActiveCosmetics[clanId].push(cosmeticType);
        }
        clanCosmetics[clanId][cosmeticType] = marketplaceItemId;

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanCosmeticApplied(
            clanId,
            marketplaceItemId,
            cosmeticType,
            block.timestamp
        );
    }

    function getClanCosmetic(
        uint256 clanId,
        string memory cosmeticType
    ) external view returns (uint256) {
        return clanCosmetics[clanId][cosmeticType];
    }

    function getClanActiveCosmetics(
        uint256 clanId
    ) external view returns (string[] memory) {
        return clanActiveCosmetics[clanId];
    }

    function inviteMember(
        uint256 clanId,
        address invitee
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Clan storage clan = clans[clanId];

        ctx.requireChecks();
        if (clan.leader != msg.sender) {
            revert Unauthorized();
        }
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        if (clan.memberCount >= MAX_CLAN_MEMBERS) {
            revert ClanFull();
        }
        if (userClan[invitee] != 0) {
            revert AlreadyInClan();
        }
        if (clanMembers[clanId][invitee].status == MembershipStatus.Active) {
            revert AlreadyInClan();
        }
        if (clanInvitations[clanId][invitee].pending) {
            revert(); // Invitation already pending
        }

        ctx.completeChecks();

        ctx.requireEffects();
        clanInvitations[clanId][invitee] = ClanInvitation({
            invitee: invitee,
            inviter: msg.sender,
            invitedAt: block.timestamp,
            pending: true
        });

        // Add to pending invitations list if not already there
        uint256[] storage userInvites = pendingInvitations[invitee];
        bool alreadyInList = false;
        for (uint256 i = 0; i < userInvites.length; i++) {
            if (userInvites[i] == clanId) {
                alreadyInList = true;
                break;
            }
        }
        if (!alreadyInList) {
            pendingInvitations[invitee].push(clanId);
        }

        // Add to sent invitations list
        sentInvitations[clanId].push(invitee);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanInvitationSent(clanId, invitee, msg.sender, block.timestamp);
    }

    function acceptInvitation(
        uint256 clanId
    ) external nonReentrant whenNotPaused {
        CEILib.CEIContext memory ctx;
        ctx.init();

        Clan storage clan = clans[clanId];

        ctx.requireChecks();
        if (clan.clanId == 0) {
            revert ClanNotFound();
        }
        if (userClan[msg.sender] != 0) {
            revert AlreadyInClan();
        }
        if (clan.memberCount >= MAX_CLAN_MEMBERS) {
            revert ClanFull();
        }

        ClanInvitation storage invitation = clanInvitations[clanId][msg.sender];
        if (!invitation.pending) {
            revert(); // No pending invitation
        }

        ClanMember memory existingMember = clanMembers[clanId][msg.sender];
        if (existingMember.status == MembershipStatus.Removed) {
            if (existingMember.removedAt + REMOVAL_COOLDOWN > block.timestamp) {
                revert CooldownNotExpired();
            }
        }

        ctx.completeChecks();

        ctx.requireEffects();
        invitation.pending = false;

        userClan[msg.sender] = clanId;
        clanMembers[clanId][msg.sender] = ClanMember({
            member: msg.sender,
            status: MembershipStatus.Active,
            joinedAt: block.timestamp,
            removedAt: 0
        });

        clanMemberList[clanId].push(msg.sender);
        clan.memberCount++;

        // Remove from pending invitations
        uint256[] storage userInvites = pendingInvitations[msg.sender];
        for (uint256 i = 0; i < userInvites.length; i++) {
            if (userInvites[i] == clanId) {
                userInvites[i] = userInvites[userInvites.length - 1];
                userInvites.pop();
                break;
            }
        }

        _updateClanStats(clanId);

        ctx.completeEffects();

        ctx.requireInteractions();
        emit ClanInvitationAccepted(
            clanId,
            msg.sender,
            invitation.inviter,
            block.timestamp
        );
    }

    function rejectInvitation(
        uint256 clanId
    ) external nonReentrant whenNotPaused {
        Clan storage clan = clans[clanId];

        if (clan.clanId == 0) {
            revert ClanNotFound();
        }

        ClanInvitation storage invitation = clanInvitations[clanId][msg.sender];
        if (!invitation.pending) {
            revert(); // No pending invitation
        }

        address inviter = invitation.inviter;
        invitation.pending = false;

        // Remove from pending invitations
        uint256[] storage userInvites = pendingInvitations[msg.sender];
        for (uint256 i = 0; i < userInvites.length; i++) {
            if (userInvites[i] == clanId) {
                userInvites[i] = userInvites[userInvites.length - 1];
                userInvites.pop();
                break;
            }
        }

        emit ClanInvitationRejected(
            clanId,
            msg.sender,
            inviter,
            block.timestamp
        );
    }

    function getPendingInvitations(
        address user
    ) external view returns (uint256[] memory) {
        return pendingInvitations[user];
    }

    function getSentInvitations(
        uint256 clanId
    ) external view returns (address[] memory) {
        return sentInvitations[clanId];
    }

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
        )
    {
        if (clans[clanId].clanId == 0) {
            revert ClanNotFound();
        }

        address[] memory clanMemberListArray = clanMemberList[clanId];
        uint256 activeCount = 0;

        for (uint256 i = 0; i < clanMemberListArray.length; i++) {
            if (
                clanMembers[clanId][clanMemberListArray[i]].status ==
                MembershipStatus.Active
            ) {
                activeCount++;
            }
        }

        members = new address[](activeCount);
        battleWins = new uint256[](activeCount);
        battleLosses = new uint256[](activeCount);
        battleWinRates = new uint256[](activeCount);

        uint256 index = 0;
        for (uint256 i = 0; i < clanMemberListArray.length; i++) {
            ClanMember memory member = clanMembers[clanId][
                clanMemberListArray[i]
            ];
            if (member.status == MembershipStatus.Active) {
                members[index] = clanMemberListArray[i];
                if (address(battleContract) != address(0)) {
                    (uint256 wins, uint256 losses, ) = IBattle(battleContract)
                        .getUserBattleStats(clanMemberListArray[i]);
                    battleWins[index] = wins;
                    battleLosses[index] = losses;
                    uint256 totalBattles = wins + losses;
                    battleWinRates[index] = totalBattles > 0
                        ? (wins * 10000) / totalBattles
                        : 0;
                } else {
                    battleWins[index] = 0;
                    battleLosses[index] = 0;
                    battleWinRates[index] = 0;
                }
                index++;
            }
        }
    }

    function getPlayersWithoutClan() external view returns (address[] memory) {
        if (address(hiloContract) == address(0)) {
            return new address[](0);
        }

        address[] memory allPlayers = CardWarsHiLo(payable(hiloContract))
            .getAllPlayers();
        address[] memory playersWithoutClan = new address[](allPlayers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allPlayers.length; i++) {
            if (userClan[allPlayers[i]] == 0) {
                playersWithoutClan[count] = allPlayers[i];
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = playersWithoutClan[i];
        }
        return result;
    }

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
        )
    {
        if (clans[clanId].clanId == 0) {
            revert ClanNotFound();
        }

        address[] memory clanMemberListArray = clanMemberList[clanId];
        uint256 activeCount = 0;

        for (uint256 i = 0; i < clanMemberListArray.length; i++) {
            ClanMember memory member = clanMembers[clanId][
                clanMemberListArray[i]
            ];
            if (member.status == MembershipStatus.Active) {
                activeCount++;
            }
        }

        if (activeCount == 0) {
            return (
                new address[](0),
                new uint256[](0),
                new uint256[](0),
                new uint256[](0)
            );
        }

        address[] memory sortedMembers = new address[](activeCount);
        uint256[] memory values = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < clanMemberListArray.length; i++) {
            ClanMember memory member = clanMembers[clanId][
                clanMemberListArray[i]
            ];
            if (member.status == MembershipStatus.Active) {
                sortedMembers[index] = clanMemberListArray[i];
                (, , , , uint256 hiloWins, uint256 superGems, ) = hiloContract
                    .getUserStats(clanMemberListArray[i]);

                uint256 battleWinsCount = 0;
                if (address(battleContract) != address(0)) {
                    (battleWinsCount, , ) = IBattle(battleContract)
                        .getUserBattleStats(clanMemberListArray[i]);
                }

                if (sortBy == 0) {
                    values[index] = hiloWins;
                } else if (sortBy == 1) {
                    values[index] = battleWinsCount;
                } else {
                    values[index] = superGems;
                }
                index++;
            }
        }

        uint256 count = activeCount < limit ? activeCount : limit;

        for (uint256 i = 0; i < count; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < activeCount; j++) {
                if (values[j] > values[maxIndex]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                address tempAddr = sortedMembers[i];
                uint256 tempVal = values[i];
                sortedMembers[i] = sortedMembers[maxIndex];
                values[i] = values[maxIndex];
                sortedMembers[maxIndex] = tempAddr;
                values[maxIndex] = tempVal;
            }
        }

        addresses = new address[](count);
        totalWins = new uint256[](count);
        battleWins = new uint256[](count);
        superGemPoints = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = sortedMembers[i];
            (, , , , uint256 hiloWins, uint256 superGems, ) = hiloContract
                .getUserStats(sortedMembers[i]);
            totalWins[i] = hiloWins;
            superGemPoints[i] = superGems;

            if (address(battleContract) != address(0)) {
                (battleWins[i], , ) = IBattle(battleContract)
                    .getUserBattleStats(sortedMembers[i]);
            } else {
                battleWins[i] = 0;
            }
        }
    }

    function getClanLeaders() external view returns (address[] memory) {
        address[] memory leaders = new address[](clanCounter);
        uint256 count = 0;

        for (uint256 i = 1; i <= clanCounter; i++) {
            if (clans[i].leader != address(0)) {
                leaders[count] = clans[i].leader;
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = leaders[i];
        }
        return result;
    }

    function getClansByMember(
        address member
    ) external view returns (uint256[] memory) {
        uint256[] memory memberClans = new uint256[](clanCounter);
        uint256 count = 0;

        for (uint256 i = 1; i <= clanCounter; i++) {
            ClanMember memory memberData = clanMembers[i][member];
            if (
                memberData.status == MembershipStatus.Active ||
                memberData.status == MembershipStatus.Removed
            ) {
                memberClans[count] = i;
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = memberClans[i];
        }
        return result;
    }
}
