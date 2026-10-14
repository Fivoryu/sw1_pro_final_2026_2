import { ethers } from "hardhat";

async function main(): Promise<void> {
  const signers = await ethers.getSigners();
  if (signers.length < 4) {
    throw new Error("Hardhat local node must expose at least four test accounts.");
  }
  const [backendSigner, customer, agency, secondaryCustomer] = signers;

  const rft = await ethers.deployContract("RoomForgeTestToken", [backendSigner.address]);
  await rft.waitForDeployment();
  const usdt = await ethers.deployContract("MockUSDT", [backendSigner.address]);
  await usdt.waitForDeployment();

  const bobUsdEscrow = await ethers.deployContract("ReservationEscrow", [
    await rft.getAddress(),
    backendSigner.address,
  ]);
  await bobUsdEscrow.waitForDeployment();
  const usdtEscrow = await ethers.deployContract("ReservationEscrow", [
    await usdt.getAddress(),
    backendSigner.address,
  ]);
  await usdtEscrow.waitForDeployment();

  // Seed customer-only test balances; these local tokens have no monetary value.
  await (await rft.mint(customer.address, 100_000_000n)).wait();
  await (await usdt.mint(customer.address, 100_000_000_000n)).wait();
  await (await rft.mint(secondaryCustomer.address, 100_000_000n)).wait();
  await (await usdt.mint(secondaryCustomer.address, 100_000_000_000n)).wait();

  console.log(
    JSON.stringify(
      {
        chain_id: 31337,
        rpc_url: "http://127.0.0.1:8545",
        contracts: {
          rft: await rft.getAddress(),
          usdt: await usdt.getAddress(),
          escrow_bob: await bobUsdEscrow.getAddress(),
          escrow_usd: await bobUsdEscrow.getAddress(),
          escrow_usdt: await usdtEscrow.getAddress(),
        },
        accounts: {
          backend_signer: backendSigner.address,
          customer_wallet: customer.address,
          secondary_customer_wallet: secondaryCustomer.address,
          agency_wallet: agency.address,
        },
        customer_test_balances: {
          rft_base_units: "100000000",
          usdt_base_units: "100000000000",
        },
      },
      null,
      2,
    ),
  );
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
