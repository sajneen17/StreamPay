import { ethers } from "ethers";
import "./style.css";

const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const REQUIRED_CHAIN_ID = 31337n;

const ADMIN_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266".toLowerCase();
const EMPLOYER_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8".toLowerCase();
const EMPLOYEE_ADDRESS = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC".toLowerCase();

const ABI = [
  "function admin() view returns (address)",
  "function adminFeeBalance() view returns (uint256)",
  "function nextStreamId() view returns (uint256)",
  "function createStream(address employee, uint256 companyId, uint256 duration) payable returns (uint256)",
  "function withdraw(uint256 streamId)",
  "function cancelStream(uint256 streamId)",
  "function claimAdminFees()",
  "function getStream(uint256 streamId) view returns (tuple(address employer,address employee,uint256 companyId,uint256 totalDeposit,uint256 startTime,uint256 duration,uint256 totalWithdrawn,bool isClosed))",
  "event StreamCreated(uint256 indexed streamId,address indexed employer,address indexed employee,uint256 amount,uint256 duration)"
];

let provider;
let signer;
let contract;
let account = "";
let timer;
let cachedStreams = [];

const $ = (id) => document.getElementById(id);
const connectBtn = $("connectBtn");
const message = $("message");

function shortAddress(value) {
  return `${value.slice(0, 6)}...${value.slice(-4)}`;
}

function eth(value, digits = 6) {
  return Number(ethers.formatEther(value)).toFixed(digits);
}

function setMessage(text, type = "") {
  message.textContent = text;
  message.className = `message ${type}`;
}

function setLoading(button, loading, label) {
  button.disabled = loading;
  if (label) button.textContent = label;
}

function roleOf(address) {
  if (address === ADMIN_ADDRESS) return "Admin";
  if (address === EMPLOYER_ADDRESS) return "Employer";
  if (address === EMPLOYEE_ADDRESS) return "Employee";
  return "Guest";
}

function showPanels(role) {
  $("adminPanel").classList.toggle("hidden", role !== "Admin");
  $("employerPanel").classList.toggle("hidden", role !== "Employer");
  $("employeePanel").classList.toggle("hidden", role !== "Employee");
  $("guestPanel").classList.toggle("hidden", role !== "Guest");
}

async function connect() {
  try {
    if (!window.ethereum) {
      throw new Error("MetaMask was not detected. Install and unlock MetaMask first.");
    }

    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    signer = await provider.getSigner();
    account = (await signer.getAddress()).toLowerCase();

    const network = await provider.getNetwork();
    if (network.chainId !== REQUIRED_CHAIN_ID) {
      throw new Error("Switch MetaMask to Anvil Localhost (Chain ID 31337), then reconnect.");
    }

    contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);

    $("walletAddress").textContent = shortAddress(account);
    $("networkStatus").textContent = `Anvil (${network.chainId})`;

    const role = roleOf(account);
    $("roleStatus").textContent = role;
    showPanels(role);

    connectBtn.textContent = "Connected";
    setMessage(`Connected as ${role}: ${shortAddress(account)}`, "success");

    await refresh();
  } catch (error) {
    console.error(error);
    setMessage(error.shortMessage || error.message, "error");
  }
}

async function loadStreams() {
  const count = Number(await contract.nextStreamId());
  const streams = [];

  for (let i = 0; i < count; i++) {
    const data = await contract.getStream(i);
    streams.push({
      id: i,
      employer: data.employer.toLowerCase(),
      employee: data.employee.toLowerCase(),
      companyId: data.companyId,
      totalDeposit: data.totalDeposit,
      startTime: data.startTime,
      duration: data.duration,
      totalWithdrawn: data.totalWithdrawn,
      isClosed: data.isClosed
    });
  }

  cachedStreams = streams;
}

function localUnlocked(stream) {
  const now = BigInt(Math.floor(Date.now() / 1000));
  const endTime = stream.startTime + stream.duration;

  if (now >= endTime) return stream.totalDeposit;
  if (now <= stream.startTime) return 0n;

  return (stream.totalDeposit * (now - stream.startTime)) / stream.duration;
}

function localClaimable(stream) {
  const unlocked = localUnlocked(stream);
  return unlocked > stream.totalWithdrawn ? unlocked - stream.totalWithdrawn : 0n;
}

function streamCard(stream, role) {
  const claimable = localClaimable(stream);
  const isEmployer = role === "Employer" && stream.employer === account;
  const isEmployee = role === "Employee" && stream.employee === account;
  const status = stream.isClosed ? "Closed" : "Active";

  let actions = "";
  if (!stream.isClosed && isEmployee) {
    actions += `<button class="withdrawBtn" data-id="${stream.id}">Withdraw Vested Funds</button>`;
  }
  if (!stream.isClosed && (isEmployer || isEmployee)) {
    actions += `<button class="cancelBtn danger" data-id="${stream.id}">Cancel Stream</button>`;
  }

  return `
    <article class="stream-card ${stream.isClosed ? "closed" : ""}">
      <h3>Stream #${stream.id} <span class="badge ${stream.isClosed ? "" : "employee"}">${status}</span></h3>
      <div class="stream-data">
        <div><span>Total salary</span><strong>${eth(stream.totalDeposit)} ETH</strong></div>
        <div><span>Duration</span><strong>${stream.duration.toString()} sec</strong></div>
        <div><span>Withdrawn</span><strong>${eth(stream.totalWithdrawn)} ETH</strong></div>
        <div><span>Company ID</span><strong>${stream.companyId.toString()}</strong></div>
      </div>
      <p>Employer: ${shortAddress(stream.employer)}</p>
      <p>Employee: ${shortAddress(stream.employee)}</p>
      <p class="claimable">Claimable now: <strong data-claimable="${stream.id}">${eth(claimable)} ETH</strong></p>
      <div class="card-actions">${actions || "<span class='muted'>No actions available for this account.</span>"}</div>
    </article>
  `;
}

function renderStreams() {
  const role = roleOf(account);
  const outgoing = cachedStreams.filter((stream) => stream.employer === account);
  const incoming = cachedStreams.filter((stream) => stream.employee === account);

  $("employerStreams").innerHTML = outgoing.length
    ? outgoing.map((stream) => streamCard(stream, role)).join("")
    : "<p class='muted'>No outgoing streams found.</p>";

  $("employeeStreams").innerHTML = incoming.length
    ? incoming.map((stream) => streamCard(stream, role)).join("")
    : "<p class='muted'>No incoming streams found.</p>";

  document.querySelectorAll(".withdrawBtn").forEach((button) => {
    button.addEventListener("click", () => withdrawStream(button.dataset.id));
  });

  document.querySelectorAll(".cancelBtn").forEach((button) => {
    button.addEventListener("click", () => cancelStream(button.dataset.id));
  });
}

function tickClaimable() {
  for (const stream of cachedStreams) {
    const element = document.querySelector(`[data-claimable="${stream.id}"]`);
    if (element && !stream.isClosed) {
      element.textContent = `${eth(localClaimable(stream))} ETH`;
    }
  }
}

async function refresh() {
  if (!contract) return;

  try {
    const role = roleOf(account);

    if (role === "Admin") {
      const fee = await contract.adminFeeBalance();
      $("adminFee").textContent = `${eth(fee)} ETH`;
    }

    await loadStreams();
    renderStreams();

    clearInterval(timer);
    timer = setInterval(tickClaimable, 1000);
  } catch (error) {
    console.error(error);
    setMessage(error.shortMessage || error.message, "error");
  }
}

async function createStream(event) {
  event.preventDefault();

  const button = event.currentTarget.querySelector("button");
  try {
    const employee = $("employeeInput").value.trim();
    const companyId = BigInt($("companyIdInput").value);
    const duration = BigInt($("durationInput").value);
    const amount = ethers.parseEther($("amountInput").value);

    if (!ethers.isAddress(employee)) throw new Error("Enter a valid employee wallet address.");
    if (duration <= 15n) throw new Error("Duration must be greater than 15 seconds.");

    setLoading(button, true, "Creating transaction...");
    setMessage("Approve the Create Stream transaction in MetaMask.");

    const tx = await contract.createStream(employee, companyId, duration, { value: amount });
    setMessage(`Transaction submitted: ${tx.hash}. Waiting for confirmation...`);
    await tx.wait();

    setMessage("Stream created successfully.", "success");
    document.querySelector("#streamForm")?.reset();
    $("companyIdInput").value = "1";
    $("durationInput").value = "120";
    $("amountInput").value = "1";
    await refresh();
  } catch (error) {
    console.error(error);
    setMessage(error.shortMessage || error.message, "error");
  } finally {
    setLoading(button, false, "Create Stream");
  }
}

async function withdrawStream(streamId) {
  try {
    setMessage("Approve the withdraw transaction in MetaMask.");
    const tx = await contract.withdraw(streamId);
    setMessage(`Withdraw submitted: ${tx.hash}. Waiting for confirmation...`);
    await tx.wait();
    setMessage("Vested funds withdrawn successfully.", "success");
    await refresh();
  } catch (error) {
    console.error(error);
    setMessage(error.shortMessage || error.message, "error");
  }
}

async function cancelStream(streamId) {
  try {
    setMessage("Approve the cancellation transaction in MetaMask.");
    const tx = await contract.cancelStream(streamId);
    setMessage(`Cancellation submitted: ${tx.hash}. Waiting for confirmation...`);
    await tx.wait();
    setMessage("Stream cancelled and settled successfully.", "success");
    await refresh();
  } catch (error) {
    console.error(error);
    setMessage(error.shortMessage || error.message, "error");
  }
}

async function claimFees() {
  const button = $("claimFeesBtn");

  try {
    setLoading(button, true, "Claiming...");
    setMessage("Approve the admin fee claim in MetaMask.");

    const tx = await contract.claimAdminFees();
    setMessage(`Fee claim submitted: ${tx.hash}. Waiting for confirmation...`);
    await tx.wait();

    setMessage("Admin fees claimed successfully.", "success");
    await refresh();
  } catch (error) {
    console.error(error);
    setMessage(error.shortMessage || error.message, "error");
  } finally {
    setLoading(button, false, "Claim Admin Fees");
  }
}

connectBtn.addEventListener("click", connect);
$("createForm").addEventListener("submit", createStream);
$("claimFeesBtn").addEventListener("click", claimFees);

if (window.ethereum) {
  window.ethereum.on("accountsChanged", connect);
  window.ethereum.on("chainChanged", () => window.location.reload());
}
