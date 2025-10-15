# Intune Autopilot & ESP — Admin Cheat Sheet (QTM)

_Last updated: 2025-10-15_

This is the step-by-step playbook I use to set up and troubleshoot **Windows Autopilot**, the **Enrollment Status Page (ESP)**, **Delivery Optimization (DO)**, and a blocking **WebView2 Win32 app**. It assumes Intune admin permissions (or that we can get the right role assignments quickly). Friendly tone, precise clicks, minimal fluff.

---

## 0) Prereqs & roles
**Pick one role that gives these capabilities:**
- **Intune Administrator** (full access), **or**
- A combo like **Policy and Profile Manager** (edit config), **Application Manager** (add Win32 apps), and rights to view **Windows enrollment**.

If a blade below isn’t visible, it’s a role issue. In the Intune admin center: **Tenant administration → Roles → All roles** → open the role → **Assignments → + Assign** to the appropriate admin group (or self, if policy allows).

---

## 1) Autopilot deployment profile & mode
**Path:** Intune admin center → **Devices → Windows → Windows enrollment → Deployment profiles (Autopilot)**

Open the deployment profile bound to the test devices and confirm:
- **Join to Microsoft Entra ID as:** _Cloud (Entra/Azure AD)_ or _Hybrid_.
- **Deployment mode:** _User‑driven_ or _Self‑deploying_.
- If using **Pre‑provisioning** (white‑glove), start it with **Windows key ×5** at OOBE.
- **Assignments** include the device group(s) we’re testing.

> Pre‑provisioning runs in two parts: **Technician flow** (device ESP before user) and **User flow** (user ESP at first sign‑in). If both phases track heavy apps, expect something like “1.5h + 1.5h”.

---

## 2) ESP (Enrollment Status Page): where to tune and what to block on
**Path:** **Devices → Windows → Windows enrollment → Enrollment Status Page**

Open the ESP profile (or create one) and set:
- **Device setup**
  - **Block device use until all apps and profiles are installed** = **Yes**.
  - **Select which apps to block on** = **Selected** (recommended). Then **Select apps** and choose only essentials (see §4).
  - **Time limits**: set device setup timeout/retry to realistic values.
  - **Allow users to collect logs** = **On** to export **MDMDiagnostics** from ESP.
- **Account setup (User)**
  - If the second phase is a time sink, consider **turning user phase Off** or keep it **On** with **no heavy apps tracked**.
- **Assignments** to the correct device group(s).

**Good blocking choices (keep it lean):**
- WebView2 runtime, Microsoft Defender platform/updates, OneDrive bootstrap.

**Avoid blocking on:**
- **Microsoft 365 Apps**, full **Teams**, or other jumbo Win32 packages. Let those install **after ESP**.

---

## 3) What ESP actually tracks
ESP blocks on **Required** apps that also match the ESP profile’s **Selected apps** list.

**Quick audit:**
1. **Apps → All apps**.
2. Filter **Assignment = Required** and scope to the same device/user groups the ESP uses.
3. Open fat packages (e.g., **Microsoft 365 Apps**, **Teams**, custom Win32 apps) and note size/installer type.
4. Cross‑check against **ESP → Selected apps**. If a big app appears in both places, **ESP will sit and wait for it**.

> **Double‑assignment trap:** If a heavy app is **Required to device** _and_ **Required to user**, both **Device** and **User** phases can wait on it.

---

## 4) Make WebView2 a blocking Win32 app (kill first‑login prompts)
We already have toolkit scripts for this:
- `Remediation\WebView2\Install-WebView2.ps1`
- `Remediation\WebView2\Detect-WebView2-Installed.ps1`

**A. Prep content on an admin workstation**
1. Create a folder, e.g., `C:\Pkg-WebView2`, and copy both scripts in.
2. (Recommended) Download the **Evergreen Standalone (offline) x64** WebView2 installer and save as:
   ```
   C:\Pkg-WebView2\MicrosoftEdgeWebView2RuntimeInstallerX64.exe
   ```

**B. Wrap as a Win32 app**
Use Microsoft’s **Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`):
```cmd
IntuneWinAppUtil.exe -c C:\Pkg-WebView2 -s Install-WebView2.ps1 -o C:\Out -q
```

**C. Create the app in Intune**
- **Apps → Windows → + Add → App type: Windows app (Win32)**
- Upload the `.intunewin` from `C:\Out`

**Program**
- **Install:**  
  `powershell.exe -ExecutionPolicy Bypass -File .\Install-WebView2.ps1`
- **Uninstall (optional):**  
  `powershell.exe -ExecutionPolicy Bypass -File .\Install-WebView2.ps1 -Force`

**Detection rules**
- **Use a custom detection script** and paste `Detect-WebView2-Installed.ps1`.

**Requirements**
- 64‑bit; Windows 10/11 supported builds.

**Assignments**
- **Required** to the Autopilot device group.

**D. Add WebView2 to ESP “Selected apps” (Device phase)**
- **Windows enrollment → Enrollment Status Page** → open the profile.
- **Device setup → Select which apps** = **Selected** → **Select apps** → add the **WebView2 Win32 app**.
- Save and re‑provision a test device.

---

## 5) Delivery Optimization (DO): policy location and sane defaults
**Path:** **Devices → Windows → Configuration → Profiles → Settings catalog policy → Edit → Delivery Optimization**  
(or search **Delivery Optimization** in Settings Catalog).

**Key knobs:**
- **Download Mode:** use **1 (LAN)** for peer‑to‑peer on the same subnet, or a **Group/Connected Cache mode** if using **Microsoft Connected Cache (MCC)**.
- **Group ID / MCC:** set when using Connected Cache or to keep peers within a site boundary.
- **Bandwidth limits:** avoid tight caps during provisioning.
- **Cache parameters:** minimum RAM to cache and cache age should not be restrictive.

**Why care:** slow content is the #1 ESP drag (M365, Teams, large Win32s). DO dictates **where/how** content arrives (internet, peers, cache) and at what speed.

---

## 6) Fast “stabilize ESP” recipe
1. **ESP → Device setup:** **Block device use = Yes**; **Selected apps** = only **WebView2**, **Defender**, **OneDrive bootstrap**.
2. **ESP → Account setup:** turn **Off** (or keep extremely minimal).
3. Keep large apps **Required** to device/user **but not in ESP Selected apps**.
4. Set a sensible **DO Download Mode** (1 or Group/Connected Cache) and don’t strangle bandwidth.
5. Re‑test with **pre‑provisioning (Windows key ×5)**. Both phases should complete much faster.

---

## 7) Run the collector during/after ESP
**During ESP (Technician flow):**
1. At OOBE, press **Shift+F10** (some laptops need **Fn+Shift+F10**) for Command Prompt.
2. Type `powershell` and press Enter.
3. Execute:  
   ```powershell
   powershell -ExecutionPolicy Bypass -File "C:\QTM-Autopilot-Toolkit\Autopilot-FirstLogin-Diag-v3.ps1" -Phase DuringESP
   ```

**After first login (User flow):**
1. Open **elevated PowerShell**.
2. Execute:  
   ```powershell
   C:\QTM-Autopilot-Toolkit\Autopilot-FirstLogin-Diag-v3.ps1 -Phase AfterLogin
   ```

**Output:**  
`C:\QTM-FirstLoginCapture\QTM_FirstLogin_<timestamp>_<Phase>.zip`

> If a device is slow, send me both archives (`_DuringESP.zip` and `_AfterLogin.zip`). I’ll call out the apps/policies/DO/WU pieces eating time.

---

## 8) Common pitfalls (quick checklist)
- **ESP tracking jumbo apps** (M365, Teams). Remove from **Selected apps** or shift to post‑ESP.
- **Same app required to Device and User** → both phases wait.
- **WebView2/EdgeUpdate missing/blocked** → first‑run prompts. Make WebView2 a **blocking app**.
- **DO unset or endpoints blocked** → sluggish downloads. Set **Download Mode** and allow WU/DO/WNS endpoints.
- **Hybrid join** adds extra dependencies → ensure network line‑of‑sight and identity prereqs are good.

---

## 9) Export/review policy as JSON
For **Settings catalog** profiles, the **Export** option shows a JSON view of configured settings. (ESP itself doesn’t currently expose a JSON export in the UI.)

---

## 10) Glossary
- **Autopilot pre‑provisioning (white‑glove):** Tech provisions the **Device** phase pre‑user. Start with **Windows key ×5** at OOBE.
- **ESP Device vs Account setup:** Device phase first; Account/User phase at first sign‑in.
- **IME:** Intune Management Extension — engine for Win32 apps. Logs reveal which apps block ESP.
- **DO:** Delivery Optimization — transport for Windows Update/Store/Win32 content.

---

## Need help?
When stuck, drop three things:
1) the blade’s **page title**, 2) what you expected vs. what happened, 3) the exact **error text**.  
I’ll translate that into clicks, and if it belongs in Settings Catalog, the JSON too.
