import { useMemo, useState } from "react";
import { BrowserProvider, Contract, parseUnits, AbiCoder } from "ethers";

import incentiveControllerAbi from "./abi/IncentiveController.json";
import revenueRouterAbi from "./abi/RevenueRouter.json";
import rewardsVaultAbi from "./abi/RewardsVault.json";
import mockRevenueAdapterAbi from "./abi/MockRevenueAdapter.json";

const positionManagerAbi = [
  "function mint((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) poolKey,int24 tickLower,int24 tickUpper,uint256 liquidity,uint256 amount0Max,uint256 amount1Max,address owner,uint256 deadline,bytes hookData) returns (uint256 tokenId,uint256)",
  "function decreaseLiquidity(uint256 tokenId,uint256 liquidity,uint256 amount0Min,uint256 amount1Min,address receiver,uint256 deadline,bytes hookData) returns (uint256)"
];

type LogLevel = "ok" | "err" | "info";

type LogEntry = {
  level: LogLevel;
  text: string;
};

declare global {
  interface Window {
    ethereum?: {
      request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
    };
  }
}

const coder = AbiCoder.defaultAbiCoder();

export default function App() {
  const [account, setAccount] = useState<string>("");
  const [status, setStatus] = useState<string>("Disconnected");
  const [logs, setLogs] = useState<LogEntry[]>([]);

  const [addresses, setAddresses] = useState({
    controller: "",
    router: "",
    vault: "",
    adapter: "",
    positionManager: "",
    poolId: ""
  });

  const [pool, setPool] = useState({
    currency0: "",
    currency1: "",
    fee: "3000",
    tickSpacing: "60",
    hooks: ""
  });

  const [program, setProgram] = useState({
    rewardToken: "",
    distributionType: "0",
    startTime: `${Math.floor(Date.now() / 1000)}`,
    endTime: "0",
    warmupPeriod: "0",
    cooldownPeriod: "86400",
    earlyWithdrawalPenaltyBps: "1000",
    emissionRate: "1",
    maxFunding: "1000000"
  });

  const [funding, setFunding] = useState({
    directAmount: "1000",
    adapterAmount: "500"
  });

  const [lp, setLp] = useState({
    tickLower: "-887220",
    tickUpper: "887220",
    liquidity: "100",
    amount0Max: "100000",
    amount1Max: "100000",
    tokenId: "",
    removeLiquidity: "10"
  });

  const [fairness, setFairness] = useState({
    lpA: "",
    lpB: "",
    lpAClaimable: "-",
    lpBClaimable: "-",
    programState: "-"
  });

  const provider = useMemo(() => {
    if (!window.ethereum) return null;
    return new BrowserProvider(window.ethereum);
  }, []);

  function pushLog(level: LogLevel, text: string) {
    setLogs((prev) => [{ level, text }, ...prev].slice(0, 40));
  }

  async function connectWallet() {
    try {
      if (!provider) throw new Error("No injected wallet found");
      await provider.send("eth_requestAccounts", []);
      const signer = await provider.getSigner();
      const next = await signer.getAddress();
      setAccount(next);
      setStatus("Connected");
      pushLog("ok", `Connected: ${next}`);
    } catch (error) {
      pushLog("err", (error as Error).message);
    }
  }

  async function signer() {
    if (!provider) throw new Error("No wallet provider found");
    return provider.getSigner();
  }

  async function writeTx(label: string, fn: () => Promise<{ hash: string; wait: () => Promise<unknown> }>) {
    try {
      setStatus(`Pending: ${label}`);
      const tx = await fn();
      pushLog("info", `${label} tx: ${tx.hash}`);
      await tx.wait();
      setStatus(`Confirmed: ${label}`);
      pushLog("ok", `${label} confirmed`);
    } catch (error) {
      setStatus(`Failed: ${label}`);
      pushLog("err", `${label} failed: ${(error as Error).message}`);
    }
  }

  async function createProgram() {
    const ctr = new Contract(addresses.controller, incentiveControllerAbi, await signer());

    const poolKey = {
      currency0: pool.currency0,
      currency1: pool.currency1,
      fee: Number(pool.fee),
      tickSpacing: Number(pool.tickSpacing),
      hooks: pool.hooks
    };

    const config = {
      rewardToken: program.rewardToken,
      distributionType: Number(program.distributionType),
      startTime: Number(program.startTime),
      endTime: Number(program.endTime),
      warmupPeriod: Number(program.warmupPeriod),
      cooldownPeriod: Number(program.cooldownPeriod),
      earlyWithdrawalPenaltyBps: Number(program.earlyWithdrawalPenaltyBps),
      emissionRate: parseUnits(program.emissionRate || "0", 18),
      maxFunding: parseUnits(program.maxFunding || "0", 18)
    };

    await writeTx("createProgram", async () => ctr.createProgram(poolKey, config));
  }

  async function directFund() {
    const router = new Contract(addresses.router, revenueRouterAbi, await signer());
    const amount = parseUnits(funding.directAmount || "0", 18);
    await writeTx("directFund", async () => router.directFund(addresses.poolId, amount));
  }

  async function adapterFund() {
    const adapter = new Contract(addresses.adapter, mockRevenueAdapterAbi, await signer());
    const amount = parseUnits(funding.adapterAmount || "0", 18);

    await writeTx("adapterMintRevenue", async () => adapter.mintRevenue(amount));
    await writeTx("adapterRouteRevenue", async () => adapter.routeRevenue(addresses.poolId, amount));
  }

  async function addLiquidity() {
    const posm = new Contract(addresses.positionManager, positionManagerAbi, await signer());

    const poolKey = {
      currency0: pool.currency0,
      currency1: pool.currency1,
      fee: Number(pool.fee),
      tickSpacing: Number(pool.tickSpacing),
      hooks: pool.hooks
    };

    const hookData = coder.encode(["address"], [account]);

    await writeTx("addLiquidity", async () =>
      posm.mint(
        poolKey,
        Number(lp.tickLower),
        Number(lp.tickUpper),
        parseUnits(lp.liquidity || "0", 18),
        parseUnits(lp.amount0Max || "0", 18),
        parseUnits(lp.amount1Max || "0", 18),
        account,
        Math.floor(Date.now() / 1000) + 600,
        hookData
      )
    );
  }

  async function removeLiquidity() {
    const posm = new Contract(addresses.positionManager, positionManagerAbi, await signer());
    const hookData = coder.encode(["address"], [account]);

    await writeTx("removeLiquidity", async () =>
      posm.decreaseLiquidity(
        BigInt(lp.tokenId || "0"),
        parseUnits(lp.removeLiquidity || "0", 18),
        0,
        0,
        account,
        Math.floor(Date.now() / 1000) + 600,
        hookData
      )
    );
  }

  async function claimRewards() {
    const ctr = new Contract(addresses.controller, incentiveControllerAbi, await signer());
    await writeTx("claimRewards", async () => ctr.claim(addresses.poolId, account));
  }

  async function refreshFairness() {
    try {
      const vault = new Contract(addresses.vault, rewardsVaultAbi, await signer());
      const [state, claimA, claimB] = await Promise.all([
        vault.getProgramState(addresses.poolId),
        fairness.lpA ? vault.claimable(addresses.poolId, fairness.lpA) : Promise.resolve(0n),
        fairness.lpB ? vault.claimable(addresses.poolId, fairness.lpB) : Promise.resolve(0n)
      ]);

      setFairness((prev) => ({
        ...prev,
        lpAClaimable: claimA.toString(),
        lpBClaimable: claimB.toString(),
        programState: JSON.stringify(
          {
            fundedBalance: state.fundedBalance.toString(),
            totalFunded: state.totalFunded.toString(),
            totalDistributed: state.totalDistributed.toString(),
            totalClaimed: state.totalClaimed.toString(),
            totalActiveWeight: state.totalActiveWeight.toString(),
            totalSlashed: state.totalSlashed.toString(),
            accRewardPerWeightX18: state.accRewardPerWeightX18.toString()
          },
          null,
          2
        )
      }));

      pushLog("ok", "Fairness data refreshed");
    } catch (error) {
      pushLog("err", `refreshFairness failed: ${(error as Error).message}`);
    }
  }

  return (
    <main className="page">
      <section className="hero">
        <p className="badge">External Revenue -&gt; LP Incentives</p>
        <h1>ERD Incentives Console</h1>
        <p>
          Configure incentive programs, route direct/mock revenue, add/remove liquidity, claim rewards, and inspect
          deterministic distribution state.
        </p>
        <div className="hero-actions">
          <button onClick={connectWallet}>Connect Wallet</button>
          <span>{status}</span>
        </div>
        <code>{account || "wallet not connected"}</code>
      </section>

      <section className="grid">
        <article className="card">
          <h2>Addresses</h2>
          <Field label="Controller" value={addresses.controller} onChange={(v) => setAddresses({ ...addresses, controller: v })} />
          <Field label="Router" value={addresses.router} onChange={(v) => setAddresses({ ...addresses, router: v })} />
          <Field label="Vault" value={addresses.vault} onChange={(v) => setAddresses({ ...addresses, vault: v })} />
          <Field label="Adapter" value={addresses.adapter} onChange={(v) => setAddresses({ ...addresses, adapter: v })} />
          <Field
            label="PositionManager"
            value={addresses.positionManager}
            onChange={(v) => setAddresses({ ...addresses, positionManager: v })}
          />
          <Field label="PoolId (bytes32)" value={addresses.poolId} onChange={(v) => setAddresses({ ...addresses, poolId: v })} />
        </article>

        <article className="card">
          <h2>Create Program</h2>
          <Field label="Currency0" value={pool.currency0} onChange={(v) => setPool({ ...pool, currency0: v })} />
          <Field label="Currency1" value={pool.currency1} onChange={(v) => setPool({ ...pool, currency1: v })} />
          <Field label="Fee" value={pool.fee} onChange={(v) => setPool({ ...pool, fee: v })} />
          <Field label="TickSpacing" value={pool.tickSpacing} onChange={(v) => setPool({ ...pool, tickSpacing: v })} />
          <Field label="Hook" value={pool.hooks} onChange={(v) => setPool({ ...pool, hooks: v })} />
          <Field label="Reward Token" value={program.rewardToken} onChange={(v) => setProgram({ ...program, rewardToken: v })} />
          <Field
            label="Distribution (0=stream,1=epoch)"
            value={program.distributionType}
            onChange={(v) => setProgram({ ...program, distributionType: v })}
          />
          <Field label="StartTime" value={program.startTime} onChange={(v) => setProgram({ ...program, startTime: v })} />
          <Field label="EndTime" value={program.endTime} onChange={(v) => setProgram({ ...program, endTime: v })} />
          <Field label="Warmup" value={program.warmupPeriod} onChange={(v) => setProgram({ ...program, warmupPeriod: v })} />
          <Field label="Cooldown" value={program.cooldownPeriod} onChange={(v) => setProgram({ ...program, cooldownPeriod: v })} />
          <Field
            label="Penalty Bps"
            value={program.earlyWithdrawalPenaltyBps}
            onChange={(v) => setProgram({ ...program, earlyWithdrawalPenaltyBps: v })}
          />
          <Field label="Emission (tokens/s)" value={program.emissionRate} onChange={(v) => setProgram({ ...program, emissionRate: v })} />
          <Field label="Max Funding" value={program.maxFunding} onChange={(v) => setProgram({ ...program, maxFunding: v })} />
          <button onClick={createProgram}>Create Program</button>
        </article>

        <article className="card">
          <h2>Funding</h2>
          <Field
            label="Direct Amount"
            value={funding.directAmount}
            onChange={(v) => setFunding({ ...funding, directAmount: v })}
          />
          <button onClick={directFund}>Direct Fund</button>
          <Field
            label="Adapter Amount"
            value={funding.adapterAmount}
            onChange={(v) => setFunding({ ...funding, adapterAmount: v })}
          />
          <button onClick={adapterFund}>Mock Adapter Fund</button>
        </article>

        <article className="card">
          <h2>LP Actions</h2>
          <Field label="Tick Lower" value={lp.tickLower} onChange={(v) => setLp({ ...lp, tickLower: v })} />
          <Field label="Tick Upper" value={lp.tickUpper} onChange={(v) => setLp({ ...lp, tickUpper: v })} />
          <Field label="Liquidity" value={lp.liquidity} onChange={(v) => setLp({ ...lp, liquidity: v })} />
          <Field label="Amount0 Max" value={lp.amount0Max} onChange={(v) => setLp({ ...lp, amount0Max: v })} />
          <Field label="Amount1 Max" value={lp.amount1Max} onChange={(v) => setLp({ ...lp, amount1Max: v })} />
          <button onClick={addLiquidity}>Add Liquidity</button>
          <Field label="TokenId" value={lp.tokenId} onChange={(v) => setLp({ ...lp, tokenId: v })} />
          <Field label="Remove Liquidity" value={lp.removeLiquidity} onChange={(v) => setLp({ ...lp, removeLiquidity: v })} />
          <button onClick={removeLiquidity}>Remove Liquidity</button>
        </article>

        <article className="card">
          <h2>Claims + Fairness</h2>
          <button onClick={claimRewards}>Claim Rewards</button>
          <Field label="LP A" value={fairness.lpA} onChange={(v) => setFairness({ ...fairness, lpA: v })} />
          <Field label="LP B" value={fairness.lpB} onChange={(v) => setFairness({ ...fairness, lpB: v })} />
          <button onClick={refreshFairness}>Refresh Math</button>
          <p>LP A claimable: <strong>{fairness.lpAClaimable}</strong></p>
          <p>LP B claimable: <strong>{fairness.lpBClaimable}</strong></p>
          <pre>{fairness.programState}</pre>
        </article>
      </section>

      <section className="card logs">
        <h2>Execution Log</h2>
        {logs.length === 0 ? <p>No events yet.</p> : null}
        {logs.map((entry, idx) => (
          <p key={`${entry.text}-${idx}`} className={`log-${entry.level}`}>
            {entry.text}
          </p>
        ))}
      </section>
    </main>
  );
}

function Field({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <label className="field">
      <span>{label}</span>
      <input value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}
