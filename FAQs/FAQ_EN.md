# FAQ

<details>
  <summary>What iOS versions does YouTube Afterglow support?</summary>
  <p>Afterglow supports iOS 14 and above. If you're sideloading on a non-jailbroken device, you also need a YouTube IPA version that works with your iOS:</p>
  <ul>
    <li><strong>iOS 14</strong>: YouTube v19.20.2</li>
    <li><strong>iOS 15</strong>: YouTube v20.21.6</li>
    <li><strong>iOS 16+</strong>: any current YouTube version</li>
  </ul>
</details>

<br>

<details>
  <summary>My iOS version is no longer supported by the latest YouTube app. What can I do?</summary>
  <p>A few options:</p>
  <ul>
    <li><a href="https://ios.cfw.guide/get-started/">Jailbreak</a> your device, install a supported YouTube version, and install Afterglow as a tweak.</li>
    <li>Install <a href="https://ios.cfw.guide/installing-trollstore/">TrollStore</a>, then <a href="https://github.com/Lessica/TrollFools/releases/">TrollFools</a>, install a supported YouTube version, and inject Afterglow with TrollFools.</li>
    <li>Find a compatible decrypted YouTube IPA and <a href="../README.md#building">build Afterglow with GitHub Actions</a>.</li>
  </ul>
</details>

<br>

<details>
  <summary>Cast stopped working on sideloaded Afterglow. What should I do?</summary>
  <p>Until this is resolved, use YouTube version 20.14.1 or below.</p>
</details>

<br>

<details>
  <summary>When I try to play a video, I get <em>Something went wrong. Refresh and try again later.</em></summary>
  <p>Before jumping to conclusions:</p>
  <ol>
    <li>It is <strong>not</strong> caused by Afterglow's ad blocking.</li>
    <li>Your account is <strong>not</strong> flagged or blacklisted.</li>
  </ol>
  <p>The issue seems to originate in the sideloading process itself, even with no tweaks applied. It likely involves an invalid or missing <code>VisitorID</code>/<code>VisitorData</code>. YouTube has been tightening anti-download measures, which makes this show up more often.</p>
  <p><strong>Temporary workaround:</strong></p>
  <ol>
    <li>Sign out of all accounts completely: <em>You tab → Switch account → Manage accounts on this device → Remove from this device</em>.</li>
    <li>Watch a few full-length videos signed out. Stay signed out for a few hours.</li>
    <li>Sign back into the account that had issues.</li>
  </ol>
</details>
