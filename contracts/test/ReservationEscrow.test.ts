import { expect } from "chai";
import { ContractFactory } from "ethers";
import { ethers, network } from "hardhat";
import type { Contract } from "ethers";
import solc from "solc";

const ZERO = ethers.ZeroAddress;
const COP_TOKEN_UNITS = 100n;
const USDT_TOKEN_UNITS = 1_000_000n;
const DEFAULT_DEADLINE = 4_000_000_000n;

type Fixture = {
  owner: any;
  signer: any;
  customer: any;
  agency: any;
  other: any;
  token: any;
  escrow: any;
};

type ActionCode = 0 | 1 | 2 | 3;
type Permit = {
  reservationId: string;
  listingId: string;
  customer: string;
  agency: string;
  actor: string;
  action: ActionCode;
  amount: bigint;
  deadline: bigint;
  nonce: bigint;
};

type PermitOptions = Partial<Permit> & {
  signer?: any;
  chainId?: bigint;
  verifyingContract?: string;
};

const ACTION_TYPES = {
  ReservationAction: [
    { name: "reservationId", type: "bytes32" },
    { name: "listingId", type: "bytes32" },
    { name: "customer", type: "address" },
    { name: "agency", type: "address" },
    { name: "actor", type: "address" },
    { name: "action", type: "uint8" },
    { name: "amount", type: "uint256" },
    { name: "deadline", type: "uint64" },
    { name: "nonce", type: "uint256" },
  ],
};

function idHash(value: string): string {
  return ethers.keccak256(ethers.toUtf8Bytes(value));
}

async function deployFixture(): Promise<Fixture> {
  const [owner, signer, customer, agency, other] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("RoomForgeTestToken");
  const token = await Token.deploy(owner.address);
  await token.waitForDeployment();
  const Escrow = await ethers.getContractFactory("ReservationEscrow");
  const escrow = await Escrow.deploy(await token.getAddress(), signer.address);
  await escrow.waitForDeployment();
  return { owner, signer, customer, agency, other, token, escrow };
}

async function deployUsdtFixture(): Promise<Fixture> {
  const [owner, signer, customer, agency, other] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("MockUSDT");
  const token = await Token.deploy(owner.address);
  await token.waitForDeployment();
  const Escrow = await ethers.getContractFactory("ReservationEscrow");
  const escrow = await Escrow.deploy(await token.getAddress(), signer.address);
  await escrow.waitForDeployment();
  return { owner, signer, customer, agency, other, token, escrow };
}

async function currentTime(): Promise<bigint> {
  const block = await ethers.provider.getBlock("latest");
  if (!block) throw new Error("Latest block is unavailable");
  return BigInt(block.timestamp);
}

async function makePermit(
  fixture: Fixture,
  options: PermitOptions = {},
): Promise<{ permit: Permit; signature: string }> {
  const reservationId = options.reservationId ?? idHash("reservation-1");
  const listingId = options.listingId ?? idHash("listing-1");
  const customer = options.customer ?? fixture.customer.address;
  const agency = options.agency ?? fixture.agency.address;
  const action = options.action ?? 0;
  const amount = options.amount ?? 0n;
  const deadline = options.deadline ?? DEFAULT_DEADLINE;
  const nonce = options.nonce ?? (await fixture.escrow.nonces(reservationId));
  const permit: Permit = {
    reservationId,
    listingId,
    customer,
    agency,
    actor: options.actor ?? (action === 0 || action === 3 ? customer : agency),
    action,
    amount,
    deadline,
    nonce,
  };
  const chain = await ethers.provider.getNetwork();
  const domain = {
    name: "RoomForgeReservationEscrow",
    version: "1",
    chainId: options.chainId ?? chain.chainId,
    verifyingContract: options.verifyingContract ?? (await fixture.escrow.getAddress()),
  };
  const signature = await (options.signer ?? fixture.signer).signTypedData(
    domain,
    ACTION_TYPES,
    permit,
  );
  return { permit, signature };
}

async function fundAndApprove(
  fixture: Fixture,
  amount: bigint,
): Promise<void> {
  await fixture.token.connect(fixture.owner).mint(fixture.customer.address, amount);
  await fixture.token.connect(fixture.customer).approve(
    await fixture.escrow.getAddress(),
    amount,
  );
}

async function deposit(
  fixture: Fixture,
  options: PermitOptions = {},
): Promise<{ permit: Permit; signature: string }> {
  const amount = options.amount ?? 5n * COP_TOKEN_UNITS;
  await fundAndApprove(fixture, amount);
  const signed = await makePermit(fixture, { ...options, action: 0, amount });
  await fixture.escrow.connect(fixture.customer).deposit(signed.permit, signed.signature);
  return signed;
}

async function setTime(timestamp: bigint): Promise<void> {
  await network.provider.send("evm_setNextBlockTimestamp", [Number(timestamp)]);
}

const CALLBACK_TOKEN_SOURCE = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
contract CallbackToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bool public failTransfers;

    function decimals() external pure returns (uint8) { return 2; }
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function setFailTransfers(bool value) external { failTransfers = value; }
    function setCallback(address target, bytes calldata data) external {
        callbackTarget = target;
        callbackData = data;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        _move(msg.sender, to, amount);
        _callback();
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        uint256 permitted = allowance[from][msg.sender];
        require(permitted >= amount, "allowance");
        allowance[from][msg.sender] = permitted - amount;
        _move(from, to, amount);
        _callback();
        return true;
    }
    function _move(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
    function _callback() private {
        if (callbackTarget != address(0)) {
            (callbackSucceeded, ) = callbackTarget.call(callbackData);
        }
    }
}`;

async function deployCallbackToken(owner: any): Promise<Contract> {
  const input = {
    language: "Solidity",
    sources: { "CallbackToken.sol": { content: CALLBACK_TOKEN_SOURCE } },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "cancun",
      outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } },
    },
  };
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (output.errors ?? []).filter(
    (entry: { severity: string }) => entry.severity === "error",
  );
  if (errors.length > 0) throw new Error(errors.map((entry: { formattedMessage: string }) => entry.formattedMessage).join("\n"));
  const compiled = output.contracts["CallbackToken.sol"].CallbackToken;
  const factory = new ContractFactory(compiled.abi, `0x${compiled.evm.bytecode.object}`, owner);
  const token = await factory.deploy();
  await token.waitForDeployment();
  return token;
}

const CONFIGURABLE_FEE_TOKEN_SOURCE = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
contract ConfigurableFeeToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public immutable decimals;
    uint256 public feeBps;

    constructor(uint8 tokenDecimals, uint256 initialFeeBps) {
        decimals = tokenDecimals;
        feeBps = initialFeeBps;
    }
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function setFeeBps(uint256 value) external { feeBps = value; }
    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 permitted = allowance[from][msg.sender];
        require(permitted >= amount, "allowance");
        allowance[from][msg.sender] = permitted - amount;
        _move(from, to, amount);
        return true;
    }
    function _move(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "balance");
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
    }
}`;

async function deployConfigurableFeeToken(owner: any, decimals = 2): Promise<Contract> {
  const input = {
    language: "Solidity",
    sources: { "ConfigurableFeeToken.sol": { content: CONFIGURABLE_FEE_TOKEN_SOURCE } },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "cancun",
      outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } },
    },
  };
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (output.errors ?? []).filter(
    (entry: { severity: string }) => entry.severity === "error",
  );
  if (errors.length > 0) throw new Error(errors.map((entry: { formattedMessage: string }) => entry.formattedMessage).join("\n"));
  const compiled = output.contracts["ConfigurableFeeToken.sol"].ConfigurableFeeToken;
  const factory = new ContractFactory(compiled.abi, `0x${compiled.evm.bytecode.object}`, owner);
  const token = await factory.deploy(decimals, 0);
  await token.waitForDeployment();
  return token;
}

describe("RoomForgeTestToken", function () {
  it("uses two decimals and converts COP amounts to exact integer base units", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("125.75", 2);
    await fixture.token.connect(fixture.owner).mint(fixture.customer.address, amount);

    expect(await fixture.token.decimals()).to.equal(2);
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(12575n);
    expect(ethers.parseUnits("125.75", 2)).to.equal(12575n);
  });

  it("allows only the owner to mint test tokens", async function () {
    const fixture = await deployFixture();
    await expect(
      fixture.token.connect(fixture.other).mint(fixture.customer.address, 100n),
    ).to.be.revertedWithCustomError(fixture.token, "OwnableUnauthorizedAccount");
  });
});

describe("MockUSDT", function () {
  it("uses six decimals and mints USDT-like base units", async function () {
    const fixture = await deployUsdtFixture();
    const amount = ethers.parseUnits("1.50", 6);
    await fixture.token.connect(fixture.owner).mint(fixture.customer.address, amount);

    expect(await fixture.token.decimals()).to.equal(6);
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(1_500_000n);
    expect(ethers.parseUnits("1.50", 6)).to.equal(USDT_TOKEN_UNITS + 500_000n);
  });

  it("allows only the owner to mint USDT-like tokens", async function () {
    const fixture = await deployUsdtFixture();
    await expect(
      fixture.token.connect(fixture.other).mint(fixture.customer.address, 1_000_000n),
    ).to.be.revertedWithCustomError(fixture.token, "OwnableUnauthorizedAccount");
  });
});

describe("ReservationEscrow with a USDT-like six-decimal token", function () {
  it("deposits and accepts a 1.00 USDT reservation moving exact base units", async function () {
    const fixture = await deployUsdtFixture();
    const amount = ethers.parseUnits("1.00", 6);
    await fundAndApprove(fixture, amount);
    const signed = await makePermit(fixture, { amount });

    await expect(
      fixture.escrow.connect(fixture.customer).deposit(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Deposited").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      amount,
      0n,
    );
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(1_000_000n);

    const accept = await makePermit(fixture, { action: 1, amount });
    await expect(
      fixture.escrow.connect(fixture.agency).accept(accept.permit, accept.signature),
    ).to.emit(fixture.escrow, "Accepted").withArgs(
      accept.permit.reservationId,
      accept.permit.listingId,
      fixture.agency.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.agency.address)).to.equal(1_000_000n);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(0n);
    expect((await fixture.escrow.reservation(accept.permit.reservationId)).status).to.equal(2n);
  });

  it("refunds the exact USDT deposit to the customer on reject", async function () {
    const fixture = await deployUsdtFixture();
    const amount = ethers.parseUnits("2.25", 6);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 2, amount });

    await expect(
      fixture.escrow.connect(fixture.agency).reject(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Rejected").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(0n);
  });

  it("refunds the exact USDT deposit when the customer cancels", async function () {
    const fixture = await deployUsdtFixture();
    const amount = ethers.parseUnits("0.75", 6);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 3, amount, actor: fixture.customer.address });

    await expect(
      fixture.escrow.connect(fixture.customer).cancel(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Cancelled").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
  });

  it("expires at the deadline and permissionlessly refunds the USDT deposit", async function () {
    const fixture = await deployUsdtFixture();
    const deadline = (await currentTime()) + 100n;
    const amount = ethers.parseUnits("3.10", 6);
    await deposit(fixture, { amount, deadline });

    await expect(fixture.escrow.connect(fixture.other).expire(idHash("reservation-1")))
      .to.be.revertedWithCustomError(fixture.escrow, "NotExpirable");
    await setTime(deadline);
    await expect(fixture.escrow.connect(fixture.other).expire(idHash("reservation-1")))
      .to.emit(fixture.escrow, "Expired").withArgs(
        idHash("reservation-1"),
        idHash("listing-1"),
        fixture.customer.address,
        amount,
        1n,
      );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
    expect((await fixture.escrow.reservation(idHash("reservation-1"))).status).to.equal(5n);
  });
});

describe("ReservationEscrow EIP-712 authorization", function () {
  it("rejects signatures made for another verifying contract", async function () {
    const fixture = await deployFixture();
    const Escrow = await ethers.getContractFactory("ReservationEscrow");
    const secondEscrow = await Escrow.deploy(await fixture.token.getAddress(), fixture.signer.address);
    await secondEscrow.waitForDeployment();
    const signed = await makePermit(fixture, { action: 1, verifyingContract: await fixture.escrow.getAddress() });

    await expect(
      secondEscrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(secondEscrow, "InvalidSigner");
  });

  it("rejects signatures made for another chain id", async function () {
    const fixture = await deployFixture();
    const chain = await ethers.provider.getNetwork();
    const signed = await makePermit(fixture, { action: 1, chainId: chain.chainId + 1n });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InvalidSigner");
  });

  it("rejects a signature from a key other than the configured backend signer", async function () {
    const fixture = await deployFixture();
    const signed = await makePermit(fixture, { action: 1, signer: fixture.other });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InvalidSigner");
  });

  it("requires the wallet submitting an action to equal its signed actor", async function () {
    const fixture = await deployFixture();
    const signed = await makePermit(fixture, {
      action: 1,
      actor: fixture.customer.address,
    });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "UnauthorizedActor");
  });

  it("rejects permits at or after their deadline", async function () {
    const fixture = await deployFixture();
    const deadline = (await currentTime()) + 20n;
    const signed = await makePermit(fixture, { action: 1, deadline });
    await setTime(deadline);

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "DeadlinePassed");
  });

  it("rejects stale/replayed nonces without changing the reservation", async function () {
    const fixture = await deployFixture();
    const signed = await makePermit(fixture, { action: 3 });
    await fixture.escrow.connect(fixture.customer).cancel(signed.permit, signed.signature);

    await expect(
      fixture.escrow.connect(fixture.customer).cancel(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InvalidNonce");
    expect(await fixture.escrow.nonces(signed.permit.reservationId)).to.equal(1n);
  });

  it("keeps monotonic nonces isolated per reservation", async function () {
    const fixture = await deployFixture();
    const first = await makePermit(fixture, {
      action: 3,
      reservationId: idHash("reservation-a"),
      listingId: idHash("listing-a"),
    });
    const second = await makePermit(fixture, {
      action: 3,
      reservationId: idHash("reservation-b"),
      listingId: idHash("listing-b"),
    });

    await fixture.escrow.connect(fixture.customer).cancel(first.permit, first.signature);
    await fixture.escrow.connect(fixture.customer).cancel(second.permit, second.signature);
    expect(await fixture.escrow.nonces(first.permit.reservationId)).to.equal(1n);
    expect(await fixture.escrow.nonces(second.permit.reservationId)).to.equal(1n);
  });

  it("binds listing and immutable reservation terms across later actions", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("2.50", 2);
    await deposit(fixture, { amount });
    const alteredListing = await makePermit(fixture, {
      action: 1,
      amount,
      listingId: idHash("different-listing"),
    });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(alteredListing.permit, alteredListing.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "ReservationMismatch");
    expect(await fixture.escrow.nonces(alteredListing.permit.reservationId)).to.equal(1n);

    const valid = await makePermit(fixture, { action: 1, amount });
    await fixture.escrow.connect(fixture.agency).accept(valid.permit, valid.signature);
    expect((await fixture.escrow.reservation(valid.permit.reservationId)).status).to.equal(2n);
  });
});

describe("ReservationEscrow deposits and transitions", function () {
  it("deposits the exact COP-scaled amount under a valid customer permit", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("38.42", 2);
    await fundAndApprove(fixture, amount);
    const signed = await makePermit(fixture, { amount });

    await expect(
      fixture.escrow.connect(fixture.customer).deposit(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Deposited").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      amount,
      0n,
    );
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(3842n);
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).depositedAmount).to.equal(amount);
  });

  it("requires a positive deposit amount and the customer's wallet", async function () {
    const fixture = await deployFixture();
    const zeroAmount = await makePermit(fixture, { amount: 0n });
    await expect(
      fixture.escrow.connect(fixture.customer).deposit(zeroAmount.permit, zeroAmount.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InvalidDepositAmount");

    const amount = ethers.parseUnits("1.00", 2);
    await fundAndApprove(fixture, amount);
    const wrongActor = await makePermit(fixture, { amount, actor: fixture.agency.address });
    await expect(
      fixture.escrow.connect(fixture.agency).deposit(wrongActor.permit, wrongActor.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "UnauthorizedActor");
  });

  it("requires sufficient token allowance and preserves nonce/state after transfer failure", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("2.00", 2);
    await fixture.token.connect(fixture.owner).mint(fixture.customer.address, amount);
    const signed = await makePermit(fixture, { amount });

    await expect(
      fixture.escrow.connect(fixture.customer).deposit(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.token, "ERC20InsufficientAllowance");
    expect(await fixture.escrow.nonces(signed.permit.reservationId)).to.equal(0n);
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(0n);
  });

  it("rejects duplicate deposits and deposits after a terminal action", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("3.00", 2);
    await deposit(fixture, { amount });
    const duplicate = await makePermit(fixture, { amount });
    await expect(
      fixture.escrow.connect(fixture.customer).deposit(duplicate.permit, duplicate.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "DepositAlreadyMade");

    const rejection = await makePermit(fixture, { action: 2, amount });
    await fixture.escrow.connect(fixture.agency).reject(rejection.permit, rejection.signature);
    const lateDeposit = await makePermit(fixture, { amount });
    await expect(
      fixture.escrow.connect(fixture.customer).deposit(lateDeposit.permit, lateDeposit.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "ReservationNotPending");
  });

  it("creates a no-deposit accepted reservation on the first authorized decision", async function () {
    const fixture = await deployFixture();
    const signed = await makePermit(fixture, { action: 1, amount: 0n });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Accepted").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.agency.address,
      0n,
      0n,
    );
    const record = await fixture.escrow.reservation(signed.permit.reservationId);
    expect(record.status).to.equal(2n);
    expect(record.depositedAmount).to.equal(0n);
    expect(await fixture.token.balanceOf(fixture.agency.address)).to.equal(0n);
  });

  it("creates a no-deposit rejected reservation on the first authorized decision", async function () {
    const fixture = await deployFixture();
    const signed = await makePermit(fixture, { action: 2, amount: 0n });

    await expect(
      fixture.escrow.connect(fixture.agency).reject(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Rejected").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      0n,
      0n,
    );
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(3n);
  });

  it("creates a no-deposit cancelled reservation on the first authorized action", async function () {
    const fixture = await deployFixture();
    const signed = await makePermit(fixture, { action: 3, amount: 0n });

    await expect(
      fixture.escrow.connect(fixture.customer).cancel(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Cancelled").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      0n,
      0n,
    );
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(4n);
  });

  it("allows first-action cancellation when a positive deposit was configured but not transferred", async function () {
    const fixture = await deployFixture();
    const configuredAmount = ethers.parseUnits("75.00", 2);
    const signed = await makePermit(fixture, { action: 3, amount: configuredAmount });

    await expect(
      fixture.escrow.connect(fixture.customer).cancel(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Cancelled").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      0n,
      0n,
    );
    const record = await fixture.escrow.reservation(signed.permit.reservationId);
    expect(record.amount).to.equal(configuredAmount);
    expect(record.depositedAmount).to.equal(0n);
  });

  it("requires a configured positive deposit before agency accept or reject", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("14.25", 2);
    const acceptPermit = await makePermit(fixture, { action: 1, amount });
    await expect(
      fixture.escrow.connect(fixture.agency).accept(acceptPermit.permit, acceptPermit.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "DepositRequired");

    const rejectPermit = await makePermit(fixture, { action: 2, amount });
    await expect(
      fixture.escrow.connect(fixture.agency).reject(rejectPermit.permit, rejectPermit.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "DepositRequired");
    expect((await fixture.escrow.reservation(acceptPermit.permit.reservationId)).status).to.equal(0n);
  });

  it("pays the agency on accept and leaves the reservation accepted without a release function", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("14.25", 2);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 1, amount });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Accepted").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.agency.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.agency.address)).to.equal(amount);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(0n);
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(2n);
    const functionNames = fixture.escrow.interface.fragments
      .filter((fragment: any) => fragment.type === "function")
      .map((fragment: any) => fragment.name);
    expect(functionNames).not.to.include("release");
  });

  it("refunds the exact deposited amount to the customer on reject", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("9.99", 2);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 2, amount });

    await expect(
      fixture.escrow.connect(fixture.agency).reject(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Rejected").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(0n);
  });

  it("refunds deposited tokens when the customer cancels", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("7.50", 2);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 3, amount, actor: fixture.customer.address });

    await expect(
      fixture.escrow.connect(fixture.customer).cancel(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Cancelled").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.customer.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
  });

  it("refunds deposited tokens when the same-agency wallet cancels", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("6.25", 2);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 3, amount, actor: fixture.agency.address });

    await expect(
      fixture.escrow.connect(fixture.agency).cancel(signed.permit, signed.signature),
    ).to.emit(fixture.escrow, "Cancelled").withArgs(
      signed.permit.reservationId,
      signed.permit.listingId,
      fixture.agency.address,
      amount,
      1n,
    );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
  });

  it("expires only at or after deadline and permissionlessly refunds a deposited reservation", async function () {
    const fixture = await deployFixture();
    const deadline = (await currentTime()) + 100n;
    const amount = ethers.parseUnits("18.10", 2);
    await deposit(fixture, { amount, deadline });

    await expect(fixture.escrow.connect(fixture.other).expire(idHash("reservation-1")))
      .to.be.revertedWithCustomError(fixture.escrow, "NotExpirable");
    await setTime(deadline);
    await expect(fixture.escrow.connect(fixture.other).expire(idHash("reservation-1")))
      .to.emit(fixture.escrow, "Expired").withArgs(
        idHash("reservation-1"),
        idHash("listing-1"),
        fixture.customer.address,
        amount,
        1n,
      );
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
    expect((await fixture.escrow.reservation(idHash("reservation-1"))).status).to.equal(5n);
  });

  it("does not require or create an on-chain expiry record for an untouched no-deposit reservation", async function () {
    const fixture = await deployFixture();
    const reservationId = idHash("reservation-without-deposit");

    await expect(
      fixture.escrow.connect(fixture.other).expire(reservationId),
    ).to.be.revertedWithCustomError(fixture.escrow, "ReservationNotPending");
    expect((await fixture.escrow.reservation(reservationId)).status).to.equal(0n);
  });

  it("rejects decision and cancellation transactions mined at the deadline", async function () {
    const acceptFixture = await deployFixture();
    const acceptDeadline = (await currentTime()) + 100n;
    await deposit(acceptFixture, { amount: 100n, deadline: acceptDeadline });
    const accept = await makePermit(acceptFixture, { action: 1, amount: 100n, deadline: acceptDeadline });
    await setTime(acceptDeadline);
    await expect(
      acceptFixture.escrow.connect(acceptFixture.agency).accept(accept.permit, accept.signature),
    ).to.be.revertedWithCustomError(acceptFixture.escrow, "DeadlinePassed");

    const cancelFixture = await deployFixture();
    const cancelDeadline = (await currentTime()) + 100n;
    await deposit(cancelFixture, { amount: 100n, deadline: cancelDeadline });
    const cancel = await makePermit(cancelFixture, { action: 3, amount: 100n, deadline: cancelDeadline });
    await setTime(cancelDeadline);
    await expect(
      cancelFixture.escrow.connect(cancelFixture.customer).cancel(cancel.permit, cancel.signature),
    ).to.be.revertedWithCustomError(cancelFixture.escrow, "DeadlinePassed");
  });

  it("cannot expire an accepted reservation and exposes no accepted-release path", async function () {
    const fixture = await deployFixture();
    const amount = ethers.parseUnits("1.00", 2);
    await deposit(fixture, { amount });
    const signed = await makePermit(fixture, { action: 1, amount });
    await fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature);

    await expect(
      fixture.escrow.connect(fixture.other).expire(signed.permit.reservationId),
    ).to.be.revertedWithCustomError(fixture.escrow, "ReservationNotPending");
    const functionNames = fixture.escrow.interface.fragments
      .filter((fragment: any) => fragment.type === "function")
      .map((fragment: any) => fragment.name);
    expect(functionNames).not.to.include("release");
  });
});

describe("ReservationEscrow token configuration and exact transfers", function () {
  async function feeTokenFixture(decimals = 2): Promise<Fixture> {
    const [owner, signer, customer, agency, other] = await ethers.getSigners();
    const token = await deployConfigurableFeeToken(owner, decimals);
    const Escrow = await ethers.getContractFactory("ReservationEscrow");
    const escrow = await Escrow.deploy(await token.getAddress(), signer.address);
    await escrow.waitForDeployment();
    return { owner, signer, customer, agency, other, token, escrow };
  }

  it("rejects a token whose metadata reports fewer than two decimals", async function () {
    const [owner, signer] = await ethers.getSigners();
    const token = await deployConfigurableFeeToken(owner, 1);
    const Escrow = await ethers.getContractFactory("ReservationEscrow");

    await expect(Escrow.deploy(await token.getAddress(), signer.address)).to.be.revertedWithCustomError(
      Escrow,
      "InvalidTokenConfiguration",
    );
  });

  it("rejects a fee-on-transfer deposit and rolls back nonce and reservation state", async function () {
    const fixture = await feeTokenFixture();
    const amount = 500n;
    await fixture.token.mint(fixture.customer.address, amount);
    await fixture.token.connect(fixture.customer).approve(await fixture.escrow.getAddress(), amount);
    await fixture.token.setFeeBps(1_000);
    const signed = await makePermit(fixture, { amount });

    await expect(
      fixture.escrow.connect(fixture.customer).deposit(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InexactTokenTransfer");
    expect(await fixture.escrow.nonces(signed.permit.reservationId)).to.equal(0n);
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(0n);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(0n);
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(amount);
  });

  it("rejects an inexact payout and atomically preserves the pending deposit", async function () {
    const fixture = await feeTokenFixture();
    const amount = 500n;
    await deposit(fixture, { amount });
    await fixture.token.setFeeBps(1_000);
    const signed = await makePermit(fixture, { action: 1, amount });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InexactTokenTransfer");
    expect(await fixture.escrow.nonces(signed.permit.reservationId)).to.equal(1n);
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(1n);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(amount);
    expect(await fixture.token.balanceOf(fixture.agency.address)).to.equal(0n);
  });

  it("rejects an inexact refund and atomically preserves the pending deposit", async function () {
    const fixture = await feeTokenFixture();
    const amount = 500n;
    await deposit(fixture, { amount });
    await fixture.token.setFeeBps(1_000);
    const signed = await makePermit(fixture, { action: 2, amount });

    await expect(
      fixture.escrow.connect(fixture.agency).reject(signed.permit, signed.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "InexactTokenTransfer");
    expect(await fixture.escrow.nonces(signed.permit.reservationId)).to.equal(1n);
    expect((await fixture.escrow.reservation(signed.permit.reservationId)).status).to.equal(1n);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(amount);
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(0n);
  });

  it("rejects an inexact expiry refund and atomically keeps the reservation pending", async function () {
    const fixture = await feeTokenFixture();
    const amount = 500n;
    const deadline = (await currentTime()) + 100n;
    await deposit(fixture, { amount, deadline });
    await fixture.token.setFeeBps(1_000);
    await setTime(deadline);

    await expect(
      fixture.escrow.connect(fixture.other).expire(idHash("reservation-1")),
    ).to.be.revertedWithCustomError(fixture.escrow, "InexactTokenTransfer");
    expect(await fixture.escrow.nonces(idHash("reservation-1"))).to.equal(1n);
    expect((await fixture.escrow.reservation(idHash("reservation-1"))).status).to.equal(1n);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(amount);
    expect(await fixture.token.balanceOf(fixture.customer.address)).to.equal(0n);
  });
});

describe("ReservationEscrow token interaction boundaries", function () {
  async function callbackFixture(): Promise<Fixture> {
    const [owner, signer, customer, agency, other] = await ethers.getSigners();
    const token = await deployCallbackToken(owner);
    const Escrow = await ethers.getContractFactory("ReservationEscrow");
    const escrow = await Escrow.deploy(await token.getAddress(), signer.address);
    await escrow.waitForDeployment();
    return { owner, signer, customer, agency, other, token, escrow };
  }

  it("rolls back state and nonce when a safe token transfer reports failure", async function () {
    const fixture = await callbackFixture();
    const amount = ethers.parseUnits("4.00", 2);
    await fixture.token.mint(fixture.customer.address, amount);
    await fixture.token.connect(fixture.customer).approve(await fixture.escrow.getAddress(), amount);
    const depositPermit = await makePermit(fixture, { amount });
    await fixture.escrow.connect(fixture.customer).deposit(depositPermit.permit, depositPermit.signature);
    await fixture.token.setFailTransfers(true);
    const accept = await makePermit(fixture, { action: 1, amount });

    await expect(
      fixture.escrow.connect(fixture.agency).accept(accept.permit, accept.signature),
    ).to.be.revertedWithCustomError(fixture.escrow, "SafeERC20FailedOperation");
    expect((await fixture.escrow.reservation(accept.permit.reservationId)).status).to.equal(1n);
    expect(await fixture.escrow.nonces(accept.permit.reservationId)).to.equal(1n);
    expect(await fixture.token.balanceOf(await fixture.escrow.getAddress())).to.equal(amount);
  });

  it("blocks a token callback from reentering a terminal action", async function () {
    const fixture = await callbackFixture();
    const amount = ethers.parseUnits("8.00", 2);
    await fixture.token.mint(fixture.customer.address, amount);
    await fixture.token.connect(fixture.customer).approve(await fixture.escrow.getAddress(), amount);
    const depositPermit = await makePermit(fixture, { amount });
    await fixture.escrow.connect(fixture.customer).deposit(depositPermit.permit, depositPermit.signature);

    const accept = await makePermit(fixture, { action: 1, amount });
    const reentrantCancel = await makePermit(fixture, {
      action: 3,
      amount,
      nonce: accept.permit.nonce + 1n,
      actor: fixture.agency.address,
    });
    const reentrantData = fixture.escrow.interface.encodeFunctionData("cancel", [
      reentrantCancel.permit,
      reentrantCancel.signature,
    ]);
    await fixture.token.setCallback(await fixture.escrow.getAddress(), reentrantData);

    await fixture.escrow.connect(fixture.agency).accept(accept.permit, accept.signature);
    expect(await fixture.token.callbackSucceeded()).to.equal(false);
    expect((await fixture.escrow.reservation(accept.permit.reservationId)).status).to.equal(2n);
    expect(await fixture.token.balanceOf(fixture.agency.address)).to.equal(amount);
  });
});
