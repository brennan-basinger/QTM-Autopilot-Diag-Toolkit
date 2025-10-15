# Intune Autopilot & ESP — Admin Cheat Sheet (QTM)

_Last updated: 2025-10-15_

This guide is a **step‑by‑step** reference for setting up and troubleshooting **Windows Autopilot**, **Enrollment Status Page (ESP)**, **Delivery Optimization (DO)**, and creating a **blocking WebView2 Win32 app**. It assumes you’re an **Intune admin** (or can request the right roles)

---

## 0) Prereqs & roles
- **Recommended roles** (any one that grants these capabilities):
  - **Intune Administrator** (full)
  - Or a combo: **Policy and Profile Manager** (edit config), **Application Manager** (add Win32 apps), and rights to view **Windows enrollment**.
- If you can’t see a blade referenced below, you likely need a role assignment. In the Intune admin center go to: **Tenant administration → Roles → All roles**, open a role, **Assignments → + Assign** yourself or your admin group.

---

## 1) Confirm your Autopilot deployment profile & mode
**Path:** Intune admin center → **Devices → Windows → Windows enrollment → Deployment profiles (Autopilot)**  
1. Open the **deployment profile** assigned to your target devices.
2. Check:
   - **Join to Microsoft Entra ID as**: _Cloud (Entra/Azure AD)_ or _Hybrid_.
   - **Deployment mode**: _User‑driven_ or _Self‑deploying_. (You’re using **Pre‑provisioning** AKA **white‑glove**, which you start by pressing **Windows key ×5** on OOBE.)
3. Confirm **Assignments** include the device group(s) you’re testing with.

> Tip: Pre‑provisioning has two stages: **Technician flow** (device ESP before user) and **User flow** (user ESP after first sign‑in). If both phases track a lot of apps, you’ll see “1.5h + 1.5h”.

---

## 2) ESP (Enrollment Status Page) — find it, tune it, and control what blocks
**Path:** **Devices → Windows → Windows enrollment → Enrollment Status Page**  
1. Open your **ESP profile** (or create one).
2. In **Device setup**:
   - Set **Block device use until all apps and profiles are installed** = **Yes**.
   - **Select which apps to block on**: choose **Selected** (recommended) and click **Select apps** to pick only essential blocking apps (see section 4).
   - **Time limits**: device setup timeout and retry settings.
   - **Allow users to collect logs**: enable so technicians can export MDMDiagnostics from ESP.
3. In **Account setup (User)**:
   - If your second “1.5h” is painful, consider **turning user phase off** or keep it on but **do not track heavy apps** here.
4. **Assignments**: scope to your device group(s).

**What should be “blocking”?**  
- _Keep it small_: WebView2 runtime, Microsoft Defender platform/updates, OneDrive bootstrap.  
- _Avoid blocking on_ **Microsoft 365 Apps**, full **Teams**, or any very large Win32 apps; let those install **post‑ESP**.

---

## 3) Find the apps that are actually tracked during ESP
ESP blocks on **Required** apps that also match your **Selected apps** list in the ESP profile.

**To review:**
1. Go to **Apps → All apps**.
2. Filter **Assignment = Required** and scope to the same device/user groups used by your ESP.
3. Open large apps (e.g., **Microsoft 365 Apps**, **Teams**, custom Win32 apps) and note approximate size/installer type.
4. Cross‑check this against the **ESP → Selected apps** list. If a large app is in both places, **ESP will wait for it**.

> Double‑assignment trap: If the same heavy app is required to **device** _and_ **user**, both **device** and **user** phases can wait on it.

---

## 4) Make WebView2 a blocking app (prevents first‑login prompts)
This uses the toolkit scripts you already have:
- `Remediation\WebView2\Install-WebView2.ps1`
- `Remediation\WebView2\Detect-WebView2-Installed.ps1`

**A. Prepare the content on your admin PC**
1. Put **both scripts** into a folder (e.g., `C:\Pkg-WebView2`).
2. (Optional but recommended) Download the **Evergreen Standalone (offline) x64** WebView2 installer and place it in that folder as:
   ```
   MicrosoftEdgeWebView2RuntimeInstallerX64.exe
   ```

**B. Wrap the folder into a Win32 app**
1. Use Microsoft’s **Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`) to wrap `C:\Pkg-WebView2` into a `.intunewin` file:
   ```cmd
   IntuneWinAppUtil.exe -c C:\Pkg-WebView2 -s Install-WebView2.ps1 -o C:\Out -q
   ```

**C. Create the app in Intune**
1. **Apps → Windows → + Add → App type: Windows app (Win32)**.
2. Upload the `.intunewin` from `C:\Out`.
3. **Program:**
   - **Install command:**  
     `powershell.exe -ExecutionPolicy Bypass -File .\Install-WebView2.ps1`
   - **Uninstall command (optional):**  
     `powershell.exe -ExecutionPolicy Bypass -File .\Install-WebView2.ps1 -Force`
4. **Detection rules:** choose **Use a custom detection script** and paste the contents of `Detect-WebView2-Installed.ps1`.
5. **Requirements:** 64‑bit; Windows 10/11 as appropriate.
6. **Assignments:** **Required** to your Autopilot device group.

**D. Add WebView2 to ESP “Selected apps” (Device phase)**
1. Go to **Windows enrollment → Enrollment Status Page** → open your profile.
2. In **Device setup**, set **Select which apps** = **Selected**, click **Select apps**, and add your **WebView2 Win32 app**.
3. Save and re‑provision a test device.

---

## 5) Delivery Optimization (DO) — where to set it & what to choose
**Path:** **Devices → Windows → Configuration → Profiles → Settings catalog policy → Edit → Delivery Optimization** (search for “Delivery Optimization” in the catalog).

**Key settings:**
- **Download Mode**: common choices are **1 (LAN)** or a **group/Connected Cache mode** if you use Microsoft Connected Cache (MCC).  
- **Group ID / MCC**: set if you’ve deployed Connected Cache or want devices to peer only within a defined group/site.  
- **Bandwidth limits**: avoid overly strict caps during provisioning.  
- **Cache**: confirm minimum RAM to cache and cache age aren’t too restrictive.

**Why this matters:** slow content downloads (M365 Apps, Teams, Win32 apps) are the #1 cause of long ESP. DO controls **where** and **how** the content is fetched (internet, peers, cache) and at what speed.

---

## 6) A fast “stabilize ESP” recipe
1. In **ESP → Device setup**: **Block device use = Yes**; **Selected apps** = only **WebView2**, **Defender**, **OneDrive bootstrap**.
2. In **ESP → Account setup**: turn **Off** (or keep minimal).  
3. Ensure **large apps** (M365 Apps, Teams) are **Required** to the device/user but **NOT** in the ESP **Selected apps** list.
4. Set a sane **DO Download Mode** (1 or group mode) and keep bandwidth limits reasonable.
5. Re‑test with **pre‑provisioning (Windows key ×5)** and watch both phases complete much faster.

---

## 7) Running the collector during and after ESP
- **During ESP (Technician flow):**
  1. On OOBE, press **Shift+F10** (on some laptops **Fn+Shift+F10**) to open Command Prompt.
  2. Type `powershell` and press Enter.
  3. Run:  
     `powershell -ExecutionPolicy Bypass -File "C:\QTM-Autopilot-Toolkit\Autopilot-FirstLogin-Diag-v3.ps1" -Phase DuringESP`
- **After login (User flow):**
  1. Open **elevated PowerShell**.
  2. Run:  
     `C:\QTM-Autopilot-Toolkit\Autopilot-FirstLogin-Diag-v3.ps1 -Phase AfterLogin`

**Output location:** `C:\QTM-FirstLoginCapture\QTM_FirstLogin_<timestamp>_<Phase>.zip`

> Send me the `_DuringESP.zip` and `_AfterLogin.zip` from a slow device; I’ll pinpoint which apps/policies or DO/WU issues are adding time.

---

## 8) Common pitfalls checklist
- **ESP waits on heavy apps** (M365 Apps, Teams) — remove from **Selected apps** or move to post‑ESP.
- **Same app required to both device & user** — causes both phases to wait.
- **EdgeUpdate/WebView2 blocked** — leads to first‑run prompts; deploy WebView2 as a blocking app.
- **DO not set or endpoints blocked** — slow downloads; set Download Mode and allow required endpoints (WU/DO/WNS).
- **Hybrid join** adds moving parts — if you’re hybrid, ensure network line‑of‑sight and identity prereqs are met.

---

## 9) Exporting or reviewing policy “as JSON”
- For **Settings catalog** profiles you can use the **Export** option (in the profile’s menu) to get a JSON view of configured settings. (ESP itself doesn’t expose JSON export in the UI.)

---

## 10) Glossary
- **Autopilot pre‑provisioning (white‑glove)**: Tech provisions “device phase” before the user; started with **Windows key ×5** on OOBE.
- **ESP Device setup vs Account setup**: Device phase runs first; Account/User phase runs at first sign‑in.
- **IME**: Intune Management Extension — the Win32 app engine. Its logs show which apps block ESP.
- **DO**: Delivery Optimization — Windows’ content delivery for Windows Update/Store/Win32 content.

---

## Need help?
If you get stuck on any step above, tell me:
- Which blade you’re on (copy the page title),
- What you expect to see vs. what you see,
- And any error text.  
I’ll translate that into the exact clicks and—if needed—the JSON to set in a Settings catalog profile.
